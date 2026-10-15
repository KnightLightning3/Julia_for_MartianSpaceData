# ============================================================================
# test/swea_migration_test.jl
#
# SWEA shape 闭包（4 常量 + SWEA_calc_shape_arr(含嵌套 mvn_swe_calc_shape_arr→deriv)
# + SWEA_calc_shape_arr_mars_towrads）自 MAVEN_data/MAVEN_load.jl 迁入
# MAVEN_data/MAVEN_SWEA.jl 的局部回归（t25）。
#
# 运行：julia --project=. test/swea_migration_test.jl
#
# 口径：
#   · 旧实现 oracle 独立取自 git 对象 5f225db（`git show 5f225db:<path>`），
#     常量按 `const NAME =` 行取、函数按函数块精确取界，include_string 到独立沙箱模块，
#     不依赖工作区源码副本；
#   · 迁入函数与 oracle 做 exact（isequal）对比，并单独覆盖 NaN / 异常类型 / arc·svy 分支；
#   · 逐函数 from/to/name/status/source_hash/target_hash 清单在 validation/migrations/swea.toml，
#     本测试按 5f225db 重算 source_hash、按 AST 工具重算 target_hash 并逐行核对；
#   · PAD 侧 mean_SWEA_pad_pa / carclu_SWEA_pad 经核验无法在「仅两源码文件」内诚实接线
#     （load_swea_pad 公开默认 mean_PA=true；example 以 MAVEN_load.carclu_SWEA_pad 限定名调用），
#     本批留原定义不作强删，清单标 pending 并写明阻塞原因。
# ============================================================================

using Test
using TOML
using SHA
using MarsData

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const SRC_REV = "5f225db"
const SRC_FILE = "MAVEN_data/MAVEN_load.jl"
const DST_FILE = "MAVEN_data/MAVEN_SWEA.jl"
const MANIFEST = joinpath(REPO_ROOT, "validation", "migrations", "swea.toml")

if !isdefined(Main, :ASTMigrate)
    include(joinpath(REPO_ROOT, "validation", "ast", "ASTMigrate.jl"))
end

# 期望迁入表（测试自带，独立于 TOML）
const MOVED = ["SWEA_N_ENERGY_BINS", "SWEA_SHAPE_FIRST_BIN", "SWEA_SHAPE_LAST_BIN",
               "SWEA_SHAPE_NBINS", "SWEA_calc_shape_arr", "SWEA_calc_shape_arr_mars_towrads"]
const CONSTS = ["SWEA_N_ENERGY_BINS", "SWEA_SHAPE_FIRST_BIN", "SWEA_SHAPE_LAST_BIN",
                "SWEA_SHAPE_NBINS"]
# t33：mean_SWEA_pad_pa 经 t32/t33 核定为 loader 层【保留例外】（swea.toml [[retained]]，**不在 moves**）：
# 不再计作“待迁入/阻塞”，测试改为断言原调用链存在、函数仍在 loader 且未出现在 SWEA。
const RETAINED = ["mean_SWEA_pad_pa"]
const MOVED_BY_T13 = ["carclu_SWEA_pad"]

# ---------------------------------------------------------------------------
# 5f225db oracle 沙箱
# ---------------------------------------------------------------------------

module SweaMigrationOracle
using Statistics
end

module SweaMigrationScratch end

Base.include(SweaMigrationOracle, joinpath(REPO_ROOT, "common", "MarsCommon.jl"))

const _SRC_CACHE = Ref{String}()
function old_source()
    isassigned(_SRC_CACHE) && return _SRC_CACHE[]
    s = String(read(`git -C $(REPO_ROOT) show $(SRC_REV):$(SRC_FILE)`))
    _SRC_CACHE[] = s
    return s
end

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

"""从 5f225db 源文里取出函数完整块（含紧邻 docstring），取界用 Meta.parse 偏移量。"""
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

"""从 5f225db 源文里取出 `const NAME = ...` 单行。"""
function extract_old_const(src::String, name::AbstractString)
    lines = split(src, '\n'; keepempty = true)
    re = Regex("^\\s*const\\s+" * name * "\\s*=")
    i = findfirst(l -> occursin(re, l), lines)
    i === nothing && error("5f225db 源码中未找到 const $name")
    return strip(lines[i])
end

old_block_text(name::AbstractString) =
    name in CONSTS ? extract_old_const(old_source(), name) :
    extract_old_function(old_source(), name)

function old_func(name::AbstractString)
    sym = Symbol(name)
    if !isdefined(SweaMigrationOracle, sym)
        Base.include_string(SweaMigrationOracle, old_block_text(name),
                            "$(SRC_REV):$(SRC_FILE):$(name)")
    end
    return getfield(SweaMigrationOracle, sym)
end

sha16(s) = uppercase(bytes2hex(SHA.sha256(codeunits(s)))[1:16])

# 被测模块：经注册表装载
const MS = MarsData.load_module(:MAVEN_SWEA; into = SweaMigrationScratch)
new_func(name::AbstractString) = getfield(MS, Symbol(name))

# oracle 沙箱先按定义顺序注入 4 个常量（旧函数体与 docstring 插值都引用它们）
for nm in CONSTS
    old_func(nm)
end

# ---------------------------------------------------------------------------
# 合成夹具（SWEA PAD 形状）
# ---------------------------------------------------------------------------

const NE = 64          # SWEA_N_ENERGY_BINS
const NPA = 16
const NT = 4

"""构造 filename，使 `filename[end-26:end-24] == tag`（原代码用该切片判 arc/svy）。"""
mkname(tag::AbstractString) = "mvn_swe_l2_" * tag * "Z"^24

function swea_dat(; filename = mkname("arc"), energy = collect(range(5.0, 200.0; length = NE)),
                  ntime = NT)
    pa = Array{Float64}(undef, ntime, NPA, NE)
    for t in 1:ntime, k in 1:NPA, e in 1:NE
        pa[t, k, e] = (k - 1) * (180.0 / (NPA - 1))
    end
    flux = fill(1.0e5, ntime, NPA, NE)
    ntime >= 2 && (flux[2, :, :] .= NaN)          # 全 NaN 行 → par 应为 NaN
    ntime >= 3 && (flux[3, 1, 1] = NaN)           # 窗口外 NaN → 该行仍应有效
    return Dict{Symbol,Any}(
        :filename => filename,
        :num_dists => ntime,
        :energy => collect(energy),
        :pa => pa,
        :d_pa => ones(ntime, NPA, NE),
        :diff_en_fluxes => flux,
        :epoch => collect(1.0:ntime),
    )
end

function mag_dat(; scale = 0.5)
    position = [1.0 0.0 0.0; 0.0 1.0 0.0; 1.0 1.0 0.0; 0.0 0.0 1.0]
    pnorm = position ./ sqrt.(sum(position .^ 2, dims = 2))
    return Dict{Symbol,Any}(
        :epoch => collect(1.0:NT),
        :position => position,
        :B => scale .* pnorm,
        :B_total => fill(1.0, NT),
    )
end

errtype(f) = try
    f()
    nothing
catch e
    typeof(e)
end

compare_shape(o, n, dat; kws...) = isequal(o(deepcopy(dat); kws...), n(deepcopy(dat); kws...))

@testset "SWEA shape 闭包迁入（t25）" begin
    @testset "迁入面与范围（无兼容别名、源定义已删）" begin
        ML = MarsData.load_module(:MAVEN_load)
        for nm in MOVED
            @test isdefined(MS, Symbol(nm))
        end
        # 旧位置不再有定义（真删，不是 alias/wrapper）
        for nm in MOVED
            @test !isdefined(ML, Symbol(nm))
        end
        # 常量值与原意一致（13:64 共 52 道）
        @test MS.SWEA_N_ENERGY_BINS == 64
        @test MS.SWEA_SHAPE_FIRST_BIN == 13
        @test MS.SWEA_SHAPE_LAST_BIN == 64
        @test MS.SWEA_SHAPE_NBINS == 52
        @test MS.SWEA_SHAPE_NBINS == MS.SWEA_SHAPE_LAST_BIN - MS.SWEA_SHAPE_FIRST_BIN + 1
        # t33 保留例外：断言原链存在（loader 层，非迁移单元）
        for nm in RETAINED
            @test isdefined(ML, Symbol(nm))       # 仍在 loader 层（与唯一调用者同层）
            @test !isdefined(MS, Symbol(nm))      # 未出现在 SWEA（不冒充已迁移）
        end
        @test haskey(ML.LOADER_FUNCS, "load_swea_pad")               # JSON 驱动的真实调用链仍在
        @test ML.LOADER_FUNCS["load_swea_pad"] === ML.load_swea_pad
        load_src = read(joinpath(REPO_ROOT, SRC_FILE), String)
        @test occursin(Regex("function\\s+load_swea_pad\\(.*mean_PA\\s*=\\s*true"), load_src)
        @test occursin("mean_SWEA_pad_pa(data_dict)", load_src)
        # t13 完成的 carclu_SWEA_pad：已迁入 SWEA
        for nm in MOVED_BY_T13
            @test isdefined(MS, Symbol(nm))
            @test !isdefined(ML, Symbol(nm))
        end
        # 嵌套私有 helper 随父函数整块搬入（不在顶层，故不作为独立清单行）
        sc_src = read(joinpath(REPO_ROOT, DST_FILE), String)
        @test occursin("function mvn_swe_calc_shape_arr(", sc_src)
        @test occursin("function deriv(", sc_src)
        old_src = old_source()
        @test occursin("function mvn_swe_calc_shape_arr(", old_src)
        @test !occursin("function SWEA_calc_shape_arr(", read(joinpath(REPO_ROOT, SRC_FILE), String))
    end

    @testset "SWEA_calc_shape_arr 与 5f225db oracle exact 对比" begin
        o, n = old_func("SWEA_calc_shape_arr"), new_func("SWEA_calc_shape_arr")
        arc = swea_dat(filename = mkname("arc"))
        svy = swea_dat(filename = mkname("svy"))

        # 1) 默认参数（arc 分支，hresflg=true）
        r_o, r_n = o(deepcopy(arc)), n(deepcopy(arc))
        @test isequal(r_o, r_n)
        @test typeof(r_o) === typeof(r_n) === Vector{Float64}
        @test length(r_o) == NT
        @test isnan(r_o[2]) && isnan(r_n[2])          # 全 NaN 行
        @test all(isfinite, r_o[[1, 3, 4]])           # 窗口外 NaN 不影响有效行

        # 2) svy 分支（hresflg=false → df_lres）
        @test compare_shape(o, n, svy)
        @test !isequal(o(deepcopy(svy)), o(deepcopy(arc)))   # 两分支确不同（模板不同）

        # 3) time_i 子集 / 不同能量窗 / 不同 PA 窗
        @test compare_shape(o, n, arc; time_i = 2:3)
        @test compare_shape(o, n, arc; energy_range = [20.0, 60.0])
        @test compare_shape(o, n, arc; pad_range = [60.0, 120.0])
        @test compare_shape(o, n, arc; energy_range = [30.0, 200.0], pad_range = [0.0, 180.0])
        @test isequal(o(deepcopy(arc); time_i = 2:3), n(deepcopy(arc); time_i = 2:3))

        # 4) 入参不被就地改写（两边都只改切片副本）
        a1, a2 = deepcopy(arc), deepcopy(arc)
        o(a1); n(a2)
        @test isequal(a1[:diff_en_fluxes], a2[:diff_en_fluxes])
        @test isequal(a1[:energy], a2[:energy])

        # 5) 异常类型一致：能量窗只余 2 道 → deriv 越界
        fine = swea_dat(energy = collect(1.0:NE))
        @test errtype(() -> o(deepcopy(fine); energy_range = [20.0, 21.0])) ===
              errtype(() -> n(deepcopy(fine); energy_range = [20.0, 21.0]))
        @test errtype(() -> o(deepcopy(fine); energy_range = [20.0, 21.0])) !== nothing

        # 6) 异常类型一致：filename 太短（原代码按 end-26:end-24 取切片）
        short = swea_dat(filename = "short.cdf")
        @test errtype(() -> o(deepcopy(short))) === errtype(() -> n(deepcopy(short)))
        @test errtype(() -> o(deepcopy(short))) !== nothing

        # 7) 异常类型一致：形状不匹配
        bad = swea_dat()
        bad[:d_pa] = ones(NT, NPA, NE - 1)
        @test errtype(() -> o(deepcopy(bad))) === errtype(() -> n(deepcopy(bad)))
    end

    @testset "SWEA_calc_shape_arr_mars_towrads 与 oracle exact 对比" begin
        o, n = old_func("SWEA_calc_shape_arr_mars_towrads"), new_func("SWEA_calc_shape_arr_mars_towrads")
        sdat, mdat = swea_dat(), mag_dat()

        ro = o(deepcopy(sdat), deepcopy(mdat))
        rn = n(deepcopy(sdat), deepcopy(mdat))
        @test length(ro) == length(rn) == 3
        for i in 1:3
            @test isequal(ro[i], rn[i])
            @test typeof(ro[i]) === typeof(rn[i])
        end
        # 指向/背离来自 B_out 的两分支，且与中间窗互补
        @test isequal(ro[3], o(deepcopy(sdat), deepcopy(mdat))[3])

        # time_i 子集
        ro2 = o(deepcopy(sdat), deepcopy(mdat); time_i = 2:3)
        rn2 = n(deepcopy(sdat), deepcopy(mdat); time_i = 2:3)
        @test all(isequal(ro2[i], rn2[i]) for i in 1:3)
        @test length(ro2[1]) == 2

        # 异常类型一致：B 与位置完全平行（acos 边界）
        m1 = mag_dat(scale = 1.0)
        @test errtype(() -> o(deepcopy(sdat), deepcopy(m1))) ===
              errtype(() -> n(deepcopy(sdat), deepcopy(m1)))

        # 异常类型一致：MAG 缺键
        m2 = mag_dat()
        delete!(m2, :B_total)
        @test errtype(() -> o(deepcopy(sdat), deepcopy(m2))) ===
              errtype(() -> n(deepcopy(sdat), deepcopy(m2)))
    end

    @testset "清单 validation/migrations/swea.toml 逐行核对" begin
        @test isfile(MANIFEST)
        doc = TOML.parsefile(MANIFEST)
        @test get(doc, "schema_version", 1) == 1
        @test haskey(doc, "moves")
        rows = doc["moves"]
        # t33：保留例外已移出 moves ⇒ 行数 = MOVED + MOVED_BY_T13（RETAINED 不在 moves）
        @test length(rows) == length(MOVED) + length(MOVED_BY_T13)
        @test sort([r["name"] for r in rows]) == sort(vcat(MOVED, MOVED_BY_T13))
        @test !any(r -> r["name"] in RETAINED, rows)
        # [[retained]] 独立登记：含唯一调用者 / 原定目标 / 保留理由，且**不标 finalized、不写 target_hash**
        retained = get(doc, "retained", [])
        @test length(retained) == length(RETAINED)
        for rr in retained
            @test String(rr["name"]) in RETAINED
            @test rr["status"] == "retained"
            @test rr["from"] == SRC_FILE
            @test rr["planned_target"] == DST_FILE
            @test haskey(rr, "sole_caller") && haskey(rr, "reason")
            @test occursin("load_swea_pad", String(rr["sole_caller"]))
            @test occursin("mean_PA", String(rr["reason"])) || occursin("loader", lowercase(String(rr["reason"])))
            @test !haskey(rr, "target_hash")                 # 不冒称迁移完成
        end
        for r in rows
            nm = r["name"]
            # 5 字段 + 口径标注 / 目标哈希
            @test issubset(["from", "to", "name", "status", "source_hash"], collect(keys(r)))
            @test r["from"] == SRC_FILE
            @test r["to"] == DST_FILE
            @test r["source_hash"] == sha16(old_block_text(nm))     # 旧源块溯源（前 16 位）
            @test get(r, "source_hash_kind", "") == "sha256-source-block-first16"
            @test get(r, "source_revision", "") == SRC_REV
            if !(nm in RETAINED)                      # t33：moves 内已无 pending（保留例外已移出）
                @test r["status"] == "finalized"
                # 目标规范 AST 哈希必须与工作区真实定义一致（与 --print-hash 同源）
                h = ASTMigrate.definition_hash(REPO_ROOT, DST_FILE, nm)
                @test h isa String && length(h) == 64
                @test r["target_hash"] == h
                @test length(r["target_hash"]) == 64
            else
                @test r["status"] == "pending"                      # 留原定义 → 不冒称完成
                @test !haskey(r, "target_hash")
                @test occursin("阻塞", get(r, "notes", ""))
            end
        end
    end
end
