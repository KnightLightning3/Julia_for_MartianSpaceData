"""生成 MAVEN 多仪器时间序列概览图的示例程序。"""

using TimesDates, Dates
if !isdefined(@__MODULE__, :constants)
    include(joinpath(@__DIR__, "..", "..", "common", "constants.jl"))
end
using ColorTypes, CairoMakie
using DataFrames
using ProgressMeter
using LinearAlgebra
using JLD2
include("../../MAVEN_data/MAVEN_load.jl");import .MAVEN_load;
include("../../MAVEN_data/MAVEN_plot.jl");import .MAVEN_plot;
include("../../MAVEN_data/MAVEN_STATIC.jl");import .MAVEN_STATIC;
include("../../Magnetic_Model/IGRF_calculate.jl");import .IGRF_calculate;

"""
    TimeFormat(time1, time2) -> String

把两个时间点之间的时长格式化为 `HH:MM:SS.mmm` 字符串。

# 参数说明
- `time1`, `time2`: 起止时间。

# 返回值
- `String`: 格式化后的时长。
"""
function TimeFormat(time1, time2)
    elapsed_time_ms = Dates.value(time2 - time1)
    hours = div(elapsed_time_ms, 3600000)
    minutes = div(mod(elapsed_time_ms, 3600000), 60000)
    seconds = div(mod(elapsed_time_ms, 60000), 1000)
    milliseconds = mod(elapsed_time_ms, 1000)
    return "$(lpad(hours, 2, '0')):$(lpad(minutes, 2, '0')):$(lpad(seconds, 2, '0')).$(lpad(milliseconds, 3, '0'))"
end
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
"""
    remove_0_point!(y) -> Vector

将非正绘图数据原地替换为 `NaN`。

# 参数说明
- `y`: 数值数组（就地修改）。

# 返回值
- 修改后的同一数组。
"""
function remove_0_point!(y)
    y[y .<= 0] .= NaN
    return y
end
"""
    plot_module(fig, x_range, data_dict; time_step=Dates.Minute(10))

向图形对象添加 MAVEN 多仪器时间序列绘图面板。

# 功能与算法概述
在给定时间范围内为磁场、密度、速度、电位及各仪器能谱等创建纵向堆叠面板，
分别绘制曲线或热图。

# 参数说明
- `fig`: Makie `Figure`。
- `x_range`: 时间范围 `[t_start, t_end]`。
- `data_dict`: 由 `get_data` 返回的数据字典。
- `time_step`: 时间刻度步长。

# 返回值
- 无（就地修改 `fig`）。

# 注意事项
- 依赖 `data_dict` 中各仪器键存在；面板名称在函数内固定。
"""
function plot_module(fig, x_range, data_dict; time_step=Dates.Minute(10))
    colors = Makie.wong_colors()
    t0 = Dates.datetime2unix((x_range[1]))
    time_range_unix = Dates.datetime2unix.([x_range[1], x_range[2]]) .- t0
    x_range_unix = (time_range_unix[1], time_range_unix[2])
    panel_name = [
        "B_xyz",
        "density",
        "H_vel",
        "scpot",
        "SWEA_spec",
        "swea_pad_high","swea_pad_low",
        "SWIA_svy_spec",
        "STATIC_c6",
        "STATIC_mass",
        "LPW_wave",
    ]
    panels = Dict(name => index for (index, name) in enumerate(panel_name))
    color_ind = 2
    padding = (60.0f0, 0.0f0, 0.0f0, 0.0f0)
    panel_ind = 1
    axs = Vector{Axis}(undef, length(panel_name))
    ax_Dict = Dict(
        :xgridvisible => false,
        :xlabelvisible => false,
        :xticklabelsvisible => false,
    )
    xtimes,x_i = MAVEN_plot.time_ticks(x_range;step=time_step,t0=t0,format = "HH:MM")
    timekp = data_dict["KP_l3"][:time]
    x, time_i = MAVEN_plot.time2x(timekp, x_range .+ [-Second(20), Second(20)];t0=t0)
    var_names = ["UT", rich("X",subscript("MSO", font = :regular)), rich("Y",subscript("MSO", font = :regular)), rich("Z",subscript("MSO", font = :regular)),"ALT"]
    tick_vars = [
        xtimes,
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:MSO_x][time_i]),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:MSO_y][time_i]),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:MSO_z][time_i]),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:alt][time_i]),
    ]

    # KP part
    #KP的时间为基准时间TIME_KP
    KP_time0 = data_dict["KP_l3"][:time]
    KP_time, KP_time_i = MAVEN_plot.time2x(KP_time0, x_range;t0=t0)
    plot_orbit = true
    if plot_orbit
        ax1 = Axis(
            fig[0, panel_ind][1,1],aspect = DataAspect(),xlabel = rich("X",subscript("MSO")),
            ylabel = rich("(Y",superscript("2"),subscript("MSO",offset=(-0.6,0))," + Z",superscript("2"),subscript("MSO",offset=(-0.6,0)),")",superscript("1/2")),
            limits = ((-3, 3), (0,4)),xreversed = true
            )
        ax2 = Axis(
            fig[0, panel_ind][1,2],aspect = DataAspect(),xlabel = rich("X",subscript("MSO")),
            ylabel = rich("Y",subscript("MSO")),
            limits = ((-3, 3), (-3,3)),xreversed = true
            )
        ax3 = Axis(
            fig[0, panel_ind][1,3],aspect = DataAspect(),xlabel = rich("X",subscript("MSO")),
            ylabel = rich("Z",subscript("MSO")),
            limits = ((-3, 3), (-3,3)),xreversed = true
            )
        x = data_dict["KP"][:MSO_x][KP_time_i]
        y = data_dict["KP"][:MSO_y][KP_time_i]
        z = data_dict["KP"][:MSO_z][KP_time_i]
        pos_tick = [tick_vars[2][2] tick_vars[3][2] tick_vars[4][2]]
        pos_tick = parse.(Float32, pos_tick)
        n_points = length(pos_tick[:,1])
        pos_ss = [x y z]

        mapped_colors = [cgrad(:jet, n_points, categorical=true)...]

        ax1,func_trans1 = MAVEN_plot.Orbit(ax1;pos_ss=pos_ss,frame="x-yz",line_krawg_sc =Dict(:color=>colors[1],:linewidth=>3))
        pp = func_trans1.(pos_tick[:,1],pos_tick[:,2],pos_tick[:,3])
        scatter!(ax1, pp, color=mapped_colors, colormap=:jet, markersize=15, marker=:xcross)
        ax2,func_trans2 = MAVEN_plot.Orbit(ax2;pos_ss=pos_ss,frame="x-y",line_krawg_sc =Dict(:color=>colors[1],:linewidth=>3))
        pp = func_trans2.(pos_tick[:,1],pos_tick[:,2],pos_tick[:,3])
        scatter!(ax2, pp, color=mapped_colors, colormap=:jet, markersize=15, marker=:xcross)
        ax3,func_trans3 = MAVEN_plot.Orbit(ax3;pos_ss=pos_ss,frame="x-z",line_krawg_sc =Dict(:color=>colors[1],:linewidth=>3))
        pp = func_trans3.(pos_tick[:,1],pos_tick[:,2],pos_tick[:,3])
        scatter!(ax3, pp, color=mapped_colors, colormap=:jet, markersize=15, marker=:xcross)

        elements = [MarkerElement(color = i, marker = :rect, markersize = 15) for i in mapped_colors]

        Legend(
            fig[0, panel_ind][1,4], elements,xtimes[2]; 
            merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false,nbanks=3)
    end
    if "B_xyz" in panel_name
        np = panels["B_xyz"]
        axs[np] = Axis(
            fig[np, panel_ind]; limits=(x_range_unix, nothing), 
            ylabel=rich("B",font =:bold," ",rich("(nT)",font = :regular)), 
            ax_Dict...)
        if data_dict["MAG_ss1s_cdf"][:data_load_flag]
            timeB_ss = data_dict["MAG_ss1s_cdf"][:epoch]
            B_ss = data_dict["MAG_ss1s_cdf"][:B]
            timeBm,Bm, = data_dict["MAG_model_ss"][:epoch],data_dict["MAG_model_ss"][:Bm_ss]
            timeB_unix, time_i = MAVEN_plot.time2x(timeB_ss, x_range;t0 = t0)
            timeBm_unix, time_im = MAVEN_plot.time2x(timeBm, x_range;t0=t0)
            if time_i != []
                for (index, name) in enumerate(["Bx", "By", "Bz"])
                    lines!(axs[np], timeB_unix, B_ss[time_i, index], label=name, linewidth=3,color=colors[index])
                    lines!(axs[np], timeBm_unix, Bm[time_im, index], linewidth=3, color=colors[index], label=name,linestyle = :dash)
                end
            end
        end
        text!(axs[np], 1, 0, text="MAG", font=:bold,color=:black, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        Legend(
            fig[np, color_ind], [[],[],[]],
            [
                rich("B",font = :italic,subscript("x", font = :regular),color=colors[1]),
                rich("B",font = :italic,subscript("y", font = :regular),color=colors[2]),
                rich("B",font = :italic,subscript("z", font = :regular),color=colors[3]),]; 
            merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false)
    end
    if "density" in panel_name 
        np = panels["density"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix,nothing), 
            ylabel=rich("N",font =:italic,subscript("e", font = :regular)," ",rich("(cm",superscript("-3"),")",font = :regular)), 
        yscale=log10, ax_Dict...)
        y = convert.(Float64, data_dict["KP"][:Ne][KP_time_i])
        lines!(axs[np], KP_time, y, linewidth=3, label="e-",color=:black)
        if data_dict["STATIC_d1_v4d"][:data_load_flag]
            x0 = data_dict["STATIC_d1_v4d"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            y1 = remove_0_point!(data_dict["STATIC_d1_v4d"][:O_den][time_i])
            y2 = remove_0_point!(data_dict["STATIC_d1_v4d"][:O2_den][time_i])
            y3 = remove_0_point!(data_dict["STATIC_d1_v4d"][:H_den][time_i])
            lines!(axs[np], x, y1, linewidth=3, label="O+",color=colors[1])
            lines!(axs[np], x, y2, linewidth=3, label="O2+",color=colors[2])
            lines!(axs[np], x, y3, linewidth=3, label="H+",color=colors[3])
        end
        if data_dict["SWIA_mom"][:data_load_flag]
            x0 = data_dict["SWIA_mom"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            y = remove_0_point!(data_dict["SWIA_mom"][:density][time_i])
            lines!(axs[np], x, y, linewidth=3, label="SWIA",color=colors[4])
        end
        text!(axs[np], 1, 0, text="LPW-STATIC-SWIA", font=:bold,color=:black,align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        Legend(
            fig[np, color_ind], [[],[],[],[],[]],
            [
                rich("e",superscript("-"),color=:black),
                rich("O",superscript("+"),color=colors[1]),
                rich("O",superscript("+"),subscript("2",offset=(-0.6,0)),color=colors[2]),
                rich("H",superscript("+"),color=colors[3]),
                rich("p",superscript("+"),color=colors[4]),
                ]; 
            merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false
            )
    end
    if "H_vel" in panel_name
        np = panels["H_vel"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, nothing), ylabel="H+ V (km/s)", ax_Dict...)
        if data_dict["SWIA_mom"][:data_load_flag]
            x0 = data_dict["SWIA_mom"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                for index in 1:3
                    lines!(axs[np], x, data_dict["SWIA_mom"][:velocity_mso][time_i,index], linewidth=3,color=colors[index])
                end
            end
        end
        text!(axs[np], 1, 0, text="SWIA", font=:bold,color=:black, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        Legend(
            fig[np, color_ind], [[],[],[]],
            [
                rich("V",subscript("x", font = :regular),color=colors[1]),
                rich("V",subscript("y", font = :regular),color=colors[2]),
                rich("V",subscript("z", font = :regular),color=colors[3]),
                ]; 
            merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false)
    end
    if "scpot" in panel_name
        np = panels["scpot"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, (-10,10)), ylabel="scpot (V)", ax_Dict...)
        if data_dict["STATIC_c6_origin"][:data_load_flag]
            x0 = data_dict["STATIC_c6_origin"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                lines!(axs[np], x, data_dict["STATIC_c6_origin"][:sc_pot][time_i], linewidth=3,color=colors[1])
            end
        end
        if data_dict["LPW_mrgscpot"][:data_load_flag]
            x0 = data_dict["LPW_mrgscpot"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                flag = data_dict["LPW_mrgscpot"][:flag][time_i]
                data = data_dict["LPW_mrgscpot"][:data][time_i]
                flag_ind = flag .>= 50
                lines!(axs[np], x[flag_ind], data[flag_ind], linewidth=3,color=colors[2])
            end
        end
        hlines!(axs[np], [0], color=:black)
        Legend(
            fig[np, color_ind], [[],[]],
            [
                rich("STATIC",color= colors[1]),
                rich("LPW_mrgscpot",color=colors[2]),
                ]; 
            merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false)
    end
    if "LPW_wave" in panel_name
        np = panels["LPW_wave"]
        c_range_lpw = (1e-14,1e-9)
        f_range = (1, 1e5)
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, f_range), 
        ylabel = rich("f ", font =:italic, rich("(Hz)",font = :regular)),
        yscale=identity,ax_Dict...)
        if data_dict["LPW_wave"][:data_load_flag]
            timeSP = data_dict["LPW_wave"][:epoch]
            x, time_i = MAVEN_plot.time2x(timeSP, x_range;t0=t0)
            if time_i != []
                wave_data = data_dict["LPW_wave"][:data][time_i, :]
                freq = data_dict["LPW_wave"][:freq][time_i, :]
                if false in isnan.(wave_data)
                    MAVEN_plot.WaveSpectra_heatmap(axs[np], x, freq, wave_data;c_range=c_range_lpw,f_range=f_range)
                end
            end
        end
        if data_dict["MAG_ss1s_cdf"][:data_load_flag]
            timeB = data_dict["MAG_ss1s_cdf"][:epoch]
            x, time_i = MAVEN_plot.time2x(timeB, x_range;t0=t0)
            if time_i != []
                # 新 MAG CDF 产品不含 :B_total，此处由三分量计算总场
                B_vec = data_dict["MAG_ss1s_cdf"][:B][time_i, :]
                B_total = sqrt.(sum(B_vec.^2, dims=2))[:, 1]
                fce = log10.(B_total .* 27.99)
                lines!(axs[np], x, fce, label="fce", linewidth=2, linestyle=:dash, color=:white)
            end
        end
        text!(axs[np], 1, 0, text="LPW", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_lpw, 
            label=rich("P",font =:italic,subscript("E", font = :regular)," ",rich("(V",superscript("2"),"/m",superscript("2"),"/Hz)",font = :regular)),
            colormap=:viridis, 
            scale=log10)
    end
    #ions
    c_range_ion = (1e4, 1e9)
    c_range_2 = (1e4, 1e9)
    if "STATIC_c6" in panel_name
        np = panels["STATIC_c6"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, nothing), yscale=log10, ylabel=rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)), ax_Dict...)
        if data_dict["STATIC_c6"][:data_load_flag]
            x0 = data_dict["STATIC_c6"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                y = data_dict["STATIC_c6"][:energy]
                c = data_dict["STATIC_c6"][:eflux][time_i, :]
                swp = data_dict["STATIC_c6"][:swp_ind][time_i]
                MAVEN_plot.sta_heatmap(axs[np], x, y, c, swp; c_range=c_range_ion)
            end
        end
        Colorbar(
            fig[np, color_ind], limits=c_range_ion, 
            label="sta_ion-eflux", colormap=:viridis, scale=log10)
        text!(axs[np], 1, 0, text="STATIC", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
    end
    if "STATIC_mass" in panel_name
        np = panels["STATIC_mass"]
        axs[np] = Axis(
            fig[np, panel_ind]; 
            limits=(x_range_unix, (0.5, 100)), 
            ylabel=rich("M",subscript("i")," ",rich("(amu)")),
            yticks = [1,10,100],yscale=log10, ax_Dict...)
        if data_dict["STATIC_c6"][:data_load_flag]
            x0 = data_dict["STATIC_mass"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                y = data_dict["STATIC_mass"][:mass]
                c = data_dict["STATIC_mass"][:eflux][time_i, :]
                swp = data_dict["STATIC_mass"][:swp_ind][time_i]
                MAVEN_plot.sta_heatmap(axs[np], x, y, c, swp; c_range=c_range_ion)
            end
            hlines!(axs[np], [1, 16, 32.0], color=:white)
        end
        text!(axs[np], 1, 0, text="STATC", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        Colorbar(fig[np, color_ind], limits=c_range_ion, label="sta_ion-eflux", colormap=:viridis, scale=log10)
    end
    c_range_e = (1e4, 1e9)
    if "SWEA_spec" in panel_name
        np = panels["SWEA_spec"]
        axs[np] = Axis(
            fig[np, panel_ind]; limits=(x_range_unix, nothing), 
            ylabel=rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)), 
            yscale=log10, ax_Dict...)
        if data_dict["SWEA_spec"][:data_load_flag]
            times_electorn = data_dict["SWEA_spec"][:time_unix]
            x, time_i = MAVEN_plot.time2x(times_electorn, x_range;t0=t0,convert = false)
            if time_i != []
                energy_e, flux_e = data_dict["SWEA_spec"][:energy], data_dict["SWEA_spec"][:diff_en_fluxes][time_i, :]
                heatmap!(axs[np], x, energy_e, flux_e, colorscale=log10, colorrange=c_range_e, colormap=:viridis,overdraw=true)
                # hlines!(axs[np], [22,27], color=:red, linestyle=:dash,overdraw=true,linewidth=1)
            end
        end
        text!(axs[np], 1, 0, text="SWEA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), strokewidth=50,space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_e, 
            label="swe_e_eflux", 
            colormap=:viridis, scale=log10
            )
    end
    if "swea_pad_low" in panel_name
        local c_range_2 = (1*10^6.5, 1*10^8.4)
        np = panels["swea_pad_low"]
        axs[np] = Axis(
            fig[np, panel_ind]; limits=(x_range_unix, (0, 180)), 
            ylabel="α (deg)", 
            yticks = [30,60,90,120,150],
            ax_Dict...)
        # swea_pad = data_dict["SWEA_pad_svy"]
        swea_pad_low = data_dict["swea_pad_low"]
        if swea_pad_low[:data_load_flag]
            # swea_pad_low = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[23, 27])
            x, y, c = swea_pad_low[:epoch], swea_pad_low[:pa], swea_pad_low[:diff_en_fluxes]
            x, time_i = MAVEN_plot.time2x(x, x_range;t0=t0)
            if time_i != []
                MAVEN_plot.SWEA_PAD_heatmap(axs[np], x, y[time_i, :], c[time_i, :]; c_range=c_range_2)
            end
        end
        text!(axs[np], 1, 0, text="SWEA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        text!(axs[np], 1, 0, text="20-30 eV", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 31),strokewidth=5, space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_2, 
            ticks = ([1*10^6,1*10^7,1*10^8],[rich("10",superscript("6")),rich("10",superscript("7")),rich("10",superscript("8"))]),
            label="swe_e_eflux", 
            colormap=:viridis, scale=log10)
    end
    if "swea_pad_high" in panel_name
        local c_range_2 = (1*10^5.6, 1*10^8.0)
        np = panels["swea_pad_high"]
        axs[np] = Axis(
            fig[np, panel_ind]; limits=(x_range_unix, (0, 180)), 
            ylabel="α (deg)", 
            yticks = [30,60,90,120,150],
            ax_Dict...)
        # swea_pad = data_dict["SWEA_pad_svy"]
        swea_pad_high = data_dict["swea_pad_high"]
        if swea_pad_high[:data_load_flag]
            # swea_pad_high = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[90, 120])
            x, y, c = swea_pad_high[:epoch], swea_pad_high[:pa], swea_pad_high[:diff_en_fluxes]
            x, time_i = MAVEN_plot.time2x(x, x_range;t0=t0)
            if time_i != []
                MAVEN_plot.SWEA_PAD_heatmap(axs[np], x, y[time_i, :], c[time_i, :]; c_range=c_range_2)
            end
        end
        text!(axs[np], 1, 0, text="SWEA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), strokewidth=5,space=:relative)
        text!(axs[np], 1, 0, text="90-120 eV", font=:bold,color=:white,align=(:right, :bottom), offset=(-6, 31),strokewidth=5,space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_2, 
            label="swe_e_eflux", 
            ticks=([1*10^6,1*10^7,1*10^8],[rich("10",superscript("6")),rich("10",superscript("7")),rich("10",superscript("8"))],),
            colormap=:viridis, scale=log10)
    end
    #I spactra    
    if "SWIA_svy_spec" in panel_name
        np = panels["SWIA_svy_spec"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, nothing), ylabel=rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)), yscale=log10, ax_Dict...)
        if data_dict["SWIA_svy_spec"][:data_load_flag]
            x0 = data_dict["SWIA_svy_spec"][:time_unix]
            x, time_i = MAVEN_plot.time2x(x0, x_range; t0=t0,convert = false)
            if time_i != []
                y = data_dict["SWIA_svy_spec"][:energy_spectra]
                c = data_dict["SWIA_svy_spec"][:spectra_diff_en_fluxes][time_i, :]
                c[c.==0] .= 1e-20
                heatmap!(axs[np], x, y, c; colorscale=log10, colorrange=c_range_ion, colormap=:viridis)
            end
        end
        if data_dict["STATIC_c6"][:data_load_flag]
            x0 = data_dict["STATIC_c6"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                y = data_dict["STATIC_c6"][:energy]
                swp = data_dict["STATIC_c6"][:swp_ind][time_i]
                y1 = [maximum(y[:,swp1+1]) for swp1 in swp]
                lines!(axs[np], x,y1, color=:white, linestyle=:dash)
            end
        end
        text!(axs[np], 1, 0, text="SWIA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6),strokewidth=5, space=:relative)
        Colorbar(fig[np, color_ind], limits=(1e4, 1e9), label="swi_ion_eflux", colormap=:viridis, scale=log10)
    end
    
    for np in eachindex(panel_name)
        text_color = (panel_name[np] in ["SWIA_svy_spec", "SWEA_spec","STATIC_mass","STATIC_c6","swea_pad_high", "swea_pad_low","LPW"]) ? :white : :black
        text_char = Char('a' + np - 1)
        text!(axs[np], 0, 1, text="($text_char)", font=:bold, align=(:left, :top),strokewidth=5,
            offset=(4, -6), space=:relative,color = text_color)
    end

    #下标刻度
    np = length(panel_name)
    axs_xtick = [Axis(fig[np, panel_ind], limits=(x_range_unix, nothing),ylabelvisible=false,yticklabelsvisible=false) for i in 1:5]
    for (i, var) in enumerate(tick_vars)
        axs_xtick[i].xticks = var
        axs_xtick[i].xticklabelpad = 25*(i-1)
        hidespines!(axs_xtick[i])
        hideydecorations!(axs_xtick[i])
        Label(fig[:, :];
            text=var_names[i],
            valign=:bottom, halign=:left,
            padding=(-60, 0, -25 - (i - 1) * 25, 0)
        )
    end
    for ax in axs
        ax.xticks = x_i
    end
    linkxaxes!(axs..., axs_xtick...)
    return fig,t0,xtimes
end;

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