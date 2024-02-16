// SPDX-FileCopyrightText: 2011 - 2024 NVIDIA CORPORATION. All Rights Reserved.
//
// SPDX-License-Identifier: BSD-3-Clause

#include <solvers/idrmsync_solver.h>
#include <amgx_cublas.h>
#include <blas.h>
#include <multiply.h>
#include <util.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <curand.h>
#include <solvers/block_common_solver.h>

namespace amgx
{
namespace idrmsync_solver
{
// Constructor
template< class T_Config>
IDRMSYNC_Solver_Base<T_Config>::IDRMSYNC_Solver_Base( AMG_Config &cfg, const std::string &cfg_scope) :
    Solver<T_Config>( cfg, cfg_scope),
    m_buffer_N(0)
{
    std::string solverName, new_scope, tmp_scope;
    cfg.getParameter<std::string>( "preconditioner", solverName, cfg_scope, new_scope );
    s = cfg.AMG_Config::template getParameter<int>("subspace_dim_s", cfg_scope);

    if (solverName.compare("NOSOLVER") == 0)
    {
        no_preconditioner = true;
        m_preconditioner = NULL;
    }
    else
    {
        no_preconditioner = false;
        m_preconditioner = SolverFactory<T_Config>::allocate( cfg, cfg_scope, "preconditioner" );
    }
}

template<class T_Config>
IDRMSYNC_Solver_Base<T_Config>::~IDRMSYNC_Solver_Base()
{
    if (!no_preconditioner) { delete m_preconditioner; }
}

template<class T_Config>
void
IDRMSYNC_Solver_Base<T_Config>::solver_setup(bool reuse_matrix_structure)
{
    AMGX_CPU_PROFILER( "IDRMSYNC_Solver::solver_setup " );
    ViewType oldView = this->m_A->currentView();
    this->m_A->setViewExterior();
    // The number of elements in temporary vectors.
    this->m_buffer_N = static_cast<int>( this->m_A->get_num_cols() * this->m_A->get_block_dimy() );
    const int N = this->m_buffer_N;
    s = this->s;
    // Allocate memory needed for iterating.
    m_z.resize(N);
    m_Ax.resize(N);
    m_v.resize(N);
    c.resize(s);
    m_f.resize(s);
    gamma.resize(s);
    mu.resize(s);
    m_alpha.resize(s);
    tempg.resize(N);
    tempu.resize(N);
    temp.resize(N);
    beta_idr.resize(1);
    t_idr.resize(N);
    h_chk.resize(N * s);
    s_chk.resize(s * s);
    svec_chk.resize(s);
    G.resize(N * s);
    G.set_lda(N);
    G.set_num_rows(N);
    G.set_num_cols(s);
    U.resize(N * s);
    U.set_lda(N);
    U.set_num_rows(N);
    U.set_num_cols(s);
    P.resize(N * s);
    P.set_num_cols(s);
    P.set_lda(N);
    P.set_num_rows(N);
    M.resize(s * s);
    M.set_lda(s);
    M.set_num_rows(s);
    M.set_num_cols(s);
    m_Ax.set_block_dimy(this->m_A->get_block_dimy());
    m_Ax.set_block_dimx(1);
    m_Ax.dirtybit = 1;
    m_Ax.delayed_send = 1;
    m_Ax.tag = this->tag * 100 + 2;
    m_z.set_block_dimy(this->m_A->get_block_dimy());
    m_z.set_block_dimx(1);
    m_z.dirtybit = 1;
    m_z.delayed_send = 1;
    m_z.tag = this->tag * 100 + 3;
    m_v.set_block_dimy(this->m_A->get_block_dimy());
    m_v.set_block_dimx(1);
    m_v.dirtybit = 1;
    m_v.delayed_send = 1;
    m_v.tag = this->tag * 100 + 4;
    c.set_block_dimx(1);
    c.set_block_dimy(1);
    c.dirtybit = 1;
    c.delayed_send = 1;
    c.tag = this->tag * 100 + 5;
    m_f.set_block_dimx(1);
    m_f.set_block_dimy(1);
    m_f.dirtybit = 1;
    m_f.delayed_send = 1;
    m_f.tag = this->tag * 100 + 6;
    gamma.set_block_dimx(1);
    gamma.set_block_dimy(1);
    gamma.dirtybit = 1;
    gamma.delayed_send = 1;
    gamma.tag = this->tag * 100 + 7;
    mu.set_block_dimx(1);
    mu.set_block_dimy(1);
    mu.dirtybit = 1;
    mu.delayed_send = 1;
    mu.tag = this->tag * 100 + 8;
    m_alpha.set_block_dimx(1);
    m_alpha.set_block_dimy(1);
    m_alpha.dirtybit = 1;
    m_alpha.delayed_send = 1;
    m_alpha.tag = this->tag * 100 + 9;
    tempg.set_block_dimx(1);
    tempg.set_block_dimy(this->m_A->get_block_dimy());
    tempg.dirtybit = 1;
    tempg.delayed_send = 1;
    tempg.tag = this->tag * 100 + 11;
    tempu.set_block_dimx(1);
    tempu.set_block_dimy(this->m_A->get_block_dimy());
    tempu.dirtybit = 1;
    tempu.delayed_send = 1;
    tempu.tag = this->tag * 100 + 12;
    temp.set_block_dimx(1);
    temp.set_block_dimy(this->m_A->get_block_dimy());
    temp.dirtybit = 1;
    temp.delayed_send = 1;
    temp.tag = this->tag * 100 + 13;
    beta_idr.set_block_dimx(1);
    beta_idr.set_block_dimy(1);
    beta_idr.dirtybit = 1;
    beta_idr.delayed_send = 1;
    beta_idr.tag = this->tag * 100 + 15;
    t_idr.set_block_dimx(1);
    t_idr.set_block_dimy(this->m_A->get_block_dimy());
    t_idr.dirtybit = 1;
    t_idr.delayed_send = 1;
    t_idr.tag = this->tag * 100 + 16;
    h_chk.set_block_dimx(1);
    h_chk.set_block_dimy(this->m_A->get_block_dimy());
    h_chk.dirtybit = 1;
    h_chk.delayed_send = 1;
    h_chk.tag = this->tag * 100 + 17;
    s_chk.set_block_dimx(1);
    s_chk.set_block_dimy(1);
    s_chk.dirtybit = 1;
    s_chk.delayed_send = 1;
    s_chk.tag = this->tag * 100 + 18;
    svec_chk.set_block_dimx(1);
    svec_chk.set_block_dimy(1);
    svec_chk.dirtybit = 1;
    svec_chk.delayed_send = 1;
    svec_chk.tag = this->tag * 100 + 19;
    G.set_block_dimx(1);
    G.set_block_dimy(this->m_A->get_block_dimy());
    G.dirtybit = 1;
    G.delayed_send = 1;
    G.tag = this->tag * 100 + 20;
    U.set_block_dimx(1);
    U.set_block_dimy(this->m_A->get_block_dimy());
    U.dirtybit = 1;
    U.delayed_send = 1;
    U.tag = this->tag * 100 + 21;
    P.set_block_dimx(1);
    P.set_block_dimy(this->m_A->get_block_dimy());
    P.dirtybit = 1;
    P.delayed_send = 1;
    P.tag = this->tag * 100 + 22;
    M.set_block_dimx(1);
    M.set_block_dimy(1);
    M.dirtybit = 1;
    M.delayed_send = 1;
    M.tag = this->tag * 100 + 23;

    // Setup the preconditionner
    if (!no_preconditioner)
    {
        m_preconditioner->setup(*this->m_A, reuse_matrix_structure);
    }

    this->m_A->setView(oldView);
}

template<class T_Config>
void
IDRMSYNC_Solver_Base<T_Config>::solve_init( VVector &b, VVector &x, bool xIsZero )
{
    AMGX_CPU_PROFILER( "IDRMSYNC_Solver::solve_init " );
    int s;
    int offset, size, N;
    Operator<T_Config> &A = *this->m_A;
    ViewType oldView = A.currentView();
    A.setViewExterior();
    A.getOffsetAndSizeForView(A.getViewExterior(), &offset, &size);
    N = A.get_num_rows();
    s = this->s;
    /// to check on the host a sequential version comment these two lines.
    this->numprox = 1;
    this->pid = 0;
#ifdef AMGX_WITH_MPI

    if (A.is_matrix_distributed())
    {
        this->pid = A.getManager()->global_id();
        this->numprox = A.getManager()->get_num_partitions();
    }

#endif
    // G and U are with zeroes
    // M is identity
    fill(h_chk, (ValueTypeB)0, 0, N * s);
    fill(G, (ValueTypeB)0, 0, N * s);
    fill(U, (ValueTypeB)0, 0, N * s);
    fill(P, (ValueTypeB)0, 0, N * s);
    fill(tempg, (ValueTypeB)0, 0, N);
    fill(tempu, (ValueTypeB)0, 0, N);
    fill(temp, (ValueTypeB)0, 0, N);
    fill(s_chk, (ValueTypeB)0, 0, s * s);
    fill(svec_chk, (ValueTypeB)0, 0, s);
    fill(t_idr, (ValueTypeB)0, 0, N);
    fill(m_f, (ValueTypeB)0, 0, s);
    fill(m_alpha, (ValueTypeB)0, 0, s);
    fill(gamma, (ValueTypeB)0, 0, s);
    fill(mu, (ValueTypeB)0, 0, s);
    fill(c, (ValueTypeB)0, 0, s);
    fill(m_v, (ValueTypeB)0, 0, N);
    setup_arrays(P, M, b, x, h_chk, s, N, this->pid);
    this->omega = (ValueTypeB) 1;
    A.setView(oldView);
}

template<class T_Config>
AMGX_STATUS
IDRMSYNC_Solver_Base<T_Config>::solve_iteration( VVector &b, VVector &x, bool xIsZero )
{
    AMGX_CPU_PROFILER( "IDRMYSNC_Solver::solve_iteration " );

    AMGX_STATUS conv_stat = AMGX_ST_NOT_CONVERGED;

    Operator<T_Config> &A = *this->m_A;
    ViewType oldView = A.currentView();
    A.setViewExterior();
    bool transposed = false;
    int offset, s, k, N, size;
    ValueTypeB alpha_blas(1), malpha_blas(-1), beta_blas(0);
    ValueTypeB beta, ns, nt, ts, rho, angle(0.7);
    A.getOffsetAndSizeForView(A.getViewExterior(), &offset, &size);
    N = A.get_num_rows();
    s = this->s;
    // f = (r'*P)'; // phi=Q'*r
    transposed = true;
    dot_parts_and_scatter(transposed, *this->m_r, P, m_f, svec_chk, N, this->s, this->numprox, this->pid, 0);
    transposed = false;

    // solving the small system  and making v orth. to P
    for (k = 0; k < s; k++)
    {
        // gamma= M(k:s,k:s)\f(k:s); trsv_v2
        // similar to IDR begins
        copy_ext(m_f, gamma, k, 0, s - k );
        trsv_extnd(transposed, M, s, gamma, s - k, 1, k + s * k);
        // v = r - G(:,k:s)*gamma; dense matvec then vector update
        gemv_extnd(transposed, G, gamma, temp, N, s - k, alpha_blas, beta_blas, 1, 1, N, k * N, 0, 0);
        axpby(*this->m_r, temp, m_v, alpha_blas, malpha_blas, 0, N);

        if (no_preconditioner) {    ;    }
        else
        {
            m_z.delayed_send = 1;
            m_v.delayed_send = 1;
            m_preconditioner->solve( m_v, m_z, true );
            m_z.delayed_send = 1;
            m_z.delayed_send = 1;
            copy(m_z, m_v, 0, N);
        }

        // U(:,k) = U(:,k:s)*c + om*v; matvec + axpy
        gemv_extnd(transposed, U, gamma, U, N, s - k, alpha_blas, beta_blas, 1, 1, N, k * N, 0, k * N);
        axpy(m_v, U, this->omega, 0, k * N, N);
        // G(:,k) = A*U(:,k); matvec
        copy_ext(U, tempu, k * N, 0, N);
        cudaDeviceSynchronize();
        A.apply(tempu, tempg);
        copy_ext(tempg, G, 0, k * N, N);
        // Bi-Orthogonalise the new basis vectors:
        // P'*g_k
        transposed = true;
        dot_parts_and_scatter(transposed, G, P, mu, svec_chk, N, this->s, this->numprox, this->pid, k * N);
        transposed = false;

        if (k > 0)
        {
            copy_ext(mu, m_alpha, 0, 0, k );
            trsv_extnd(transposed, M, s, m_alpha, k, 1, 0);
            gemv_extnd(transposed, G, m_alpha, G, N, k, malpha_blas, alpha_blas, 1, 1, N, 0, 0, k * N);
            gemv_extnd(transposed, U, m_alpha, U, N, k, malpha_blas, alpha_blas, 1, 1, N, 0, 0, k * N);
            gemv_extnd(transposed, M, m_alpha, mu, s - k, k, malpha_blas, alpha_blas, 1, 1, s, k, 0, k);
        }

        copy_ext(mu, M, k, k * s + k, s - k);
        divide_for_beta(m_f, M, beta_idr, &beta, k, s);

        if (beta == (ValueTypeB)0)
        {
            FatalError("M(k,k)=0 breakdown condition (beta):IDRMSYNC", AMGX_ERR_INTERNAL);
        }

        // r = r - beta*G(:,k);
        axpy(G, *this->m_r, -beta, k * N, 0, N);
        // x = x + beta*U(:,k);
        axpy(U, x, beta, k * N, 0, N);
        // Do we converge ?
        this->m_curr_iter = this->m_curr_iter + 1;

        if ( this->m_monitor_convergence &&
             isDone( conv_stat = this->compute_norm_and_converged() ) )
        {
            A.setView(oldView);
            return conv_stat;
        }

        //Early exit: last iteration, no need to prepare the next one.
        if ( this->is_last_iter() )
        {
            A.setView(oldView);
            return this->m_monitor_convergence ? AMGX_ST_NOT_CONVERGED : AMGX_ST_CONVERGED;
        }

        // New f = P'*r (first k  components are zero)
        // if ( k < s )
        //     f(k+1:s)   = f(k+1:s) - beta*M(k+1:s,k);
        // end
        if (k < s - 1)
        {
            axpy(M, m_f, -beta, k * s + k + 1, k + 1, s - k - 1);
        }
    }/// for ends for smaller space

    //check for convergence once again. If converged just leave the function
    if ( this->m_monitor_convergence &&
         isDone( conv_stat = this->compute_norm_and_converged() ) )
    {
        A.setView(oldView);
        return conv_stat;
    }

    copy( *this->m_r, m_v, 0, N);

    if (no_preconditioner)
    {
        ;
    }
    else
    {
        m_z.delayed_send = 1;
        m_v.delayed_send = 1;
        m_preconditioner->solve( m_v, m_z, true );
        m_z.delayed_send = 1;
        m_v.delayed_send = 1;
        copy( m_z, m_v, 0, N);
    }

    A.apply(m_v, t_idr );
    // calculate new omega
    ns = get_norm(A, *this->m_r, L2); // distributed norm
    nt = get_norm(A, t_idr, L2); //distributed norm
    ts = dot(A, t_idr, *this->m_r); // distributed dot.
    rho = abs(ts / (nt * ns));
    this->omega = ts / (nt * nt);

    if (rho < angle)
    {
        this->omega = this->omega * angle / rho;
    }

    if (this->omega == (ValueTypeB) 0)
    {
        std::cout << "Error happened in this->omega==0" << std::endl;
        exit(1);
    }

    // r = r - omega*t;
    axpy( t_idr, *this->m_r, -(this->omega), 0, N );
    axpy( m_v, x, this->omega, 0, N );
    // No convergence so far.
    A.setView(oldView);
    return this->m_monitor_convergence ? AMGX_ST_NOT_CONVERGED : AMGX_ST_CONVERGED;
}

template<class T_Config>
void
IDRMSYNC_Solver_Base<T_Config>::solve_finalize( VVector &b, VVector &x )
{}

template<class T_Config>
void
IDRMSYNC_Solver_Base<T_Config>::printSolverParameters() const
{
    if (!no_preconditioner)
    {
        std::cout << "preconditioner: " << this->m_preconditioner->getName()
                  << " with scope name: "
                  << this->m_preconditioner->getScope() << std::endl;
    }
}


template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> >::dot_ina_loop(const VVector &a, const VVector &b, int offseta, int offsetb, VVector &res, VVector &hres, int offsetres, int size, int k, int s)
{
    int i;

    for (i = k; i < s; i++)
    {
        hres.raw()[i + offsetres] = dotc(a, b, offseta + i * size, offsetb, size);
    }
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::dot_ina_loop(const VVector &a, const VVector &b, int offseta, int offsetb, VVector &res, Vector_h &hres,  int offsetres, int size, int k, int s)
{
    int i;

    for (i = k; i < s; i++)
    {
        hres.raw()[i + offsetres] = dotc(a, b, offseta + i * size, offsetb, size);
    }

    cudaMemcpy((void *) res.raw(),       (void *) hres.raw(),       (s - k)*sizeof(ValueTypeB),   cudaMemcpyHostToDevice);
}
template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::divide_for_beta(VVector &nume, VVector &denom, VVector &Result, ValueTypeB *hresult, int k, int s)
{
    ValueTypeB nume_h, denom_h;
//
    cudaMemcpy((void *) &denom_h,
               (void *) & (denom.raw()[k * s + k]),
               sizeof(ValueTypeB),   cudaMemcpyDeviceToHost);

    if (denom_h != (ValueTypeB) 0)
    {
        cudaMemcpy((void *) &nume_h,
                   (void *) & (nume.raw()[k]),
                   sizeof(ValueTypeB),   cudaMemcpyDeviceToHost);
        *hresult = (ValueTypeB) nume_h / (ValueTypeB)denom_h;
    }
    else
    {
        *hresult = (ValueTypeB) 0;
    }
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> >::divide_for_beta(VVector &nume, VVector &denom, VVector &Result, ValueTypeB *hresult, int k, int s)
{
    if ((denom.raw()[k * s + k]) != (ValueTypeB) 0)
    {
        *hresult = (ValueTypeB) (nume.raw()[k]) / (ValueTypeB)(denom.raw()[k * s + k]);
    }
    else
    {
        *hresult = (ValueTypeB) 0;
    }
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver< TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::dot_parts_and_scatter(bool transposed, VVector &a, VVector &b, VVector &result, Vector_h &hresult,
        int size, int s, int numprox, int pid, int offsetvec)
{
    Matrix<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> > *Aptr =  dynamic_cast<Matrix<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> > * >(this->m_A);
#ifdef AMGX_WITH_MPI
    Matrix<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> > &A   = *Aptr;
#endif

    if ( !Aptr )  //not a matrix!
    {
        FatalError("IDRMSync only works with explicit matrices.", AMGX_ERR_INTERNAL);
    }

    for (int j = 0; j < s; j++)
    {
        hresult.raw()[j] = dotc(b, a, j * size, offsetvec, size);
    }

    if (numprox > 1)  // more than one processor
    {
        //now result vector must be aggregated across all processors
#ifdef AMGX_WITH_MPI
        Vector_h tresult(hresult);
        A.manager->getComms()->global_reduce_sum(hresult, tresult, A, 0);
#endif
    }// else ends for more than one processor

    cudaMemcpy((void *)result.raw(), (void *)hresult.raw(), s * sizeof(ValueTypeB), cudaMemcpyHostToDevice);
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> >::dot_parts_and_scatter(bool transposed, VVector &a, VVector &b, VVector &result, VVector &hresult,
        int size, int s, int numprox, int pid, int offsetvec)
{
    Matrix<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> > *Aptr =  dynamic_cast<Matrix<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> > * >(this->m_A);
#ifdef AMGX_WITH_MPI
    Matrix<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> > &A   = *Aptr;
#endif

    if ( !Aptr )  //not a matrix!
    {
        FatalError("IDRMSync only works with explicit matrices.", AMGX_ERR_INTERNAL);
    }

    for (int j = 0; j < s; j++)
    {
        hresult.raw()[j] = dotc(b, a, j * size, offsetvec, size);
    }

    if (numprox > 1)  // more than one processor
    {
        //now result vector must be aggregated across all processors
#ifdef AMGX_WITH_MPI
        VVector tresult(hresult);
        A.manager->getComms()->global_reduce_sum(hresult, tresult, A, 0); // tag is not important for allreduce
#endif
    }// else ends for more than one processor
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::gemv_div(bool trans, const VVector &A, const VVector &x, VVector &y, int m, int n,
        ValueTypeB alpha, ValueTypeB beta, int incx, int incy, int lda,
        int offsetA, int offsetx, int offsety, VVector &nume, int k, int s, ValueTypeB *ratio)
{
    ValueTypeB numer, denom;//, dotval;
    gemv_extnd(trans, A, x, y, m, n, alpha, beta, incx, incy, lda, offsetA, offsetx, offsety);
    cudaDeviceSynchronize();
    cudaMemcpy((void *) &numer,
               (void *) & ((nume.raw())[k]),
               sizeof(ValueTypeB),   cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();
    cudaMemcpy((void *) &denom, (void *) & (y.raw())[k + s * k],  sizeof(ValueTypeB),   cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();

    if (denom != (ValueTypeB) 0)
    {
        *ratio = numer / denom;
    }
    else
    {
        *ratio = (ValueTypeB) 0;
    }
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> >::gemv_div(bool trans, const VVector &A, const VVector &x, VVector &y, int m, int n,
        ValueTypeB alpha, ValueTypeB beta, int incx, int incy, int lda,
        int offsetA, int offsetx, int offsety, VVector &nume, int k, int s, ValueTypeB *ratio)
{
    ValueTypeB beta_iter;
    gemv_extnd(trans, A, x, y, m, n, alpha, beta, incx, incy, lda, offsetA, offsetx, offsety);

    if (y[k + s * k] != (ValueTypeB)0)
    {
        beta_iter = (nume)[k] / (y)[k + s * k];
        *ratio = beta_iter;
    }
    else
    {
        *ratio = (ValueTypeB) 0;
    }
}


template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
typename IDRMSYNC_Solver< TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::ValueTypeB
IDRMSYNC_Solver<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::dotc_div(VVector &a, VVector &b, int offseta, int offsetb, int size, VVector &denom, int i, int s, ValueTypeB *ratio)
{
    ValueTypeB dnr;
    cudaMemcpy((void *) &dnr, (void *) & (denom.raw())[i + s * i],  sizeof(ValueTypeB),   cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();

    if (dnr != (ValueTypeB) 0)
    {
        *ratio = dotc(a, b, offseta, offsetb, size) / dnr;
    }
    else
    {
        *ratio = (ValueTypeB) 0;
    }

    return dnr;
}


template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
typename IDRMSYNC_Solver< TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> > ::ValueTypeB
IDRMSYNC_Solver<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> >::dotc_div(VVector &a, VVector &b, int offseta, int offsetb, int size, VVector &denom, int i, int s, ValueTypeB *ratio)
{
    ValueTypeB alpha_iter;

    if (denom[i * s + i] != (ValueTypeB) 0)
    {
        alpha_iter = dotc(a, b, offseta, offsetb, size) / denom[i * s + i];
        *ratio = alpha_iter;
    }
    else
    {
        *ratio = (ValueTypeB) 0;
    }

    return alpha_iter;
}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_device, t_vecPrec, t_matPrec, t_indPrec> >::setup_arrays(VVector &P, VVector &M, VVector &b, VVector &x, Vector_h &hbuff,
        int s, int N, int pid)
{
    int i;

    for (i = 0; i < s; i++) { (hbuff.raw())[i * s + i] = (ValueTypeB) 1.0; }

    cudaMemcpy((void *)M.raw(), (void *)hbuff.raw(), s * s * sizeof(ValueTypeB), cudaMemcpyHostToDevice);
    srand(0);

    for (i = 0; i < N * s; i++)
    {
        (hbuff.raw())[i] = (ValueTypeB) rand() / (ValueTypeB (RAND_MAX));
    }
    
    cudaMemcpy((void *)P.raw(), (void *)hbuff.raw(), N * s * sizeof(ValueTypeB), cudaMemcpyHostToDevice);

}

template <AMGX_VecPrecision t_vecPrec, AMGX_MatPrecision t_matPrec, AMGX_IndPrecision t_indPrec>
void IDRMSYNC_Solver<TemplateConfig<AMGX_host, t_vecPrec, t_matPrec, t_indPrec> >::setup_arrays(VVector &P, VVector &M, VVector &b, VVector &x, VVector &hbuff,
        int s, int N, int pid)
{
    int i;

    for (i = 0; i < s; i++) { (M.raw())[i * s + i] = (ValueTypeB) 1.0; }

    srand(0);

    for (i = 0; i < N * s; i++)
    {
        (hbuff.raw())[i] = (ValueTypeB) rand() / (ValueTypeB (RAND_MAX));
    }
}
/****************************************
 * Explict instantiations
 ***************************************/
#define AMGX_CASE_LINE(CASE) template class IDRMSYNC_Solver_Base<TemplateMode<CASE>::Type>;
AMGX_FORALL_BUILDS(AMGX_CASE_LINE)
#undef AMGX_CASE_LINE

#define AMGX_CASE_LINE(CASE) template class IDRMSYNC_Solver<TemplateMode<CASE>::Type>;
AMGX_FORALL_BUILDS(AMGX_CASE_LINE)
#undef AMGX_CASE_LINE
}
} // namespace amgx
