module MAVEN_data_plot
using ColorTypes, CairoMakie
using LaTeXStrings
using TimesDates, Dates
using DataFrames
function sta_heatmap(ax,x,y,c,nswp;c_range=(1e4,1e10),ylabel="energy",xlimit=nothing,ylimit=nothing)    
    ax.limits = (xlimit,ylimit)
    ax.ylabel = ylabel
    ax.yscale = log10
    unique_elements = unique(nswp)
    for element in unique_elements
        indices = findall(x -> x == element, nswp)
        heatmap!(ax,x[indices],y[:,element+1],c[indices,:],colormap=:jet,colorscale=log10,colorrange=c_range,overdraw=true)
    end
    return ax
end
function SWEA_PAD_heatmap(ax,time,pa,eflux;xlimit=nothing,ylimit=(0,180), c_range=(1e4,1e10),ylabel="Pitch Angle [deg]")
    ax.limits = (xlimit, ylimit)
    ax.ylabel = ylabel
    ntime=length(time)
    for i=1:3:ntime-3
        heatmap!(ax,time[i:i+3],pa[i,:],eflux[i:i+3,:],colormap=:jet,colorscale=log10,colorrange=c_range,overdraw=true)
    end
    return ax
end
function WaveSpactra_heatmap(ax,time,freq,data;xlimit=nothing, ylimit=(1e0,1e4), c_range=(1e-14,1e-9),ylabel = "freq")
    ax.limits = (xlimit, ylimit)
    ax.ylabel=ylabel
    ax.yscale=log10
    x,y,c = time,freq,data
    nc=size(c) ; nx=nc[1]; ny=nc[2]
    x = repeat(x,ny) ; x = reshape(x,nx,ny)
    x = vec(x) ; y = vec(y) ; c = vec(c)
    y[y .< 1] .= 1
    df = DataFrame(X=x, Y=y, C=c)
    df_unique = unique(df, [:X, :Y])
    x = df_unique.X ; y = df_unique.Y ; c = df_unique.C
    heatmap!(ax,x,y,c,colormap=:jet,colorscale=log10,colorrange=c_range)
    return ax
end
function Orbit(ax,position_ss; xlimit=(-5,4), ylimit=(0,3), xlabel="X_mso",ylabel=" ",obs_position = [-0.5,0,0])
    ax.limits = (xlimit, ylimit)
    ax.ylabel=ylabel # L"\sqrt{Y_{mso}^{2} + X_{mso}^{2}}"
    ax.xlabel=xlabel
    ax.xreversed=true

    p_mso = position_ss./3393.5
    x=p_mso[:,1]
    y= sqrt.(p_mso[:,2].^2 .+ p_mso[:,3].^2)
    lines!(ax,x,y)

    p_obs  = obs_position./3393.5
    x=p_obs[1]
    y= sqrt.(p_obs[2].^2 .+ p_obs[3].^2)
    poly!(ax,Circle(Point2f(x, y), 0.1),color=:red)
    theta = LinRange(pi, 2pi, 100)
    x = sin.(theta)
    y = cos.(theta)
    half_circle = [Point2f(x[i], y[i]) for i in 1:length(x)]
    poly!(ax,Circle(Point2f(0, 0), 1),color=:white,strokewidth = 2,strokecolor =:black)
    poly!(ax, half_circle, color=:black)

    return ax
end
function time2julian(x_range)
    x_range_julian = Dates.datetime2julian.(x_range)
    time_julian0   = x_range_julian[1]
    x_range_julian = x_range_julian .- time_julian0
    return x_range_julian, time_julian0
end
function time2x(time,time_julian0,range)
    time_i = findall(t -> range[1] <= t <= range[2], time)
    x = time[time_i]
    x = Dates.datetime2julian.(x) .- time_julian0
    return x,time_i
end
function x_ticks(ax , x,var,x_i;xlabel="",xticklabelpad=3,num_pannel=1,model="null",range=x_range_julian)
    ax.limits = (range, nothing) 
    ax.xlabel=xlabel
    ax.xlabelpadding=3
    ax.xticklabelpad=xticklabelpad
    hidespines!(ax); hideydecorations!(ax)
    if model == "time"
        ax.xticks = var
        return ax
    end
    y_i=[var[argmin(abs.(x .- xi))[1]] for xi in x_i]; y_i= string.(round.(y_i, digits=1))
    ax.xticks = (x_i,y_i)
    return ax
end

end