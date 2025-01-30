using TimesDates, Dates
using ColorTypes, CairoMakie
using DataFrames
using ProgressMeter
using LinearAlgebra
using LaTeXStrings
using JLD2
include("../../MAVEN_data/MAVEN_load.jl")
include("../../MAVEN_data/MAVEN_plot.jl")
include("../../MAVEN_data/MAVEN_STATIC.jl")
include("../../Magnetic_Model/IGRF_calculate.jl")
import .MAVEN_load;
import .MAVEN_plot;
import .MAVEN_STATIC;
import .IGRF_calculate;
@inline function mag2sphere(data_dict)
    position = data_dict["MAG_ss1s_l3"][:position]
    b = data_dict["MAG_ss1s_l3"][:B]
    data = MAVEN_load.Bpc2sphere.(position[:, 1], position[:, 2], position[:, 3], b[:, 1], b[:, 2], b[:, 3])
    br = [x[1] for x in data]
    bθ = [x[2] for x in data]
    bϕ = [x[3] for x in data]
    data_dict["MAG_ss1s_l3"][:SphereB] = (br, bθ, bϕ)
    return data_dict
end
@inline function get_data(date; time_range=time_range)
    model_index = [
        "STATIC_d1_v4d",
        "MAG_ss1s_l3","MAG_pc1s_l3",
        "MAG_ss1s_vsc",
        "LPW_wave",
        "KP_l3",
        "SWEA_spec",
        "STATIC_c6",
        "SWIA_svy_spec",
        "SWEA_pad_svy",
    ]
    data_dict = MAVEN_load.data_get_from_date(date, model_index=model_index, show_filename=true)
    # 替换KP_l3数据中的数字标为元标签
    KP_data_name_replace = Dict(
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
    data_dict["KP"] = Dict()
    data_dict["KP"][:data_load_flag] = data_dict["KP_l3"][:data_load_flag]
    for key in keys(KP_data_name_replace)
        data_dict["KP"][key] = data_dict["KP_l3"][:vars][:,[KP_data_name_replace[key]]]
    end
    return data_dict
end
@inline function get_B_model_ss(data_dict)
    B_times0 = data_dict["MAG_pc1s_l3"][:epoch]
    position0 = data_dict["MAG_pc1s_l3"][:position]
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
        ind = findmin(x -> abs(x - B_times[i]), kp_dict[:time])[2]
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
function plot_module(fig, x_range, data_dict, date_str; time_step=Dates.Minute(10), orbit_str="0", time_stemp=[DateTime(2015, 10, 29, 0, 0, 0)])
    colors = Makie.wong_colors()
    eflux_unit = ["(cm",superscript("-2")," s",superscript("-1")," sr",superscript("-1"),")"]
    x_range_unix = Dates.datetime2unix.((x_range[1], x_range[2]))
    xd = Dates.datetime2unix.(range(x_range[1], x_range[2], step=time_step))
    t0 = x_range_unix[1]
    panel_name = [
        "B_xyz",
        "density",
        "SWEA_spec",
        "swea_pad_high","swea_pad_low",
        "SWIA_svy_spec",
        "STATIC_c6",
        "LPW_wave",
        # "STATIC_mass",
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

    # KP part
    #KP的时间为基准时间TIME_KP
    KP_time0 = data_dict["KP_l3"][:time]
    KP_time, KP_time_i = MAVEN_plot.time2x(KP_time0, x_range;t0=t0)
    if "B_xyz" in panel_name
        np = panels["B_xyz"]
        axs[np] = Axis(
            fig[np, panel_ind]; limits=(x_range_unix, nothing), 
            ylabel=rich("B",font =:bold," ",rich("(nT)",font = :regular)), 
            yticks=[-300,-150,0,150,300,450] ,ax_Dict...)
        if data_dict["MAG_ss1s_l3"][:data_load_flag]
            timeB_ss = data_dict["MAG_ss1s_l3"][:epoch]
            B_total_ss= data_dict["MAG_ss1s_l3"][:B_total]
            B_ss = data_dict["MAG_ss1s_l3"][:B]
            timeBm,Bm, = data_dict["MAG_model_ss"][:epoch],data_dict["MAG_model_ss"][:Bm_ss]
            timeB_unix, time_i = MAVEN_plot.time2x(timeB_ss, x_range;t0 = t0)
            timeBm_unix, time_im = MAVEN_plot.time2x(timeBm, x_range;t0=t0)
            if time_i != []
                for (index, name) in enumerate(["Bx", "By", "Bz"])
                    scatter!(axs[np], timeB_unix[1:20:end], B_ss[time_i[1:20:end], index], label=name, color=colors[index], marker='O', markersize=15)
                    lines!(axs[np], timeBm_unix, Bm[time_im, index], linewidth=3, color=colors[index], label=name)
                end
                # axislegend(axs[np], merge=true)
                # Legend(fig[np, color_ind], axs[np]; merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false)
            end
        end
        text!(axs[np], 1, 0, text="MAG", font=:bold,color=:black, align=(:right, :bottom), offset=(-6, 6), space=:relative)
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
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, (10, 5e4)), 
            ylabel=rich("N",font =:italic,subscript("e", font = :regular)," ",rich("(cm",superscript("-3"),")",font = :regular)), 
        yscale=log10, ax_Dict...)
        y = convert.(Float64,data_dict["KP"][:Ne][KP_time_i,1])
        lines!(axs[np], KP_time, y, linewidth=3, label="e-",color=colors[1])
        if data_dict["STATIC_d1_v4d"][:data_load_flag]
            x0 = data_dict["STATIC_d1_v4d"][:epoch]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            ind_tag = findfirst(x -> x >= DateTime(2015, 10, 29, 11, 33, 12), x0[time_i])
            y1 = data_dict["STATIC_d1_v4d"][:O_den][time_i]
            y2 = data_dict["STATIC_d1_v4d"][:O2_den][time_i]
            y3 = data_dict["STATIC_d1_v4d"][:H_den][time_i]
            y1[ind_tag] = NaN
            y2[ind_tag] = NaN
            y3[ind_tag] = NaN
            lines!(axs[np], x, y1, linewidth=3, label="O+",color=colors[2])
            lines!(axs[np], x, y2, linewidth=3, label="O2+",color=colors[3])
            lines!(axs[np], x, y3, linewidth=3, label="H+",color=colors[4])
        end
        Legend(
            fig[np, color_ind], [[],[],[],[]],
            [
                rich("e",superscript("-"),color=colors[1]),
                rich("O",superscript("+"),color=colors[2]),
                rich("O",superscript("+"),subscript("2",offset=(-0.6,0)),color=colors[3]),
                rich("H",superscript("+"),color=colors[4]),
                # rich("H",superscript("+"),color=colors[4]),
                ]; 
            merge=true, padding=padding, framevisible=false, tellheight=false, tellwidth=false
            )
    end
    if "LPW_wave" in panel_name
        np = panels["LPW_wave"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, (1e0, 5e3)), yscale=log10,ax_Dict...)
        if data_dict["LPW_wave"][:data_load_flag]
            timeSP, freq, wave_data = data_dict["LPW_wave"][:epoch], data_dict["LPW_wave"][:freq], data_dict["LPW_wave"][:data]
            c_range = (1e-14, 1e-9)
            x, time_i = MAVEN_plot.time2x(timeSP, x_range;t0=t0)
            if time_i != []
                MAVEN_plot.WaveSpactra_heatmap(axs[np], x, freq[time_i, :], wave_data[time_i, :])
                if data_dict["MAG_ss1s_l3"][:data_load_flag]
                    timeB = data_dict["MAG_ss1s_l3"][:epoch]
                    B_total = data_dict["MAG_ss1s_l3"][:B_total]
                    fce = B_total .* 27.99
                    timeB_unix = datetime2unix.(timeB)
                    lines!(axs[np], timeB_unix, fce, label="fce", linewidth=2, linestyle=:dash, color=:white)
                end

            end
        end
        Colorbar(fig[np, color_ind], limits=c_range, label=L"P_{E}", colormap=:viridis, scale=log10)
    end
    #ions
    c_range_ion = (1e4, 1e9)
    c_range_2 = (1e4, 1e9)
    if "STATIC_c6" in panel_name
        np = panels["STATIC_c6"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, (1, 1e3)), yscale=log10, ylabel=rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)), ax_Dict...)
        if data_dict["STATIC_c6"][:data_load_flag]
            x0, y, c, swp = data_dict["STATIC_c6"][:epoch], data_dict["STATIC_c6"][:energy], data_dict["STATIC_c6"][:eflux], data_dict["STATIC_c6"][:swp_ind]
            # ind_tag = findfirst(x-> x>=DateTime(2015, 10, 29,11,33,12) ,times_ion)
            # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_ion)
            end
        end
        # Colorbar(
        #     fig[np, color_ind], limits=c_range_ion, 
        #     label=rich("J",font =:italic,subscript("i", font = :regular)," ",rich(eflux_unit...,font = :regular)), colormap=:viridis, scale=log10)
        text!(axs[np], 1, 0, text="STATIC", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), space=:relative)
    end
    if "STATIC_mass" in panel_name
        np = panels["STATIC_mass"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, (0.5, 100)), yticks = [1,10,100],yscale=log10, ax_Dict...)
        if data_dict["STATIC_c6"][:data_load_flag]
            x0, y, c, swp = data_dict["STATIC_mass"][:epoch], data_dict["STATIC_mass"][:mass], data_dict["STATIC_mass"][:eflux], data_dict["STATIC_mass"][:swp_ind]
            # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            if time_i != []
                MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_ion)
            end
            hlines!(axs[np], [1, 16, 32.0], color=:white)
        end
        Colorbar(fig[np, color_ind], limits=c_range_ion, label="ion eflux", colormap=:viridis, scale=log10)
    end
    c_range_e = (1e4, 1e9)
    if "SWEA_spec" in panel_name
        np = panels["SWEA_spec"]
        axs[np] = Axis(
            fig[np, panel_ind]; limits=(x_range_unix, (3, 2000)), 
            ylabel=rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)), 
            yscale=log10, ax_Dict...)
        if data_dict["SWEA_spec"][:data_load_flag]
            times_electorn, energy_e, flux_e = data_dict["SWEA_spec"][:epoch], data_dict["SWEA_spec"][:energy], data_dict["SWEA_spec"][:diff_en_fluxes]
            x, time_i = MAVEN_plot.time2x(times_electorn, x_range;t0=t0)
            if time_i != []
                heatmap!(axs[np], x, energy_e, flux_e[time_i, :], colorscale=log10, colorrange=c_range_e, colormap=:viridis,overdraw=true)
                # hlines!(axs[np], [22,27], color=:red, linestyle=:dash,overdraw=true,linewidth=1)
            end
        end
        text!(axs[np], 1, 0, text="SWEA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_e, 
            # label=rich("J",font =:italic,subscript("e", font = :regular)," ",rich(eflux_unit...,font = :regular)), 
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
        text!(axs[np], 1, 0, text="SWEA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), space=:relative)
        text!(axs[np], 1, 0, text="23-27 eV", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 31), space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_2, 
            ticks = ([1*10^6,1*10^7,1*10^8],[rich("10",superscript("6")),rich("10",superscript("7")),rich("10",superscript("8"))]),
            # label=rich("J",font =:italic,subscript("e", font = :regular)," ",rich(eflux_unit...,font = :regular)), 
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
        text!(axs[np], 1, 0, text="SWEA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), space=:relative)
        text!(axs[np], 1, 0, text="90-120 eV", font=:bold,color=:white,align=(:right, :bottom), offset=(-6, 31),space=:relative)
        Colorbar(
            fig[np, color_ind], limits=c_range_2, 
            label=rich("J",font =:italic,subscript("e", font = :regular)," ",rich(eflux_unit...,font = :regular)), 
            ticks=([1*10^6,1*10^7,1*10^8],[rich("10",superscript("6")),rich("10",superscript("7")),rich("10",superscript("8"))],),
            colormap=:viridis, scale=log10)
    end
    #I spactra    
    if "SWIA_svy_spec" in panel_name
        np = panels["SWIA_svy_spec"]
        axs[np] = Axis(fig[np, panel_ind]; limits=(x_range_unix, nothing), ylabel=rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)), yscale=log10, ax_Dict...)
        if data_dict["SWEA_spec"][:data_load_flag]
            x0, y, c = data_dict["SWIA_svy_spec"][:epoch], data_dict["SWIA_svy_spec"][:energy_spectra], data_dict["SWIA_svy_spec"][:spectra_diff_en_fluxes]
            x, time_i = MAVEN_plot.time2x(x0, x_range; t0=t0)
            c[c.==0] .= 1e-20
            if time_i != []
                heatmap!(axs[np], x, y, c[time_i, :]; colorscale=log10, colorrange=c_range_ion, colormap=:viridis)
            end
        end
        if data_dict["STATIC_c6"][:data_load_flag]
            x0, y, swp = data_dict["STATIC_c6"][:epoch], data_dict["STATIC_c6"][:energy], data_dict["STATIC_c6"][:swp_ind]
            x, time_i = MAVEN_plot.time2x(x0, x_range;t0=t0)
            y1 = [maximum(y[:,swp1+1]) for (i,swp1) in enumerate(swp[time_i])]
            lines!(axs[np], x,y1, color=:white, linestyle=:dash)
        end
        text!(axs[np], 1, 0, text="SWIA", font=:bold,color=:white, align=(:right, :bottom), offset=(-6, 6), space=:relative)
        # Colorbar(fig[np, color_ind], limits=(1e4, 1e9), label="Ion eflux", colormap=:viridis, scale=log10)
    end
    
    #colorbar 合并处理
    # Colorbar(
            # fig[panels["SWEA_spec"]:panels["swea_pad_high"], color_ind], limits=c_range_ion, 
            # label=rich("J",font =:italic,subscript("e", font = :regular)," ",rich(eflux_unit...,font = :regular)), colormap=:viridis, scale=log10)
    # Colorbar(
    #     fig[panels["SWIA_svy_spec"]:panels["STATIC_c6"], color_ind], limits=c_range_ion, 
    #     label=rich("J",font =:italic,subscript("i", font = :regular)," ",rich(eflux_unit...,font = :regular)), colormap=:viridis, scale=log10)
    for np in eachindex(panel_name)
        text_color = (panel_name[np] in ["SWIA_svy_spec", "STATIC_H", "STATIC_O", "STATIC_O2","SWEA_spec","STATIC_mass","swea_pad_high", "swea_pad_low"]) ? :white : :black
        text_char = Char('a' + np - 1)
        text!(axs[np], 0, 1, text="($text_char)", font=:bold, align=(:left, :top),
            offset=(4, -6), space=:relative,color = text_color)
    end

    #下标刻度
    np = length(panel_name)
    axs_xtick = [Axis(fig[np, panel_ind], limits=(x_range_unix, nothing),ylabelvisible=false,yticklabelsvisible=false) for i in 1:5]
    xd = range(x_range[1], x_range[2], step=time_step)
    x_i = datetime2unix.(xd)
    xtimes = Dates.format.(xd, "HH:MM")

    timekp = data_dict["KP_l3"][:time]
    x, time_i = MAVEN_plot.time2x(timekp, x_range .+ [-Second(20), Second(20)];t0=t0)
    var_names = ["UT", rich("X",subscript("MSO", font = :regular)), rich("Y",subscript("MSO", font = :regular)), rich("Z",subscript("MSO", font = :regular)),"ALT"]
    vars = [
        (x_i,xtimes),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:MSO_x][time_i]),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:MSO_y][time_i]),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:MSO_z][time_i]),
        MAVEN_plot.interpolate_x_ticks(x_i,x,data_dict["KP"][:alt][time_i]),
    ]
    for (i, var) in enumerate(vars)
        axs_xtick[i].xticks = var
        axs_xtick[i].xticklabelpad = 25*(i-1)
        hidespines!(axs_xtick[i])
        hideydecorations!(axs_xtick[i])
        Label(fig[:, :];
            text=var_names[i],
            valign=:bottom, halign=:left,
            padding=(-90, 0, -35 - (i - 1) * 25, 0)
        )
    end
    for ax in axs
        ax.xticks = x_i
    end
    linkxaxes!(axs..., axs_xtick...)
    return fig, (xtimes, x_range, x_range_unix)
end;
yyyy = 2015
mm = 10
dd = 29
time_range = [DateTime(yyyy, mm, dd, 11, 20), DateTime(yyyy, mm, dd, 11, 45)]
save_file_name = "/example/MAVEN_plot_sample/MAVEN_data_" * Dates.format(DateTime(yyyy, mm, dd), "yyyymmdd") * "_MAVEN_data.jld2"
@time if isfile(save_file_name)
    data_dict = load(save_file_name)["data"]
    println("Read Done")
else
    data_dict = get_data(DateTime(yyyy, mm, dd); time_range=time_range)
    sta_data = data_dict["STATIC_c6"]
    if sta_data[:data_load_flag] == false
        sta_total = Dict(:data_load_flag => false)
        sta_mass = Dict(:data_load_flag => false)
        sta_O2 = Dict(:data_load_flag => false)
    else
        sta_data = MAVEN_STATIC.STA_count2df_all(sta_data)
        sta_total = MAVEN_STATIC.static_c6_mass_mean(sta_data)
        sta_mass = MAVEN_STATIC.static_c6_energy_mean(sta_data)
        sta_O2 = MAVEN_STATIC.static_c6_mass_mean(sta_data, mass_range=[20, 40])
    end
    data_dict["STATIC_c6_orign"] = sta_data
    data_dict["STATIC_c6"] = sta_total
    data_dict["STATIC_mass"] = sta_mass
    data_dict["STATIC_O2"] = sta_O2

    x1, y1, z1 = data_dict["KP"][:GEO_x], data_dict["KP"][:GEO_y], data_dict["KP"][:GEO_z]
    alt = sqrt.(x1 .^ 2 .+ y1 .^ 2 .+ z1 .^ 2) .- 3393.5
    data_dict["KP"][:alt] = alt
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
    data_dict = get_B_model_ss(data_dict)
    # data_dict = mag2sphere(data_dict)
    save(save_file_name, "data", data_dict)
    println("Loading Done")
end

fig = Figure(; size=(2500, 1000))
x_range = [DateTime(2015, 10, 29, 11, 0, 0), DateTime(2015, 10, 29, 12, 0, 0)]
date_str = " "
@time fig, xx = plot_module(fig, x_range, data_dict, date_str; time_step=Dates.Minute(6), time_stemp=[DateTime(2015, 10, 29, 11, 20, 0)])
save("example/MAVEN_plot_sample/MAVEN_case_" * Dates.format(DateTime(yyyy, mm, dd), "yyyymmdd") * ".png", fig)
