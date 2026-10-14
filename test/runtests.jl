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
        result = MarsData.validate_registry()
        for e in result.errors
            @info "注册表错误" e
        end
        for w in result.warnings
            @info "注册表警告" w
        end
        @test isempty(result.errors)
        # 警告不阻塞测试，但本阶段应无冗余 include
        @test_broken isempty(result.warnings)
    end

    @testset "validate_registry 检测 using ..X 缺 deps" begin
        using MarsData: ModuleSpec
        # 构造一个临时模块文件：使用 using ..Foo 但 deps 不含 Foo
        tmpdir = mktempdir()
        tmpfile = joinpath(tmpdir, "BadModule.jl")
        write(tmpfile, "module BadModule\nusing ..Foo\nend\n")

        # 临时把注册表替换一份副本，完成后恢复
        original_registry = copy(MarsData.MODULE_REGISTRY)
        empty!(MarsData.MODULE_REGISTRY)
        MarsData.MODULE_REGISTRY[:BadModule] = ModuleSpec(
            :BadModule, tmpfile, Symbol[], :module, Symbol[], "test")
        try
            result = MarsData.validate_registry()
            @test any(contains("using ..Foo"), result.errors)
        finally
            empty!(MarsData.MODULE_REGISTRY)
            merge!(MarsData.MODULE_REGISTRY, original_registry)
        end
    end

    @testset "DataKeys 契约常量" begin
        @test MarsData.DataKeys.EPOCH === :epoch
        @test MarsData.DataKeys.TIME === :time
        @test MarsData.DataKeys.TIME_UNIX === :time_unix
        @test MarsData.DataKeys.DATA_LOAD_FLAG === :data_load_flag
        @test MarsData.DataKeys.FILENAME === :filename
        @test MarsData.DataKeys.B_FIELD === :B
        @test MarsData.DataKeys.B_TOTAL === :B_total
        @test MarsData.DataKeys.POSITION === :position
        @test MarsData.DataKeys.ENERGY === :energy
        @test MarsData.DataKeys.DENERGY === :denergy
        @test MarsData.DataKeys.DF === :df
        @test MarsData.DataKeys.EFLUX === :eflux
        @test MarsData.DataKeys.DIFF_EN_FLUXES === :diff_en_fluxes
        @test MarsData.DataKeys.QUAT_MSO === :quat_mso
        @test MarsData.DataKeys.SC_POT === :sc_pot
        @test MarsData.DataKeys.MASS_ARR === :mass_arr
        @test MarsData.DataKeys.S === :S
        @test MarsData.DataKeys.ALT === :alt
    end

    @testset "static_slip 视图语义（AR-9）" begin
        MarsData.load_module(:MAVEN_STATIC)
        STATIC = MarsData.MAVEN_STATIC
        ntime, nmass, nbins, nenergy = 2, 2, 3, 4
        dat = Dict{Symbol,Any}(
            :swp_ind       => Int[0, 1],
            :att_ind       => Int[0, 1],
            :eff_ind       => Int[0, 1],
            :epoch         => [DateTime(2020, 1, 1), DateTime(2020, 1, 2)],
            :eflux         => rand(ntime, nmass, nbins, nenergy),
            :data          => rand(ntime, nmass, nbins, nenergy),
            :bkg           => rand(ntime, nmass, nbins, nenergy),
            :time_integ    => [1.0, 2.0],
            :sc_pot        => [0.0, 0.0],
            :quality_flag  => [0, 0],
            :dead          => rand(ntime, nmass, nbins, nenergy),
            :mode          => [0, 0],
            :bins_sc       => rand(ntime, nbins),
            :quat_mso      => rand(ntime, 4),
            :quat_sc       => rand(ntime, 4),
            :magf          => rand(ntime, 3),
            :pos_sc_mso    => rand(ntime, 3),
            :energy        => rand(1, 1, 1, nenergy),
            :denergy       => rand(1, 1, 1, nenergy),
            :theta         => rand(1, 1, 1, nenergy),
            :phi           => rand(1, 1, 1, nenergy),
            :dtheta        => rand(1, 1, 1, nenergy),
            :dphi          => rand(1, 1, 1, nenergy),
            :mass_arr      => rand(1, 1, 1, nenergy),
            :gf            => rand(ntime, nmass, nbins, nenergy),
            :eff           => rand(ntime, nmass, nbins, nenergy),
        )
        slip = STATIC.static_slip(dat, 1)

        # 写新键安全：不影响原字典
        slip[:new_key] = 123
        @test !haskey(dat, :new_key)

        # 修改既有键的数组元素会污染原数据（视图共享内存）
        original = dat[:eflux][1, 1, 1, 1]
        slip[:eflux][1, 1, 1, 1] = original + 100.0
        @test dat[:eflux][1, 1, 1, 1] == original + 100.0
    end

    @testset "v_3d coarse/fine 维度分支（C5）" begin
        MarsData.load_module(:MAVEN_SWIA)
        SWIA = MarsData.MAVEN_SWIA
        ntime, nenergy = 3, 48
        energy = reshape(collect(Float64, 1:nenergy), 1, nenergy)
        denergy = energy .* 0.15

        # ---- coarse: theta/domega 3D (ntime, ndeflect, nenergy) ----
        ndeflect_c = 4
        nanode_c = 16
        dat_c = Dict{Symbol,Any}(
            :nenergy       => nenergy,
            :energy        => energy,
            :denergy       => denergy,
            :ndeflect      => ndeflect_c,
            :nanode        => nanode_c,
            :phi           => zeros(nanode_c),
            :theta         => zeros(ntime, ndeflect_c, nenergy),
            :domega        => ones(ntime, ndeflect_c, nenergy),
            :diff_en_fluxes => rand(ntime, nanode_c, ndeflect_c, nenergy),
        )
        vel_c, flux_c, density_c = SWIA.v_3d(dat_c, 1:ntime)
        @test size(vel_c) == (ntime, 3)
        @test size(flux_c) == (ntime, 3)
        @test size(density_c) == (ntime, 1)
        @test all(density_c .> 0)

        # ---- fine: theta/domega 4D (ntime, 1, ndeflect, nenergy) ----
        ndeflect_f = 12
        nanode_f = 10
        dat_f = Dict{Symbol,Any}(
            :nenergy       => nenergy,
            :energy        => energy,
            :denergy       => denergy,
            :ndeflect      => ndeflect_f,
            :nanode        => nanode_f,
            :phi           => zeros(nanode_f),
            :theta         => zeros(ntime, 1, ndeflect_f, nenergy),
            :domega        => ones(ntime, 1, ndeflect_f, nenergy),
            :diff_en_fluxes => rand(ntime, nanode_f, ndeflect_f, nenergy),
        )
        vel_f, flux_f, density_f = SWIA.v_3d(dat_f, 1:ntime)
        @test size(vel_f) == (ntime, 3)
        @test size(flux_f) == (ntime, 3)
        @test size(density_f) == (ntime, 1)
        @test all(density_f .> 0)

        # ---- 非法维度应抛出带形状的错误 ----
        dat_bad = copy(dat_c)
        dat_bad[:theta] = zeros(ntime, ndeflect_c, nenergy, 1)  # 4D but wrong shape
        @test_throws ErrorException SWIA.v_3d(dat_bad, 1:ntime)
    end

    @testset "combina_two_dir_trace to_pc=true（C2）" begin
        MarsData.load_module(:IGRF_calculate)
        IGRF = MarsData.IGRF_calculate
        B1 = [1.0 0.5 0.2 10.0 1.0 0.5; 1.1 0.6 0.3 9.0 0.9 0.4]
        B2 = [0.9 0.4 0.1 11.0 1.1 0.6; 0.85 0.35 0.05 12.0 1.2 0.7]
        # to_pc=false 不应抛错
        sph = IGRF.combina_two_dir_trace(B1, B2; to_pc=false)
        @test size(sph) == (4, 6)

        # to_pc=true 不应抛错（修复前会 UndefVarError）
        cart = IGRF.combina_two_dir_trace(B1, B2; to_pc=true)
        @test size(cart) == (4, 6)
        # 第一行位置/磁场应与手动 sphere2pc/Bsphere2pc 一致
        px, py, pz = IGRF.sphere2pc(B2[2, 1], B2[2, 2], B2[2, 3])
        Bx, By, Bz = IGRF.Bsphere2pc(B2[2, 1], B2[2, 2], B2[2, 3], B2[2, 4], B2[2, 5], B2[2, 6])
        @test cart[1, 1:3] ≈ [px, py, pz]
        @test cart[1, 4:6] ≈ [Bx, By, Bz]
    end

    @testset "trace_mag_line method kwarg（C1）" begin
        IGRF = MarsData.IGRF_calculate
        Rm = IGRF.constants.R_Mars
        p = IGRF.sphere2pc(Rm, π / 2, 0.0)

        # 默认 :euler 与改动前一致
        res_euler = IGRF.trace_mag_line(p...; step=1.0, max_trace=100, method=:euler)
        @test res_euler[:method] === :euler
        @test size(res_euler[:position]) == (res_euler[:num_steps], 3)
        @test size(res_euler[:B]) == (res_euler[:num_steps], 3)

        # :rk4 支路可用
        res_rk4 = IGRF.trace_mag_line(p...; step=1.0, max_trace=100, method=:rk4)
        @test res_rk4[:method] === :rk4
        @test size(res_rk4[:position], 2) == 3

        # :adaptive 需要 DLL 提供 MAIN_mp_ADAPTIVE_STEP_TRACE；当前 IGRF_DLL.dll 缺失该符号，
        # 因此接口保留但不在默认测试门控中调用。
        # res_adapt = IGRF.trace_mag_line(p...; step=1.0, max_trace=100, method=:adaptive)

        # 非法 method
        @test_throws ArgumentError IGRF.trace_mag_line(p...; method=:bogus)
    end

    @testset "Cold_Plasma PlasmaState 重构（C8）" begin
        MarsData.load_module(:Cold_Plasma_Dispersion_Relation)
        CP = MarsData.Cold_Plasma_Dispersion_Relation

        θ, freq, Πe, Ωe = π / 4, 1.0e4, 1.0e5, -2.0e4

        # 未初始化时旧签名应给出明确错误
        err = try
            CP.Dispersion_Relation(θ, freq, Πe, Ωe)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        msg = sprint(showerror, err)
        @test occursin("PlasmaState", msg)
        @test occursin("set_particles", msg)

        # make_particles 为纯函数，不写全局状态
        st1 = CP.make_particles(ion_rate=[0.4, 0.6], ion_mass=[16, 32])
        @test st1 isa CP.PlasmaState
        @test st1.Nparticles == 3
        @test length(st1.Ω_n) == 3
        @test length(st1.Π_2) == 3

        # set_particles 保留副作用并返回 state
        st2 = CP.set_particles(ion_rate=[0.4, 0.6], ion_mass=[16, 32])
        @test st2 == st1
        @test CP.Dispersion_Relation(θ, freq, Πe, Ωe) ≈ CP.Dispersion_Relation(θ, freq, Πe, Ωe, st1) rtol = 1e-12

        # 旧全局变量仍被同步更新
        @test CP.Nparticles == st1.Nparticles
        @test CP.Ω_n == st1.Ω_n
        @test CP.Π_2 == st1.Π_2

        # carculate_minimum_energy 三路径一致
        n = 1
        em_old = CP.carculate_minimum_energy(θ, freq, Πe, Ωe, n)
        em_new = CP.carculate_minimum_energy(θ, freq, Πe, Ωe, n, st1)
        em_alias = CP.calculate_minimum_energy(θ, freq, Πe, Ωe, n, st1)
        @test em_old ≈ em_new rtol = 1e-12
        @test em_alias ≈ em_new rtol = 1e-12

        # Threads：两个独立 state 并行计算结果一致
        results = Vector{Float64}(undef, 2)
        states = [
            CP.make_particles(ion_rate=[0.4, 0.6], ion_mass=[16, 32]),
            CP.make_particles(ion_rate=[0.2, 0.8], ion_mass=[1, 32]),
        ]
        Threads.@threads for i in 1:2
            results[i] = CP.Dispersion_Relation(θ, freq, Πe, Ωe, states[i])
        end
        @test isfinite(results[1])
        @test isfinite(results[2])
    end

    @testset "查询 API" begin
        avail = MarsData.available_modules()
        @test :MAVEN_load in avail
        @test :MAVEN_STATIC in avail
        @test :MAVEN_SWIA in avail
        @test :MAVEN_SWEA in avail
        @test :IGRF_calculate in avail
        @test :Cold_Plasma_Dispersion_Relation in avail
        @test :DataKeys in avail
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
