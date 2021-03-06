!-----------------------------------------------------------------------------
! Copyright (c) 2017,  Met Office, on behalf of HMSO and Queen's Printer
! For further details please refer to the file LICENCE.original which you
! should have received as part of this distribution.
!-----------------------------------------------------------------------------
!
!-------------------------------------------------------------------------------

!> @brief Kernel which applies the inverse of a columnwise assembled operator
!>
!> @detail Given a field \f$x\f$, this calculates \f$y+=A^{-1}x\f$, i.e.
!> solves \f$A\delta y=x\f$ for \f$\delta y\f$ and adds this to \f$y\f$.
!> Only works if the assembled matrix is square and tridiagonal, and the 
!> Thomas algorithm can be used. The PSY layer should check whether the
!> matrix has the correct properties.
!>
!> Reference for Thomas algorithm:
!>   Numerical Recipes, Second Edition, CAMBRIDGE UNIVERSITY PRESS (1992)

module columnwise_op_appinv_kernel_mod

use kernel_mod,              only : kernel_type
use argument_mod,            only : arg_type, func_type,                    &
                                    GH_FIELD, GH_COLUMNWISE_OPERATOR,       &
                                    GH_READ, GH_WRITE,                      &
                                    ANY_SPACE_1,                            &
                                    GH_COLUMN_INDIRECTION_DOFMAP,           &
                                    CELLS 

use constants_mod,           only : r_def, i_def

implicit none

!-------------------------------------------------------------------------------
! Public types
!-------------------------------------------------------------------------------

type, public, extends(kernel_type) :: columnwise_op_appinv_kernel_type
  private
  type(arg_type) :: meta_args(3) = (/                                      &
       arg_type(GH_FIELD,    GH_WRITE, ANY_SPACE_1),                       &
       arg_type(GH_FIELD,    GH_READ,  ANY_SPACE_1),                       &
       arg_type(GH_COLUMNWISE_OPERATOR, GH_READ, ANY_SPACE_1, ANY_SPACE_1) &
       /)
  integer :: iterates_over = CELLS
contains
  procedure, nopass :: columnwise_op_appinv_kernel_code
end type columnwise_op_appinv_kernel_type

!-------------------------------------------------------------------------------
! Constructors
!-------------------------------------------------------------------------------

! overload the default structure constructor for function space
interface columnwise_op_appinv_kernel_type
   module procedure columnwise_op_appinv_kernel_constructor
end interface

!-------------------------------------------------------------------------------
! Contained functions/subroutines
!-------------------------------------------------------------------------------
public columnwise_op_appinv_kernel_code
contains
  
  type(columnwise_op_appinv_kernel_type) function columnwise_op_appinv_kernel_constructor() result(self)
    implicit none
    return
  end function columnwise_op_appinv_kernel_constructor

  !> @brief The subroutine which is called directly from the PSY layer and
  !> applies the operator as lhs += A^{-1}.x
  !>
  !> @param [in] cell the horizontal cell index
  !> @param [in] ncell_2d number of cells in 2d grid
  !> @param [inout] lhs Resulting field lhs += A^{-1}.x
  !> @param [in] x input field
  !> @param [in] columnwise_matrix banded matrix to assemble into
  !> @param [in] nrow number of rows (and columns) in the banded matrix
  !> @param [in] bandwidth bandwidth of the banded matrix
  !> @param [in] alpha banded matrix parameter \f$\alpha\f$
  !> @param [in] beta banded matrix parameter \f$\beta\f$
  !> @param [in] gamma_m banded matrix parameter \f$\gamma_-\f$
  !> @param [in] gamma_p banded matrix parameter \f$\gamma_+\f$
  !> @param [in] ndf number of degrees of freedom per cell for function space
  !> @param [in] undf unique number of degrees of freedom  for function space
  !> @param [in] map dofmap for the function space
  !> @param [in] indirection_dofmap_ indirection map for function space
  subroutine columnwise_op_appinv_kernel_code(cell,                    &
                                              ncell_2d,                &
                                              lhs, x,                  & 
                                              columnwise_matrix,       &
                                              nrow,                    &
                                              bandwidth,               &
                                              alpha,                   &
                                              beta,                    &
                                              gamma_m,                 &
                                              gamma_p,                 &
                                              ndf, undf, map,          &
                                              indirection_dofmap)
    implicit none
    
    ! Arguments
    integer(kind=i_def), intent(in) :: cell, ncell_2d
    integer(kind=i_def), intent(in) :: nrow, bandwidth
    integer(kind=i_def), intent(in) :: undf, ndf
    real(kind=r_def), dimension(undf), intent(inout) :: lhs
    real(kind=r_def), dimension(undf), intent(in) :: x
    real(kind=r_def), dimension(bandwidth,nrow,ncell_2d), intent(in) :: columnwise_matrix
    integer(kind=i_def), dimension(ndf), intent(in) :: map

    integer(kind=i_def), intent(in) :: alpha, beta, gamma_m, gamma_p
    integer(kind=i_def), dimension(nrow), intent(in) :: indirection_dofmap

    ! Internal parameters
    integer(kind=i_def) :: i, mu_i ! Row and column index

    ! Arrays c' and d' used in Thomas algorithm
    real(kind=r_def), dimension(nrow) :: c_prime, d_prime
    ! inverse denominator
    real(kind=r_def) :: inv_denom
    
    ! Spurious instructions to avoid 'unused variable' warnings
    i = alpha + beta + gamma_m + gamma_p

    ! Step 1: Forward sweep, loop over all rows
    do i=1, nrow
       mu_i = map(1) + indirection_dofmap(i) - 1
       if (i == 1) then 
          ! First row
          inv_denom = 1.0_r_def/columnwise_matrix(2,i,cell)
          c_prime(i) = inv_denom * columnwise_matrix(3,i,cell)
          d_prime(i) = inv_denom * x(mu_i)
       else 
          ! Subsequent rows 2,...,nrow-1
          inv_denom = 1.0_r_def / ( columnwise_matrix(2,i,cell) &
                    - columnwise_matrix(1,i,cell) * c_prime(i-1) )
          if (i < nrow) then
             ! We don't need c' in the last row
             c_prime(i) = inv_denom * columnwise_matrix(3,i,cell)
          end if
          d_prime(i) = inv_denom * ( x(mu_i) &
                     - columnwise_matrix(1,i,cell) * d_prime(i-1) )
       end if
    end do
    ! Step 2: Backward sweep (substitution), loop over all rows backwards
    do i=nrow,1,-1
       ! Overwrite d' with solution and then copy to correct position in vector
       mu_i = map(1) + indirection_dofmap(i) - 1
       if (i<nrow) then 
          d_prime(i) = d_prime(i) - c_prime(i) * d_prime(i+1)
       end if
       lhs(mu_i) = d_prime(i)
    end do

  end subroutine columnwise_op_appinv_kernel_code

end module columnwise_op_appinv_kernel_mod
