# ============================================================================
# benchmark/common.jl — 合成数据生成器与辅助函数
# 
# 为 PHASE 6 的 benchmark 和 golden snapshot 提供可复现的合成数据。
# 所有生成器返回与真实数据契约一致的结构（以 03 附录 A 为准）。
# ============================================================================

using Random
using Dates
using LinearAlgebra
using StaticArrays
using Statistics

# 常量（与 common/constants.jl 一致）
const R_Mars = 3389.5  # km
const m_p = 1.6726219e-27  # kg (质子质量)
const e_charge = 1.602176634e-19  # C (电子电荷)

# 固定随机种子确保可复现
const BENCH_SEED = 12345

# ---------------------------------------------------------------------------
# STATIC 合成数据生成器
# ---------------------------------------------------------------------------

"""
    gen_static_slice(; ntime=100, nenergy=48, nmass=4) -> Dict{Symbol,Any}

生成 STATIC c6/d1 切片字典（与真实契约一致）。
"""
function gen_static_slice(; ntime::Int = 100, nenergy::Int = 48, nmass::Int = 4)
    rng = MersenneTwister(BENCH_SEED)
    
    # 时间轴
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
    
    # 能量网格（eV）——几何级数，近似 STATIC 实际能道
    E_min, E_max = 1.0, 20000.0  # eV
    energy = E_min .* (E_max / E_min) .^ (range(0, 1, length = nenergy))
    denergy = diff([energy[1] / 2; (energy[1:end-1] .+ energy[2:end]) ./ 2; energy[end] * 1.5])
    
    # 质量通道
    mass_arr = Float32.(collect(1:nmass))  # 1, 2, 3, 4 (简化)
    
    # 计数率（3D: ntime × nenergy × nmass）——合成真实量级
    # 典型计数率 ~ 0.01–100 counts/accumulation
    counts_3d = Float32.(rand(rng, ntime, nenergy, nmass) .* 10 .+ 0.1)
    
    # 效率因子（1D: nenergy）
    eff = Float32.(rand(rng, nenergy) .* 0.3 .+ 0.7)
    
    # SWP/ATT 掩码
    swp = rand(rng, Bool, ntime)
    att = rand(rng, Bool, ntime)
    
    # 相位角（简化）
    theta = Float32.(rand(rng, ntime) .* 360.0)
    
    return Dict{Symbol,Any}(
        :epoch => epoch,
        :energy => Float32.(energy),
        :denergy => Float32.(denergy[1:nenergy]),  # nenergy 长度
        :mass_arr => mass_arr,
        :counts_3d => counts_3d,
        :eff => eff,
        :swp => swp,
        :att => att,
        :theta => theta,
        :data_load_flag => true,
    )
end

"""
    gen_c6_day(; ntime=8640) -> Dict{Symbol,Any}

生成一整天的 c6 数据（10 分钟分辨率）。
"""
function gen_c6_day(; ntime::Int = 8640)  # 1 day at 10s cadence = 8640
    rng = MersenneTwister(BENCH_SEED)
    
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:10:(ntime * 10 - 10)))
    
    # 质量谱：主要离子的计数
    mass_arr = Float32.([1.0, 4.0, 16.0, 32.0])  # H+, He2+, O+, S+ (近似)
    
    # 6 个能道（c6 的"6"）
    nenergy = 6
    energy = Float32.([100.0, 300.0, 1000.0, 3000.0, 10000.0, 20000.0])
    
    # 形状: (ntime, nenergy, nmass)
    counts_3d = Float32.(rand(rng, ntime, nenergy, length(mass_arr)) .* 10 .+ 0.5)
    
    # df (distribution function) 可选键
    df = similar(counts_3d)
    df .= counts_3d .* 1e-15  # 量级约 1e-15
    
    return Dict{Symbol,Any}(
        :epoch => epoch,
        :mass_arr => mass_arr,
        :energy => energy,
        :counts_3d => counts_3d,
        :df => df,
        :data_load_flag => true,
    )
end

# ---------------------------------------------------------------------------
# SWEA 合成数据生成器
# ---------------------------------------------------------------------------

"""
    gen_swea_spec(; ntime=50, nenergy=64, npad=52) -> Dict{Symbol,Any}

生成 SWEA 能谱数据。
"""
function gen_swea_spec(; ntime::Int = 50, nenergy::Int = 64, npad::Int = 52)
    rng = MersenneTwister(BENCH_SEED)
    
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
    
    # 能量道 (1–64)
    energy_channels = Float32.(1:nenergy)
    
    # 能谱 (ntime × nenergy)
    spec = Float32.(rand(rng, ntime, nenergy) .* 1e-3 .+ 1e-6)
    
    # PAD (pitch angle distribution): ntime × npad
    pad = Float32.(rand(rng, ntime, npad) .* 0.5 .+ 0.1)
    
    return Dict{Symbol,Any}(
        :epoch => epoch,
        :energy_channels => energy_channels,
        :spec => spec,
        :pad => pad,
        :data_load_flag => true,
    )
end

"""
    gen_swea_n1d_input(; ntime=100, nenergy=64) -> Dict{Symbol,Any}

生成 n1d 函数的输入数据（能谱计算）。
"""
function gen_swea_n1d_input(; ntime::Int = 100, nenergy::Int = 64)
    rng = MersenneTwister(BENCH_SEED)
    
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
    
    # 能量边界和中心
    energy = Float32.(exp10.(range(log10(1.0), log10(20000.0), length = nenergy)))
    denergy = Float32.(diff([energy[1] / 2; (energy[1:end-1] .+ energy[2:end]) ./ 2; energy[end] * 1.5])[1:nenergy])
    
    # 计数（与能量相关的衰减谱）
    counts = Float32.(rand(rng, ntime, nenergy) .* energy' .* 1e-3 .+ 1e-3)
    
    # 效率
    eff = Float32.(rand(rng, nenergy) .* 0.4 .+ 0.6)
    
    return Dict{Symbol,Any}(
        :epoch => epoch,
        :energy => energy,
        :denergy => denergy,
        :counts => counts,
        :eff => eff,
        :data_load_flag => true,
    )
end

# ---------------------------------------------------------------------------
# SWIA 合成数据生成器
# ---------------------------------------------------------------------------

"""
    gen_swia_coarse(; ntime=100) -> Dict{Symbol,Any}

生成 SWIA coarse 网格数据（3D theta/domega）。
与 get_3dc! 输出一致：theta 形状 (ntime, 4, 48)。
"""
function gen_swia_coarse(; ntime::Int = 100)
    rng = MersenneTwister(BENCH_SEED)
    
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
    
    # 能道
    nenergy = 48
    energy = Float32.(exp10.(range(log10(5.0), log10(25000.0), length = nenergy)))
    
    # 俯仰角 (4 deflection sectors)
    ndeflect = 4
    
    # theta/domega 形状: (ntime, ndeflect, nenergy) —— coarse 数据！
    theta = Float32.(rand(rng, ntime, ndeflect, nenergy) .* 90.0 .+ 45.0)  # degrees
    domega = Float32.(rand(rng, ntime, ndeflect, nenergy) .* 0.01 .+ 0.005)  # sr
    
    # 计数 (4D: ntime × ndeflect × nenergy × 1 或 3D)
    # coarse 格式：3D
    counts = Float32.(rand(rng, ntime, ndeflect, nenergy) .* 100 .+ 10)
    
    # 效率
    eff = Float32.(rand(rng, nenergy) .* 0.5 .+ 0.5)
    
    return Dict{Symbol,Any}(
        :epoch => epoch,
        :energy => energy,
        :theta => theta,   # 3D for coarse
        :domega => domega, # 3D for coarse
        :counts => counts,
        :eff => eff,
        :data_load_flag => true,
    )
end

"""
    gen_swia_fine(; ntime=50) -> Dict{Symbol,Any}

生成 SWIA fine 网格数据（4D theta/domega）。
"""
function gen_swia_fine(; ntime::Int = 50)
    rng = MersenneTwister(BENCH_SEED)
    
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
    
    # Fine 网格
    nenergy = 48
    ntheta = 8  # fine 有更多角度分辨率
    
    energy = Float32.(exp10.(range(log10(5.0), log10(25000.0), length = nenergy)))
    
    # theta/domega 形状: (ntime, ntheta, nenergy) —— 4D 格式实际是 (ntime, ntheta, nenergy, 1)
    # 这里简化为 3D 表示
    theta = Float32.(rand(rng, ntime, ntheta, nenergy) .* 90.0 .+ 45.0)
    domega = Float32.(rand(rng, ntime, ntheta, nenergy) .* 0.01 .+ 0.005)
    
    counts = Float32.(rand(rng, ntime, ntheta, nenergy) .* 100 .+ 10)
    eff = Float32.(rand(rng, nenergy) .* 0.5 .+ 0.5)
    
    return Dict{Symbol,Any}(
        :epoch => epoch,
        :energy => energy,
        :theta => theta,
        :domega => domega,
        :counts => counts,
        :eff => eff,
        :data_load_flag => true,
    )
end

# ---------------------------------------------------------------------------
# 文件列表生成器
# ---------------------------------------------------------------------------

"""
    gen_filename_list(; nfiles=1000, date_range=Date(2015,1,1):Day(1):Date(2017,12,31)) -> Dict{String,Vector{String}}

生成文件名列表（用于测试日期索引）。
"""
function gen_filename_list(; 
    nfiles::Int = 1000, 
    date_range::AbstractVector{<:Date} = collect(Date(2015, 1, 1):Day(1):Date(2017, 12, 31))
)
    rng = MersenneTwister(BENCH_SEED)
    
    model_files = String[]
    
    for i in 1:nfiles
        # 随机选择日期
        d = date_range[rand(rng, 1:length(date_range))]
        date_str = Dates.format(d, "yyyymmdd")
        
        # 生成文件名（包含日期）
        filename = "mvn_l2_sta_c6_$date_str_v01_r01.cdf"
        push!(model_files, filename)
    end
    
    return Dict{String,Vector{String}}("sta_c6" => model_files)
end

# ---------------------------------------------------------------------------
# 绘图 data_dict 生成器
# ---------------------------------------------------------------------------

"""
    gen_plot_datadict(; ntime=200) -> Dict{String,Any}

生成绘图模块所需的完整 data_dict（12 面板）。
"""
function gen_plot_datadict(; ntime::Int = 200)
    rng = MersenneTwister(BENCH_SEED)
    
    epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
    
    # 基础轨道数据
    orbit = Dict{Symbol,Any}(
        :epoch => epoch,
        :altitude => Float32.(rand(rng, ntime) .* 500 .+ 200),  # 200–700 km
        :latitude => Float32.(rand(rng, ntime) .* 180 .- 90),   # -90 to 90
        :longitude => Float32.(rand(rng, ntime) .* 360),        # 0 to 360
        :local_time => Float32.(rand(rng, ntime) .* 24),        # 0 to 24 LT
    )
    
    # 磁场数据
    B_xyz = Dict{Symbol,Any}(
        :epoch => epoch,
        :B => Float32.(rand(rng, 3, ntime) .* 50 .- 25),  # -25 to 25 nT per component
        :data_load_flag => true,
    )
    
    # STATIC 密度/速度
    static_d1 = gen_static_slice(; ntime = ntime)
    
    # SWIA 密度/速度
    swia = gen_swia_coarse(; ntime = ntime)
    
    # SWEA 能谱
    swea = gen_swea_spec(; ntime = ntime)
    
    # KP 指数
    kp = Dict{Symbol,Any}(
        :epoch => epoch,
        :kp => Float32.(rand(rng, ntime) .* 9),  # 0–9
        :data_load_flag => true,
    )
    
    # 电势
    scpot = Dict{Symbol,Any}(
        :epoch => epoch,
        :sc_pot => Float32.(rand(rng, ntime) .* 10 .- 5),  # -5 to 5 V
    )
    
    return Dict{String,Any}(
        "orbit" => orbit,
        "MAG" => B_xyz,
        "STATIC_d1_v4d" => static_d1,
        "SWIA_coarse" => swia,
        "SWEA_spec" => swea,
        "KP" => kp,
        "sc_pot" => scpot,
    )
end

# ---------------------------------------------------------------------------
# MarsCommon 纯函数测试输入
# ---------------------------------------------------------------------------

"""
    gen_marscommon_test_inputs() -> NamedTuple

生成 MarsCommon 纯函数测试的输入网格。
"""
function gen_marscommon_test_inputs()
    rng = MersenneTwister(BENCH_SEED)
    
    # 球坐标测试点
    r = collect(range(1.0, 5.0, length = 20))  # R_Mars 归一化
    theta = collect(range(0.0, 180.0, length = 18))  # degrees
    phi = collect(range(0.0, 360.0, length = 36))  # degrees
    
    # 能量/速度测试点
    E_eV = Float32.(exp10.(range(0.0, 4.0, length = 50)))  # 1 eV to 10 keV
    
    # 球谐网格
    x = Float32.(rand(rng, 100) .* 4 .- 2)  # -2 to 2 R_Mars
    y = Float32.(rand(rng, 100) .* 4 .- 2)
    z = Float32.(rand(rng, 100) .* 4 .- 2)
    
    return (
        r = r,
        theta = theta,
        phi = phi,
        E_eV = E_eV,
        x = x,
        y = y,
        z = z,
    )
end

# ---------------------------------------------------------------------------
# Cold Plasma 测试输入
# ---------------------------------------------------------------------------

"""
    gen_coldplasma_inputs(; ngrid=100) -> NamedTuple

生成 Cold_Plasma_Dispersion_Relation 测试的参数网格。
"""
function gen_coldplasma_inputs(; ngrid::Int = 100)
    rng = MersenneTwister(BENCH_SEED)
    
    # 角度
    theta = collect(range(0.0, π, length = 20))
    
    # 频率
    freq = Float64.(exp10.(range(0.0, 5.0, length = 30)))  # Hz
    
    # 等离子体频率
    Πe = Float64.(rand(rng, ngrid) .* 1e6 .+ 1e5)  # ~100 kHz
    
    # 电子回旋频率
    Ωe = Float64.(rand(rng, ngrid) .* 1e5 .+ 1e4)  # ~10 kHz
    
    # 离子参数
    ion_rate = Float64.(rand(rng, ngrid) .* 0.1 .+ 0.01)
    ion_mass = Float64.([1.0, 4.0, 16.0, 32.0])  # H+, He2+, O+, S+
    
    return (
        theta = theta,
        freq = freq,
        Πe = Πe,
        Ωe = Ωe,
        ion_rate = ion_rate,
        ion_mass = ion_mass,
    )
end

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------

"""
    sha256_file(path) -> String

计算文件的 SHA-256 哈希（用于真实数据基准）。
"""
function sha256_file(path::AbstractString)
    isfile(path) || return "FILE_NOT_FOUND"
    data = read(path)
    return bytes2hex(sha256(data))
end

# Julia 标准库没有 sha256，需要 Digest 库或简化
# 这里返回文件大小作为简化（真实基准可用 Digest）
function simple_hash(path::AbstractString)
    isfile(path) || return "FILE_NOT_FOUND"
    stat = stat(path)
    return "$(stat.size)_$(stat.mtime)"
end

"""
    bench_summary(bench_result) -> NamedTuple

从 BenchmarkTools 结果提取关键指标。
"""
function bench_summary(bench_result)
    return (
        min = BenchmarkTools.minimum(bench_result),
        median = BenchmarkTools.median(bench_result),
        mean = BenchmarkTools.mean(bench_result),
        std = BenchmarkTools.std(bench_result),
        samples = length(BenchmarkTools.samples(bench_result)),
        evals = BenchmarkTools.params(bench_result).evals,
    )
end

# 避免 BenchmarkTools 未加载时报错
function bench_summary(x)
    return (min = missing, median = missing, mean = missing, std = missing, samples = missing, evals = missing)
end

# 输出模块加载确认
println("benchmark/common.jl 加载完成——合成数据生成器就绪")