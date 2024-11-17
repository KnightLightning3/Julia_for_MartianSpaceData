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
import .MAVEN_load;
import .MAVEN_plot;
import .MAVEN_STATIC;

@inline function get_data(date; time_range=time_range)
    @inline function get_ion_vel(time_range, datas_dict)
        data_sta = datas_dict["STATIC_d1"]
        sta_epoch = data_sta["epoch"]
        time_i = findall(x -> time_range[2] >= x >= time_range[1], sta_epoch)
        time = data_sta["epoch"][time_i]
        ntime = length(time)
        H_vel_1 = zeros(ntime, 4)
        H_vel_2 = zeros(ntime, 4)
        O_vel_1 = zeros(ntime, 4)
        O_vel_2 = zeros(ntime, 4)
        O2_vel_1 = zeros(ntime, 4)
        O2_vel_2 = zeros(ntime, 4)
        H_den = zeros(ntime)
        O_den = zeros(ntime)
        O2_den = zeros(ntime)

        timeb = datas_dict["MAG_ss1s_l3"]["epoch"]
        position = datas_dict["MAG_ss1s_l3"]["position"]

        @showprogress dt = 1 desc = "carcu_sta_vel" for (i, time_ind) in enumerate(time_i)

            timeB_ind = findfirst(x -> x >= sta_epoch[time_ind], timeb)
            vsc = (position[timeB_ind+1, :] .- position[timeB_ind-1, :]) ./ (datetime2unix(timeb[timeB_ind+1]) - datetime2unix(timeb[timeB_ind-1]))

            dat_slip = MAVEN_STATIC.static_slip(data_sta, time_ind)
            dat_slip = MAVEN_STATIC.static_rotation(dat_slip; frame="MSO")
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 10], mass_range=[20, 40], m_int=32)
            O2_vel_1[i, 1:3] = vel .+ vsc
            O2_vel_1[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 10], mass_range=[10, 20], m_int=16)
            O_vel_1[i, 1:3] = vel .+ vsc
            O_vel_1[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 10], mass_range=[0, 2], m_int=1)
            H_vel_1[i, 1:3] = vel .+ vsc
            H_vel_1[i, 4] = den

            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[10, 1e4], mass_range=[20, 40], m_int=32)
            O2_vel_2[i, 1:3] = vel .+ vsc
            O2_vel_2[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[10, 1e4], mass_range=[10, 20], m_int=16)
            O_vel_2[i, 1:3] = vel .+ vsc
            O_vel_2[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[10, 1e4], mass_range=[0, 2], m_int=1)
            H_vel_2[i, 1:3] = vel .+ vsc
            H_vel_2[i, 4] = den

            den = MAVEN_STATIC.sta_n_4d(dat_slip; energy_range=[0, 1e4], mass_range=[20, 40], m_int=32)
            O2_den[i] = den
            den = MAVEN_STATIC.sta_n_4d(dat_slip; energy_range=[0, 1e4], mass_range=[10, 20], m_int=16)
            O_den[i] = den
            den = MAVEN_STATIC.sta_n_4d(dat_slip; energy_range=[0, 1e4], mass_range=[0, 2], m_int=1)
            H_den[i] = den

        end
        datas_dict["ion_vel"] = Dict{String,Any}(
            "epoch" => time,
            "H_vel_1" => H_vel_1,
            "H_vel_2" => H_vel_2,
            "O_vel_1" => O_vel_1,
            "O_vel_2" => O_vel_2,
            "O2_vel_1" => O2_vel_1,
            "O2_vel_2" => O2_vel_2,
            "H_den" => H_den,
            "O_den" => O_den,
            "O2_den" => O2_den
        )
        return datas_dict
    end
    @inline function mag2sphere(datas_dict)
        position = datas_dict["MAG_ss1s_l3"]["position"]
        b = datas_dict["MAG_ss1s_l3"]["B"]
        data = MAVEN_load.Bpc2sphere.(position[:, 1], position[:, 2], position[:, 3], b[:, 1], b[:, 2], b[:, 3])
        br = [x[1] for x in data]
        bθ = [x[2] for x in data]
        bϕ = [x[3] for x in data]
        datas_dict["MAG_ss1s_l3"]["SphereB"] = (br, bθ, bϕ)
        return datas_dict
    end
    model_index = [
        "MAG_ss1s_l3",
        "LPW_wave",
        "KP_l3",
        "SWEA_spec",
        "STATIC_c6",
        "SWEA_pad_svy",
        "LPW_mrgscpot"
    ]
    datas_dict = MAVEN_load.data_get_from_date(date, model_index=model_index, show_filename=true)
    # 替换KP_l3数据中的数字标为元标签
    KP_data_name_replace = Dict(
        :Ne => "2",
        :Ne_quality_min => "3",
        :Ne_quality_max => "4",
        :GEO_x => "187",
        :GEO_y => "188",
        :GEO_z => "189",
        :MSO_x => "190",
        :MSO_y => "191",
        :MSO_z => "192",
        :Orbit_Number => "210",
        :Shape_parameter => "39",
        :H_flow_MSO_x => "43",
        :H_flow_MSO_y => "45",
        :H_flow_MSO_z => "47",
        :O_iondensity => "56",
        :O2_iondensity => "58",
        :O_ionTemperature => "62",
        :O2_ionTemperature => "64",
    )
    datas_dict["KP"] = Dict()
    datas_dict["KP"]["data_load_flag"] = datas_dict["KP_l3"]["data_load_flag"]
    for key in keys(KP_data_name_replace)
        datas_dict["KP"][key] = datas_dict["KP_l3"][KP_data_name_replace[key]]
    end
    sta_data = datas_dict["STATIC_c6"]
    if sta_data["data_load_flag"] == false
        sta_total = Dict("data_load_flag" => false)
        sta_mass = Dict("data_load_flag" => false)
        sta_O2 = Dict("data_load_flag" => false)
    else
        sta_data = MAVEN_STATIC.STA_count2df_all(sta_data)
        sta_total = MAVEN_STATIC.static_c6_mass_mean(sta_data)
        sta_mass = MAVEN_STATIC.static_c6_energy_mean(sta_data)
        sta_O2 = MAVEN_STATIC.static_c6_mass_mean(sta_data, mass_range=[20, 40])
    end
    datas_dict["STATIC_c6_orign"] = sta_data
    datas_dict["STATIC_c6"] = sta_total
    datas_dict["STATIC_mass"] = sta_mass
    datas_dict["STATIC_O2"] = sta_O2

    x1, y1, z1 = datas_dict["KP"][:GEO_x], datas_dict["KP"][:GEO_y], datas_dict["KP"][:GEO_z]
    alt = sqrt.(x1 .^ 2 .+ y1 .^ 2 .+ z1 .^ 2) .- 3393.5
    datas_dict["KP"][:alt] = alt
    swea_pad = datas_dict["SWEA_pad_svy"]
    if swea_pad["data_load_flag"] == false
        swea_pad_low = Dict("data_load_flag" => false)
        swea_pad_high = Dict("data_load_flag" => false)
    else
        swea_pad_low = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[20, 30])
        swea_pad_high = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[90, 120])
    end
    datas_dict["swea_pad_low"] = swea_pad_low
    datas_dict["swea_pad_high"] = swea_pad_high

    # datas_dict = mag2sphere(datas_dict)

    time_range = time_range
    # datas_dict = get_ion_vel(time_range, datas_dict) # 计算离子速度, 速度计算较慢,需要载入"STATIC_d1"

    return datas_dict
end

yyyy = 2015
mm = 10
dd = 29
save_file_name = "/example/MAVEN_plot_sample/MAVEN_data_" * Dates.format(DateTime(yyyy, mm, dd), "yyyymmdd") * "_MAVEN_data.jld2"
@time if isfile(save_file_name)
    datas_dict = load(save_file_name)["data"]
    println("Read Done")
else
    datas_dict = get_data(DateTime(yyyy, mm, dd); time_range=[DateTime(yyyy, mm, dd, 11, 20), DateTime(yyyy, mm, dd, 11, 45)])
    save(save_file_name, "data", datas_dict)
    println("Loading Done")
end

@inline function plot_module(fig, x_range, datas_dict, date_str; time_step=Dates.Minute(6), time_stemp=[DateTime(2015, 10, 29, 0, 0, 0)])

    x_range_unix = Dates.datetime2unix.((x_range[1], x_range[2]))
    xd = Dates.datetime2unix.(range(x_range[1], x_range[2], step=time_step))
    #KP的时间为基准时间TIME_KP
    KP_time0 = datas_dict["KP_l3"]["time"]
    KP_time, KP_time_i = MAVEN_plot.time2x(KP_time0, x_range)

    pannel_name = [
        # "orbit",
        # "E_field",
        # "NGIMS",
        "Ion_temp",
        "Ne",
        "MAGF",
        "STATIC_c6",
        "STATIC_mass",
        "STATIC_O2",
        "SWEA_spec",
        "swea_pad_high",
        "lpw_wave",
    ]
    pannels = Dict(name => index for (index, name) in enumerate(pannel_name))
    axs = Vector{Axis}(undef, length(pannel_name))
    color_ind = 3
    pannel_ind = 1:2

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
        half_circle = [Point2f(sin(theta[i]), cos(theta[i])) for i in eachindex(theta)]
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
    if "MAGF" in pannel_name
        np = pannels["MAGF"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, nothing), ylabel=L"\textbf{\text{B}} \; (\; \text{nT} \;)")
        # timeB, _, B0, _ = datas_dict["MAG_ss1s_l3"]["Vars"]
        timeB = datas_dict["MAG_ss1s_l3"]["epoch"]
        B0 = datas_dict["MAG_ss1s_l3"]["B"]
        timeB_unix, time_i = MAVEN_plot.time2x(timeB, x_range)
        if time_i != []
            shadow_Br = false
            if shadow_Br
                br, _, _ = datas_dict["MAG_ss1s_l3"]["SphereB"]
                br = br .> 0
                @inline function find_segments(x::Vector{T}, y::BitVector) where {T}
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
                    return segments1, segments2
                end
                s1, s2 = find_segments(timeB_unix, br[time_i])
                vspan!(axs[np], s1, s2, label="Br>0", alpha=0.2, color=:gray)
                band!(axs[np], timeB_unix, br[time_i], br[time_i] .* 0, label="Br>0", linewidth=2, alpha=0.2, color=:gray, overdraw=true)
            end
            color = Makie.wong_colors()[1:3]
            for (index, name) in enumerate(["Bx", "By", "Bz"])
                lines!(axs[np], timeB_unix, B0[time_i, index], label=name, linewidth=2, color=color[index])
            end
            fig[np, color_ind] = Legend(fig, axs[np])
        end
    end
    # KP part
    if "Ne" in pannel_name
        np = pannels["Ne"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, nothing), ylabel=L"N_{e} (cm^{-3})", yscale=log10)
        y = datas_dict["KP"][:Ne][KP_time_i]
        y1 = datas_dict["KP"][:Ne_quality_max][KP_time_i]
        y2 = datas_dict["KP"][:Ne_quality_min][KP_time_i]
        rangebars!(axs[np], KP_time, abs.(y1), abs.(y2))
        scatter!(axs[np], KP_time, y, markersize=5, color=:red)
    end
    if "Ion_temp" in pannel_name
        np = pannels["Ion_temp"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (0, 0.25)), ylabel="K [eV]")
        y = datas_dict["KP"][:O_ionTemperature][KP_time_i]
        y1 = datas_dict["KP"][:O2_ionTemperature][KP_time_i]
        lines!(axs[np], KP_time, y, linewidth=2, label="O+")
        lines!(axs[np], KP_time, y1, linewidth=2, label="O2+")
        fig[np, color_ind] = Legend(fig, axs[np])
    end
    if "E_field" in pannel_name
        np = pannels["E_field"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, nothing), ylabel="mV/m")
        x = datas_dict["E_field"]["time"]
        y = datas_dict["E_field"]["data"]
        lines!(axs[np], x, y)
    end
    c_range_1 = (1e4, 1e9)
    c_range_2 = (1e4, 1e9)
    if "STATIC_c6" in pannel_name
        np = pannels["STATIC_c6"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (1, 1e4)), yscale=log10)
        if datas_dict["STATIC_c6"]["data_load_flag"]
            x0, y, c, swp = datas_dict["STATIC_c6"]["epoch"], datas_dict["STATIC_c6"]["energy"], datas_dict["STATIC_c6"]["eflux"], datas_dict["STATIC_c6"]["swp_ind"]
            # ind_tag = findfirst(x-> x>=DateTime(2015, 10, 29,11,33,12) ,times_ion)
            # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
            x, time_i = MAVEN_plot.time2x(x0, x_range)
            if time_i != []
                MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_1)
            end
        end
        Colorbar(fig[np, color_ind], limits=c_range_1, label="ion eflux", colormap=:viridis, scale=log10)
    end
    if "STATIC_mass" in pannel_name
        np = pannels["STATIC_mass"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (0.5, 64)), yscale=log10)
        if datas_dict["STATIC_c6"]["data_load_flag"]
            x0, y, c, swp = datas_dict["STATIC_mass"]["epoch"], datas_dict["STATIC_mass"]["mass"], datas_dict["STATIC_mass"]["eflux"], datas_dict["STATIC_mass"]["swp_ind"]
            # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
            x, time_i = MAVEN_plot.time2x(x0, x_range)
            if time_i != []
                MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_1, ylabel="mass AMU")
            end
            hlines!(axs[np], [1, 16, 32.0], color=:white)
        end
        Colorbar(fig[np, color_ind], limits=c_range_1, label="ion eflux", colormap=:viridis, scale=log10)
    end
    if "STATIC_O2" in pannel_name
        np = pannels["STATIC_O2"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (1, 1e4)), yscale=log10)
        if datas_dict["STATIC_c6"]["data_load_flag"]
            x0, y, c, swp = datas_dict["STATIC_O2"]["epoch"], datas_dict["STATIC_O2"]["energy"], datas_dict["STATIC_O2"]["eflux"], datas_dict["STATIC_O2"]["swp_ind"]
            x, time_i = MAVEN_plot.time2x(x0, x_range)
            if time_i != []
                MAVEN_plot.sta_heatmap(axs[np], x, y, c[time_i, :], swp[time_i]; c_range=c_range_2, ylabel="energy")
            end
        end
        Colorbar(fig[np, color_ind], limits=c_range_2, label="O2+ eflux", colormap=:viridis, scale=log10)
    end

    # sc potential
    # if datas_dict["LPW_mrgscpot"]["data_load_flag"] && "STATIC_c6" in pannel_name
    #     np = pannels["STATIC_c6"]
    #     time_scp, data_scp = datas_dict["LPW_mrgscpot"]["epoch"], datas_dict["LPW_mrgscpot"]["data"]
    #     x, time_i = MAVEN_plot.time2x(time_scp, x_range)
    #     ax_scp1 = Axis(fig[np, pannel_ind], yticklabelcolor=:orange, yaxisposition=:right, limits=(x_range_unix, (-10, 10)), ylabel="potential")
    #     hidespines!(ax_scp1)
    #     hidexdecorations!(ax_scp1)
    #     y = replace(data_scp[time_i], NaN => 0)
    #     stem!(ax_scp1, x, y, offset=0, trunkcolor=:white, marker=:circle, stemcolor=:white, color=:orange,
    #         markersize=5, trunklinestyle=:dot)
    # end
    #electorn spactra            
    if "SWEA_spec" in pannel_name
        np = pannels["SWEA_spec"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (3, 1000)), ylabel="energy", yscale=log10)
        if datas_dict["SWEA_spec"]["data_load_flag"]
            times_electorn, energy_e, flux_e = datas_dict["SWEA_spec"]["epoch"], datas_dict["SWEA_spec"]["energy"], datas_dict["SWEA_spec"]["diff_en_fluxes"]
            x, time_i = MAVEN_plot.time2x(times_electorn, x_range)
            if time_i != []
                hm_e_sp = heatmap!(axs[np], x, energy_e, flux_e[time_i, :], colorscale=log10, colorrange=(1e5, 1e8), colormap=:viridis)
            end
        end
        Colorbar(fig[np, color_ind], limits=(1e5, 1e8), label="electorn eflux", colormap=:viridis, scale=log10)
    end
    # swea pad
    if "swea_pad_low" in pannel_name
        np = pannels["swea_pad_low"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (0, 180)))
        if datas_dict["swea_pad_low"]["data_load_flag"]
            x, y, c = datas_dict["swea_pad_low"]["epoch"], datas_dict["swea_pad_low"]["pa"], datas_dict["swea_pad_low"]["diff_en_fluxes"]
            x, time_i = MAVEN_plot.time2x(x, x_range)
            if time_i != []
                MAVEN_plot.SWEA_PAD_heatmap(axs[np], x, y[time_i, :], c[time_i, :]; c_range=c_range_1, ylabel="Pitch angle \n [deg]")
            end
        end
        Colorbar(fig[np, color_ind], limits=c_range_1, label="SWEA \n 20-30eV", colormap=:viridis, scale=log10)
    end
    if "swea_pad_high" in pannel_name
        np = pannels["swea_pad_high"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (0, 180)))
        if datas_dict["swea_pad_high"]["data_load_flag"]
            x, y, c = datas_dict["swea_pad_high"]["epoch"], datas_dict["swea_pad_high"]["pa"], datas_dict["swea_pad_high"]["diff_en_fluxes"]
            x, time_i = MAVEN_plot.time2x(x, x_range)
            if time_i != []
                MAVEN_plot.SWEA_PAD_heatmap(axs[np], x, y[time_i, :], c[time_i, :]; c_range=c_range_2, ylabel="Pitch angle \n [deg]")
            end
        end
        Colorbar(fig[np, color_ind], limits=c_range_2, label="SWEA \n 90-120eV", colormap=:viridis, scale=log10)
    end
    # Wave Spectra
    if "lpw_wave" in pannel_name
        np = pannels["lpw_wave"]
        axs[np] = Axis(fig[np, pannel_ind], limits=(x_range_unix, (1e0, 1e4)), yscale=log10)
        if datas_dict["LPW_wave"]["data_load_flag"]
            timeSP, freq, wave_data = datas_dict["LPW_wave"]["epoch"], datas_dict["LPW_wave"]["freq"], datas_dict["LPW_wave"]["data"]
            c_range = (1e-14, 1e-9)
            x, time_i = MAVEN_plot.time2x(timeSP, x_range)
            if time_i != []
                MAVEN_plot.WaveSpactra_heatmap(axs[np], x, freq[time_i, :], wave_data[time_i, :])
                if datas_dict["MAG_ss1s_l3"]["data_load_flag"]
                    timeB = datas_dict["MAG_ss1s_l3"]["epoch"]
                    B_total = datas_dict["MAG_ss1s_l3"]["B_total"]
                    fce = B_total .* 27.99
                    timeB_unix = datetime2unix.(timeB)
                    lines!(axs[np], timeB_unix, fce, label="fce", linewidth=2, linestyle=:dash, color=:white)
                end

            end
        end
        Colorbar(fig[np, color_ind], limits=c_range, label=L"P_{E}", colormap=:viridis, scale=log10)
    end

    np = length(pannel_name)
    axs_xtick = Axis(fig[np, pannel_ind], limits=(x_range_unix, nothing))
    #####!!!!!!!!!!!!待办, 试试看只用一个坐标轴, 将label设置成"time \n , x \n y \n z \n Alt \n"格式
    #设置下标刻度
    # alt = datas_dict["KP"][:alt][KP_time_i]
    xtimes,x_i = MAVEN_plot.time_ticks(x_range;step=step=time_step)
    axs_xtick.xticks = xtimes
    # axs_xtick[2] = x_ticks(axs_xtick[2], x, alt, x_i; xticklabelpad=20, range=x_range_unix)
    # axs_xtick[2].xlabel = "Alt[Km]"
    # axs_xtick[2].backgroundcolor = :gray
    # linkxaxes!(axs..., axs_xtick)
    for ax in axs
        hidexdecorations!(ax, grid=false)
    end
    # 时间戳
    for ax in axs
        as = datetime2unix.(time_stemp)
        vlines!(ax, as, linestyle=:dash, color=:black)
    end
    return fig, (xtimes, x_range, x_range_unix)
end;

fig = Figure(; size=(1080, 1920))
x_range = [DateTime(2015, 10, 29, 11, 0, 0), DateTime(2015, 10, 29, 11, 50, 0)]
date_str = " "
@time fig, xx = plot_module(fig, x_range, datas_dict, date_str; time_step=Dates.Minute(6), time_stemp=[DateTime(2015, 10, 29, 11, 20, 0)])
save("example/MAVEN_plot_sample/MAVEN_plot_" * Dates.format(DateTime(yyyy, mm, dd), "yyyymmdd") * ".png", fig)
