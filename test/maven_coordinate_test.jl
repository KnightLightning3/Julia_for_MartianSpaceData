using Test
using StaticArrays
using MarsData

# Load the coordinate module in isolation: it must not manufacture MarsCommon or
# constants as nested dependencies.
module MAVENCoordinateFixture
using LinearAlgebra
using StaticArrays
using Rotations
include(joinpath(@__DIR__, "..", "common", "function_coordinate.jl"))
end
const FC = MAVENCoordinateFixture.FunctionCoordinate

# Load the complete historical source from git, parse it, and evaluate only the
# two legacy definitions in a separate module. This keeps the oracle independent
# from both the current implementation and the package loader.
module MAVENCoordinateOracle
using StaticArrays
end
const MAVEN_COORDINATE_BASELINE = "a09511aa7b88c874cefe8ca966c98aa267db9365"
const MAVEN_COORDINATE_ROOT = normpath(joinpath(@__DIR__, ".."))
const MAVEN_COORDINATE_SOURCE = read(
    `git -C $MAVEN_COORDINATE_ROOT show $MAVEN_COORDINATE_BASELINE:common/MarsCommon.jl`, String)

function extract_legacy_function!(target::Module, node, name::Symbol)
    found = 0
    extracted = nothing
    function visit(expr)
        if expr isa Expr
            if expr.head === :function && !isempty(expr.args)
                signature = expr.args[1]
                if signature isa Expr && signature.head === :call && signature.args[1] === name
                    extracted = Core.eval(target, expr)
                    found += 1
                    return
                end
            end
            foreach(visit, expr.args)
        end
    end
    visit(node)
    found == 1 || error("Expected one historical definition of $name, found $found")
    return extracted
end

const MAVEN_LEGACY_AST = Meta.parseall(MAVEN_COORDINATE_SOURCE)
const old_maven_sphere2xyz = extract_legacy_function!(
    MAVENCoordinateOracle, MAVEN_LEGACY_AST, :instrument_sphere_to_cartesian)
const old_maven_xyz2sphere = extract_legacy_function!(
    MAVENCoordinateOracle, MAVEN_LEGACY_AST, :instrument_cartesian_to_sphere)

@testset "MAVEN coordinate functions moved to FunctionCoordinate" begin
    @test !isdefined(FC, :MarsCommon)
    @test !isdefined(FC, :constants)
    @test !isdefined(MAVENCoordinateFixture, :MarsCommon)
    @test !isdefined(MarsData.MarsCommon, :instrument_sphere_to_cartesian)
    @test !isdefined(MarsData.MarsCommon, :instrument_cartesian_to_sphere)

    @testset "baseline formulas and inverse" begin
        for T in (Float64, Float32)
            tol = 100eps(T)
            for p in (SVector{3,T}(1, 0, 0), SVector{3,T}(2, 30, 45),
                      SVector{3,T}(4.25, -17.5, 123.0))
                got = FC.MAVEN_sphere2xyz(p)
                expected = old_maven_sphere2xyz(p...)
                @test got == expected
                @test FC.MAVEN_xyz2sphere(got) ≈ old_maven_xyz2sphere(got...) rtol=tol atol=tol
                @test FC.MAVEN_sphere2xyz(FC.MAVEN_xyz2sphere(got)) ≈ got rtol=tol atol=tol
            end
        end
    end

    @testset "axes and distinct MINPA convention" begin
        @test FC.MAVEN_sphere2xyz(SVector(1.0, 0.0, 0.0)) ≈ SVector(1.0, 0.0, 0.0)
        @test FC.MAVEN_sphere2xyz(SVector(1.0, 90.0, 0.0)) ≈ SVector(0.0, 0.0, 1.0) atol=1e-15
        @test FC.MINPA_sphere2xyz(SVector(1.0, 0.0, 0.0)) ≈ SVector(0.0, 1.0, 0.0) atol=1e-15
        @test FC.MAVEN_sphere2xyz(SVector(1.0, 0.0, 0.0)) != FC.MINPA_sphere2xyz(SVector(1.0, 0.0, 0.0))

        same_xyz = SVector(1.0, 0.0, 0.0)
        maven_sphere = FC.MAVEN_xyz2sphere(same_xyz)
        @test maven_sphere ≈ old_maven_xyz2sphere(same_xyz...)
        @test maven_sphere != FC.MINPA_xyz2sphere(same_xyz)
    end

    @testset "vector adapters, broadcasting, and rejected shapes" begin
        v = [2.0, 30.0, 45.0]
        @test FC.MAVEN_sphere2xyz(v) ≈ FC.MAVEN_sphere2xyz(SVector{3}(v))
        xyz = [FC.MAVEN_sphere2xyz(SVector(1.0, 10.0, 20.0)),
               FC.MAVEN_sphere2xyz(SVector(2.0, 30.0, 40.0))]
        @test FC.MAVEN_xyz2sphere.(xyz) isa Vector
        @test_throws DimensionMismatch FC.MAVEN_sphere2xyz([1.0, 2.0])
        @test_throws DimensionMismatch FC.MAVEN_xyz2sphere([1.0, 2.0])
        @test_throws MethodError FC.MAVEN_sphere2xyz(reshape(1.0:6.0, 2, 3))
        @test_throws MethodError FC.MAVEN_sphere2xyz(1.0, 2.0, 3.0)
        @test_throws MethodError FC.MAVEN_xyz2sphere(1.0, 2.0, 3.0)
    end

    @testset "hypot keeps extreme finite radii representable" begin
        for (scale, expected) in ((1e200, 1e200), (1e-200, 1e-200))
            xyz = SVector(scale, 0.0, 0.0)
            @test FC.MAVEN_xyz2sphere(xyz)[1] == expected
            @test FC.pa_xyz2sphere(xyz)[1] == expected
            @test FC.MINPA_xyz2sphere(xyz)[1] == expected
        end
        zero_result = FC.MAVEN_xyz2sphere(SVector(0.0, 0.0, 0.0))
        @test zero_result[1] == 0.0
        old_zero = old_maven_xyz2sphere(0.0, 0.0, 0.0)
        @test isequal(zero_result, old_zero)
        @test zero_result[1] == 0.0
    end
end
