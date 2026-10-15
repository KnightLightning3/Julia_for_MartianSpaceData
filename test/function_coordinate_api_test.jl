using Test
using LinearAlgebra
using StaticArrays
using Rotations

include(joinpath(@__DIR__, "..", "common", "function_coordinate.jl"))
using .FunctionCoordinate

# Load the four original coordinate implementations into an isolated module, directly
# from the requested baseline revision. This does not load MarsData or any model DLL.
# This round explicitly permits hypot-induced roundoff and extreme-value changes.
const baseline = "a09511aa7b88c874cefe8ca966c98aa267db9365"
const repo = normpath(joinpath(@__DIR__, ".."))
const original_fc = read(`git -C $(repo) show $(baseline):common/function_coordinate.jl`, String)
module OriginalFunctionCoordinate
using LinearAlgebra, StaticArrays, Rotations
end
function eval_baseline_function!(mod, source, signature, filename)
    found = findfirst(signature, source)
    @assert found !== nothing "baseline function not found: $signature"
    expr, _ = Meta.parse(source, first(found); raise=true)
    @assert expr isa Expr && expr.head === :function "baseline parse did not yield a function: $signature"
    Core.eval(mod, expr)
end
for name in ("pa_xyz2sphere", "pa_sphere2xyz", "MINPA_sphere2xyz", "MINPA_xyz2sphere")
    signature = "function " * name * "("
    eval_baseline_function!(OriginalFunctionCoordinate, original_fc, signature, "baseline_function_coordinate.jl")
end

# The baseline IGRF file lived under Magnetic_Model; extract only its two scalar
# coordinate functions into another isolated namespace.
const original_igrf = read(`git -C $(repo) show $(baseline):Magnetic_Model/IGRF_calculate.jl`, String)
module OriginalIGRFCoordinates
using LinearAlgebra
end
eval_baseline_function!(OriginalIGRFCoordinates, original_igrf,
    "function pc2sphere(x::Real, y::Real, z::Real)", "baseline_igrf_coordinates.jl")
eval_baseline_function!(OriginalIGRFCoordinates, original_igrf,
    "function sphere2pc(r::Real, θ::Real, ϕ::Real)", "baseline_igrf_coordinates.jl")

@testset "FunctionCoordinate static 3D API" begin
    @test !isdefined(FunctionCoordinate, :Quaternion_Rot)
    @test !isdefined(FunctionCoordinate, :Quaternion_Rot_reverse)

    # Axis conventions of the established pitch-angle and MINPA interfaces.
    @test pa_xyz2sphere(SVector(1.0, 0.0, 0.0)) ≈ SVector(1.0, 0.0, 0.0)
    @test pa_xyz2sphere(SVector(0.0, 1.0, 0.0)) ≈ SVector(1.0, 90.0, 0.0)
    @test pa_xyz2sphere(SVector(0.0, 0.0, 1.0)) ≈ SVector(1.0, 90.0, 90.0)
    @test pa_sphere2xyz(SVector(2.0, 90.0, 90.0)) ≈ SVector(0.0, 0.0, 2.0) atol=1e-14
    @test MINPA_sphere2xyz(SVector(2.0, 90.0, 0.0)) ≈ SVector(-2.0, 0.0, 0.0) atol=1e-14
    @test MINPA_xyz2sphere(SVector(0.0, 1.0, 0.0))[1] ≈ 1.0

    for (forward, reverse, points) in (
        (pa_xyz2sphere, pa_sphere2xyz, [SVector(1.2, -2.3, 4.5), SVector(-3.0, 1.0, 2.0)]),
        (MINPA_xyz2sphere, MINPA_sphere2xyz, [SVector(1.2, -2.3, 4.5), SVector(-3.0, 1.0, 2.0)]),
    )
        for p in points
            @test reverse(forward(p)) ≈ p atol=1e-12
        end
    end
    @test pa_xyz2sphere(SVector(0.0, 0.0, 0.0)) == SVector(0.0, 0.0, 0.0)
    @test pa_sphere2xyz(SVector(0.0, 20.0, 30.0)) == SVector(0.0, 0.0, 0.0)
    @test isequal(MINPA_xyz2sphere(SVector(0.0, 0.0, 0.0)), OriginalFunctionCoordinate.MINPA_xyz2sphere(SVector(0.0, 0.0, 0.0)))
    @test isequal(MINPA_xyz2sphere(SVector(1.0, 0.0, 0.0)), OriginalFunctionCoordinate.MINPA_xyz2sphere(SVector(1.0, 0.0, 0.0)))
    for T in (Float32, Float64)
        finite_edges = (SVector{3,T}(0, 0, 0), SVector{3,T}(1, 0, 0),
                        SVector{3,T}(1, floatmin(T), -floatmin(T)),
                        SVector{3,T}(1, eps(T), -eps(T)),
                        SVector{3,T}(1, nextfloat(zero(T)), nextfloat(zero(T))),
                        SVector{3,T}(1.4132073, 0.6580574, -0.30105034))
        for p in finite_edges
            actual = MINPA_xyz2sphere(p)
            expected = OriginalFunctionCoordinate.MINPA_xyz2sphere(p)
            @test all(isequal(actual[i], expected[i]) ||
                      (isfinite(actual[i]) && isfinite(expected[i]) &&
                       abs(actual[i] - expected[i]) <= eps(T) * max(one(T), abs(expected[i]))) for i in 1:3)
        end
        # The true norm is representable here, although squaring the components
        # overflows the baseline norm implementation.
        large = SVector{3,T}(floatmax(T) / 4, floatmax(T) / 4, 0)
        large_result = MINPA_xyz2sphere(large)
        @test isfinite(large_result[1])
        @test large_result[1] ≈ hypot(large...) rtol=eps(T)
        @test large_result[2] ≈ -45.0 atol=eps(T) * 90
        @test large_result[3] == 0.0

        # hypot gives Inf precedence over NaN; MINPA's following Inf/Inf ratios
        # are NaN. Assert each resulting component explicitly.
        for p in (SVector{3,T}(1, NaN, Inf), SVector{3,T}(1, Inf, NaN),
                  SVector{3,T}(1, -Inf, Inf), SVector{3,T}(NaN, 1, Inf))
            result = MINPA_xyz2sphere(p)
            @test isinf(result[1])
            @test isnan(result[2])
            @test isnan(result[3])
        end
        for p in (SVector{3,T}(1, NaN, Inf), SVector{3,T}(1, Inf, NaN))
            result = pa_xyz2sphere(p)
            @test isinf(result[1])
            @test result[2] == 90
            @test isnan(result[3])
        end
        pa_mixed = pa_xyz2sphere(SVector{3,T}(NaN, 1, Inf))
        @test isinf(pa_mixed[1])
        @test isnan(pa_mixed[2])
        @test pa_mixed[3] == 90
        pa_infinities = pa_xyz2sphere(SVector{3,T}(1, -Inf, Inf))
        @test isinf(pa_infinities[1])
        @test pa_infinities[2] == 90
        @test pa_infinities[3] == 135
    end
    @test isequal(pa_sphere2xyz(SVector(Inf, NaN, 2.0)),
                  OriginalFunctionCoordinate.pa_sphere2xyz(SVector(Inf, NaN, 2.0)))
    @test isequal(MINPA_sphere2xyz(SVector(Inf, NaN, 2.0)),
                  OriginalFunctionCoordinate.MINPA_sphere2xyz(SVector(Inf, NaN, 2.0)))

    funcs = (pa_xyz2sphere, pa_sphere2xyz, MINPA_sphere2xyz, MINPA_xyz2sphere)
    all_point_funcs = (pa_xyz2sphere, pa_sphere2xyz, MINPA_sphere2xyz,
                       MINPA_xyz2sphere, pc2sphere, sphere2pc)
    float_inputs = (SVector{3,Float64}(1.2, -2.3, 4.5),
                    SVector{3,Float64}(3.2, 47.0, -22.0),
                    SVector{3,Float64}(3.2, 110.0, 231.0),
                    SVector{3,Float64}(1.2, -2.3, 4.5),
                    SVector{3,Float64}(1.2, -2.3, 4.5),
                    SVector{3,Float64}(3.2, 1.1, -0.7))
    for (f, p) in zip(all_point_funcs, float_inputs)
        inferred = @inferred f(p)
        @test inferred isa SVector{3,Float64}
        mixed = Real[Float32(1), 2, 3//2]
        promoted = promote(mixed...)
        mixed_result = f(mixed)
        @test mixed_result isa SVector{3}
        @test isconcretetype(eltype(mixed_result)) && eltype(mixed_result) <: Real
        @test mixed_result == f(SVector(promoted...))
        @test_throws DimensionMismatch f(Real[1, 2])
        @test_throws DimensionMismatch f(Real[1, 2, 3, 4])
        @test_throws MethodError f(ones(3, 1))
    end
    baseline_funcs = (OriginalFunctionCoordinate.pa_xyz2sphere,
                      OriginalFunctionCoordinate.pa_sphere2xyz,
                      OriginalFunctionCoordinate.MINPA_sphere2xyz,
                      OriginalFunctionCoordinate.MINPA_xyz2sphere)
    values = (SVector(1.2, -2.3, 4.5), SVector(3.2, 47.0, -22.0),
              SVector(3.2, 110.0, 231.0), SVector(1.2, -2.3, 4.5))
    for (f, old, p) in zip(funcs, baseline_funcs, values)
        if f === pa_xyz2sphere || f === MINPA_xyz2sphere
            @test all(abs(f(p)[i] - old(p)[i]) <= eps(eltype(p)) * max(1.0, abs(old(p)[i])) for i in 1:3)
            @test all(abs(f(collect(p))[i] - old(p)[i]) <= eps(eltype(p)) * max(1.0, abs(old(p)[i])) for i in 1:3)
        else
            @test f(p) == old(p)
            @test f(collect(p)) == old(p)
        end
        @test typeof(f(p)) <: SVector{3}
        @test typeof(f(collect(p))) <: SVector{3}
        mapped = f.([p, p])
        if f === pa_xyz2sphere || f === MINPA_xyz2sphere
            @test all(all(abs(mapped[j][i] - old(p)[i]) <= eps(eltype(p)) * max(1.0, abs(old(p)[i])) for i in 1:3) for j in 1:2)
        else
            @test mapped == [old(p), old(p)]
        end
    end
    rows = [1.0 2.0 3.0; -2.0 4.0 1.0; 0.5 -1.0 2.5]
    @test [pa_xyz2sphere(SVector(rows[i, 1], rows[i, 2], rows[i, 3])) for i in axes(rows, 1)] ==
          pa_xyz2sphere.(eachrow(rows))

    # The general planetary spherical coordinates use radians and colatitude.
    @test pc2sphere(SVector(1.0, 0.0, 0.0)) ≈ SVector(1.0, π / 2, 0.0)
    @test pc2sphere(SVector(0.0, 1.0, 0.0)) ≈ SVector(1.0, π / 2, π / 2)
    @test pc2sphere(SVector(0.0, 0.0, 1.0)) ≈ SVector(1.0, 0.0, 0.0)
    @test sphere2pc(SVector(2.0, π / 2, 0.0)) ≈ SVector(2.0, 0.0, 0.0) atol=1e-14
    for p in (SVector(1.2, -2.3, 4.5), SVector(-3.0, 1.0, 2.0))
        @test sphere2pc(pc2sphere(p)) ≈ p atol=1e-12
        @test pc2sphere(collect(p)) == pc2sphere(p)
        @test sphere2pc(collect(pc2sphere(p))) == sphere2pc(pc2sphere(p))
        @test pc2sphere(p) == SVector(OriginalIGRFCoordinates.pc2sphere(p...))
        @test sphere2pc(pc2sphere(p)) ≈ SVector(OriginalIGRFCoordinates.sphere2pc(OriginalIGRFCoordinates.pc2sphere(p...)...)) atol=1e-12
    end
    @test isequal(pc2sphere(SVector(0.0, 0.0, 0.0)), SVector(OriginalIGRFCoordinates.pc2sphere(0.0, 0.0, 0.0)))
    for p in (SVector(Inf, 1.0, 2.0), SVector(NaN, -Inf, 0.0))
        @test isequal(pc2sphere(p), SVector(OriginalIGRFCoordinates.pc2sphere(p...)))
    end
    for p in (SVector(Inf, 1.1, 0.2), SVector(NaN, -0.7, 0.0))
        @test isequal(sphere2pc(p), SVector(OriginalIGRFCoordinates.sphere2pc(p...)))
    end
    @test_throws DomainError sphere2pc(SVector(1.0, -Inf, 0.0))
    @test_throws DomainError OriginalIGRFCoordinates.sphere2pc(1.0, -Inf, 0.0)
    @test pc2sphere.(eachrow(rows)) == [pc2sphere(SVector(rows[i, :]...)) for i in axes(rows, 1)]

    q = Rotations.QuatRotation(Rotations.RotZ(0.37) * Rotations.RotX(-0.22))
    v = SVector(1.0, -2.0, 0.5)
    @test q isa QuatRotation
    @test q * v isa SVector{3}
    @test inv(q) * (q * v) isa SVector{3}
    @test inv(q) * (q * v) ≈ v atol=1e-12
    @test slice2d_cal_rot(SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0)) isa RotMatrix{3}
    @test size(rotation_matrix(0.2, -0.4)) == (3, 3)
end
