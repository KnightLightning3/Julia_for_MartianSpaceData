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

function x_ticks(ax,x,var,x_i;xticklabelpad=3,model="null",range=x_range_julian)

    # ax = Axis(fig[np,1],limits = (range, nothing) ,xlabel=xlabel

    #     ,xlabelpadding=3,xticklabelpad=xticklabelpad)

    # hidespines!(ax); hideydecorations!(ax) 
    ax.limits= (range, nothing)  
    ax.xticklabelpad=xticklabelpad 
    hidespines!(ax) 
    hideydecorations!(ax) 
    if model == "time" 
        ax.xticks = var 
        return ax 
    end
    y_i=[var[argmin(abs.(x .- xi))[1]] for xi in x_i]; 

    y_i=convert(Vector{Int64}, round.(y_i)) 
    y_i= string.(y_i) 
    ax.xticks = (x_i,y_i) 
    return ax 
end
function Orbit(ax,x,y; times = ([],[]),no_lines=false)
    function bowshock(xshock)
        xF = 0.6 # Rm
        ϵ = 1.026
        L = 2.081 # rm
        # rSD = 1.63
        temp = (ϵ^2-1.0)*(xshock-xF)^2-2ϵ*L*(xshock-xF)+L^2
        if temp>=0 
            return sqrt(temp)
        else
            return Inf64
        end
    end
    function magnetopause(xmp)
        rSD = 1.25
        if xmp>0  
            xF = 0.64
            ϵ = 0.77
            L = 1.08
        else
            xF = 1.60
            ϵ = 1.009
            L = 0.528
        end
        temp = (ϵ^2-1.0)*(xmp-xF)^2-2ϵ*L*(xmp-xF)+L^2
        if temp>=0 
            return sqrt(temp)
        else
            return Inf64
        end
    end
    ax.xreversed=true

    theta = LinRange(pi, 2pi, 100)
    half_circle = [Point2f(sin(theta[i]), cos(theta[i])) for i in 1:length(theta)]
    poly!(ax,Circle(Point2f(0, 0), 1),color=:white,strokewidth = 2,strokecolor =:black)
    poly!(ax, half_circle, color=:black)
    
    lines!(ax,x,y,overdraw=true)

    if times != ([],[])
        times_t = times[2]
        time_index = times[1]
        colormap = :viridis
        n_colors = length(time_index)
        colors = resample_cmap(colormap, n_colors)
        for (it,i) in enumerate(time_index)
            poly!(ax,Circle(Point2f(x[i], y[i]), 0.15),color=colors[it],label = times_t[it])
        end
    end
    if no_lines
        return ax
    end
    x = -10:0.01:2
    y = bowshock.(x)
    x= [x;x];y=[-y;y]
    lines!(ax,x,y;linestyle=:dash)#label="bowshock"
    x = -10:0.01:2
    y = magnetopause.(x)
    x= [x;x];y=[-y;y]
    lines!(ax,x,y; linestyle=:dash)#label="magnetopause",
    return ax
end
function plot_module(fig,x_range,datas_dict,date_str; time_step=Dates.Minute(6),time_stemp = [DateTime(2015,10,29,0,0,0)])    
    
    # rowsize!(fig.layout, 1, Auto(0.9))
    # colsize!(fig.layout, 4, Relative(1/6))

    x_range_julian = Dates.datetime2julian.(x_range)
    xd = Dates.datetime2julian.(range(x_range[1], x_range[2], step=time_step))
    time_julian0   = x_range_julian[1]
    x_range_julian = x_range_julian .- time_julian0
       
    pannel_name = [
        # "orbit",
        # "E_field",
        "NGIMS",
        "Ion_temp",
        "Ne",
        "B_xyz",
        # "H+ velocity",
        "STATIC_c6","STATIC_mass",
        "STATIC_H",
        # "H_vel",#"H_vel_angle",
        "STATIC_O",
        # "O_vel",
        "STATIC_O2",
        "O2_vel_1","O2_vel_2",#"O2_vel_angle",
        "SWEA_spec",
        "swea_pad_low",
        "swea_pad_high",
        # "lpw_wave",
    ]
    pannels = Dict(name => index for (index, name) in enumerate(pannel_name))
    axs = Vector{Axis}(undef, length(pannel_name))
    color_ind  = 3
    pannel_ind = 1:2

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
    # np = pannels["E_field"];        axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,nothing),ylabel="mV/m")
    np = pannels["NGIMS"];        axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(1,1e4)),ylabel="cm^-3",yscale=log10)
    np = pannels["Ion_temp"];        axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(0,0.25)),ylabel="K [eV]")
    np = pannels["B_xyz"];        axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,nothing),ylabel=L"\textbf{\text{B}} \; (\; \text{nT} \;)")
    np = pannels["Ne"];           axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,nothing),ylabel=L"N_{e} (cm^{-3})",yscale=log10)
    # np = pannels["H+ velocity"];  axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,nothing),ylabel=L"\textbf{\text{H}}^{+} (km/s)")
    np = pannels["STATIC_c6"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(1,1e4)),yscale = log10)
    np = pannels["STATIC_mass"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(0.5,64)),yscale = log10)
    np = pannels["STATIC_O"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(1,1e4)),yscale = log10)
    np = pannels["STATIC_O2"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(1,1e4)),yscale = log10)
    np = pannels["STATIC_H"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(1,1e4)),yscale = log10)

    # np = pannels["H_vel"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(-20,50)),ylabel="H+ vel [km/s]")
    # np = pannels["H_vel_angle"]; axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(0,180)),ylabel="H+ pitch angle [deg]")
    # np = pannels["O_vel"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(-10,10)),ylabel="O+ vel [km/s]")
    np = pannels["O2_vel_1"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(-10,10)),ylabel="O2+ vel [km/s]")
    np = pannels["O2_vel_2"];       axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(-10,10)),ylabel="O2+ vel [km/s]")
    # np = pannels["O2_vel_angle"]; axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(0,180)),ylabel="O2+ pitch angle [deg]")
    np = pannels["SWEA_spec"];    axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(3,1000)),ylabel="energy",yscale=log10)
    np = pannels["swea_pad_low"]; axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(0,180)))
    np = pannels["swea_pad_high"];axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian,(0,180)))
    # np = pannels["lpw_wave"];     axs[np] = Axis(fig[np,pannel_ind],limits=(x_range_julian, (1e0,1e4)),yscale=log10)

    # if datas_dict["LPW_we12"]["data_load_flag"]
    #     timeE,dataE = datas_dict["LPW_we12"]["epoch"],datas_dict["LPW_we12"]["data"]
    #     timeE_julian,time_i = MAVEN_plot.time2x(timeE,time_julian0,x_range)
    #     if time_i != []            
    #         np = pannels["E_field"]
    #         lines!(axs[np],timeE_julian,dataE[time_i],linewidth=2)
    #     end
    # end

    # lines = readlines("test_vel_20151029_d1.tab")
    # narray = length(lines)
    # time_idl = []
    # vel_idl = zeros(narray,7)
    # vel_sc_idl = zeros(narray,6)
    # vels_mso = zeros(narray,3)
    # for (i,line) in enumerate(lines)
    #     vars = parse.(Float64,split(line))
    #     push!(time_idl,unix2datetime(vars[1]))
    #     vels = vars[2:end]
    #     vel_idl[i,7]   = vels[1]
    #     vel_idl[i,1:3] = vels[12:14]
    #     vel_idl[i,4:6] = vels[9:11]
    #     vel_sc_idl[i,1:3] = vels[15:17]
    #     vel_sc_idl[i,1:3] = vels[18:20]
    # end
    # np = pannels["E_field"]
    # time_idl_julian,time_i = MAVEN_plot.time2x(time_idl,time_julian0,x_range)
    # lines!(axs[np],time_idl_julian,vel_idl[time_i,7],label="IDL_sc")
    
    # if datas_dict["NGIMS_den_l4"]["data_load_flag"]
        # for sp_str in ["O","CO","CO2"]
        #     time,data = datas_dict["NGIMS_den_l4"][sp_str]["epoch"],datas_dict["NGIMS_den_l4"][sp_str]["density_bins"]
        #     time_julian,time_i = MAVEN_plot.time2x(time,time_julian0,x_range)
        #     if time_i != []            
        #         np = pannels["NGIMS"]
        #         lines!(axs[np],time_julian,10.0.^data[time_i],linewidth=2,label = sp_str)
        #     end
        # end
    # end

    # orbit
    timeB_julian = [-1,-2]
    fce = [1,1]
    if datas_dict["MAG_ss1s_l3"]["data_load_flag"]
        timeB_ss,B_total_ss,B_ss,position_ss = datas_dict["MAG_ss1s_l3"]["Vars"]
        timeB_julian,time_i = MAVEN_plot.time2x(timeB_ss,time_julian0,x_range)
        fce = B_total_ss[time_i] .* 27.99
        if time_i != []
            # np = pannels["orbit"];
            # x_i=xd.-time_julian0
            # y_i=[argmin(abs.(timeB_julian .- xi))[1] for xi in x_i];
            # xtimes = (y_i, Dates.format.(julian2datetime.(xd), "HH:MM"))
            
            # p_mso = position_ss[time_i,:]./3393.5
            
            # axs_orbit_1.ylabel = L"(Y_{mso}^2+Z_{mso}^2)^(1/2)" ; axs_orbit_1.xlabel = L"X_{mso}"
            # axs_orbit_1 = Orbit(axs_orbit_1,p_mso[:,1],sqrt.(p_mso[:,2].^2 .+ p_mso[:,3].^2),times = xtimes)

            # axs_orbit_2.ylabel = L"Y_{mso}" ; axs_orbit_2.xlabel = L"X_{mso}"
            # axs_orbit_2 = Orbit(axs_orbit_2,p_mso[:,1],p_mso[:,2],times = xtimes,no_lines=true)

            # axs_orbit_3.ylabel = L"Z_{mso}" ; axs_orbit_3.xlabel = L"X_{mso}"
            # axs_orbit_3 = Orbit(axs_orbit_3,p_mso[:,1],p_mso[:,3],times = xtimes,no_lines=true)

            # Legend_local = Legend(fig, axs_orbit_1);
            # Legend_local.nbanks = 2
            # fig[pannels["lpw_wave"]-3, 1] = Legend_local
            # Label(fig[np, color_ind],"Orbit:\n"*orbit_str)
            
            np = pannels["B_xyz"];
            br,_,_ = datas_dict["MAG_ss1s_l3"]["SphereB"]
            brmax = maximum(br)
            br = br .> 0
            function find_segments(x::Vector{T}, y::BitVector) where T
                segments1 = []
                segments2 = []
                start_idx = nothing
                for i in 1:length(y)
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
            # band!(axs[np],timeB_julian,br[time_i],br[time_i].*0,label="Br>0",linewidth=2,alpha=0.2,color = :gray,overdraw=true)
            color=[:blue,:red,:green]
            for (index, name) in enumerate(["Bx","By","Bz"])
                lines!(axs[np],timeB_julian,B_ss[time_i,index],label=name,linewidth=2,color = color[index])
            end
            fig[np, color_ind] = Legend(fig, axs[np]);
        end
    end
    
    # KP part
        np = pannels["Ne"];
        timeKP =datas_dict["KP"]["time"]
        y =datas_dict["KP"]["electorn density"]
        y1=datas_dict["KP"]["Ne quality max"]
        y2=datas_dict["KP"]["Ne quality min"]

        # ind_NaN = findall(i -> isnan(i),y)
        # # var = convert(Vector{Union{Missing, Float64}},value)
        # y[ind_NaN]  .= 1e-10
        # y1[ind_NaN] .= 1e-10
        # y2[ind_NaN] .= 1e-10
        
        x,time_i=MAVEN_plot.time2x(timeKP,time_julian0,x_range)
        rangebars!(axs[np],x, abs.(y1[time_i]), abs.(y2[time_i]))
        scatter!(axs[np], x, y[time_i] ,markersize=5,color=:red);

        np = pannels["Ion_temp"]
        y =datas_dict["KP"]["O+ Temperature"]
        y1 =datas_dict["KP"]["O2+ Temperature"]
        # y[ y.<= 0] .= 1e-10
        # y1[ y1.<= 0] .= 1e-10
        lines!(axs[np],x,y[time_i],linewidth=2,label = "O+")
        lines!(axs[np],x,y1[time_i],linewidth=2,label = "O2+")
        fig[np, color_ind] = Legend(fig, axs[np]);

        np = pannels["NGIMS"]
        y =datas_dict["KP"]["O+ density"]
        y1 =datas_dict["KP"]["O2+ density"]
        y[ y.<= 0] .= 1e-10
        y1[ y1.<= 0] .= 1e-10
        lines!(axs[np],x,y[time_i],linewidth=2,label = "O+")
        lines!(axs[np],x,y1[time_i],linewidth=2,label = "O2+")
        
        lines!(axs[np],x,datas_dict["KP"]["16 density"][time_i],linewidth=2,label = "16+")
        lines!(axs[np],x,datas_dict["KP"]["32 density"][time_i],linewidth=2,label = "32+")
        lines!(axs[np],x,datas_dict["KP"]["44 density"][time_i],linewidth=2,label = "44+")
        fig[np, color_ind] = Legend(fig, axs[np]);
    
# H_v
    # np = pannels["H+ velocity"];
    # # datas_dict["KP"]["H_flow_MSO_x"]
    # # datas_dict["KP"]["H_flow_MSO_y"]
    # # datas_dict["KP"]["H_flow_MSO_z"]
    # # color=[63,127,255]
    # y = sqrt.(datas_dict["KP"]["H_flow_MSO_x"][time_i].^2 + datas_dict["KP"]["H_flow_MSO_y"][time_i].^2 + datas_dict["KP"]["H_flow_MSO_z"][time_i].^2)
    # lines!(axs[np],x,y,linewidth=2)
    # # y = sqrt.(datas_dict["KP"]["O2_flow_MSO_x"][time_i].^2 + datas_dict["KP"]["O2_flow_MSO_y"][time_i].^2 + datas_dict["KP"]["O2_flow_MSO_z"][time_i].^2)
    # # lines!(axs[np],x,y,linewidth=2)
#ions

    c_range_1= (1e4,1e10)
    c_range_2= (1e4,1e10)
    if datas_dict["STATIC_c6"]["data_load_flag"]
        np = pannels["STATIC_c6"];
        x0,y,c, swp = datas_dict["STATIC_c6"]["epoch"],datas_dict["STATIC_c6"]["energy"],datas_dict["STATIC_c6"]["eflux"],datas_dict["STATIC_c6"]["swp_ind"]  
        # ind_tag = findfirst(x-> x>=DateTime(2015, 10, 29,11,33,12) ,times_ion)
        # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
        x,time_i=MAVEN_plot.time2x(x0,time_julian0,x_range)
        if time_i == []
            println("no_sta")
        else
            MAVEN_plot.sta_heatmap(axs[np],x,y,c[time_i,:], swp[time_i];c_range=c_range_1)
            Colorbar(fig[np,color_ind],limits = c_range_1,label="ion eflux",colormap=:viridis,scale=log10)
            
            np = pannels["STATIC_mass"];
            x0,y,c, swp = datas_dict["STATIC_mass"]["epoch"],datas_dict["STATIC_mass"]["mass"],datas_dict["STATIC_mass"]["eflux"],datas_dict["STATIC_mass"]["swp_ind"]  
            # flux_ion[ind_tag,:] = flux_ion[ind_tag,:]./100
            x,time_i=MAVEN_plot.time2x(x0,time_julian0,x_range)
            MAVEN_plot.sta_heatmap(axs[np],x,y,c[time_i,:], swp[time_i];c_range=c_range_2,ylabel="mass AMU")
            lines!(axs[np],[x[1],x[end]],[64.0,64.0],color=:black)
            lines!(axs[np],[x[1],x[end]],[16.0,16.0],color=:black)
            lines!(axs[np],[x[1],x[end]],[32.0,32.0],color=:black)
            Colorbar(fig[np,color_ind],limits = c_range_2,label="ion eflux",colormap=:viridis,scale=log10)

            np = pannels["STATIC_H"];
            x0,y,c, swp = datas_dict["STATIC_H"]["epoch"],datas_dict["STATIC_H"]["energy"],datas_dict["STATIC_H"]["eflux"],datas_dict["STATIC_H"]["swp_ind"]  
            x,time_i=MAVEN_plot.time2x(x0,time_julian0,x_range)
            MAVEN_plot.sta_heatmap(axs[np],x,y,c[time_i,:], swp[time_i];c_range=c_range_2,ylabel="energy")
            Colorbar(fig[np,color_ind],limits = c_range_2,label="H+ eflux",colormap=:viridis,scale=log10)
            
            np = pannels["STATIC_O"];
            x0,y,c, swp = datas_dict["STATIC_O"]["epoch"],datas_dict["STATIC_O"]["energy"],datas_dict["STATIC_O"]["eflux"],datas_dict["STATIC_O"]["swp_ind"]  
            x,time_i=MAVEN_plot.time2x(x0,time_julian0,x_range)
            MAVEN_plot.sta_heatmap(axs[np],x,y,c[time_i,:], swp[time_i];c_range=c_range_2,ylabel="energy")
            Colorbar(fig[np,color_ind],limits = c_range_2,label="O+ eflux",colormap=:viridis,scale=log10)
            
            np = pannels["STATIC_O2"];
            x0,y,c, swp = datas_dict["STATIC_O2"]["epoch"],datas_dict["STATIC_O2"]["energy"],datas_dict["STATIC_O2"]["eflux"],datas_dict["STATIC_O2"]["swp_ind"]  
            x,time_i=MAVEN_plot.time2x(x0,time_julian0,x_range)
            MAVEN_plot.sta_heatmap(axs[np],x,y,c[time_i,:], swp[time_i];c_range=c_range_2,ylabel="energy")
            lines!(axs[np],[x[1],x[end]],[200.0,200.0],color=:white)
            lines!(axs[np],[x[1],x[end]],[150.0,150.0],color=:white)
            lines!(axs[np],[x[1],x[end]],[100.0,100.0],color=:white)
            lines!(axs[np],[x[1],x[end]],[80.0,80.0],  color=:white)
            lines!(axs[np],[x[1],x[end]],[50.0,50.0],  color=:white)

            lines!(axs[np],[x[1],x[end]],[30.0,30.0],  color=:white)
            Colorbar(fig[np,color_ind],limits = c_range_2,label="O2+ eflux",colormap=:viridis,scale=log10)
        end

        # ion vels
        x,time_i = MAVEN_plot.time2x(datas_dict["ion_vel"]["epoch"],time_julian0,x_range)
        timeB_ss,_,B_ss,_ = datas_dict["MAG_ss1s_l3"]["Vars"]
        B_sta = zeros(length(time_i),3)
        for ii in time_i
            timeb_ind = findfirst(x-> x  >= datas_dict["ion_vel"]["epoch"][ii],timeB_ss)
            B_sta[ii,:] = B_ss[timeb_ind,:]
        end
        low_energy_range = true
        # np = pannels["H_vel"]
        #     axs[np].limits = (nothing,nothing)
        #     if low_energy_range
        #         lines!(axs[np],x,datas_dict["ion_vel"]["H_vel_1"][time_i,1],label = "<10eV-x",color = :red  )
        #         lines!(axs[np],x,datas_dict["ion_vel"]["H_vel_1"][time_i,2],label = "<10eV-y",color = :blue )
        #         lines!(axs[np],x,datas_dict["ion_vel"]["H_vel_1"][time_i,3],label = "<10eV-z",color = :green)
        #         lines!(axs[np],x,sqrt.(sum(datas_dict["ion_vel"]["H_vel_1"][time_i,1:3].^2,dims=2))[:,1] ,label = "v0",color = :black)
        #     else
        #         lines!(axs[np],x,datas_dict["ion_vel"]["H_vel_2"][time_i,1],label = ">10eV-x",color = :red  , linestyle = :dash)
        #         lines!(axs[np],x,datas_dict["ion_vel"]["H_vel_2"][time_i,2],label = ">10eV-y",color = :blue , linestyle = :dash)
        #         lines!(axs[np],x,datas_dict["ion_vel"]["H_vel_2"][time_i,3],label = ">10eV-z",color = :green, linestyle = :dash)
        #         lines!(axs[np],x,sqrt.(sum(datas_dict["ion_vel"]["H_vel_2"][time_i,1:3].^2,dims=2))[:,1] ,label = "v0",color = :black)
        #     end
        #     fig[np, color_ind] = Legend(fig, axs[np]);
        #     # np = pannels["H_vel_angle"]
        #     # ys = datas_dict["ion_vel"]["H_vel_2"][time_i,1:3]
        #     # y = [acosd(dot(ys[i,:],B_sta[i,:])/(norm(ys[i,:])*norm(B_sta[i,:]))) for i in 1:length(ys[:,1])]
        #     # band!(axs[np],x,y,zeros(length(y)).+90)
        # np = pannels["O_vel"]
        #     axs[np].limits = (nothing,nothing)
        #     if low_energy_range
        #         lines!(axs[np],x,datas_dict["ion_vel"]["O_vel_1"][time_i,1],label = "<10eV-x",color = :red  )
        #         lines!(axs[np],x,datas_dict["ion_vel"]["O_vel_1"][time_i,2],label = "<10eV-y",color = :blue )
        #         lines!(axs[np],x,datas_dict["ion_vel"]["O_vel_1"][time_i,3],label = "<10eV-z",color = :green)
        #         lines!(axs[np],x,sqrt.(sum(datas_dict["ion_vel"]["O_vel_1"][time_i,1:3].^2,dims=2))[:,1] ,label = "v0",color = :black)
        #     else
        #         lines!(axs[np],x,datas_dict["ion_vel"]["O_vel_2"][time_i,1],label = ">10eV-x",color = :red  , linestyle = :dash)
        #         lines!(axs[np],x,datas_dict["ion_vel"]["O_vel_2"][time_i,2],label = ">10eV-y",color = :blue , linestyle = :dash)
        #         lines!(axs[np],x,datas_dict["ion_vel"]["O_vel_2"][time_i,3],label = ">10eV-z",color = :green, linestyle = :dash)
        #         lines!(axs[np],x,sqrt.(sum(datas_dict["ion_vel"]["O_vel_2"][time_i,1:3].^2,dims=2))[:,1] ,label = "v0",color = :black)
        #     end
        #     fig[np, color_ind] = Legend(fig, axs[np]);
        np1 = pannels["O2_vel_1"]
        np2 = pannels["O2_vel_2"]
            axs[np1].limits = (nothing,nothing)
            axs[np2].limits = (nothing,nothing)
            lines!(axs[np1],x,datas_dict["ion_vel"]["O2_vel_1"][time_i,1],label = "<10eV-x",color = :red  )
            lines!(axs[np1],x,datas_dict["ion_vel"]["O2_vel_1"][time_i,2],label = "<10eV-y",color = :blue )
            lines!(axs[np1],x,datas_dict["ion_vel"]["O2_vel_1"][time_i,3],label = "<10eV-z",color = :green)
            lines!(axs[np1],x,sqrt.(sum(datas_dict["ion_vel"]["O2_vel_1"][time_i,1:3].^2,dims=2))[:,1] ,label = "v0",color = :black)

            lines!(axs[np2],x,datas_dict["ion_vel"]["O2_vel_2"][time_i,1],label = ">10eV-x",color = :red  , linestyle = :dash)
            lines!(axs[np2],x,datas_dict["ion_vel"]["O2_vel_2"][time_i,2],label = ">10eV-y",color = :blue , linestyle = :dash)
            lines!(axs[np2],x,datas_dict["ion_vel"]["O2_vel_2"][time_i,3],label = ">10eV-z",color = :green, linestyle = :dash)
            lines!(axs[np2],x,sqrt.(sum(datas_dict["ion_vel"]["O2_vel_2"][time_i,1:3].^2,dims=2))[:,1] ,label = "v0",color = :black)

            fig[np1, color_ind] = Legend(fig, axs[np1]);
            fig[np2, color_ind] = Legend(fig, axs[np2]);
            # np = pannels["O2_vel_angle"]
            # ys = datas_dict["ion_vel"]["O2_vel_2"][time_i,1:3]
            # y = [acosd(dot(ys[i,:],B_sta[i,:])/(norm(ys[i,:])*norm(B_sta[i,:]))) for i in 1:length(ys[:,1])]
            # band!(axs[np],x,y,zeros(length(y)).+90)
    end
    # sc potential
    np = pannels["STATIC_c6"]
        time_scp,data_scp = datas_dict["LPW_mrgscpot"]["epoch"],datas_dict["LPW_mrgscpot"]["data"]
        x,time_i = MAVEN_plot.time2x(time_scp,time_julian0,x_range)
        ax_scp1 = Axis(fig[np, pannel_ind], yticklabelcolor = :orange, yaxisposition = :right,limits = (x_range_julian, (-10,10)),ylabel="potential");hidespines!(ax_scp1);hidexdecorations!(ax_scp1)
        y = replace(data_scp[time_i], NaN => 0)
        stem!(ax_scp1,x, y,offset = 0, trunkcolor = :white, marker = :circle,stemcolor = :white, color = :orange,
        markersize = 5, trunklinestyle = :dot)
    
    #electorn spactra            
    if datas_dict["SWEA_spec"]["data_load_flag"]
        np = pannels["SWEA_spec"];
        times_electorn, energy_e, flux_e = datas_dict["SWEA_spec"]["epoch"],datas_dict["SWEA_spec"]["energy"],datas_dict["SWEA_spec"]["diff_en_fluxes"]
        x,time_i=MAVEN_plot.time2x(times_electorn,time_julian0,x_range)
        if time_i != []
            hm_e_sp = heatmap!(axs[np],x,energy_e,flux_e[time_i,:],colorscale=log10,colorrange=(1e4,1e10),colormap=:viridis)
            Colorbar(fig[np,color_ind],hm_e_sp,label="electorn eflux")#
        end
    end
    # swea pad
    if datas_dict["SWEA_pad_svy"]["data_load_flag"]
        colorrange_1=(1e7,1e9);
        colorrange_2=(1e4,1e9);
        np = pannels["swea_pad_low"];
        x,y,c   = datas_dict["swea_pad_low"]["epoch"],datas_dict["swea_pad_low"]["pa"],datas_dict["swea_pad_low"]["diff_en_fluxes"]
        
        x,time_i=MAVEN_plot.time2x(x,time_julian0,x_range)
        if time_i != []
            MAVEN_plot.SWEA_PAD_heatmap(axs[np],x,y[time_i,:],c[time_i,:];c_range=colorrange_1,ylabel="Pitch angle \n [deg]")
            Colorbar(fig[np,color_ind],limits = colorrange_1,label="SWEA \n 20-30eV",colormap=:viridis,scale=log10)
            np = pannels["swea_pad_high"];
            x,y,c = datas_dict["swea_pad_high"]["epoch"],datas_dict["swea_pad_high"]["pa"],datas_dict["swea_pad_high"]["diff_en_fluxes"]
            x,time_i=MAVEN_plot.time2x(x,time_julian0,x_range)
            MAVEN_plot.SWEA_PAD_heatmap(axs[np],x,y[time_i,:],c[time_i,:];c_range=colorrange_2,ylabel="Pitch angle \n [deg]")
            Colorbar(fig[np,color_ind],limits = colorrange_2,label="SWEA \n 90-120eV",colormap=:viridis,scale=log10)
        end
    end
# Wave Spectra
    # if datas_dict["LPW_wave"]["data_load_flag"]
    #     np = pannels["lpw_wave"];
    #     timeSP, freq, wave_data = datas_dict["LPW_wave"]["epoch"],datas_dict["LPW_wave"]["freq"],datas_dict["LPW_wave"]["data"]
    #     c_range=(1e-14,1e-9)
    #     x,time_i=MAVEN_plot.time2x(timeSP,time_julian0,x_range)
    #     if time_i != []
    #         MAVEN_plot.WaveSpactra_heatmap(axs[np],x, freq[time_i,:], wave_data[time_i,:])
    #         if datas_dict["MAG_ss1s_l3"]["data_load_flag"]
    #             # lines!(axs[np], timeB_julian, 0.05*fce, label="0.05fce",linewidth = 2 ,linstyle=:dash,color=:white)
    #             # lines!(axs[np], timeB_julian, 0.5.*fce, label="0.5fce",linewidth = 2,linstyle=:dash,color=:white)
    #             lines!(axs[np], timeB_julian, fce, label="fce",linewidth = 2,linstyle=:dash,color=:white)
    #         end
    #         Colorbar(fig[np,color_ind],limits = c_range,label=L"P_{E}",colormap=:viridis,scale=log10)
    #     end
    # end
    np=length(pannel_name)
    axs_xtick = [Axis(fig[np,pannel_ind]),Axis(fig[np,pannel_ind])]
    #下标刻度
    # timeB,alt
    timekp = datas_dict["KP"]["time"]
    alt = datas_dict["KP"]["alt"]
    x,time_i = MAVEN_plot.time2x(timekp,time_julian0,x_range)
    x_i=xd.-time_julian0
    xtimes = (x_i, Dates.format.(julian2datetime.(xd), "HH:MM"))
        axs_xtick[1] = x_ticks(axs_xtick[1],x,xtimes,x_i;model="time",range=x_range_julian)
        axs_xtick[2] = x_ticks(axs_xtick[2],x,alt[time_i],x_i;xticklabelpad=20,range=x_range_julian)
        axs_xtick[2].xlabel = "Alt[Km]"
        axs_xtick[2].backgroundcolor = :gray

    linkxaxes!(axs...,axs_xtick...)
    for ax in axs
        hidexdecorations!(ax, grid = false)
    end
    # 时间戳
    for ax in axs
        as = datetime2julian.(time_stemp).-time_julian0
        vlines!(ax,as,linestyle=:dash,color = :black)
    end
    return fig,(time_julian0,xtimes,x_range,x_range_julian)
end;