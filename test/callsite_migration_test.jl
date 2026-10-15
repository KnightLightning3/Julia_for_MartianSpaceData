# ============================================================================
# test/callsite_migration_test.jl
# t13 调用点接线回归（真实入口；不依赖外部数据与 DLL）
#
# 覆盖：
#   1) head.jl / calculate_models.jl 旧入口已移除且全仓无消费者；
#   2) Pickup_ion.jl 的显式模块载入与三个新权威调用点（FC.slice2d_cal_rot、
#      MarsEnvironment.bowshock_zero、MarsCommon.*），旧裸名零残留；
#   3) carclu_SWEA_pad 迁入 MAVEN_SWEA（MAVEN_load 不再持有/导出），example 同步；
#   4) static_c6_* 旧副本已删，且以 5f225db 旧实现在**旧输入（无 :df）**上证等价；
#   5) 策略 P（MarsCommon/MarsEnvironment 预装同实例）、环境变体、TimeFormat 两版；
#   6) 保留例外：mean_SWEA_pad_pa 保持 loader 层原行为（swea.toml [[retained]]，非迁移单元，源码零改动）。
# 运行：julia --project=. test/callsite_migration_test.jl
# ============================================================================

using Test
using MarsData
using Statistics
using Dates

const REPO = normpath(joinpath(@__DIR__, ".."))
const SRC_REV = "5f225db"

module CallsiteOldSandbox
using Statistics
end

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

# 用 Meta.parse 偏移量精确取界（不依赖 AST 行号，也不靠 end 文本匹配）
function extract_fn(src::String, name::AbstractString)
    lines = split(src, '\n'; keepempty = true)
    offs = _offsets(src)
    i = findfirst(l -> occursin(Regex("^\\s*function\\s+" * name * "\\s*\\("), l), lines)
    i === nothing && error("未在旧源中找到函数 $name")
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

old_load_src() = String(read(`git -C $(REPO) show $(SRC_REV):MAVEN_data/MAVEN_load.jl`))

function load_old_fn(name)
    sym = Symbol(name)
    if !isdefined(CallsiteOldSandbox, sym)
        Base.include_string(CallsiteOldSandbox, extract_fn(old_load_src(), name),
                            "$(SRC_REV):MAVEN_data/MAVEN_load.jl:$(name)")
    end
    return getfield(CallsiteOldSandbox, sym)
end

filetxt(rel) = read(joinpath(REPO, rel), String)

@testset "t13 调用点接线回归" begin
    @testset "旧入口已真删、零消费者（t28：清单补 source_revision 后物理删除）" begin
        # t27 工具支持「from 文件合法删除」：清单补 source_revision = "5f225db" 后即可真删，
        # 由工具 git show 5f225db:<path> 取证旧源定义，不再需要空壳。
        @test !isfile(joinpath(REPO, "common", "head.jl"))
        @test !isfile(joinpath(REPO, "calculate", "calculate_models.jl"))
        @test !haskey(MarsData.MODULE_REGISTRY, :calculate_models)   # 注册条目已随空壳拆除
        # 两文件已物理删除（不再是适配工具的空壳）；旧定义只存在于 5f225db 取证路径。
        @test !isfile(joinpath(REPO, "common", "head.jl"))
        @test !isfile(joinpath(REPO, "calculate", "calculate_models.jl"))
        for rel in ("models/Pickup_ion.jl", "MAVEN_data/MAVEN_plot.jl", "MAVEN_data/MAVEN_load.jl",
                    "MAVEN_data/MAVEN_SWEA.jl", "MAVEN_data/Build_data/STATIC_VD.jl")
            isfile(joinpath(REPO, rel)) || continue
            txt = filetxt(rel)
            # 只认「行首的有效 include 语句」；注释里提到 head.jl 的说明文字不计
            @test !occursin(Regex("(?m)^\\s*include\\(\"\\.\\./common/head\\.jl\"\\)"), txt)
            @test !occursin(Regex("(?m)^\\s*include\\(joinpath\\(@__DIR__, \"\\.\\.\", \"common\", \"head\\.jl\"\\)\\)"), txt)
        end
        reg = MarsData.validate_registry()
        @test isempty(reg.errors)
    end

    @testset "Pickup_ion.jl：显式载入 + 三处新权威 + 旧裸名零残留" begin
        # head.jl 零 includer（唯一旧消费者 Pickup 已显式化）
        @test !any(rel -> occursin(Regex("(?m)^\\s*include\\(.*head\\.jl.*\\)"),
                                   filetxt(rel)),
                   ["models/Pickup_ion.jl", "MAVEN_data/MAVEN_load.jl", "MAVEN_data/MAVEN_SWEA.jl"])
        txt = filetxt("models/Pickup_ion.jl")
        @test occursin("import MarsData", txt)              # 刻意 import（避免 @load 与 JLD2 冲突）
        @test occursin("using DataFrames", txt)
        @test occursin("using JLD2", txt)
        @test occursin("MarsData.@load MAVEN_load MAVEN_plot MAVEN_STATIC MAVEN_SWIA IGRF_calculate", txt)
        @test occursin("const MarsCommon = MarsData.MarsCommon", txt)
        @test occursin("const MarsEnvironment = MarsData.MarsEnvironment", txt)
        @test occursin("include(joinpath(@__DIR__, \"..\", \"common\", \"function_coordinate.jl\"))", txt)
        # 新权威限定名（真实调用点）
        @test occursin("MarsEnvironment.bowshock_zero(", txt)
        @test occursin("FunctionCoordinate.slice2d_cal_rot(", txt)
        @test occursin("MarsCommon.get_angle(", txt)
        @test occursin("MarsCommon.searchsortednearest_range(", txt)
        @test occursin("MarsCommon.searchsortednearest(time_", txt)
        # 旧裸名零残留
        @test !occursin(Regex("(?<!MarsEnvironment\\.)bowshock_zero\\("), txt)
        @test !occursin(Regex("(?<!FunctionCoordinate\\.)slice2d_cal_rot\\("), txt)
        @test !occursin(Regex("(?<!MarsCommon\\.)get_angle\\("), txt)
        @test !occursin(Regex("(?<!MarsCommon\\.)searchsortednearest"), txt)
        # 仍可解析
        ex = Meta.parseall(txt)
        @test ex isa Expr
        # 真实入口：模块对象层面确实可取到这些权威（非文本断言）
        @test MarsData.MarsEnvironment.bowshock_zero(1.0) === MarsData.MarsEnvironment.bowshock(1.0)
        @test MarsData.MarsCommon.get_angle([1.0, 0, 0], [0.0, 1.0, 0]) == 90.0
        fc_txt = filetxt("common/function_coordinate.jl")
        @test occursin("module FunctionCoordinate", fc_txt)
    end

    @testset "carclu_SWEA_pad 迁入 MAVEN_SWEA 且 example 同步" begin
        swea_txt = filetxt("MAVEN_data/MAVEN_SWEA.jl")
        load_txt = filetxt("MAVEN_data/MAVEN_load.jl")
        @test occursin(Regex("(?m)^\\s*function\\s+carclu_SWEA_pad\\s*\\("), swea_txt)
        @test !occursin(Regex("(?m)^\\s*function\\s+carclu_SWEA_pad\\s*\\("), load_txt)
        @test !occursin("export mean_SWEA_pad_pa, carclu_SWEA_pad", load_txt)
        @test occursin("export mean_SWEA_pad_pa", load_txt)
        SW = MarsData.load_module(:MAVEN_SWEA)
        LD = MarsData.load_module(:MAVEN_load)
        @test isdefined(SW, :carclu_SWEA_pad)
        @test !isdefined(LD, :carclu_SWEA_pad)
        # t33：mean_SWEA_pad_pa = loader 层【保留例外】（记录于 swea.toml 的 [[retained]]，非迁移单元）。
        # 断言真实调用链仍在、函数仍在 loader、未出现在 SWEA（不冒充已迁移）。
        @test isdefined(LD, :mean_SWEA_pad_pa)
        @test !isdefined(SW, :mean_SWEA_pad_pa)
        @test haskey(LD.LOADER_FUNCS, "load_swea_pad")
        @test LD.LOADER_FUNCS["load_swea_pad"] === LD.load_swea_pad
        load_txt_mean = filetxt("MAVEN_data/MAVEN_load.jl")
        @test occursin(Regex("function\\s+load_swea_pad\\(.*mean_PA\\s*=\\s*true"), load_txt_mean)
        @test occursin("mean_SWEA_pad_pa(data_dict)", load_txt_mean)
        swea_toml_txt = filetxt("validation/migrations/swea.toml")
        @test occursin("[[retained]]", swea_toml_txt)
        @test occursin("status          = \"retained\"", swea_toml_txt)
        for rel in ("example/MAVEN_plot_sample/MAVEN_overview_cases.jl",
                    "example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl")
            txt = filetxt(rel)
            @test occursin("MAVEN_SWEA.carclu_SWEA_pad", txt)
            @test !occursin("MAVEN_load.carclu_SWEA_pad", txt)
        end
    end

    @testset "static_c6_*：旧副本已删，旧输入（无 :df）上与 5f225db 旧实现 exact" begin
        load_txt = filetxt("MAVEN_data/MAVEN_load.jl")
        for nm in ("static_c6_mass_mean", "static_c6_energy_mean")
            @test !occursin(Regex("(?m)^\\s*function\\s+" * nm * "\\s*\\("), load_txt)
        end
        STA = MarsData.load_module(:MAVEN_STATIC)
        # 旧输入夹具（无 :df 键 ⇒ 两实现共享同一分支）
        nmass, nenergy, nswp, ntime = 2, 3, 2, 2
        E = [10.0 * k + j for i in 1:nmass, j in 1:nenergy, k in 1:nswp]
        dE = [1.0 + 0.1 * k for i in 1:nmass, j in 1:nenergy, k in 1:nswp]
        MA = [i == 1 ? 1.0 : 16.0 for i in 1:nmass, j in 1:nenergy, k in 1:nswp]
        ef = [3.0 * (1 + t + i + j) for t in 1:ntime, i in 1:nmass, j in 1:nenergy]
        fx = Dict{Symbol,Any}(:epoch => [1, 2], :energy => E, :denergy => dE, :eflux => ef,
                             :swp_ind => [0, 1], :apid => 42, :mass_arr => MA,
                             :num_dists => ntime, :nmass => nmass, :nswp => nswp, :nenergy => nenergy)
        for nm in ("static_c6_mass_mean", "static_c6_energy_mean")
            oldf = load_old_fn(nm)
            newf = getfield(STA, Symbol(nm))
            o = oldf(deepcopy(fx))
            n = newf(deepcopy(fx))
            @test keys(o) == keys(n)
            for k in keys(o)
                @test isequal(o[k], n[k])       # 旧输入上逐位一致
            end
        end
    end

    @testset "策略 P / 环境变体 / TimeFormat" begin
        MP = MarsData.MAVEN_plot
        @test MarsData.MarsCommon === MP.MarsCommon
        @test MarsData.MarsEnvironment === MP.MarsEnvironment
        @test MarsData.load_module(:MarsCommon) === MP.MarsCommon
        @test MarsData.load_module(:MarsEnvironment) === MP.MarsEnvironment
        @test MarsData.MODULE_REGISTRY[:MarsCommon].kind === :preloaded
        @test MarsData.MODULE_REGISTRY[:MarsEnvironment].kind === :preloaded
        @test MarsData.MODULE_REGISTRY[:constants].kind === :module
        @test !haskey(MarsData.MODULE_REGISTRY, :Mars_Environment)
        @test MP.bowshock === MP.MarsEnvironment.bowshock
        @test MP.bowshock(1.0) === MP.bowshock_plot_nan64(1.0)
        @test MP.bowshock(2.0) isa Float32 && MP.bowshock_plot_nan64(2.0) isa Float64
        @test MarsData.TimeFormat(DateTime(2020, 1, 1), DateTime(2020, 1, 1, 1, 2, 3, 4)) == "01:02:03.004"
        SPO = MarsData.load_module(:Single_Particle_Orbit)
        @test SPO.TimeFormatMMSS(DateTime(2020, 1, 1), DateTime(2020, 1, 1, 1, 2, 3, 4)) == "02:03.004"
        @test !isdefined(SPO, :TimeFormat)
    end
end
