# ============================================================================
# test/igrf_move_test.jl
# t16 回归：IGRF 源码模块 + 同目录资源（gh_gao / IGRF_DLL.dll）整批移入 models/
#
# 覆盖验收：
#   1) 三文件确在 models/、旧目录已无、二进制 sha256 与原字节一致；gh_gao.txt 原位保留；
#   2) 资源定位仍为 dirname(@__FILE__) 同目录（未统一到通用 DLL 目录），注册表/消费者无旧路径；
#   3) 模块装载即读取系数（gh_gao）；既有受支持的 DLL 调用（trace_mag_line :euler/:rk4、
#      combina_two_dir_trace）回归；:adaptive 缺符号为既有开放项，如实断言“当前会抛错”而不伪造通过；
#      任意 CWD 下以绝对路径装载仍能定位同目录资源；
#   4) 迁移清单含 3 文件与全部调用点。
# 运行：julia --project=. test/igrf_move_test.jl
# ============================================================================

using Test
using MarsData

const REPO = normpath(joinpath(@__DIR__, ".."))

const MOVED = Dict(
    # t36 授权函数迁出（Bsphere2pc/Bpc2sphere 权威移入 MarsCommon）⇒ 整文件字节已变，
    # 故此处只锁授权后的现行 sha256（大小不再锁定）；两个二进制资源仍逐字节锁定。
    "models/IGRF_calculate.jl" => (nothing,
        "8d77c121c384fef96fd568e005eceb8132d3e9bde541b1315502d27dda7634c7"),
    "models/gh_gao" => (197152,
        "efaebe934b4e084192c93a263b95cf7df6533d941b38ecc17c0dbb5ec1b9d6ab"),
    "models/IGRF_DLL.dll" => (27136,
        "6ffb3f3b66916ba280fc892452608898893c42784b05dacf837eabac56b5ad2b"),
)
const OLD_PATHS = ["Magnetic_Model/IGRF_calculate.jl", "Magnetic_Model/gh_gao",
                   "Magnetic_Model/IGRF_DLL.dll"]
const BACKUP_TXT = ("Magnetic_Model/gh_gao.txt", 443556,
                    "ae2c981eb73ee6805ef692dce26a35e5fe5f169e8f64d8da3198b75c17e36b65")

havoc_sha() = try
    @eval using SHA
    true
catch
    false
end

@testset "t16 IGRF 与系数/DLL 同批迁入 models" begin
    @testset "文件层面：位置、旧路径消失、sha256、备份原位" begin
        for (rel, (sz, sha)) in MOVED
            p = joinpath(REPO, rel)
            @test isfile(p)
            sz === nothing || @test filesize(p) == sz   # 源码文件在授权迁出后字节数会变，故可不锁大小
            if havoc_sha()
                @test bytes2hex(SHA.sha256(read(p))) == sha
            else
                @info "SHA 标准库不可用，跳过 sha256 断言（字节数/功能断言仍生效）" rel
            end
        end
        for rel in OLD_PATHS
            @test !isfile(joinpath(REPO, rel))
        end
        # 文本备份原位保留、未被改写
        txt, tsz, tsha = BACKUP_TXT
        @test isfile(joinpath(REPO, txt))
        @test filesize(joinpath(REPO, txt)) == tsz
        if havoc_sha()
            @test bytes2hex(SHA.sha256(read(joinpath(REPO, txt)))) == tsha
        end
    end

    @testset "注册表与消费者：新路径、无旧路径兼容" begin
        spec = MarsData.MODULE_REGISTRY[:IGRF_calculate]
        @test spec.path == "models/IGRF_calculate.jl"
        @test MarsData.load_module(:IGRF_calculate) isa Module
        # 活跃 consumer 里不得再出现旧路径（注释/文档不计）
        for rel in ("src/modules.jl", "example/MAVEN_plot_sample/MAVEN_overview_cases.jl",
                    "example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl",
                    "models/Pickup_ion.jl")
            txt = read(joinpath(REPO, rel), String)
            @test !occursin("Magnetic_Model/IGRF_calculate.jl", txt)
            @test occursin("models/IGRF_calculate.jl", txt)
        end
    end

    @testset "资源定位：dirname(@__FILE__) 同目录、未统一通用 DLL 目录" begin
        IGRF = MarsData.load_module(:IGRF_calculate)   # 走公开装载入口（与 @load 绑定同一实例）
        models_dir = joinpath(REPO, "models")
        @test dirname(IGRF.IGRF_DLL_PATH) == models_dir
        @test dirname(IGRF.gh_filename) == models_dir
        @test basename(IGRF.IGRF_DLL_PATH) == "IGRF_DLL.dll"
        @test basename(IGRF.gh_filename) == "gh_gao"
        @test isfile(IGRF.IGRF_DLL_PATH)
        @test isfile(IGRF.gh_filename)
    end

    @testset "系数读取与既有 DLL 调用回归" begin
        IGRF = MarsData.load_module(:IGRF_calculate)
        # 装载即调用 read_gh()；形状/数值双证系数读取成功
        @test IGRF.NIGRF == 110
        @test size(IGRF.GG) == (111, 111)
        @test size(IGRF.HH) == (111, 111)
        @test any(!iszero, IGRF.GG)
        g2, h2 = IGRF.read_gh()
        @test g2 == IGRF.GG && h2 == IGRF.HH
        # 既有受支持的 DLL 调用（ccall IGRF_110_MODEL_mp_RK4_STEP）
        Rm = IGRF.constants.R_Mars
        p = IGRF.sphere2pc(Rm, π / 2, 0.0)
        for m in (:euler, :rk4)
            res = IGRF.trace_mag_line(p...; step=1.0, max_trace=50, method=m)
            @test res[:method] === m
            @test size(res[:position], 2) == 3 && size(res[:B], 2) == 3
        end
        # combina_two_dir_trace：to_pc=true/false 均可用
        B1 = [1.0 0.5 0.2 10.0 1.0 0.5; 1.1 0.6 0.3 9.0 0.9 0.4]
        B2 = [0.9 0.4 0.1 11.0 1.1 0.6; 0.85 0.35 0.05 12.0 1.2 0.7]
        @test size(IGRF.combina_two_dir_trace(B1, B2; to_pc=false)) == (4, 6)
        @test size(IGRF.combina_two_dir_trace(B1, B2; to_pc=true)) == (4, 6)
        @test_throws ArgumentError IGRF.trace_mag_line(p...; method=:bogus)
        # 既有开放项（不伪造通过）：DLL 缺 MAIN_mp_ADAPTIVE_STEP_TRACE ⇒ :adaptive 当前必抛错
        adapt_ok = try
            IGRF.trace_mag_line(p...; step=1.0, max_trace=10, method=:adaptive)
            true
        catch
            false
        end
        @test adapt_ok == false   # 若该符号补齐，此断言会失败并提示更新清单/测试
    end

    @testset "任意 CWD：以绝对路径装载仍定位同目录资源" begin
        cwd0 = pwd()
        tmp = mktempdir()
        try
            cd(tmp)
            sb = Module(:IGRFCWDSandbox)
            Base.include(sb, joinpath(REPO, "models", "IGRF_calculate.jl"))
            M = getfield(sb, :IGRF_calculate)   # include 后在沙箱内建立同名模块
            @test dirname(M.IGRF_DLL_PATH) == joinpath(REPO, "models")
            @test dirname(M.gh_filename) == joinpath(REPO, "models")
            @test size(M.GG) == (111, 111)
            @test M.NIGRF == 110
        finally
            cd(cwd0)
            rm(tmp; force = true, recursive = true)
        end
        @test pwd() == cwd0
    end

    @testset "迁移清单含 3 文件与全部调用点" begin
        toml = joinpath(REPO, "validation", "migrations", "igrf.toml")
        @test isfile(toml)
        t = read(toml, String)
        @test occursin("schema_version = 1", t)
        for rel in ("Magnetic_Model/IGRF_calculate.jl", "models/IGRF_calculate.jl",
                    "models/gh_gao", "models/IGRF_DLL.dll")
            @test occursin(rel, t)
        end
        # 资源类以字节 sha256 记录；源码模块以目标规范 AST hash 记录（二者口径不同，勿混用）
        for sha in ("efaebe934b4e084192c93a263b95cf7df6533d941b38ecc17c0dbb5ec1b9d6ab",
                    "6ffb3f3b66916ba280fc892452608898893c42784b05dacf837eabac56b5ad2b")
            @test occursin(sha, t)
        end
        # t36 授权函数迁出 / t38 依赖与实例复用 / t40 去全局第二档 —— 模块 AST 变化，故更新 target_hash；source_revision 保留
        @test occursin("d7a92ef3c0cef2f3c9b7fd144d9d5b9d748723d7a0cd8130177df1f9686ad9ea", t)
        @test occursin("source_revision  = \"5f225db\"", t)
        @test occursin("source_revision  = \"5f225db\"", t)
        for consumer in ("src/modules.jl", "example/MAVEN_plot_sample/MAVEN_overview_cases.jl",
                         "example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl",
                         "models/Pickup_ion.jl")
            @test occursin(consumer, t)
        end
        @test occursin("Magnetic_Model/gh_gao.txt", t)
    end
end
