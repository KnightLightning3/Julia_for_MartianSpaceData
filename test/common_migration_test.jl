# ============================================================================
# test/common_migration_test.jl
#
# MarsCommon「能力子文件」迁入的局部回归（t9）。
#
# 运行：julia --project=. test/common_migration_test.jl
#
# 口径：
#   · 旧实现 oracle **独立取自 git 对象 5f225db**（`git show 5f225db:<path>`），
#     按函数块精确取界后 include_string 到独立沙箱模块，不依赖工作区源码副本；
#   · 迁入组与本模块产物做 exact（isequal）对比，并单独覆盖 NaN / 抛错 / 副作用；
#   · 逐函数 from/to/name/status/source_hash 清单在 validation/migrations/common.toml，
#     本测试按 5f225db 重算 source_hash 并与清单逐行核对；
#   · 源文件（head/MAVEN_plot/calculate_models/MAVEN_load）本次不修改、不删除，由最终集成单元清理。
# ============================================================================

using Test
using TOML
using SHA
using LinearAlgebra
using StaticArrays
using MarsData

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const SRC_REV = "5f225db"
const MANIFEST = joinpath(REPO_ROOT, "validation", "migrations", "common.toml")

const SUBFILES = ["common/marscommon/statistics.jl", "common/marscommon/geometry.jl",
                  "common/marscommon/numerics.jl", "common/marscommon/cyclotron.jl"]
const SOURCE_FILES = ["common/head.jl", "MAVEN_data/MAVEN_plot.jl",
                      "calculate/calculate_models.jl", "MAVEN_data/MAVEN_load.jl"]

# 期望迁入表（测试自带，独立于 TOML；src = 5f225db 中的原函数名，name = MarsCommon 中的名字）
const MOVES = [
    (from = "common/head.jl", name = "safe_log_mean", src = "safe_log_mean", to = "common/marscommon/statistics.jl"),
    (from = "common/head.jl", name = "skipnan", src = "skipnan", to = "common/marscommon/statistics.jl"),
    (from = "common/head.jl", name = "nozeros", src = "nozeros", to = "common/marscommon/statistics.jl"),
    (from = "common/head.jl", name = "geomean", src = "geomean", to = "common/marscommon/statistics.jl"),
    (from = "common/head.jl", name = "find_range", src = "find_range", to = "common/marscommon/statistics.jl"),
    (from = "common/head.jl", name = "get_normal_plane", src = "get_normal_plane", to = "common/marscommon/geometry.jl"),
    (from = "common/head.jl", name = "get_angle", src = "get_angle", to = "common/marscommon/geometry.jl"),
    (from = "MAVEN_data/MAVEN_plot.jl", name = "vector_angle", src = "vector_angle", to = "common/marscommon/geometry.jl"),
    (from = "common/head.jl", name = "solve_func", src = "solve_func", to = "common/marscommon/numerics.jl"),
    (from = "MAVEN_data/MAVEN_plot.jl", name = "Vandermonde", src = "Vandermonde", to = "common/marscommon/numerics.jl"),
    (from = "MAVEN_data/MAVEN_plot.jl", name = "polynomial_fit", src = "polynomial_fit", to = "common/marscommon/numerics.jl"),
    (from = "calculate/calculate_models.jl", name = "Linear_fit", src = "Linear_fit", to = "common/marscommon/numerics.jl"),
    (from = "calculate/calculate_models.jl", name = "cyclotron_radius", src = "cyclotron_radius", to = "common/marscommon/cyclotron.jl"),
    (from = "calculate/calculate_models.jl", name = "cyclotron_frequency", src = "cyclotron_frequency", to = "common/marscommon/cyclotron.jl"),
    (from = "MAVEN_data/MAVEN_load.jl", name = "cyclotron_frequency_kg", src = "cyclone_frequency", to = "common/marscommon/cyclotron.jl"),
    (from = "MAVEN_data/MAVEN_load.jl", name = "cyclotron_radius_velocity", src = "cyclone_R", to = "common/marscommon/cyclotron.jl"),
]

# ---------------------------------------------------------------------------
# 5f225db 旧实现沙箱（独立命名空间，避免与迁入产物互相遮蔽）
# ---------------------------------------------------------------------------
module CommonMigrationOracle
using LinearAlgebra, Statistics, StaticArrays
end

module CommonMigrationScratch end

Base.include(CommonMigrationOracle, joinpath(REPO_ROOT, "common", "constants.jl"))
Core.eval(CommonMigrationOracle, :(using .constants))

sha16(s) = uppercase(bytes2hex(SHA.sha256(codeunits(s)))[1:16])

function _line_offsets(src::String)
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

"""
    extract_old_function(src, name) -> String

从 5f225db 的源文件全文里取出 `name` 的**完整函数块**：
从紧邻的 docstring 起始行（若存在）到该函数自身的 `end`/`end;` 行为止，去掉尾部空行与游离注释。
取界用 `Meta.parse` 的偏移量（不依赖 AST 行号），对 CRLF 源同样成立。
"""
function extract_old_function(src::String, name::AbstractString)
    lines = split(src, '\n'; keepempty = true)
    offs = _line_offsets(src)
    re = Regex("^\\s*function\\s+" * name * "\\s*\\(")
    di = findfirst(l -> occursin(re, l), lines)
    di === nothing && error("5f225db 源码中未找到函数 $name")
    start = di
    if di > 1 && strip(lines[di-1]) == "\"\"\""
        k = di - 2
        while k >= 1 && strip(lines[k]) != "\"\"\""
            k -= 1
        end
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

const _SRC_CACHE = Dict{String,String}()
old_source(path::AbstractString) =
    get!(_SRC_CACHE, String(path)) do
        String(read(`git -C $(REPO_ROOT) show $(SRC_REV):$(path)`))
    end

function old_function(path::AbstractString, srcname::AbstractString)
    sym = Symbol(srcname)
    if !isdefined(CommonMigrationOracle, sym)
        code = extract_old_function(old_source(path), srcname)
        Base.include_string(CommonMigrationOracle, code, "$(SRC_REV):$(path):$(srcname)")
    end
    return getfield(CommonMigrationOracle, sym)
end

# 被测模块：经注册表装载（同时验证子文件 include 路径在装载器下可用）
const MC = MarsData.load_module(:MarsCommon; into = CommonMigrationScratch)
# 旧 calculate_models 的 cyclotron_* 依赖未迁移的辅助函数（e_energy2v / ion_energy2v），沙箱按模块名解析；
# 这些辅助函数不在本次迁入面内，故指向同一模块实例。
Core.eval(CommonMigrationOracle, :(const MarsCommon = $(MC)))

oldof(m) = old_function(m.from, m.src)
newof(m) = getfield(MC, Symbol(m.name))
moveof(nm) = MOVES[findfirst(m -> m.name == nm, MOVES)]

@testset "MarsCommon 能力子文件迁入（t9）" begin
    @testset "迁入面、无兼容别名、源文件与注册表范围" begin
        for m in MOVES
            @test isdefined(MC, Symbol(m.name))
        end
        # 独立名迁移：不复用 MAVEN_load 的旧名，不提供 alias/兼容分支
        @test !isdefined(MC, :cyclone_frequency)
        @test !isdefined(MC, :cyclone_R)
        # 子文件按能力 include：不是注册表模块，也不改 constants 的既有非预装规范
        @test all(isfile(joinpath(REPO_ROOT, f)) for f in SUBFILES)
        @test MarsData.MODULE_REGISTRY[:constants].kind === :module
        @test isempty(MarsData.MODULE_REGISTRY[:constants].deps)
        @test isempty(MarsData.MODULE_REGISTRY[:constants].allow)
        # 策略 P（t13）：MarsCommon 改为随包预装，规范实例 = MAVEN_plot 内实例；
        # deps/allow 保持原值（真实依赖不因告警而清空）。
        @test MarsData.MODULE_REGISTRY[:MarsCommon].kind === :preloaded
        @test MarsData.MODULE_REGISTRY[:MarsCommon].deps == [:constants]
        @test MarsData.MODULE_REGISTRY[:MarsCommon].allow ==
              [:searchsortednearest, :e_energy2v, :ion_energy2v]
        for f in SUBFILES
            stem = Symbol(splitext(basename(f))[1])
            @test !haskey(MarsData.MODULE_REGISTRY, stem)
        end
        # 子文件 include 不引入新的注册表错误/警告（既有 MarsCommon.jl/constants.jl 冗余 include 警告不在此列）
        reg = MarsData.validate_registry()
        @test isempty(reg.errors)
        @test !any(w -> occursin("marscommon/", w), reg.warnings)
        @test !any(w -> any(s -> occursin(basename(s), w), SUBFILES), reg.warnings)
        # 旧定义已从三个源文件移除（t13 起这些文件会合法地被修改，故不再断言“工作区未改动”）：
        # MAVEN_plot 的 Vandermonde/polynomial_fit 改由 MarsCommon 提供；MAVEN_load 的 cyclone_*
        # 与 calculate_models 的四个定义已删。改用「源文件里已无对应本地定义」作耐久不变量。
        for (path, names) in (("MAVEN_data/MAVEN_plot.jl", ["Vandermonde", "polynomial_fit", "vector_angle"]),
                              ("MAVEN_data/MAVEN_load.jl", ["cyclone_frequency", "cyclone_R"]))
            txt = read(joinpath(REPO_ROOT, path), String)
            for nm in names
                @test !occursin(Regex("(?m)^\\s*function\\s+" * nm * "\\s*[\\(;]"), txt)
            end
        end
        # t28：这两个旧入口文件已**物理删除**（旧源由 5f225db 取证），故按存在性断言。
        for path in ("common/head.jl", "calculate/calculate_models.jl")
            @test !isfile(joinpath(REPO_ROOT, path))
        end
    end

    @testset "common/head.jl 迁入组 exact 对比" begin
        slm_o, slm_n = oldof(moveof("safe_log_mean")), newof(moveof("safe_log_mean"))
        for x in ([1.0, 10.0, 100.0], [0.0, 10.0, 100.0], [-1.0, NaN, Inf, 5.0],
                 [0.0, 0.0], Float64[], [1.0e-30, 1.0e30])
            @test isequal(slm_o(x), slm_n(x))
        end

        sn_o, sn_n = oldof(moveof("skipnan")), newof(moveof("skipnan"))
        for x in ([1.0, NaN, 3.0], [NaN, NaN], [1.0, 2.0], Float64[])
            @test isequal(sn_o(copy(x)), sn_n(copy(x)))
            @test typeof(sn_o(copy(x))) === typeof(sn_n(copy(x)))
        end

        nz_o, nz_n = oldof(moveof("nozeros")), newof(moveof("nozeros"))
        @test isequal(nz_o([0.0, 1.0, -2.0, 0.0]), nz_n([0.0, 1.0, -2.0, 0.0]))

        gm_o, gm_n = oldof(moveof("geomean")), newof(moveof("geomean"))
        M = [1.0 10.0 100.0; 2.0 20.0 200.0]
        @test isequal(gm_o(M), gm_n(M))
        @test isequal(gm_o(M; dims = 2), gm_n(M; dims = 2))

        fr_o, fr_n = oldof(moveof("find_range")), newof(moveof("find_range"))
        xr = collect(1.0:5.0)
        @test isequal(fr_o(xr, [2.0, 4.0]), fr_n(xr, [2.0, 4.0]))
        @test typeof(fr_o(xr, [2.0, 4.0])) === typeof(fr_n(xr, [2.0, 4.0]))

        gp_o, gp_n = oldof(moveof("get_normal_plane")), newof(moveof("get_normal_plane"))
        for v in ([1.0, 2.0, 3.0], [0.5, -1.25, 2.0], SVector(2.0, 0.0, 1.0))
            a, b = gp_o(v), gp_n(v)
            @test isequal(a[1], b[1]) && isequal(a[2], b[2])
            @test typeof(a[1]) === typeof(b[1])
        end

        ga_o, ga_n = oldof(moveof("get_angle")), newof(moveof("get_angle"))
        for (p, q) in (([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]),
                       ([1.0, 0.0, 0.0], [1.0, 1.0e-12, 0.0]),
                       ([1.0, 0.0, 0.0], [-1.0, 0.0, 0.0]),
                       (SVector(1.0, 2.0, 3.0), SVector(-2.0, 1.0, 0.5)))
            @test isequal(ga_o(p, q), ga_n(p, q))
        end

        sf_o, sf_n = oldof(moveof("solve_func")), newof(moveof("solve_func"))
        lin = t -> 2.0t - 1.0
        quad = t -> t^2 - 2.0
        @test isequal(sf_o([0.0, 1.0], 0.0, lin), sf_n([0.0, 1.0], 0.0, lin))
        @test isequal(sf_o([0.0, 3.0], 0.0, quad), sf_n([0.0, 3.0], 0.0, quad))
        @test isequal(sf_o([-2.0, 1.57], 1.5, t -> t * 0.5 + 1.0), sf_n([-2.0, 1.57], 1.5, t -> t * 0.5 + 1.0))
    end

    @testset "MAVEN_plot / calculate_models / MAVEN_load 迁入组 exact 对比" begin
        va_o, va_n = oldof(moveof("vector_angle")), newof(moveof("vector_angle"))
        for (a, b) in (([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]),
                       ([1.0, 0.0, 0.0], [-1.0, 0.0, 0.0]),
                       ([0.3, -0.7, 0.2], [0.9, 0.1, -0.4]),
                       (SVector(1.0, 1.0, 0.0), SVector(1.0, -1.0, 0.0)))
            @test isequal(va_o(a, b), va_n(a, b))
        end

        vm_o, vm_n = oldof(moveof("Vandermonde")), newof(moveof("Vandermonde"))
        xv = [1.0, 2.0, 3.0, 4.0]
        @test isequal(vm_o(xv, 2), vm_n(xv, 2))
        @test isequal(vm_n(xv, 0), vm_o(xv, 0))

        pf_o, pf_n = oldof(moveof("polynomial_fit")), newof(moveof("polynomial_fit"))
        xp = collect(1.0:6.0)
        yp = exp.(-0.35 .* xp)
        @test isequal(pf_o(xp, yp, 1), pf_n(xp, yp, 1))
        @test isequal(pf_o(xp, yp, 2), pf_n(xp, yp, 2))
        yp_nan = copy(yp)
        yp_nan[3] = NaN
        yp_nan[5] = Inf
        @test isequal(pf_o(xp, yp_nan, 1), pf_n(xp, yp_nan, 1))

        lf_o, lf_n = oldof(moveof("Linear_fit")), newof(moveof("Linear_fit"))
        for (xf, yf) in ((collect(1.0:5.0), [2.0, 4.0, 6.0, 8.0, 10.0]),
                         (collect(1.0:5.0), [1.3, 2.1, 2.6, 4.4, 5.2]),
                         (collect(1.0:4.0), fill(3.5, 4)))   # y 恒定 → r_squared 走 SST≈0 分支
            a, b = lf_o(xf, yf), lf_n(xf, yf)
            @test keys(a) == keys(b)
            @test isequal(a.P1, b.P1) && isequal(a.P2, b.P2)
            @test isequal(a.r_squared, b.r_squared)
            @test isequal(a.fit_function(2.5), b.fit_function(2.5))
        end

        cr_o, cr_n = oldof(moveof("cyclotron_radius")), newof(moveof("cyclotron_radius"))
        cf_o, cf_n = oldof(moveof("cyclotron_frequency")), newof(moveof("cyclotron_frequency"))
        for (B, ek, nM, nQ) in ((200.0, 100.0, 32, 1), (200.0, 100.0, 1, -1),
                                (50.0, 1.0e3, 16, 1), (12.5, 4.0, 44, 2))
            @test isequal(cr_o(B, ek; nM = nM, nQ = nQ), cr_n(B, ek; nM = nM, nQ = nQ))
            @test isequal(cf_o(B; nM = nM, nQ = nQ), cf_n(B; nM = nM, nQ = nQ))
        end
        # 数值签名默认值保持（默认调用 == 显式默认调用，且在两侧同值）
        @test isequal(cr_o(200.0, 100.0), cr_n(200.0, 100.0))
        @test isequal(cr_n(200.0, 100.0), cr_n(200.0, 100.0; nM = 1, nQ = -1))
        @test isequal(cf_n(200.0), cf_n(200.0; nM = 1, nQ = -1))
        @test isequal(cf_o(200.0), cf_n(200.0))

        cfk_o, cfk_n = oldof(moveof("cyclotron_frequency_kg")), newof(moveof("cyclotron_frequency_kg"))
        crv_o, crv_n = oldof(moveof("cyclotron_radius_velocity")), newof(moveof("cyclotron_radius_velocity"))
        @test isequal(cfk_o(200.0), cfk_n(200.0))                       # 默认 mass=constants.me
        @test isequal(cfk_o(200.0; mass = MC.constants.mp),
                      cfk_n(200.0; mass = MC.constants.mp))
        @test isequal(crv_o(1.0e5, 200.0), crv_n(1.0e5, 200.0))
        @test isequal(crv_o(1.0e5, 200.0; mass = MC.constants.mp),
                      crv_n(1.0e5, 200.0; mass = MC.constants.mp))
        # 默认 mass 保持为 constants.me
        @test isequal(cfk_n(200.0), cfk_n(200.0; mass = MC.constants.me))
        @test isequal(crv_n(1.0e5, 200.0), crv_n(1.0e5, 200.0; mass = MC.constants.me))
    end

    @testset "NaN / 抛错 / 副作用保持" begin
        # NaN 传播
        ga_o, ga_n = oldof(moveof("get_angle")), newof(moveof("get_angle"))
        # 零向量：实测既有行为是 atand(0.0, 0.0) == 0.0（旧 docstring 写“返回 NaN”与实现不符）；
        # 本次为纯迁入，保持文本与行为原样，只在此固化实测口径供集成单元知悉。
        @test isequal(ga_o([0.0, 0.0, 0.0], [1.0, 0.0, 0.0]), ga_n([0.0, 0.0, 0.0], [1.0, 0.0, 0.0]))
        @test ga_n([0.0, 0.0, 0.0], [1.0, 0.0, 0.0]) == 0.0

        va_o, va_n = oldof(moveof("vector_angle")), newof(moveof("vector_angle"))
        @test isnan(va_o([0.0, 0.0, 0.0], [1.0, 0.0, 0.0]))
        @test isnan(va_n([0.0, 0.0, 0.0], [1.0, 0.0, 0.0]))

        # solve_func 端点同号 → NaN64（不抛错）
        sf_o, sf_n = oldof(moveof("solve_func")), newof(moveof("solve_func"))
        same = t -> t + 1.0
        @test isnan(sf_o([0.0, 1.0], 0.0, same))
        @test isnan(sf_n([0.0, 1.0], 0.0, same))

        # polynomial_fit 有效点不足 → ErrorException
        pf_o, pf_n = oldof(moveof("polynomial_fit")), newof(moveof("polynomial_fit"))
        @test_throws ErrorException pf_o([1.0], [1.0], 1)
        @test_throws ErrorException pf_n([1.0], [1.0], 1)
        @test_throws ErrorException pf_n([1.0, 2.0], [1.0, NaN], 1)

        # Linear_fit 三种非法输入 → ErrorException
        lf_o, lf_n = oldof(moveof("Linear_fit")), newof(moveof("Linear_fit"))
        @test_throws ErrorException lf_o([1.0, 2.0], [1.0])
        @test_throws ErrorException lf_n([1.0, 2.0], [1.0])
        @test_throws ErrorException lf_o([1.0], [1.0])
        @test_throws ErrorException lf_n([1.0], [1.0])
        @test_throws ErrorException lf_o([2.0, 2.0, 2.0], [1.0, 2.0, 3.0])
        @test_throws ErrorException lf_n([2.0, 2.0, 2.0], [1.0, 2.0, 3.0])

        # 副作用：nozeros 原地修改并返回同一对象
        nz_o, nz_n = oldof(moveof("nozeros")), newof(moveof("nozeros"))
        xo = [0.0, 1.0, -1.0, 0.0]
        xn = copy(xo)
        @test nz_o(xo) === xo
        @test nz_n(xn) === xn
        @test isequal(xo, xn)
        @test isequal(xn, [1.0e-20, 1.0, -1.0, 1.0e-20])

        # 副作用：skipnan 返回新数组，不改入参
        sn_o, sn_n = oldof(moveof("skipnan")), newof(moveof("skipnan"))
        io_ = [1.0, NaN, 3.0]
        in_ = copy(io_)
        ro, rn = sn_o(io_), sn_n(in_)
        @test ro !== io_ && rn !== in_
        @test isequal(io_, [1.0, NaN, 3.0]) && isequal(in_, [1.0, NaN, 3.0])
        @test isequal(ro, rn)
    end

    @testset "清单 validation/migrations/common.toml 逐函数核对" begin
        @test isfile(MANIFEST)
        doc = TOML.parsefile(MANIFEST)
        @test haskey(doc, "moves")
        rows = doc["moves"]
        @test length(rows) == length(MOVES)
        @test sort([r["name"] for r in rows]) == sort([m.name for m in MOVES])
        for m in MOVES
            idx = findfirst(r -> r["name"] == m.name, rows)
            @test idx !== nothing
            idx === nothing && continue
            r = rows[idx]
            # schema：from/to/name/status/source_hash（重命名行额外带 source_name）
            @test issubset(["from", "to", "name", "status", "source_hash"], collect(keys(r)))
            @test issubset(collect(keys(r)),
                           ["from", "to", "name", "status", "source_hash", "source_name",
                            "target_hash", "notes", "source_revision", "source_hash_kind"])
            @test r["from"] == m.from
            @test r["to"] == m.to
            @test get(r, "source_name", m.name) == m.src
            # t28：工具已支持 from 文件合法删除 + 限定基座解析，common 全部行均可终化。
            @test r["status"] == "finalized"
            @test occursin(r"^[0-9a-f]{64}$", lowercase(String(r["target_hash"])))
            @test r["source_hash"] == sha16(extract_old_function(old_source(m.from), m.src))
        end
    end
end
