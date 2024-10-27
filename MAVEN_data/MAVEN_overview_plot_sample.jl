using TimesDates, Dates
using ColorTypes, CairoMakie
using DataFrames
using ProgressMeter
using LinearAlgebra
using LaTeXStrings
using JLD2
include("../MAVEN_data/MAVEN_load.jl")
include("../MAVEN_data/MAVEN_plot.jl")
include("../MAVEN_data/MAVEN_STATIC.jl")
import .MAVEN_load;
import .MAVEN_plot;
import .MAVEN_STATIC;


function plot_module(fig, x_range, datas_dict, date_str; time_step=Dates.Minute(6), time_stemp=[DateTime(2015, 10, 29, 0, 0, 0)])

    x_range_julian = Dates.datetime2julian.(x_range)
    xd = Dates.datetime2julian.(range(x_range[1], x_range[2], step=time_step))
    #KP的时间为基准时间TIME_KP
    KP_time0 = datas_dict["KP"]["time"]
    KP_time, KP_time_i = MAVEN_plot.time2x(KP_time0, x_range)

    pannel_name = [
        # "orbit",
        "E_field",
        "NGIMS",
        "Ion_temp",
        "Ne",
        "MAGF",
        "STATIC_c6",
        "STATIC_mass",
        "STATIC_O2",
        "O2_vel_1", "O2_vel_2",
        "SWEA_spec",
        "swea_pad_high",
        "lpw_wave",
    ]
    pannels = Dict(name => index for (index, name) in enumerate(pannel_name))
    axs = Vector{Axis}(undef, length(pannel_name))
    color_ind = 3
    pannel_ind = 1:2
    #这些函数都是定义在函数内的闭包, 当变量在定义它们之前被定义,它们将可以使用它
    #比较复杂的绘图块将在这里定义以增加可读性

    np = length(pannel_name)
    axs_xtick = [Axis(fig[np, pannel_ind]), Axis(fig[np, pannel_ind])]
    #####!!!!!!!!!!!!待办, 试试看只用一个坐标轴, 将label设置成"time \n , x \n y \n z \n Alt \n"格式
    #设置下标刻度
    alt = datas_dict["KP"]["alt"][KP_time_i]
    xtimes = (xd, Dates.format.(julian2datetime.(xd), "HH:MM"))
    axs_xtick[1] = x_ticks(axs_xtick[1], x, xtimes, x_i; model="time", range=x_range_julian)
    axs_xtick[2] = x_ticks(axs_xtick[2], x, alt, x_i; xticklabelpad=20, range=x_range_julian)
    axs_xtick[2].xlabel = "Alt[Km]"
    axs_xtick[2].backgroundcolor = :gray

    linkxaxes!(axs..., axs_xtick...)
    for ax in axs
        hidexdecorations!(ax, grid=false)
    end
    # 时间戳
    for ax in axs
        as = datetime2julian.(time_stemp)
        vlines!(ax, as, linestyle=:dash, color=:black)
    end

    function Orbit(ax, x, y; times=([], []), no_lines=false)
        function bowshock(xshock)
            xF = 0.6 # Rm
            ϵ = 1.026
            L = 2.081 # rm
            # rSD = 1.63
            temp = (ϵ^2 - 1.0) * (xshock - xF)^2 - 2ϵ * L * (xshock - xF) + L^2
            if temp >= 0
                return sqrt(temp)
            else
                return Inf64
            end
        end
        function magnetopause(xmp)
            rSD = 1.25
            if xmp > 0
                xF = 0.64
                ϵ = 0.77
                L = 1.08
            else
                xF = 1.60
                ϵ = 1.009
                L = 0.528
            end
            temp = (ϵ^2 - 1.0) * (xmp - xF)^2 - 2ϵ * L * (xmp - xF) + L^2
            if temp >= 0
                return sqrt(temp)
            else
                return Inf64
            end
        end
        ax.xreversed = true

        theta = LinRange(pi, 2pi, 100)
        half_circle = [Point2f(sin(theta[i]), cos(theta[i])) for i in 1:length(theta)]
        poly!(ax, Circle(Point2f(0, 0), 1), color=:white, strokewidth=2, strokecolor=:black)
        poly!(ax, half_circle, color=:black)

        lines!(ax, x, y, overdraw=true)

        if times != ([], [])
            times_t = times[2]
            time_index = times[1]
            colormap = :viridis
            n_colors = length(time_index)
            colors = resample_cmap(colormap, n_colors)
            for (it, i) in enumerate(time_index)
                poly!(ax, Circle(Point2f(x[i], y[i]), 0.15), color=colors[it], label=times_t[it])
            end
        end
        if no_lines
            return ax
        end
        x = -10:0.01:2
        y = bowshock.(x)
        x = [x; x]
        y = [-y; y]
        lines!(ax, x, y; linestyle=:dash)#label="bowshock"
        x = -10:0.01:2
        y = magnetopause.(x)
        x = [x; x]
        y = [-y; y]
        lines!(ax, x, y; linestyle=:dash)#label="magnetopause",
        return ax
    end

    # # np = pannels["orbit"]; 
    # axs_orbit_1 = Axis(fig[pannels["lpw_wave"],1],limits=((-3,3),(0,3)))
    # axs_orbit_2 = Axis(fig[pannels["lpw_wave"]-1,1],limits=((-9,3),(-3,3)))
    # axs_orbit_3 = Axis(fig[pannels["lpw_wave"]-2,1],limits=((-9,3),(-3,3)))
    # Label(fig[0,2],date_str*" Orbit_num: "*orbit_str,justification = :center)
    # hidexdecorations!(axs_orbit_2, grid = false)
    # hidexdecorations!(axs_orbit_3, grid = false)
    # colsize!(fig.layout, 1, Relative(0.18))
    # colsize!(fig.layout, 2, Relative(0.82))

    # rowsize!(fig.layout, 1, Relative(0.3))
    # colsize!(fig.layout, 1, Relative(1/6))
    # colsize!(fig.layout, 2, Relative(1/6))
    # colsize!(fig.layout, 3, Relative(1/6))


    # MAGF
    if "MAGF" in pannels
        np = pannels["MAGF"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, nothing), ylabel=L"\textbf{\text{B}} \; (\; \text{nT} \;)")
        timeB, _, B0, _ = datas_dict["MAG_ss1s"]["Vars"]
        timeB_julian, time_i = MAVEN_plot.time2x(timeB, x_range)
        if time_i != []
            shadow_Br = true
            if shadow_Br
                br,_,_ = datas_dict["MAG_ss1s"]["SphereB"]
                br = br .> 0
                @inline function find_segments(x::Vector{T}, y::BitVector) where T
                    segments1 = []
                    segments2 = []
                    start_idx = nothing
                    for i in eachindex(y)
                        if y[i] == 1
                            if start_idx === nothing
                                start_idx = i
                            end
                        elseif start_idx !== nothing
                            push!(segments1, x[start_idx])
                            push!(segments2, x[i-1])
                            start_idx = nothing
                        end
                    end
                    if start_idx !== nothing
                        push!(segments1, x[start_idx])
                        push!(segments2, x[end])
                    end
                    return segments1,segments2
                end
                s1,s2 = find_segments(timeB_julian, br[time_i])
                vspan!(axs[np],s1,s2,label="Br>0",alpha=0.2,color = :gray) 
                band!(axs[np],timeB_julian,br[time_i],br[time_i].*0,label="Br>0",linewidth=2,alpha=0.2,color = :gray,overdraw=true)
            end
            color = Makie.wong_colors()[1:3]
            for (index, name) in enumerate(["Bx", "By", "Bz"])
                lines!(axs[np], timeB_julian, B0[time_i, index], label=name, linewidth=2, color=color[index])
            end
            fig[np, color_ind] = Legend(fig, axs[np])
        end
    end
    # KP part
    if "Ne" in pannels
        np = pannels["Ne"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, nothing), ylabel=L"N_{e} (cm^{-3})", yscale=log10)
        y = datas_dict["KP"]["electorn density"][KP_time_i]
        y1 = datas_dict["KP"]["Ne quality max"][KP_time_i]
        y2 = datas_dict["KP"]["Ne quality min"][KP_time_i]
        rangebars!(axs[np], KP_time, abs.(y1), abs.(y2))
        scatter!(axs[np], KP_time, y, markersize=5, color=:red)
    end
    if "Ion_temp" in pannels
        np = pannels["Ion_temp"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (0, 0.25)), ylabel="K [eV]")
        y = datas_dict["KP"]["O+ Temperature"][KP_time_i]
        y1 = datas_dict["KP"]["O2+ Temperature"][KP_time_i]
        lines!(axs[np], KP_time, y, linewidth=2, label="O+")
        lines!(axs[np], KP_time, y1, linewidth=2, label="O2+")
        fig[np, color_ind] = Legend(fig, axs[np])
    end
    if "E_field" in pannels
        np = pannels["E_field"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, nothing), ylabel="mV/m")
        x = datas_dict["E_field"]["time"]
        y = datas_dict["E_field"]["data"]
        lines!(axs[np], x, y)
    end
    c_range_1 = (1e4, 1e9)
    c_range_2 = (1e4, 1e9)
    if "STATIC_c6" in pannels && datas_dict["STATIC_c6"]["data_load_flag"]
        np = pannels["STATIC_c6"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (1, 1e4)), yscale=log10)
        x0, y, c, swp = datas_dict["STATIC_c6"]["epoch"], datas_dict["STATIC_c6"]["energy"], datas_dict["STATIC_c6"]["eflux"], datas_dict["STATIC_c6"]["swp_ind"]
        # ind_tag = findfirst(x-> x>=DateTime(2015, 10, 29,11,33,12) ,times_ion)
        # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
        x, time_i = MAVEN_plot.time2x(x0, x_range)
        if time_i != []
            MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_1)
        end
        Colorbar(fig[np, color_ind], limits=c_range_1, label="ion eflux", colormap=:viridis, scale=log10)
    end
    if "STATIC_mass" in pannels && datas_dict["STATIC_c6"]["data_load_flag"]
        np = pannels["STATIC_mass"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (0.5, 64)), yscale=log10)
        x0, y, c, swp = datas_dict["STATIC_mass"]["epoch"], datas_dict["STATIC_mass"]["mass"], datas_dict["STATIC_mass"]["eflux"], datas_dict["STATIC_mass"]["swp_ind"]
        # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
        x, time_i = MAVEN_plot.time2x(x0, x_range)
        if time_i != []
            MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_1, ylabel="mass AMU")
        end
        hlines!(axs[np], [1,16,32.0], color=:white)
        Colorbar(fig[np, color_ind], limits=c_range_1, label="ion eflux", colormap=:viridis, scale=log10)
    end
    if "STATIC_O2" in pannels && datas_dict["STATIC_c6"]["data_load_flag"]
        np = pannels["STATIC_O2"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (1, 1e4)), yscale=log10)
        x0, y, c, swp = datas_dict["STATIC_O2"]["epoch"], datas_dict["STATIC_O2"]["energy"], datas_dict["STATIC_O2"]["eflux"], datas_dict["STATIC_O2"]["swp_ind"]
        x, time_i = MAVEN_plot.time2x(x0, x_range)
        if time_i != []
            MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_2, ylabel="energy")
        end
        hlines!(axs[np],[30.0,200], color=:white)
        Colorbar(fig[np, color_ind], limits=c_range_2, label="O2+ eflux", colormap=:viridis, scale=log10)
    end

    # sc potential
    if datas_dict["LPW_mrgscpot" ] && "STATIC_c6" in pannels
        np = pannels["STATIC_c6"]
        time_scp, data_scp = datas_dict["LPW_mrgscpot"]["epoch"], datas_dict["LPW_mrgscpot"]["data"]
        x, time_i = MAVEN_plot.time2x(time_scp, x_range)
        ax_scp1 = Axis(fig[np, pannel_ind], yticklabelcolor=:orange, yaxisposition=:right, limits=(x_range_julian, (-10, 10)), ylabel="potential")
        hidespines!(ax_scp1)
        hidexdecorations!(ax_scp1)
        y = replace(data_scp[time_i], NaN => 0)
        stem!(ax_scp1, x, y, offset=0, trunkcolor=:white, marker=:circle, stemcolor=:white, color=:orange,
            markersize=5, trunklinestyle=:dot)
    end
    #electorn spactra            
    if datas_dict["SWEA_spec"]["data_load_flag"] && "SWEA_spec" in pannels
        np = pannels["SWEA_spec"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (3, 1000)), ylabel="energy", yscale=log10)
        times_electorn, energy_e, flux_e = datas_dict["SWEA_spec"]["epoch"], datas_dict["SWEA_spec"]["energy"], datas_dict["SWEA_spec"]["diff_en_fluxes"]
        x, time_i = MAVEN_plot.time2x(times_electorn, x_range)
        if time_i != []
            hm_e_sp = heatmap!(axs[np], x, energy_e, flux_e[time_i, :], colorscale=log10, colorrange=(1e4, 1e10), colormap=:viridis)
            Colorbar(fig[np, color_ind], hm_e_sp, label="electorn eflux")#
        end
    end
    # swea pad
    if "swea_pad_low" in pannels && datas_dict["swea_pad_low"]["data_load_flag"]
        colorrange_1 = (1e7, 1e9)
        colorrange_2 = (1e4, 1e9)
        np = pannels["swea_pad_low"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (0, 180)))
        x, y, c = datas_dict["swea_pad_low"]["epoch"], datas_dict["swea_pad_low"]["pa"], datas_dict["swea_pad_low"]["diff_en_fluxes"]
        x, time_i = MAVEN_plot.time2x(x, x_range)
        if time_i != []
            MAVEN_plot.SWEA_PAD_heatmap(axs[np], x, y[time_i, :], c[time_i, :]; c_range=colorrange_1, ylabel="Pitch angle \n [deg]")
        end
        Colorbar(fig[np, color_ind], limits=colorrange_1, label="SWEA \n 20-30eV", colormap=:viridis, scale=log10)
    end
    if "swea_pad_high" in pannels && datas_dict["swea_pad_high"]["data_load_flag"]    
        np = pannels["swea_pad_high"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (0, 180)))
        x, y, c = datas_dict["swea_pad_high"]["epoch"], datas_dict["swea_pad_high"]["pa"], datas_dict["swea_pad_high"]["diff_en_fluxes"]
        x, time_i = MAVEN_plot.time2x(x, x_range)
        if time_i != []
            MAVEN_plot.SWEA_PAD_heatmap(axs[np], x, y[time_i, :], c[time_i, :]; c_range=colorrange_2, ylabel="Pitch angle \n [deg]")
        end
        Colorbar(fig[np, color_ind], limits=colorrange_2, label="SWEA \n 90-120eV", colormap=:viridis, scale=log10)
    end
    # Wave Spectra
    if "lpw_wave" in pannels && datas_dict["LPW_wave"]["data_load_flag"]
        np = pannels["lpw_wave"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_julian, (1e0, 1e4)), yscale=log10)
        timeSP, freq, wave_data = datas_dict["LPW_wave"]["epoch"], datas_dict["LPW_wave"]["freq"], datas_dict["LPW_wave"]["data"]
        c_range = (1e-14, 1e-9)
        x, time_i = MAVEN_plot.time2x(timeSP, x_range)
        if time_i != []
            MAVEN_plot.WaveSpactra_heatmap(axs[np], x, freq[time_i, :], wave_data[time_i, :])
            if datas_dict["MAG_ss1s_l3"]["data_load_flag"]
                timeB, _, B0, _ = datas_dict["MAG_ss1s"]["Vars"]
                fce = B0 .*27.99
                timeB_julian = datetime2julian.(timeB)
                lines!(axs[np], timeB_julian, fce, label="fce", linewidth=2, linstyle=:dash, color=:white)
            end
            Colorbar(fig[np, color_ind], limits=c_range, label=L"P_{E}", colormap=:viridis, scale=log10)
        end
    end
    return fig, (xtimes, x_range, x_range_julian)
end;