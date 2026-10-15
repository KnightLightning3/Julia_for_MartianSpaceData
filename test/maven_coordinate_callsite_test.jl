using Test
using LinearAlgebra
using StaticArrays
using Rotations: QuatRotation

const REPO = normpath(joinpath(@__DIR__, ".."))
include(joinpath(REPO, "MAVEN_data", "MAVEN_STATIC.jl"))
const FC = MAVEN_STATIC.FunctionCoordinate
const MC = MAVEN_STATIC.MarsCommon

# Independently evaluate the two original scalar MarsCommon functions from the
# requested full-source baseline, without loading the current package module.
const BASELINE = "a09511aa7b88c874cefe8ca966c98aa267db9365"
const old_marscommon_source = read(`git -C $REPO show $BASELINE:common/MarsCommon.jl`, String)
module OriginalMarsCommonCoordinates
using StaticArrays
end
function eval_old_marscommon_function!(mod, source, name)
    signature = "function " * name * "("
    found = findfirst(signature, source)
    @assert found !== nothing "baseline MarsCommon function not found: $name"
    expr, _ = Meta.parse(source, first(found); raise=true)
    @assert expr isa Expr && expr.head === :function "baseline parse failed: $name"
    Core.eval(mod, expr)
end
eval_old_marscommon_function!(OriginalMarsCommonCoordinates, old_marscommon_source,
    "instrument_sphere_to_cartesian")
eval_old_marscommon_function!(OriginalMarsCommonCoordinates, old_marscommon_source,
    "instrument_cartesian_to_sphere")
old_sphere2xyz(r, theta, phi) =
    OriginalMarsCommonCoordinates.instrument_sphere_to_cartesian(r, theta, phi)
old_xyz2sphere(p) = OriginalMarsCommonCoordinates.instrument_cartesian_to_sphere(p...)

@testset "MAVEN coordinate production callsites" begin
    @testset "STATIC.static_rotation identity and rotation" begin
        for (quat, expected_rotation) in (
            (QuatRotation(1.0, 0.0, 0.0, 0.0), Matrix{Float64}(I, 3, 3)),
            (QuatRotation(cos(π/4), 0.0, 0.0, sin(π/4)),
             [0.0 -1.0 0.0; 1.0 0.0 0.0; 0.0 0.0 1.0]),
        )
            theta = reshape([17.0, -23.0, 41.0, 8.0], 1, 2, 2)
            phi = reshape([31.0, 77.0, -102.0, 145.0], 1, 2, 2)
            magf = [1.2, -3.4, 5.6]
            dat = Dict{Symbol,Any}(:theta=>copy(theta), :phi=>copy(phi), :magf=>copy(magf),
                :nmass=>1, :nbins=>2, :nenergy=>2, :quat_mso=>quat)
            old_angles = map(eachindex(theta)) do i
                old_xyz2sphere(expected_rotation * old_sphere2xyz(1.0, theta[i], phi[i]))
            end
            result = MAVEN_STATIC.static_rotation(dat)
            @test result === dat
            @test size(result[:theta]) == size(theta)
            @test size(result[:phi]) == size(phi)
            @test result[:theta][:] ≈ [p[2] for p in old_angles] rtol=1e-12 atol=1e-12
            @test result[:phi][:] ≈ [p[3] for p in old_angles] rtol=1e-12 atol=1e-12
            @test result[:magf] ≈ expected_rotation * magf rtol=1e-14 atol=1e-14
        end

        # With Float32 angle inputs the point adapter constructs SVector(1.0,t,p),
        # promoting angles to Float64 before trig. The original scalar formula ran
        # cosd/sind on Float32 angles first, so allow only a few Float32 angle ulps;
        # this checks numeric agreement, not bitwise equivalence for every forward call.
        theta32 = reshape(Float32[17.0, -23.0, 41.0, 8.0], 1, 2, 2)
        phi32 = reshape(Float32[31.0, 77.0, -102.0, 145.0], 1, 2, 2)
        angle_atol32 = 4eps(Float32) * 180
        max_angle_error32 = 0.0
        for (quat, expected_rotation) in (
            (QuatRotation(1.0, 0.0, 0.0, 0.0), Matrix{Float64}(I, 3, 3)),
            (QuatRotation(cos(π/4), 0.0, 0.0, sin(π/4)),
             [0.0 -1.0 0.0; 1.0 0.0 0.0; 0.0 0.0 1.0]),
        )
            dat = Dict{Symbol,Any}(:theta=>copy(theta32), :phi=>copy(phi32),
                :magf=>[1.2, -3.4, 5.6], :nmass=>1, :nbins=>2, :nenergy=>2,
                :quat_mso=>quat)
            old_angles = map(eachindex(theta32)) do i
                old_xyz2sphere(expected_rotation * old_sphere2xyz(1.0, theta32[i], phi32[i]))
            end
            result = MAVEN_STATIC.static_rotation(dat)
            theta_error = abs.(result[:theta][:] .- [p[2] for p in old_angles])
            phi_error = abs.(mod.(result[:phi][:] .- [p[3] for p in old_angles] .+ 180.0, 360.0) .- 180.0)
            max_angle_error32 = max(max_angle_error32, maximum(theta_error), maximum(phi_error))
            @test eltype(theta32) === Float32 && eltype(phi32) === Float32
            @test maximum(theta_error) <= angle_atol32
            @test maximum(phi_error) <= angle_atol32
        end
        @info "Float32 STATIC angle comparison against original scalar formulas" max_angle_error_degrees=max_angle_error32 tolerance_degrees=angle_atol32
    end

    @testset "STATIC.static_slip_2_V shapes, aggregation and point algorithm" begin
        n_m, n_b, n_e = 2, 2, 2
        mass_arr = reshape([16.0, 8.0, 18.0, 12.0, 16.0, 30.0, 14.0, 19.0], n_m, n_b, n_e)
        energy = reshape([4.0, 9.0, 16.0, 25.0], 1, n_b, n_e)
        phi = reshape([10.0, 70.0, 130.0, -40.0], 1, n_b, n_e)
        theta = reshape([-20.0, 0.0, 30.0, 55.0], 1, n_b, n_e)
        df = reshape(collect(1.0:8.0), n_m, n_b, n_e)
        eflux = 2 .* df
        dat = Dict{Symbol,Any}(:nenergy=>n_e, :nbins=>n_b, :energy=>energy,
            :phi=>phi, :theta=>theta, :mass_arr=>mass_arr, :sc_pot=>1.5,
            :df=>df, :eflux=>eflux, :magf=>[0.1, 0.2, 0.3])
        vsc = [3.0, -2.0, 0.5]
        got = MAVEN_STATIC.static_slip_2_V(dat; mass_range=[10,20], m_int=16, vsc=vsc)

        mask = (mass_arr .>= 10) .& (mass_arr .<= 20)
        @test size(got[:df]) == (n_b, n_e)
        @test size(got[:eflux]) == (n_b, n_e)
        @test size(got[:v]) == (n_b, n_e, 3)
        @test got[:df] == sum(df .* mask; dims=1)[1,:,:]
        @test got[:eflux] == sum(eflux .* mask; dims=1)[1,:,:]
        @test got[:energy] == max.(energy[1,:,:] .+ 1.5, 0.001)
        @test got[:magf] === dat[:magf]
        for j in 1:n_b, k in 1:n_e
            speed = MC.ion_energy2v(got[:energy][j,k], 16) / 1e3
            expected = old_sphere2xyz(speed, theta[1,j,k], phi[1,j,k]) + SVector(vsc...)
            @test got[:v][j,k,:] ≈ expected rtol=1e-14 atol=1e-14
        end
    end

    @testset "无生产旧调用点，批量转换点接口保持形状" begin
        static_source = read(joinpath(REPO, "MAVEN_data", "MAVEN_STATIC.jl"), String)
        pickup_source = read(joinpath(REPO, "analysis", "Pickup_ion.jl"), String)
        @test !occursin("MarsCommon.instrument_sphere_to_cartesian", static_source)
        @test !occursin("MarsCommon.instrument_cartesian_to_sphere", static_source)
        @test !occursin("MarsCommon.instrument_cartesian_to_sphere", pickup_source)
        @test occursin("FunctionCoordinate.MAVEN_xyz2sphere(p)", pickup_source)

        radii = reshape([1.0, 2.5, 4.0, 7.0], 2, 2)
        th = reshape([-35.0, 0.0, 20.0, 60.0], 2, 2)
        ph = reshape([15.0, -120.0, 90.0, 210.0], 2, 2)
        points = map((r,t,p) -> FC.MAVEN_sphere2xyz(SVector(r,t,p)), radii, th, ph)
        back = map(FC.MAVEN_xyz2sphere, points)
        @test size(points) == size(radii) == size(th) == size(ph)
        @test size(back) == size(points)
        @test [p[1] for p in back] ≈ radii rtol=1e-14
        @test [p[2] for p in back] ≈ th rtol=1e-13 atol=1e-13
        phi_error = mod.([p[3] for p in back] .- ph .+ 180.0, 360.0) .- 180.0
        @test phi_error ≈ zeros(size(ph)) atol=1e-13
    end
end
