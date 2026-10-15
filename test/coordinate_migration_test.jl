# ============================================================================
# test/coordinate_migration_test.jl
# FunctionCoordinate 坐标模块迁入回归：以 5f225db 旧定义为**独立 oracle** 比对
#
# 运行：julia --project=. test/coordinate_migration_test.jl
#
# 原则：
#   * oracle 一律按 5f225db 原文重放，**不用新输出自证**；
#   * 未改变的接口用 === / 逐位 ==；本轮用户允许 hypot 引起 roundoff 和极值变化，
#     对 pa_xyz2sphere 的有限普通点按 eps 尺度比较；
#   * canonical_hash 只覆盖 AST、不含 docstring，故文档保真另做「整块原文逐字对照」；
#   * 本文件不修复调用面：models/Pickup_ion.jl 的裸名调用需由调用点迁移单元显式接线
#     （见 validation/migrations/coordinate.toml 的 module 包装副作用说明）。
#
# 对应迁移清单：validation/migrations/coordinate.toml（1 move、2 remove）
# ============================================================================

using Test
using TOML
using StaticArrays
using Rotations
using LinearAlgebra: norm, normalize, cross, I

include(joinpath(@__DIR__, "..", "common", "function_coordinate.jl"))
const FC = FunctionCoordinate

const COORD_TOML = joinpath(@__DIR__, "..", "validation", "migrations", "coordinate.toml")

# ---------------------------------------------------------------------------
# 独立 oracle：5f225db 原文重放（与迁移后代码无共享实现）
# ---------------------------------------------------------------------------
function o_rotation_matrix(θ, φ)
    Rz = [cos(φ) -sin(φ) 0;
          sin(φ)  cos(φ) 0;
          0       0      1]
    Ry = [cos(θ)  0  sin(θ);
          0       1  0;
         -sin(θ)  0  cos(θ)]
    return Rz * Ry
end

o_quaternion_rot(u, q) = q * u
o_quaternion_rot_reverse(u, q) = inv(q) * u

# 5f225db 中 slice2d_cal_rot 的原文重放（保留项，证明未被包装改动）
function o_slice2d_cal_rot(v1, v2)
    a = normalize(v1)
    cross_av = cross(a, v2)
    norm_c = norm(cross_av)
    if norm_c < 1e-8
        error("v1 与 v2 共线，无法唯一定义切片平面的法向量！")
    end
    c = cross_av / norm_c
    b = cross(c, a)
    R_static = SMatrix{3,3,Float64,9}(
        a[1], b[1], c[1],
        a[2], b[2], c[2],
        a[3], b[3], c[3],
    )
    return RotMatrix(R_static)
end

# 5f225db 中 pa_xyz2sphere 的原文重放（保留项）
function o_pa_xyz2sphere(p::SVector{3,T}) where T <: Real
    r = norm(p)
    if iszero(r)
        return SVector{3,T}(zero(T), zero(T), zero(T))
    else
        theta = acosd(p[1]/r)
        phi = atand(p[3], p[2])
        return SVector{3}(r, theta, phi)
    end
end

"""抓取文件中 name 定义紧邻上方的 `\"\"\"` docstring 块（含两端三引号行）。"""
function grab_docstring(lines, name)
    i = findfirst(l -> occursin(Regex("^\\s*function\\s+" * name * "\\s*[\\(;]"), l), lines)
    i === nothing && return String[]
    j = i - 1
    j >= 1 || return String[]
    strip(lines[j]) == "\"\"\"" || return String[]
    k = j - 1
    while k >= 1 && strip(lines[k]) != "\"\"\""
        k -= 1
    end
    return k >= 1 ? lines[k:j] : String[]
end

@testset "FunctionCoordinate 坐标模块迁入回归（5f225db 独立 oracle）" begin

    @testset "module 包装：加载、导出、依赖绑定" begin
        @test FC isa Module
        @test String(nameof(FC)) == "FunctionCoordinate"
        # rotation_matrix 与五个保留函数仍在模块内；已移除的四元数包装不存在
        for n in (:rotation_matrix, :slice2d_cal_rot, :pa_xyz2sphere, :pa_sphere2xyz,
                  :MINPA_sphere2xyz, :MINPA_xyz2sphere)
            @test isdefined(FC, n)
        end
        @test !isdefined(FC, :Quaternion_Rot)
        @test !isdefined(FC, :Quaternion_Rot_reverse)
        # 迁入前的坐标文件并**无** module 包装；包装后 bowshock_zero 已移出到环境权威
        @test !isdefined(FC, :bowshock_zero)
        # 独立坐标模块不再加载或绑定 MC/constants。
        @test !isdefined(FC, :constants)
        @test !isdefined(FC, :MarsCommon)
        # 全部公开名都已 export（供调用方 using .FunctionCoordinate 恢复裸名用法）
        exported = Set(names(FC))
        for n in (:rotation_matrix, :slice2d_cal_rot, :pa_xyz2sphere, :pa_sphere2xyz,
                  :MINPA_sphere2xyz, :MINPA_xyz2sphere)
            @test n in exported
        end
        @test !(:Quaternion_Rot in exported)
        @test !(:Quaternion_Rot_reverse in exported)
    end

    @testset "rotation_matrix：5 组 (θ,φ) 逐位一致" begin
        for (θ, φ) in [(0.0, 0.0), (0.3, 0.7), (-1.2, 2.5), (π/2, π), (1.0, -0.5)]
            a = FC.rotation_matrix(θ, φ)
            b = o_rotation_matrix(θ, φ)
            @test a == b
            @test typeof(a) == typeof(b)
        end
        @test size(FC.rotation_matrix(0.3, 0.7)) == (3, 3)
        # 正交性自检（结构性事实，非 oracle 比对）
        R = FC.rotation_matrix(0.3, 0.7)
        @test R * R' ≈ Matrix(I, 3, 3) atol = 1e-12
    end

    @testset "四元数包装已删除：直接旋转仍与旧 oracle 一致（含 SVector/Vector）" begin
        qs = (QuatRotation(1.0, 0.0, 0.0, 0.0),
              QuatRotation(0.5, 0.5, 0.5, 0.5),
              QuatRotation(0.2, -0.3, 0.4, 0.1))
        for (u, q) in ((SVector(1.0, 2.0, 3.0), qs[1]),
                       (SVector(0.0, 0.0, 1.0), qs[2]),
                       ([1.0, -2.0, 0.5], qs[3]),
                       (SVector(1.0, 2.0, 3.0), qs[3]))
            @test q * u == o_quaternion_rot(u, q)
            @test inv(q) * u == o_quaternion_rot_reverse(u, q)
        end
        # 往返一致：reverse(rot(u)) == u
        u = SVector(1.0, 2.0, 3.0)
        q = QuatRotation(0.2, -0.3, 0.4, 0.1)
        @test inv(q) * (q * u) ≈ u
        # 单位四元数是恒等变换
        @test qs[1] * u == u
        @test inv(qs[1]) * u == u
    end

    @testset "保留项：slice2d_cal_rot 与 pa_xyz2sphere 接口与行为未变" begin
        for (v1, v2) in ((SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0)),
                         (SVector(1.0, 1.0, 0.0), SVector(0.0, 1.0, 1.0)),
                         (SVector(2.0, -1.0, 0.5), SVector(1.0, 3.0, -2.0)))
            a = FC.slice2d_cal_rot(v1, v2)
            b = o_slice2d_cal_rot(v1, v2)
            @test a == b
            @test typeof(a) == typeof(b)
        end
        for p in (SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0), SVector(1.0, 2.0, 3.0),
                  SVector(0.0, 0.0, 0.0))
            actual = FC.pa_xyz2sphere(p)
            expected = o_pa_xyz2sphere(p)
            @test all(abs(actual[i] - expected[i]) <= eps(Float64) * max(1.0, abs(expected[i])) for i in 1:3)
        end
        # 零向量特例仍返回零（避免 0/0）
        @test FC.pa_xyz2sphere(SVector(0.0, 0.0, 0.0)) == SVector(0.0, 0.0, 0.0)
        # 共线输入 → 抛错（保留项的既有防护，不得随包装丢失）
        @test_throws ErrorException FC.slice2d_cal_rot(SVector(1.0, 0.0, 0.0),
                                                       SVector(2.0, 0.0, 0.0))
        @test_throws ErrorException o_slice2d_cal_rot(SVector(1.0, 0.0, 0.0),
                                                      SVector(2.0, 0.0, 0.0))
        # 其余保留函数仍存在且可调用（接口未变）
        @test FC.pa_sphere2xyz(SVector(1.0, 0.0, 0.0)) isa SVector
        @test FC.MINPA_xyz2sphere(FC.MINPA_sphere2xyz(SVector(1.0, 30.0, 45.0))) isa SVector
    end

    @testset "calculate_models：三个历史旋转定义可取证，包装当前已删除" begin
        repo = normpath(joinpath(@__DIR__, ".."))
        # 工作区该文件已物理删除（存在性断言）
        @test !isfile(joinpath(repo, "calculate", "calculate_models.jl"))
        # oracle 一律取自 5f225db（不可用新实现自证）：旧源确有这三个顶层定义
        src = split(String(read(`git -C $repo show 5f225db:calculate/calculate_models.jl`)), '\n')
        for n in ("rotation_matrix", "Quaternion_Rot", "Quaternion_Rot_reverse")
            @test any(l -> occursin(Regex("^\\s*function\\s+" * n * "\\s*[\\(;]"), l), src)
        end
        @test isdefined(FC, :rotation_matrix)
        @test !isdefined(FC, :Quaternion_Rot)
        @test !isdefined(FC, :Quaternion_Rot_reverse)
    end

    @testset "环境权威已在：bowshock_zero 可从 MarsEnvironment 取用" begin
        # 删除旧源的前提条件：环境权威必须已就位且行为一致
        include(joinpath(@__DIR__, "..", "models", "Mars_Environment.jl"))
        ME = MarsEnvironment
        @test isdefined(ME, :bowshock_zero)
        for x in (-10.0, -2.0, 0.55, 1.0, 1.57)
            # 与 head.bowshock 同模型：有效区一致
            @test ME.bowshock_zero(x) === ME.bowshock(x)
        end
        for x in (2.0, 2.1, 3.0, 5.0)
            @test ME.bowshock_zero(x) === 0.0
        end
        @test ME.bowshock_zero(1.0) === 1.5640512299793765
    end

    @testset "迁移清单：1 条 move、2 条 remove，字段与源定义相符" begin
        @test isfile(COORD_TOML)
        doc = TOML.parsefile(COORD_TOML)
        moves = doc["moves"]
        @test length(moves) == 3
        expected_hashes = Dict(
            "rotation_matrix" => "A72CCBF83598F1B3740D361F981C9AED265E60B9C6483BDE85A3054DA087DF6E",
            "Quaternion_Rot" => "5BE99640F110CACCEDC547D2EBD29B72A7C4CA2CCC25E86946AF16462D0C64E8",
            "Quaternion_Rot_reverse" => "DF1143FB1C784547F1FB231D69C7FEE58E2B6E712B38F04B2DFE0197C014C400",
        )
        actions = Dict(String(m["name"]) => String(get(m, "action", "")) for m in moves)
        @test actions == Dict("rotation_matrix" => "move", "Quaternion_Rot" => "remove",
                              "Quaternion_Rot_reverse" => "remove")
        for m in moves
            n = String(m["name"])
            @test haskey(m, "action")
            @test uppercase(String(m["source_hash"])) == expected_hashes[n]
            if get(m, "action", "") == "move"
                @test n == "rotation_matrix"
                @test String(m["from"]) == "calculate/calculate_models.jl"
                @test String(m["to"]) == "common/function_coordinate.jl"
                @test String(m["source_revision"]) == "5f225db"
                @test uppercase(String(m["target_hash"])) == expected_hashes[n]
            else
                @test String(m["from"]) == "common/function_coordinate.jl"
                @test String(m["source_revision"]) == "d828a6e"
                @test !haskey(m, "to")
                @test !haskey(m, "target_hash")
                @test !isdefined(FC, Symbol(n))
            end
        end
    end

    @testset "清单哈希：逐行按 source_revision/from 独立重算（非自证）" begin
        repo = normpath(joinpath(@__DIR__, ".."))
        has_git = success(`git -C $repo cat-file -e 5f225db`)
        @test has_git
        if has_git
            include(joinpath(repo, "validation", "ast", "ASTMigrate.jl"))
            A = ASTMigrate
            doc = TOML.parsefile(COORD_TOML)
            for m in doc["moves"]
                n = String(m["name"])
                revision = String(m["source_revision"])
                source = String(m["from"])
                source_tmp = mktempdir()
                source_path = joinpath(source_tmp, source)
                mkpath(dirname(source_path))
                open(source_path, "w") do io
                    run(pipeline(`git -C $repo show $revision:$source`, stdout = io))
                end
                idx = A.build_index(source_tmp; files = [source], names = Set([n]))
                sc = idx.scans[source]
                defs = A.top_defs(sc, n)
                @test !isempty(defs)
                if !isempty(defs)
                    @test uppercase(defs[1].hash) == uppercase(String(m["source_hash"]))
                end
                rm(source_tmp; recursive = true, force = true)
            end
        end
    end

    @testset "文档保真：仅 rotation_matrix docstring 与 5f225db 原文逐字一致" begin
        repo = normpath(joinpath(@__DIR__, ".."))
        # 源：5f225db 的 calculate 文件（临时抽取）；目标：迁移后的坐标文件
        has_git = success(`git -C $repo cat-file -e 5f225db`)
        @test has_git
        if has_git
            tmp = mktempdir()
            srcfile = joinpath(tmp, "calc.jl")
            open(srcfile, "w") do io
                run(pipeline(`git -C $repo show 5f225db:calculate/calculate_models.jl`, stdout = io))
            end
            src_lines = readlines(srcfile)
            dst_lines = readlines(joinpath(repo, "common", "function_coordinate.jl"))
            for n in ("rotation_matrix",)
                sb = grab_docstring(src_lines, n)
                db = grab_docstring(dst_lines, n)
                @test !isempty(sb)
                @test !isempty(db)
                @test length(sb) == length(db)
                @test all(sb .== db)          # 逐行（逐字节）一致，未改写
            end
            dst_text = join(dst_lines, "\n")
            @test isempty(grab_docstring(dst_lines, "Quaternion_Rot"))
            @test isempty(grab_docstring(dst_lines, "Quaternion_Rot_reverse"))
            @test !occursin("Quaternion_Rot(u::AbstractVector", dst_text)
            @test !occursin("Quaternion_Rot_reverse(u::AbstractVector", dst_text)
            rm(tmp; recursive = true, force = true)
        end
    end
end
