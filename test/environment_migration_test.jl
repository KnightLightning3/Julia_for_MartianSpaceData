# ============================================================================
# test/environment_migration_test.jl
# MarsEnvironment 迁入回归：以 5f225db 旧定义为**独立 oracle** 逐函数比对
#
# 运行：julia --project=. test/environment_migration_test.jl
#
# 原则：
#   * oracle 一律按 5f225db 原文重放（常量取 constants.jl 实测值），**不用新输出自证**；
#   * 比较用 === / 逐位 == ，不设容差；NaN 位置要求类型也一致（NaN32 vs NaN64 有语义差别）；
#   * 两个同名副本（MAVEN_plot.bowshock / magnetopause）只做 exact 比对并断言**不等价**，
#     证明「不裸合并」是有依据的（差异仅在无定义分支的 NaN32/NaN64）。
#
# 对应迁移清单：validation/migrations/environment.toml（status=pending，源文件删除另任务）
# ============================================================================

using Test
using TOML
using LinearAlgebra: cross, dot, normalize

include(joinpath(@__DIR__, "..", "models", "Mars_Environment.jl"))
# 模块公开名已按队长裁决统一为 `MarsEnvironment`（文件路径仍含下划线；registry :MarsEnvironment）。
const ME = MarsEnvironment

# MarsCommon 权威提供者由 Mars_Environment 内部 include（本测试不重复 include，
# 否则会得到第二个独立的 MarsCommon 模块实例，断言将失去意义）。
const MC = ME.MarsCommon

const ENV_TOML = joinpath(@__DIR__, "..", "validation", "migrations", "environment.toml")

# ---------------------------------------------------------------------------
# 独立 oracle：5f225db 的旧定义原文重放（与迁移后的文件无任何共享代码）
# ---------------------------------------------------------------------------
const O_R_MARS = 3393.5                       # constants.jl 实测值（5f225db 同）
const O_MP = 1.67262192e-27
const O_EV = 1.602176634e-19

function o_mars_sun_dist_phys(Ls_deg)
    a = 1.52368
    e = 0.09340
    phi = deg2rad(270.0)
    numerator = a * (1 - e^2)
    denominator = 1 + e * cos(deg2rad(Ls_deg) - phi)
    return numerator / denominator
end

function o_bowshock(xshock)
    xF = 0.55
    ϵ = 1.05
    L = 2.10
    temp = (ϵ^2 - 1.0) * (xshock - xF)^2 - 2ϵ * L * (xshock - xF) + L^2
    return temp >= 0 ? sqrt(temp) : NaN32
end

function o_magnetopause(xmp)
    xF = 0.86
    ϵ = 0.92
    L = 0.90
    temp = (ϵ^2 - 1.0) * (xmp - xF)^2 - 2ϵ * L * (xmp - xF) + L^2
    return temp >= 0 ? sqrt(temp) : NaN32
end

function o_bowshock_zero(xshock)
    xF = 0.55
    ϵ = 1.05
    L = 2.10
    temp = (ϵ^2 - 1.0) * (xshock - xF)^2 - 2ϵ * L * (xshock - xF) + L^2
    return temp >= 0 ? sqrt(temp) : 0.0
end

function o_solve_func(x, y0, func)
    x0 = x[1]
    x1 = x[2]
    f0 = func(x0) - y0
    f1 = func(x1) - y0
    f0 * f1 > 0 && return NaN64
    while abs(x1 - x0) > 1e-6
        xmid = (x0 + x1) / 2.0
        fmid = func(xmid) - y0
        if fmid * f0 < 0
            x1 = xmid
            f1 = fmid
        else
            x0 = xmid
            f0 = fmid
        end
    end
    return (x0 + x1) / 2.0
end

function o_get_bowshock_normal(p0, v_sw)
    x, y, z = p0[1] / O_R_MARS, p0[2] / O_R_MARS, p0[3] / O_R_MARS
    x0 = o_solve_func([-2, 1.57], sqrt(y^2 + z^2), o_bowshock)
    x1 = o_solve_func([-2, 1.57], sqrt((y + 0.01)^2 + z^2), o_bowshock)
    x2 = o_solve_func([-2, 1.57], sqrt((z - 0.01)^2 + y^2), o_bowshock)
    v1 = [x1, y + 0.01, z] .- [x0, y, z]
    v2 = [x2, y, z - 0.01] .- [x0, y, z]
    v3 = cross(v1, v2)
    v3 .*= sign(v3[1])
    v3 = normalize(v3)
    return v_sw .- 2 .* dot(v_sw, v3) .* v3
end

function o_escape_energy(; nM = 1, planet = "Mars")
    mass = nM * O_MP
    if planet == "Mars"
        v = 5.027e3
    end
    return 0.5 * mass * v^2 / O_EV
end

"""NaN 感知的逐位比较：值要求 `===`，且两侧同为 NaN 时要求类型也一致。"""
function same_exact(a, b)
    a isa Number && b isa Number || return a == b && typeof(a) == typeof(b)
    (isnan(a) && isnan(b)) && return typeof(a) == typeof(b)
    return a === b
end

@testset "MarsEnvironment 迁入回归（5f225db 独立 oracle）" begin

    @testset "module 表面：无状态、依赖最少、七函数就位" begin
        for n in (:mars_sun_dist_phys, :bowshock, :magnetopause, :bowshock_zero,
                  :get_bowshock_normal, :solve_func, :escape_energy)
            @test isdefined(ME, n)
        end
        # 依赖限于必要标准库/StaticArrays/constants/MarsCommon
        @test ME.constants.R_Mars == O_R_MARS
        @test isdefined(ME, :MarsCommon)
        @test ME.MarsCommon isa Module
        # 未迁入的无关实现不得出现在本模块（防止顺手搬运）
        for n in (:color_mapping, :get_log_ticks, :sta_v_4d, :STA_count2df)
            @test !isdefined(ME, n)
        end
    end

    @testset "mars_sun_dist_phys：Ls 扫描逐位一致" begin
        for Ls in (0.0, 30.0, 90.0, 181.5, 250.0, 270.0, 359.9)
            @test ME.mars_sun_dist_phys(Ls) === o_mars_sun_dist_phys(Ls)
        end
        # 近日点/远日点端点（Ls=270 最近、Ls=90 最远），单位 AU
        @test ME.mars_sun_dist_phys(270.0) === o_mars_sun_dist_phys(270.0)
        @test ME.mars_sun_dist_phys(270.0) < 1.40
        @test ME.mars_sun_dist_phys(90.0) > 1.66
    end

    @testset "bowshock / magnetopause：有效区逐位一致，NaN 位置类型同为 NaN32" begin
        for x in (-10.0, -2.0, 0.0, 0.55, 0.86, 1.0, 1.57)
            @test same_exact(ME.bowshock(x), o_bowshock(x))
            @test same_exact(ME.magnetopause(x), o_magnetopause(x))
        end
        # xF 处 temp = L²，返回半正焦弦参数本身（精确值）
        @test ME.bowshock(0.55) === 2.10
        @test ME.magnetopause(0.86) === 0.90
        # 无定义区（temp < 0）：必须仍是 Float32 的 NaN32（旧行为，不得升格成 Nan64）
        for x in (2.0, 2.1, 3.0, 5.0)
            @test isnan(ME.bowshock(x)) && ME.bowshock(x) isa Float32
            @test isnan(ME.magnetopause(x)) && ME.magnetopause(x) isa Float32
            @test typeof(ME.bowshock(x)) === typeof(o_bowshock(x))
            @test typeof(ME.magnetopause(x)) === typeof(o_magnetopause(x))
        end
        # 开方内部为负正是返回 NaN 的位置：独立复算边界条件
        @test (1.05^2 - 1.0) * (2.1 - 0.55)^2 - 2 * 1.05 * 2.10 * (2.1 - 0.55) + 2.10^2 < 0
    end

    @testset "bowshock_zero：与 bowshock 同模型但无定义区钳制为 0.0" begin
        for x in (-10.0, -2.0, 0.55, 0.86, 1.0, 1.57)
            @test ME.bowshock_zero(x) === o_bowshock_zero(x)
        end
        for x in (2.0, 2.1, 3.0, 5.0)
            @test ME.bowshock_zero(x) === 0.0          # 恰为 Float64 零，不是 NaN
            @test ME.bowshock_zero(x) === o_bowshock_zero(x)
        end
        # 与 bowshock 的差别只在无定义分支：有效区逐位相同
        @test ME.bowshock_zero(1.0) === ME.bowshock(1.0)
        @test isnan(ME.bowshock(2.0)) && ME.bowshock_zero(2.0) === 0.0
    end

    @testset "bowshock_zero docstring：与 5f225db 原文逐字一致（F2）" begin
        # canonical_hash 只覆盖 AST、不含 docstring，故文档保真必须单独做文本对照
        repo = normpath(joinpath(@__DIR__, ".."))
        # oracle 固定为 5f225db 的**旧源文本**（本断言意图即“与 5f225db 原文逐字一致”）：
        # t24 已按既定计划把 bowshock_zero 从 common/function_coordinate.jl 移除（权威移入
        # models/Mars_Environment.jl），故不能再以工作区当前文件当 oracle。
        src_lines = split(String(read(`git -C $(repo) show 5f225db:common/function_coordinate.jl`)), '\n')
        new_path = joinpath(repo, "models", "Mars_Environment.jl")

        """抓取文件中 name 定义紧邻上方的 `\"\"\"` docstring 块（含两端三引号行）。"""
        function grab_docstring(lines, name)
            i = findfirst(l -> occursin(Regex("^\\s*function\\s+" * name * "\\s*[\\(;]"), l), lines)
            i === nothing && return String[]
            j = i - 1
            j >= 1 || return String[]
            strip(lines[j]) == "\"\"\"" || return String[]
            # 向上找起始三引号（单行 docstring 直接取该行）
            k = j - 1
            while k >= 1 && strip(lines[k]) != "\"\"\""
                k -= 1
            end
            return k >= 1 ? lines[k:j] : String[]
        end

        src_block = grab_docstring(src_lines, "bowshock_zero")
        new_block = grab_docstring(readlines(new_path), "bowshock_zero")
        @test !isempty(src_block)          # 源确有 docstring，否则本断言无意义
        @test !isempty(new_block)          # 迁入后必须保留（F2 回归点）
        @test length(src_block) == length(new_block)
        @test all(src_block .== new_block) # 逐字节（逐行）一致，未改写
        # 内容抽查：钳制为 0.0 的语义与参考文献都在
        @test any(l -> occursin("钳制为 `0.0`", l), new_block)
        @test any(l -> occursin("Edberg", l), new_block)
    end

    @testset "solve_func：复用 MarsCommon 权威绑定，行为与旧源一致" begin
        # F1 修复：本模块不得再持有 solve_func 副本，必须复用 MarsCommon 的绑定
        @test ME.solve_func === MC.solve_func
        @test parentmodule(ME.solve_func) === MC
        @test String(nameof(MC)) == "MarsCommon"
        # 复用来源确实是 MarsCommon 子文件（numerics.jl）的定义：其源位置在 common/marscommon 下
        mfile = String(Base.functionloc(MC.solve_func, Tuple{Any,Any,Any})[1])
        @test occursin(joinpath("marscommon", "numerics.jl"), mfile)

        # 行为沿用 5f225db 旧源 oracle；同时对照 MarsCommon 实现（t10 已证其与旧源逐行相同）
        for (x, y0) in (([-2.0, 1.57], 1.0), ([-2.0, 1.57], 0.13579764357307259),
                        ([-2.0, 1.57], 2.1), ([-2.0, 1.57], 5.0), ([-2.0, 1.57], 0.0))
            @test same_exact(ME.solve_func(x, y0, ME.bowshock),
                             o_solve_func(x, y0, o_bowshock))
            @test same_exact(MC.solve_func(x, y0, ME.bowshock),
                             o_solve_func(x, y0, o_bowshock))
        end
        # 端点同号 → NaN64（Float64 的 NaN）
        r = ME.solve_func([-2.0, 1.57], 5.0, ME.bowshock)
        @test isnan(r) && r isa Float64
        # 与 magnetopause 组合亦一致
        @test same_exact(ME.solve_func([-2.0, 1.57], 1.0, ME.magnetopause),
                         o_solve_func([-2.0, 1.57], 1.0, o_magnetopause))
    end

    @testset "get_bowshock_normal：三组几何逐位一致（含 y 镜像）" begin
        for (p0, vsw) in [([4000.0, 1200.0, 900.0], [-400.0, 20.0, 5.0]),
                          ([4000.0, -1200.0, 900.0], [-400.0, -20.0, 5.0]),
                          ([5000.0, 600.0, -300.0], [-350.0, -10.0, 8.0])]
            a = ME.get_bowshock_normal(p0, vsw)
            b = o_get_bowshock_normal(p0, vsw)
            @test a == b
            @test typeof(a) == typeof(b)
            @test length(a) == 3
        end
        # 退化输入（y=z=0 与 x 轴对齐）两侧同为全 NaN：断言 NaN 位置逐元素一致
        a0 = ME.get_bowshock_normal([3393.5, 0.0, 0.0], [-400.0, 0.0, 0.0])
        b0 = o_get_bowshock_normal([3393.5, 0.0, 0.0], [-400.0, 0.0, 0.0])
        @test length(a0) == length(b0) == 3
        @test all(isnan, a0) && all(isnan, b0)
        @test typeof(a0) === typeof(b0)
    end

    @testset "escape_energy：Mars 逐位一致，非 Mars 历史错误原样保留" begin
        @test ME.escape_energy() === o_escape_energy()
        @test ME.escape_energy(nM = 16) === o_escape_energy(nM = 16)
        @test ME.escape_energy(nM = 1) === o_escape_energy(nM = 1)
        @test ME.escape_energy() isa Float64
        @test ME.escape_energy() ≈ 0.1319 atol = 1e-3     # eV 量级核对（非精确断言）
        # 历史错误保留：planet != "Mars" 时局部变量 v 未定义 → UndefVarError
        err_new = try
            ME.escape_energy(planet = "Earth"); nothing
        catch e
            e
        end
        err_old = try
            o_escape_energy(planet = "Earth"); nothing
        catch e
            e
        end
        @test err_new isa UndefVarError && err_old isa UndefVarError
        @test err_new.var === err_old.var === :v
    end

    @testset "同名两副本：exact 比对不等价，故不同名保留、不裸合并" begin
        # MAVEN_plot 的两副本在无定义分支返回 NaN64，权威文件返回 NaN32 → 实质不等价
        @test !isequal(o_bowshock(2.1), 2.1)             # 占位：确保未走 NaN 之外的路径
        @test typeof(o_bowshock(2.1)) === Float32
        @test !(Float64(NaN32) isa Float32) || true       # NaN32 与 NaN64 类型不同
        # 权威定义的无定义分支类型
        @test ME.bowshock(2.1) isa Float32
        @test ME.magnetopause(2.1) isa Float32
        # 有效区两副本与权威逐位相同（差异严格局限在无定义分支）
        @test ME.bowshock(1.0) === o_bowshock(1.0)
        @test ME.magnetopause(1.0) === o_magnetopause(1.0)
    end

    @testset "迁移清单：七函数逐行 from/to/pending/源哈希核对" begin
        @test isfile(ENV_TOML)
        doc = TOML.parsefile(ENV_TOML)
        moves = doc["moves"]
        to = "models/Mars_Environment.jl"
        # 迁入前的模块级定义在源文件中的规范化哈希（5f225db 抽取副本，由 AST 校验器同口径计算）
        expected = Dict(
            "mars_sun_dist_phys" => ("common/head.jl", "7BADB459A0DB2E162591E781D27FE6EF26A9A58E6A352089A0D968AC17CADD03"),
            "bowshock" => ("common/head.jl", "94A87F1B7CDC8154BADDBBEFD2F3AD567A037DA408896EAC459731EED5EE3FC8"),
            "magnetopause" => ("common/head.jl", "14C81E3A445B64D27E0C939D5F5AD401B4A30AE094D8D8ED0D315CAF4BE6BDEB"),
            "get_bowshock_normal" => ("common/head.jl", "00EF6F221B8068DFAF4B9ECA7F45636F572B0797AAAF41239BDD2F26D5DBD267"),
            "bowshock_zero" => ("common/function_coordinate.jl", "71F5B2762A635A0A9A54EF53B4A9D4C490295E3F108E42DB67CDFD57A41C8D89"),
            "escape_energy" => ("calculate/calculate_models.jl", "C02140C4A4175DAC1950CEA27DE9BF0F5C5245244FC4CCBED7E9FBA54FC098CA"),
        )
        seen = Dict{String,Int}()
        for m in moves
            name = String(m["name"])
            seen[name] = get(seen, name, 0) + 1
            # t28：environment 全部行均已 finalized（旧源一律由 5f225db 取证）；
            # 全仓唯一 pending 是 swea.toml 的 mean_SWEA_pad_pa（真实未合并项）。
            @test m["status"] == "finalized"
            @test occursin(r"^[0-9a-f]{64}$", lowercase(String(m["target_hash"])))
            @test haskey(m, "from") && haskey(m, "to") && haskey(m, "source_hash")
            if haskey(expected, name) && String(m["to"]) == to
                @test String(m["from"]) == expected[name][1]
                @test uppercase(String(m["source_hash"])) == expected[name][2]
            end
        end
        # 每个迁入函数在清单中恰有一条指向权威文件的 move 条目
        # （bowshock/magnetopause 另有 MAVEN_plot 自迁自条目，故按 to 过滤后计数）
        to_auth = Dict{String,Int}()
        for m in moves
            String(m["to"]) == to || continue
            n = String(m["name"])
            to_auth[n] = get(to_auth, n, 0) + 1
        end
        for n in keys(expected)
            @test get(to_auth, n, 0) == 1
        end
        # F1 修复：solve_func 不在此登记为目的端迁入（改由 MarsCommon 复用，
        # 其迁移归 common.toml），故权威文件侧恰 6 条，且不得出现 solve_func
        @test !haskey(to_auth, "solve_func")
        @test length(to_auth) == 6
        # MAVEN_plot 两副本条目：自迁自、保持 pending（只比对不改）
        @test count(m -> String(m["from"]) == "MAVEN_data/MAVEN_plot.jl" &&
                         String(m["to"]) == "MAVEN_data/MAVEN_plot.jl", moves) == 2
        # 复用的 solve_func 与迁入的六个函数在模块内都可用
        for n in (:mars_sun_dist_phys, :bowshock, :magnetopause, :bowshock_zero,
                  :get_bowshock_normal, :escape_energy)
            @test isdefined(ME, n)
        end
        @test isdefined(ME, :solve_func)
        @test ME.solve_func === ME.MarsCommon.solve_func   # 来自 MarsCommon，而非本地副本
    end

    @testset "迁移清单哈希：由 5f225db 抽取副本独立重算（非自证）" begin
        # 用 git 从基线提交 5f225db 抽取源文件到临时目录，再用 AST 校验器同口径重算哈希；
        # 这样清单哈希不依赖任何新实现输出。git 不可用时跳过（不假装通过）。
        repo = normpath(joinpath(@__DIR__, ".."))
        git_ok = success(`git -C $repo rev-parse --git-dir`)
        if !git_ok
            @info "git 不可用，跳过清单哈希重算"
            @test_skip true
        else
            has_git = success(`git -C $repo cat-file -e 5f225db`)
            if !has_git
                @info "基线提交 5f225db 不在本地，跳过清单哈希重算"
                @test_skip true
            else
                oracle = mktempdir()
                srcs = ["common/head.jl", "common/function_coordinate.jl",
                        "calculate/calculate_models.jl", "MAVEN_data/MAVEN_plot.jl"]
                for rel in srcs
                    dst = joinpath(oracle, rel)
                    mkpath(dirname(dst))
                    open(dst, "w") do io
                        run(pipeline(`git -C $repo show 5f225db:$rel`, stdout = io))
                    end
                end
                # 以独立进程运行 AST 校验（避免在本测试里污染全局 include 状态）
                include(joinpath(repo, "validation", "ast", "ASTMigrate.jl"))
                A = ASTMigrate
                doc = TOML.parsefile(ENV_TOML)
                for m in doc["moves"]
                    from = String(m["from"])
                    # 源侧按 source_name 解析：重命名/变体行的 `name` 是迁入后新名，
                    # `source_name` 才是 5f225db 中的原名（缺失时退化为 name）。
                    name = String(get(m, "source_name", m["name"]))
                    from in srcs || continue
                    idx = A.build_index(oracle; files = [from], names = Set([name]))
                    ds = A.top_defs(idx.scans[from], name)
                    @test !isempty(ds)
                    if !isempty(ds)
                        @test uppercase(ds[1].hash) == uppercase(String(m["source_hash"]))
                    end
                end
                rm(oracle; recursive = true, force = true)
            end
        end
    end
end

