# MarsData 模块装载管理器测试（阶段 A）
#
# 运行：julia --project=. test/runtests.jl
#
# 约定：不触碰真实科学数据、不做网络下载；重模块只做一次冒烟装载。

using Test
using MarsData
using Dates

# `module` 只能定义在顶层，故 scratch 命名空间放在测试集之外
module ScratchBlank end
module ScratchAllow end
module ScratchWhitelist end

# 顶层验证 `@load` 的脚本用法（展开为 const 赋值）
MarsData.@load MAVEN_SWEA

@testset "MarsData 模块装载管理器" begin
    @testset "注册表自检" begin
        problems = MarsData.validate_registry()
        if !isempty(problems)
            foreach(p -> @info "注册表问题" p, problems)
        end
        @test isempty(problems)
    end

    @testset "查询 API" begin
        avail = MarsData.available_modules()
        @test :MAVEN_load in avail
        @test :MAVEN_STATIC in avail
        @test :MAVEN_SWIA in avail
        @test :MAVEN_SWEA in avail
        @test :IGRF_calculate in avail
        @test :Cold_Plasma_Dispersion_Relation in avail
        @test length(avail) == length(MarsData.MODULE_REGISTRY)
        @test issorted(avail)

        @test MarsData.module_path(:MAVEN_SWEA) ==
              joinpath(MarsData.project_root(), "MAVEN_data", "MAVEN_SWEA.jl")

        info = MarsData.module_info(:MAVEN_load)
        @test info.name === :MAVEN_load
        @test info.kind === :module
        @test issubset([:constants, :MarsCommon, :Paths], info.deps)
        @test info.allow == [:load_cdf, :load_MAVEN_data]   # 已开放的白名单
        @test info.loaded isa Bool
    end

    @testset "未知名报错并给出相近建议" begin
        err = try
            MarsData.load_module(:MAVEN_loa)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("MAVEN_loa", msg)
        @test occursin("MAVEN_load", msg)   # 编辑距离建议

        @test_throws ArgumentError MarsData.module_path(:NotAModule)
    end

    @testset "幂等：重复装载返回同一对象" begin
        m1 = MarsData.load_module(:MAVEN_SWEA)
        m2 = MarsData.load_module(:MAVEN_SWEA)
        @test m1 isa Module
        @test m1 === m2
        @test m1 === MarsData.MAVEN_SWEA
    end

    @testset ":preloaded 不重复装载" begin
        @test MarsData.load_module(:MAVEN_plot) === MarsData.MAVEN_plot
        @test MarsData.load_module(:Paths) === MarsData.Paths
    end

    @testset "空 allow ⇒ 只绑定模块名、零裸名" begin
        MarsData.load_module(:constants; into = ScratchBlank)
        @test isdefined(ScratchBlank, :constants)
        # 空白名单：R_Mars 不应成为 ScratchBlank 的裸名
        @test Core.eval(ScratchBlank, :(isdefined(@__MODULE__, :R_Mars))) == false
        # 但带前缀仍可用
        @test Core.eval(ScratchBlank, :(constants.R_Mars)) ==
              Core.eval(MarsData.MAVEN_plot.constants, :(R_Mars))
    end

    @testset "非空 allow ⇒ 未 export 的名字也可裸名（白名单是唯一闸门）" begin
        old = MarsData.MODULE_REGISTRY[:constants]
        # 临时把白名单设为 :R_Mars（constants 模块并未 export 它）
        MarsData.MODULE_REGISTRY[:constants] = MarsData.ModuleSpec(
            old.name, old.path, old.deps, old.kind, [:R_Mars], old.note,
        )
        try
            @test !(:R_Mars in names(MarsData.MAVEN_plot.constants))   # 确认未 export
            MarsData.load_module(:constants; into = ScratchAllow)
            @test Core.eval(ScratchAllow, :(isdefined(@__MODULE__, :R_Mars))) == true
            @test Core.eval(ScratchAllow, :(R_Mars)) ==
                  Core.eval(MarsData.MAVEN_plot.constants, :(R_Mars))
        finally
            MarsData.MODULE_REGISTRY[:constants] = old
        end
    end

    @testset "into 隔离：不污染 MarsData / Main" begin
        @test !isdefined(MarsData, :constants)
        @test !isdefined(Main, :constants)
        @test isdefined(ScratchBlank, :constants)
    end

    @testset "@load 宏绑定模块名（顶层用法）" begin
        @test isdefined(Main, :MAVEN_SWEA)
        @test Main.MAVEN_SWEA isa Module
        # 载体机制：全进程共享同一模块实例，不再每个命名空间各 include 一份
        @test Main.MAVEN_SWEA === MarsData.MAVEN_SWEA
    end

    @testset ":all 拓扑序装载" begin
        order = MarsData._topo_order()
        @test length(order) == length(MarsData.MODULE_REGISTRY)
        @test Set(order) == Set(MarsData.available_modules())
        # 依赖必须排在被依赖者之前
        for s in order
            for d in MarsData.MODULE_REGISTRY[s].deps
                @test findfirst(==(d), order) < findfirst(==(s), order)
            end
        end
    end

    @testset "白名单内容与生效" begin
        # 已开放的三条
        @test MarsData.MODULE_REGISTRY[:MarsCommon].allow ==
              [:searchsortednearest, :e_energy2v, :ion_energy2v]
        @test MarsData.MODULE_REGISTRY[:MAVEN_load].allow == [:load_cdf, :load_MAVEN_data]
        @test MarsData.MODULE_REGISTRY[:IGRF_calculate].allow ==
              [:IGRF_pc, :pc2sphere, :sphere2pc]
        # MarsCommon 的 `using ..constants` 需要载体里先有 constants（deps 自动装载）
        @test :constants in MarsData.MODULE_REGISTRY[:MarsCommon].deps
        # 其余仍留空
        @test isempty(MarsData.MODULE_REGISTRY[:MAVEN_STATIC].allow)
        @test isempty(MarsData.MODULE_REGISTRY[:MAVEN_SWEA].allow)

        # MarsCommon 可独立装载（deps 已自动递归装入载体：constants）
        mcm = MarsData.load_module(:MarsCommon; into = ScratchWhitelist)
        @test mcm isa Module
        @test isdefined(ScratchWhitelist, :MarsCommon)
        @test isdefined(ScratchWhitelist, :searchsortednearest)
        @test isdefined(ScratchWhitelist, :e_energy2v)
        @test isdefined(ScratchWhitelist, :ion_energy2v)
        # 不在白名单的名字不应成为裸名（MarsCommon 也未 export 它）
        @test !isdefined(ScratchWhitelist, :spherical_to_cartesian)
        # 白名单内的函数确实可调用
        @test Core.eval(ScratchWhitelist, :(e_energy2v(1.0e3))) isa Real

        # MAVEN_load 白名单
        MarsData.load_module(:MAVEN_load; into = ScratchWhitelist)
        @test isdefined(ScratchWhitelist, :load_cdf)
        @test isdefined(ScratchWhitelist, :load_MAVEN_data)
        @test !isdefined(ScratchWhitelist, :load_kp)
    end

    @testset "重模块冒烟：MAVEN_load 装入 MarsData" begin
        m = MarsData.load_module(:MAVEN_load)
        @test m isa Module
        @test m === MarsData.MAVEN_load
        @test isdefined(m, :load_MAVEN_data)
        @test isdefined(m, :load_kp)
        # 载体机制：模块在运行时载体中求值（绕开包模块的严格依赖校验）
        @test parentmodule(m) === MarsData._carrier()
        @test parentmodule(m) !== MarsData
        # 记录在已装载清单里
        @test haskey(MarsData.loaded_modules(), :MAVEN_load)
        # 幂等：再次装载仍是同一对象
        @test MarsData.load_module(:MAVEN_load) === m
    end
end
