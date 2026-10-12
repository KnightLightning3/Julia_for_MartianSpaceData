"""生成 MAVEN 多仪器时间序列概览图的示例程序。"""

using TimesDates, Dates
if !isdefined(@__MODULE__, :constants)
    include(joinpath(@__DIR__, "..", "..", "common", "constants.jl"))
end
using MarsData        # 绘图功能已包化：plot_module / TimeFormat / MAVEN_plot 基元
using CairoMakie      # Figure / Axis / save 等图形对象（MarsData 不重新导出 Makie）
using DataFrames
using ProgressMeter
using LinearAlgebra
using JLD2
include("../../MAVEN_data/MAVEN_load.jl");import .MAVEN_load;
include("../../MAVEN_data/MAVEN_STATIC.jl");import .MAVEN_STATIC;
include("../../Magnetic_Model/IGRF_calculate.jl");import .IGRF_calculate;

@inline function mag2sphere(data_dict)
    """将 MAVEN 磁场分量转换为球坐标并写回数据字典。"""
    position = data_dict["MAG_ss1s_cdf"][:position]
    b = data_dict["MAG_ss1s_cdf"][:B]
    data = MAVEN_load.Bpc2sphere.(position[:, 1], position[:, 2], position[:, 3], b[:, 1], b[:, 2], b[:, 3])
    br = [x[1] for x in data]
    bθ = [x[2] for x in data]
    bϕ = [x[3] for x in data]
    data_dict["MAG_ss1s_cdf"][:SphereB] = (br, bθ, bϕ)
    return data_dict
end
# 绘图所需的 KP 变量（语义名 => KP 变量序号）。当前注册表 kp_dict 只含子集，
# 这里按绘图需要扩展；`change_kp_read_data` 会重设 MAVEN_load 的全局 kp_dict。
const KP_PLOT_VARS = Dict{Symbol,Int}(
    :Ne => 2,
    :Ne_quality_min => 3,
    :Ne_quality_max => 4,
    :GEO_x => 187,
    :GEO_y => 188,
    :GEO_z => 189,
    :MSO_x => 190,
    :MSO_y => 191,
    :MSO_z => 192,
    :Orbit_Number => 210,
    :Shape_parameter => 39,
    :H_flow_MSO_x => 43,
    :H_flow_MSO_y => 45,
    :H_flow_MSO_z => 47,
    :O_iondensity => 56,
    :O2_iondensity => 58,
    :O_ionTemperature => 62,
    :O2_ionTemperature => 64,
)

"""
    load_model_safe(date, model) -> Dict{Symbol,Any}

按产品名安全读取单个产品；读取失败时返回带 `:data_load_flag => false` 的占位字典，
使个别产品缺文件或格式异常不会中断整幅概览图的绘制。
"""
@inline function load_model_safe(date, model)
    try
        return MAVEN_load.data_get_from_date(date, model_index=[model], show_filename=false)[model]
    catch err
        @warn "产品 $(model) 读取失败，已跳过" exception = (err, catch_backtrace())
        return Dict{Symbol,Any}(:data_load_flag => false)
    end
end

@inline function get_data(date)
    """读取指定日期绘图所需的 MAVEN 数据产品（逐产品容错）。

    KP 使用注册表产品 `KP`（原始文本）经 `load_kp` 读取，并同时解析坐标变换矩阵；
    当前注册表中已不存在旧示例使用的 `KP_l3` / `MAG_pc1s_l3` 产品，故分别以
    `KP`（load_kp + pc2ss_Matrix）与 `MAG_pc1s_cdf` 替代。
    """
    MAVEN_load.change_kp_read_data(KP_PLOT_VARS)
    kp_flag, kp_file = MAVEN_load.find_file_of_data("KP", date)
    if !kp_flag
        return nothing, false
    end
    KP_data = MAVEN_load.load_kp(kp_file; pc2ss_Matrix_load=true)
    KP_data[:data_load_flag] = true
    # 由 GEO 位置计算高度（km）
    KP_data[:alt] = sqrt.(KP_data[:GEO_x].^2 .+ KP_data[:GEO_y].^2 .+ KP_data[:GEO_z].^2) .- constants.R_Mars

    model_index = [
        "STATIC_d1_v4d",
        "MAG_ss1s_cdf", "MAG_pc1s_cdf",
        "LPW_wave",
        "SWEA_spec",
        "STATIC_c6",
        "SWIA_svy_spec",
        "SWEA_pad_svy",
        "SWIA_mom",
        "LPW_mrgscpot",
    ]
    data_dict = Dict{String,Any}()
    data_dict["KP"] = KP_data
    data_dict["KP_l3"] = KP_data   # 兼容 plot_module 中的旧键名
    for model in model_index
        data_dict[model] = load_model_safe(date, model)
    end
    return data_dict, true
end
@inline function get_B_model_ss(data_dict)
    """计算并保存航天器坐标系中的 IGRF 模型磁场。"""
    B_times0 = data_dict["MAG_pc1s_cdf"][:epoch]
    position0 = data_dict["MAG_pc1s_cdf"][:position]
    B_times = B_times0
    sc_trace = position0
    # 计算IGRF
    num = length(B_times)
    Bm = zeros(num, 3)
    Bm_ss = zeros(num, 3)
    pos_ss = zeros(num, 3)
    kp_dict = data_dict["KP_l3"]
    B_compress = 0
    @inbounds for i in 1:num
        Bx1, By1, Bz1 = IGRF_calculate.IGRF_pc(sc_trace[i, 1], sc_trace[i, 2], sc_trace[i, 3])
        Bm[i, :] = [Bx1, By1, Bz1]
        ind = MAVEN_load.MarsCommon.searchsortednearest(kp_dict[:time], B_times[i])
        rot = kp_dict[:pc2ss_Matrix][ind, :, :]
        Bm_ss[i, :] = rot * ([Bx1, By1, Bz1] .+ B_compress)
        pos_ss[i, :] = rot * sc_trace[i, :]
    end
    data_dict["MAG_model_ss"] = Dict{Symbol,Any}(
        :epoch => B_times, 
        :Bm_pc => Bm, 
        :Bm_ss => Bm_ss, 
        :p_pc => sc_trace, 
        :p_ss => pos_ss,
    )
    return data_dict
end

# ==================== 绘图参数（按需修改） ====================
yyyy = 2015
mm = 7
dd = 19
time_range = [DateTime(yyyy, mm, dd, 2, 0), DateTime(yyyy, mm, dd, 4, 0)]
# 输出目录：默认写入系统临时目录（便于验证）；可用环境变量 MAVEN_OVERVIEW_OUTDIR 覆盖
out_dir = get(ENV, "MAVEN_OVERVIEW_OUTDIR", joinpath(tempdir(), "maven_overview_sample"))
mkpath(out_dir)
# ============================================================

data_dict, ok = get_data(DateTime(yyyy, mm, dd))
ok || error("指定日期缺 KP 数据，无法绘图")

# STATIC c6 按质量/能量区间的均值派生
sta_data = data_dict["STATIC_c6"]
if sta_data[:data_load_flag] == false
    sta_total = Dict(:data_load_flag => false)
    sta_mass = Dict(:data_load_flag => false)
else
    sta_total = MAVEN_STATIC.static_c6_mass_mean(sta_data)
    sta_mass = MAVEN_STATIC.static_c6_energy_mean(sta_data)
end
data_dict["STATIC_c6_origin"] = sta_data
data_dict["STATIC_c6"] = sta_total
data_dict["STATIC_mass"] = sta_mass

# SWEA PAD 低/高能段积分
swea_pad = data_dict["SWEA_pad_svy"]
if swea_pad[:data_load_flag] == false
    swea_pad_low = Dict(:data_load_flag => false)
    swea_pad_high = Dict(:data_load_flag => false)
else
    swea_pad_low = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[20, 30])
    swea_pad_high = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[90, 120])
end
data_dict["swea_pad_low"] = swea_pad_low
data_dict["swea_pad_high"] = swea_pad_high

# IGRF 模型磁场（航天器坐标系）
data_dict = get_B_model_ss(data_dict)

# ==================== 绘图 ====================
x_range = time_range
date_str = Dates.format(DateTime(yyyy, mm, dd), "yyyy-mm-dd")
kp_x = data_dict["KP_l3"][:time]
# 时间轴最近邻查找：使用二分查找 searchsortednearest（时序数据约定）
i = [MAVEN_load.MarsCommon.searchsortednearest(kp_x, x_range1) for x_range1 in x_range]
orbit = data_dict["KP"][:Orbit_Number][i]
fig_title = date_str * " " * Dates.format(x_range[1], "HH:MM") * "-" * Dates.format(x_range[2], "HH:MM") *
            " Orbit = $(orbit[1])-$(orbit[2])"
fig = Figure(; size=(2500, 2500))
@time fig, t0, xtimes = plot_module(fig, x_range, data_dict; time_step=Dates.Minute(10))
Label(fig[-1, :]; text=fig_title, halign=:center, valign=:top, padding=(0, 0, 0, 0))
rowsize!(fig.layout, 0, Relative(0.2))

out_file = joinpath(
    out_dir,
    "MAVEN_overview_" * Dates.format(DateTime(yyyy, mm, dd), "yyyymmdd") * "_" *
    Dates.format(x_range[1], "HHMM") * "-" * Dates.format(x_range[2], "HHMM") * ".png",
)
save(out_file, fig)
println("SAVED: ", out_file)
fig