using DiffEqBase, OrdinaryDiffEq, ParameterizedFunctions, ForwardDiff

export ContinuousDynamicalSystem, DiscreteDynamicalSystem,
odeproblem, update!, evolve!


#######################################################################################
#                                     Constructors                                    #
#######################################################################################
"""
    ContinuousDynamicalSystem <: DynamicalSystem
# Fields:
* `u::AbstractVector` : Current state-vector of the system (initialized as the
  initial conditions).
* `J::AbstractMatrix` : Jacobian matrix of the e.o.m. at the current `u`.
* `eom!::Function` : The function representing the equations of motion in an
  **autonomous and in-place form**, in the Julia stylistic syntax:
  `eom!(du, u)`. If your system is non-autonomous, simply make it autonomous by
  extending the dimensionality by one, introducing a new variable `τ = t` such that
  `dτ/dt = 1`.
* `jacobian!::Function` : An in-place function `jacobian!(J, u)` that given a
  state-vector calculates the corresponding Jacobian of the vector-field (e.o.m.)
  and writes it in-place for `J`.
# Constructors:
If you have an already defined function for the `jacobian!`, please use the first
constructor. The other constructors do automatic calculation of the Jacobian function
(and matrix):
1. `ContinuousDynamicalSystem(u0, eom!::Function, jacobian!::Function)`
  creates a system with user-provided functions for the equations of motion and the
  Jacobian of them (most efficient).
2. `ContinuousDynamicalSystem(u0, eom!::Function)`
  uses the package `ForwardDiff` for automatic (numeric) forward
  differentiation to calculate the `jacobian!` function.
3. `ContinuousDynamicalSystem(u0, f::AbstractParameterizedFunction)`
  uses the package `ParameterizedFunctions` to perform a symbolic computation of the
  `jacobian!` function. This is more efficient than the 2nd constructor, but
  it is still not as efficient as the 1st one.
"""
struct ContinuousDynamicalSystem <: DynamicalSystem
  u::AbstractVector
  J::AbstractMatrix
  eom!::Function
  jacobian!::Function
end

function ContinuousDynamicalSystem(
  u0::AbstractVector, eom::Function, jac::Function)
  j = zeros(eltype(u0), (length(u0), length(u0)))
  jac(j, u0)
  ContinuousDynamicalSystem(u0, j, eom, jac)
end

function ContinuousDynamicalSystem(u0::AbstractVector, f!::Function)
  jacob! = (J, u) -> ForwardDiff.jacobian!(J, f!, zeros(length(u)), u)
  J = zeros(eltype(u0), (length(u0), length(u0)))
  jacob!(J, u0)
  ContinuousDynamicalSystem(u0, J, f!, jacob!)
end

function ContinuousDynamicalSystem(u0, f::AbstractParameterizedFunction)
  J = zeros(eltype(u0), (length(u0), length(u0)))
  jacobian!(J, u) = f(Val{:jac},0.0,u,J)
  jacobian!(J, u0)
  eom!(du, u) = f(0.0, u, du)
  ContinuousDynamicalSystem(u0, J, eom!, jacobian!)
end


#######################################################################################
#                                 System Evolution                                    #
#######################################################################################
"""
```julia
odeproblem(system::ContinuousDynamicalSystem, t)
```
Return a type `ODEProblem` with the given system information (t0 is zero).
This can be passed directly into `solve` from `DifferentialEquations`.
"""
function odeproblem(system::ContinuousDynamicalSystem, t)
  t0 = zero(t)
  DiffEqBase.ODEProblem(diff_eq_f(system), system.u, (t0, t))
end
function diff_eq_f(system::ContinuousDynamicalSystem)
  f(t, u, du) = system.eom!(du, u)
end


"""
```julia
update!(system::ContinuousDynamicalSystem, u0::AbstractVector)
```
Update `system.u` and `system.J` based on given state `u0`.
"""
function update!(system::ContinuousDynamicalSystem, u0::AbstractArray)
  system.u .= u0;
  system.jacobian!(system.J, u0);
  return system
end


"""
```julia
evolve!(system::ContinuousDynamicalSystem, t::Real[, diff_eq_kwargs])
```
Evolve the `system` from the current state `system.u` for total time `t`.
Optionally you can pass a dictionary `Dict{Symbol, Any}` that will contain keyword
arguments passed into the `solve` of the `DifferentialEquations` package, like for
example `:abstol => 1e-9`. If you want to specify the solving algorithm,
do so by using `:solver` as one of your keywords.

**Do not** use this function if you want to get e.g. the time-series of the system's
variables! This function is used to evolve the system step-by-step and as a result
does not save any data of intermediate steps!
Instead use the `solve` interface of `DifferentialEquations` by taking
advantage of the function `odeproblem(system, tspan)`. E.g.:
```julia
using DiffEqBase #defines the `solve` and `ODEProblem` interfaces
using OrdinaryDiffEq #contains solver algorithms and keywords for `solve`
sol = solve(odeproblem(system, t), TsitPap8(), dense=false, saveat=0.01)
```
"""
function evolve!(system::ContinuousDynamicalSystem, t::Real)
  prob = odeproblem(system, t)
  sol = solve(prob, Tsit5(); save_everystep=false)
  update!(system, sol[end])
end
function evolve!(system::ContinuousDynamicalSystem, t::Real, diff_eq_kwargs::Dict)

  prob = odeproblem(system, t)
  if haskey(diff_eq_kwargs, :solver)
    solver = diff_eq_kwargs[:solver]
    pop!(diff_eq_kwargs, :solver)
    if length(diff_eq_kwargs) == 0
      sol = solve(prob, solver; save_everystep=false)
    else
      sol = solve(prob, solver; diff_eq_kwargs..., save_everystep=false)
    end
  else
    sol = solve(prob, Tsit5(); diff_eq_kwargs..., save_everystep=false)
  end
  update!(system, sol[end])
end