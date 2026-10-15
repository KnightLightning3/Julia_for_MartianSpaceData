# ============================================================================
# test/coordinate_variants_test.jl
# t36 回归：非等价坐标/磁场坐标函数按“不同显式名保留”，并与 5f225db 旧源逐位对照
#
# 覆盖：
#   1) Bsphere2pc / Bpc2sphere（hypot 权威）已迁 MarsCommon.geometry，IGRF 只经 using 绑定；
#   2) Bpc2sphere_naive（原 MAVEN_load 的 sqrt 版）显式改名迁入，签名/溢出行为保留；
#   3) TW 版 slice2d_cal_rot → slice2d_cal_rot_matrix（SMatrix + 共线行为不变），FC/MAVEN_plot 版不动；
#   4) oracle 一律取自 5f225db 旧源（不经新实现自证），逐位/异常类型对照。
# 运行：julia --project=. test/coordinate_variants_test.jl
# ============================================================================

using Test
using MarsData
using LinearAlgebra
using StaticArrays
using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))

# 每个 (旧源, 函数) 放进**独立的沙箱模块**：不同源里同名函数（如两处 Bpc2sphere）互不覆盖
const ORACLES = Dict{String,Module}()

function _offsets(src::String)
    offs = Int[1]
    i = 1
    while true
        j = findnext(==('\n'), src, i)
        j === nothing && break
        push!(offs, j + 1)
        i = j + 1
    end
    return offs
end

function extract_fn(src::String, name::AbstractString)
    lines = split(src, '\n'; keepempty = true)
    offs = _offsets(src)
    i = findfirst(l -> occursin(Regex("^\\s*function\\s+" * name * "\\s*\\("), l), lines)
    i === nothing && error("未在旧源中找到 $name")
    start = i
    if i > 1 && strip(lines[i-1]) == "\"\"\""
        k = i - 2
        while k >= 1 && strip(lines[k]) != "\"\"\""; k -= 1; end
        k >= 1 && (start = k)
    end
    _ex, pos = Meta.parse(src, offs[start])
    text = rstrip(src[offs[start]:prevind(src, pos)])
    ls = split(text, '\n'; keepempty = true)
    while !isempty(ls) && (isempty(strip(ls[end])) || startswith(strip(ls[end]), "#"))
        pop!(ls)
    end
    return join(ls, "\n")
end

old_src(path) = String(read(`git -C $(REPO) show 5f225db:$(path)`))

function load_old(path, name)
    key = path * "::" * name
    if !haskey(ORACLES, key)
        m = Module(Symbol("Oracle_", replace(path, r"[^A-Za-z0-9]" => "_"), "_", name))
        Base.include_string(m, "using LinearAlgebra, StaticArrays", key * ":deps")
        Base.include_string(m, extract_fn(old_src(path), name), key)
        ORACLES[key] = m
    end
    return getfield(ORACLES[key], Symbol(name))
end

# 统一的“结果或异常类型”取证：值用 isequal（NaN 感知），异常只比类型
function outcome(f, args)
    try
        return (:ok, f(args...))
    catch e
        return (:err, typeof(e))
    end
end
same_outcome(a, b) = a[1] == b[1] && (a[1] === :ok ? isequal(a[2], b[2]) : a[2] === b[2])

MC = MarsData.MarsCommon
IGRF = MarsData.load_module(:IGRF_calculate)
TW = MarsData.load_module(:TW_MINPA)

@testset "t36 非等价坐标函数：权威归属与显式命名" begin
    @testset "Bsphere2pc / Bpc2sphere 权威在 MarsCommon（IGRF 仅绑定）" begin
        @test isdefined(MC, :Bsphere2pc) && isdefined(MC, :Bpc2sphere)
        # 迁出而非转发：IGRF 侧无本地定义，且绑定到同一函数对象
        igrf_txt = read(joinpath(REPO, "models", "IGRF_calculate.jl"), String)
        @test !occursin(Regex("(?m)^\\s*function\\s+Bsphere2pc\\s*\\("), igrf_txt)
        @test !occursin(Regex("(?m)^\\s*function\\s+Bpc2sphere\\s*\\("), igrf_txt)
        @test occursin("using .MarsCommon: Bsphere2pc, Bpc2sphere", igrf_txt)
        # t38：注册表 deps 补 :MarsCommon + guard 复用 ⇒ 规范实例与函数对象**同一**（不再是第二份实例）
        @test :MarsCommon in MarsData.MODULE_REGISTRY[:IGRF_calculate].deps
        @test IGRF.MarsCommon === MC.MarsCommon
        @test IGRF.Bsphere2pc === MC.Bsphere2pc
        @test IGRF.Bpc2sphere === MC.Bpc2sphere
        # 定义来源仍在 common 层（双证：对象同一 + functionloc 指位）
        loc(f) = string(first(functionloc(f)))
        @test occursin(joinpath("common", "marscommon", "geometry.jl"), loc(IGRF.Bsphere2pc))
        @test occursin(joinpath("common", "marscommon", "geometry.jl"), loc(MC.Bpc2sphere))
        # 只有必要依赖绑定：MarsCommon 不反向依赖 IGRF
        # 只有必要依赖绑定：MarsCommon 不得代码级依赖 IGRF（注释里提及其函数不算依赖）
        mc_txt = read(joinpath(REPO, "common", "MarsCommon.jl"), String)
        @test !occursin(Regex("(?m)^\\s*(include|using|import)\\b.*IGRF"), mc_txt)
    end

    @testset "三个磁场坐标函数与 5f225db 旧源逐位对照（普通/零/1e155）" begin
        old_s2p = load_old("Magnetic_Model/IGRF_calculate.jl", "Bsphere2pc")
        old_p2s = load_old("Magnetic_Model/IGRF_calculate.jl", "Bpc2sphere")
        old_naive = load_old("MAVEN_data/MAVEN_load.jl", "Bpc2sphere")

        normal = (1.5, 0.7, -0.3, 12.0, -3.0, 0.25)
        zero = (0.0, 0.0, 0.0, 1.0, 2.0, 3.0)
        big = (1.0e155, 2.0e155, -3.0e155, 1.0, 2.0, 3.0)
        for args in (normal, zero, big)
            @test isequal(MC.Bsphere2pc(args...), old_s2p(args...))
            @test isequal(MC.Bpc2sphere(args...), old_p2s(args...))
            @test isequal(MC.Bpc2sphere_naive(args...), old_naive(args...))
        end
        # 行为差异如实固定：|坐标| ≤ 1e153 两版逐位相同；≥ 1e154 分歧（sqrt 中间量上溢）
        small = (1.0e100, 2.0e100, -3.0e100, 1.0, 2.0, 3.0)
        @test isequal(MC.Bpc2sphere(small...), MC.Bpc2sphere_naive(small...))
        @test !isequal(MC.Bpc2sphere(big...), MC.Bpc2sphere_naive(big...))
        # 零坐标 NaU/Inf 语义与类型保持
        @test MC.Bpc2sphere(zero...) isa Tuple
        @test all(x -> x isa Float64, MC.Bpc2sphere(normal...))
        @test all(x -> x isa Float64, MC.Bpc2sphere_naive(normal...))
        # 签名保留：naive 版无类型标注（可接受非 Real 输入），hypot 版有 ::Real
        @test MC.Bpc2sphere_naive(1, 2, 3, 4.0f0, 5.0f0, 6.0f0) isa Tuple   # Int/Float32 混入不报错
        @test_throws MethodError MC.Bpc2sphere("x", 2, 3, 4, 5, 6)         # ::Real 标注仍在
    end

    @testset "TW slice2d_cal_rot_matrix：显式改名、类型与行为与旧源一致" begin
        old_tw = load_old("TW_data/TW_MINPA.jl", "slice2d_cal_rot")
        tw_txt = read(joinpath(REPO, "TW_data", "TW_MINPA.jl"), String)
        @test occursin(Regex("(?m)^function\\s+slice2d_cal_rot_matrix\\s*\\("), tw_txt)
        @test !occursin(Regex("(?m)^function\\s+slice2d_cal_rot\\s*\\("), tw_txt)
        @test !isdefined(TW, :slice2d_cal_rot)
        @test isdefined(TW, :slice2d_cal_rot_matrix)
        @test occursin("slice2d_cal_rot_matrix(E_cross_B,bvec)", tw_txt)   # 注释调用点同步

        well = ([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
        skew = ([3.0, 1.0, 2.0], [0.5, -1.0, 0.25])
        collinear = ([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])
        near = ([1.0, 0.0, 0.0], [1.0, 1.0e-12, 0.0])
        for pair in (well, skew, collinear, near)
            @test same_outcome(outcome(TW.slice2d_cal_rot_matrix, pair), outcome(old_tw, pair))
        end
        # 类型/形状：SVector 输入 ⇒ SMatrix{3,3,Float64,9}（Vector 输入走普通矩阵，与旧源一致）
        r = TW.slice2d_cal_rot_matrix(SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0))
        @test r isa SMatrix{3,3,Float64,9}
        rv = TW.slice2d_cal_rot_matrix(well...)
        @test occursin("SMatrix", string(typeof(rv))) || rv isa Matrix{Float64}
        @test isequal(rv, old_tw(well...))
        # 共线不是 NaN 而是与旧版相同的异常（如实记录真实行为）
        @test outcome(TW.slice2d_cal_rot_matrix, collinear)[1] === :err
    end

    @testset "未授权的等价化/删除未发生：FC 版与 MAVEN_plot 嵌套版不动" begin
        fc_txt = read(joinpath(REPO, "common", "function_coordinate.jl"), String)
        @test occursin(Regex("(?m)^function\\s+slice2d_cal_rot\\s*\\("), fc_txt)
        @test occursin("export slice2d_cal_rot", fc_txt)
        fc_sb = Module(:FCSandbox)
        Base.include(fc_sb, joinpath(REPO, "common", "function_coordinate.jl"))
        FCM = getfield(fc_sb, :FunctionCoordinate)
        @test FCM.slice2d_cal_rot isa Function
        @test_throws ErrorException FCM.slice2d_cal_rot([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])  # 共线抛错（原行为）
        # FC 版返回类型不动（Rotations.jl 的 RotMatrix3；此处按类型名核对，避免额外引入依赖）
        @test occursin("RotMatrix3",
                       string(typeof(FCM.slice2d_cal_rot([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]))))
        mp_txt = read(joinpath(REPO, "MAVEN_data", "MAVEN_plot.jl"), String)
        @test occursin(Regex("(?m)^\\s+function\\s+slice2d_cal_rot\\s*\\("), mp_txt)      # 嵌套局部版仍在
        # loader 不再自持 sqrt 版
        ml_txt = read(joinpath(REPO, "MAVEN_data", "MAVEN_load.jl"), String)
        @test !occursin(Regex("(?m)^\\s*function\\s+Bpc2sphere\\s*\\("), ml_txt)
        @test !isdefined(MarsData.load_module(:MAVEN_load), :Bpc2sphere)
    end

    @testset "示例调用点已指向新权威（无旧名调用）" begin
        for rel in ("example/MAVEN_plot_sample/MAVEN_overview_cases.jl",
                    "example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl")
            txt = read(joinpath(REPO, rel), String)
            @test occursin("MarsData.MarsCommon.Bpc2sphere_naive.(", txt)
            @test !occursin("MAVEN_load.Bpc2sphere", txt)
        end
    end

    @testset "迁移清单：源/目标哈希与 source_revision 完整" begin
        rel = joinpath("validation", "migrations", "coordinate_variants.toml")
        path = joinpath(REPO, rel)
        @test isfile(path)
        toml = read(path, String)
        @test occursin("schema_version = 1", toml)
        for nm in ("Bsphere2pc", "Bpc2sphere", "Bpc2sphere_naive", "slice2d_cal_rot_matrix")
            @test occursin(nm, toml)
        end
        @test occursin("source_revision", toml)
        # 实际解析：每行 finalized 必带 64 位 target_hash；retained 行不得带 target_hash
        parsed = TOML.parsefile(path)
        for r in get(parsed, "moves", [])
            @test get(r, "status", "") == "finalized"
            @test occursin(r"^[0-9a-f]{64}$", String(r["target_hash"]))
            @test get(r, "source_revision", "") == "5f225db"
            @test length(String(get(r, "source_hash", ""))) == 16
        end
        for r in get(parsed, "retained", [])
            @test get(r, "status", "") == "retained"
            @test !haskey(r, "target_hash")
        end
        @test length(get(parsed, "moves", [])) == 4
        @test length(get(parsed, "retained", [])) >= 1
    end
end
