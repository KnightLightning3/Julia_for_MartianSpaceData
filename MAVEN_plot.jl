module MAVEN_data_plot
using ColorTypes, CairoMakie
using LaTeXStrings
using TimesDates, Dates
using DataFrames
using Interpolations
using LinearAlgebra
const EV=1.602176487e-19
const C=3.0e8
const me=9.109e-31
const Rm = 3393.5  #km
const E0 = 511.0
const RAD = π / 180
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

    p_mso = position_ss./Rm
    x=p_mso[:,1]
    y= sqrt.(p_mso[:,2].^2 .+ p_mso[:,3].^2)
    lines!(ax,x,y,label="Orbit")

    p_obs  = obs_position./Rm
    x=p_obs[1]
    y= sqrt.(p_obs[2].^2 .+ p_obs[3].^2)
    poly!(ax,Circle(Point2f(x, y), 0.1),color=:red)
    theta = LinRange(pi, 2pi, 100)
    x = sin.(theta)
    y = cos.(theta)
    half_circle = [Point2f(x[i], y[i]) for i in 1:length(x)]
    poly!(ax,Circle(Point2f(0, 0), 1),color=:white,strokewidth = 2,strokecolor =:black)
    poly!(ax, half_circle, color=:black)

    # bowshock
    x = -10:0.1:10
    y = bowshock.(x)
    lines!(ax,x,y;label="bowshock", linestyle=:dash)
    # magnetopause
    y = magnetopause.(x)
    lines!(ax,x,y;label="magnetopause", linestyle=:dash)
    return ax
end
function PAD_slice(ax,pa,energy,eflux;potential=0.0,xlimit=(0,180),ylimit=(1e-17,1e-11),xlabel="pitch angle",ylabel="PSD",n=4)
    colormap = :jet  # 可以选择任何Makie支持的颜色图
    n_colors = length(energy)
    colors = resample_cmap(colormap, n_colors)
    ax.limits=(xlimit, ylimit)
    ax.ylabel=ylabel
    ax.xlabel=xlabel
    ax.yscale=log10
    energy_t = energy .- potential
    for (index, e) in enumerate(energy_t)
        y = eflux[:, index]
        indext = findall(a -> a >= 1e-5, y)
        y = y[indext]
        x = pa[:, index]
        x = x[indext]
        color = colors[index]
        for (i_yy,yy) in enumerate(y)
            y[i_yy] = eflux2F.(e,yy)
        end
        scatter!(ax, x, y, label=string(round.(e,digits=1)), color=color)
        coefficients = polynomial_fit(x, y, n)
        # if length(x) >= 2
            # xfit=minimum(x):1:maximum(x)
        # else
            xfit=0:1:180
        # end
        fitted_y = exp.(Vandermonde(xfit, n) * coefficients)
        lines!(ax, xfit, fitted_y, color=color)
    end
end
function PAD_slice_polar(ax,pa,energy,eflux;potential=0.0,ylimit=(0,200),xlimit=(-200,200),xlabel="Ek_para [eV]",ylabel="Ek_prep [eV]", c_range = (1e-17,1e-11))
    colormap = :jet  # 可以选择任何Makie支持的颜色图
    n_colors = 256
    colors = resample_cmap(colormap, n_colors)

    ax.limits=(xlimit, ylimit)
    ax.ylabel=ylabel
    ax.xlabel=xlabel
    ax.ytickformat = "{:.1f}"
    ax.xtickformat = "{:.1f}"
    energy_t = energy .- potential
    PSD = zeros(length(pa[:,1]),length(energy))
    Ek_perp = zeros(length(pa[:,1]),length(energy))
    Ek_par  = zeros(length(pa[:,1]),length(energy))
    Ek0 = energy_t .* 1.0
    for i = 1:length(pa[:,1])
        PSD[i,:] =  eflux2F.(energy_t[:], eflux[i,:])
        Ek_perp[i,:] = Ek0 .* sind.(pa[i,:])
        Ek_par[i,:]  = Ek0 .* cosd.(pa[i,:])
    end

    LPSD_range = log10.(c_range)
    LPSD = log10.(PSD)
    println(minimum(LPSD))
    levels = (1:256) ./ 256 .* (maximum(LPSD_range) - minimum(LPSD_range))  .+ minimum(LPSD_range)
    rr = Ek0[:]
    for j = 1:length(rr)-1
        psi = pa[:,j]
        
        local_color_index = []
        for value in LPSD[:,j]
            index = findmin(abs.(levels .- value))[2]
            push!(local_color_index, index)
        end
        
        nan_index = findall(x -> x == -Inf, LPSD[:,j])
        local_colors = colors[local_color_index]
        local_colors[nan_index] .= RGBA{Float32}(1,1,1,1)

        extended_psi = [0; psi; 180]
        part_sizes = [(extended_psi[i+1]-extended_psi[i-1])/2 for i = 2:length(extended_psi)-1]
        part_sizes[1] = part_sizes[1] + psi[1]/2
        part_sizes[end] = part_sizes[end] + (180 - psi[end])/2

        pie!(ax, part_sizes.* RAD, inner_radius = rr[j] , radius = rr[j+1], strokewidth = 0 ,color =local_colors, overdraw=true,normalize=false)
    end
    return ax
end
function PAD_slice_velocity(ax,pa,energy,eflux;potential=0.0,xlimit=(-1.5e7,1.5e7),ylimit=(0,1.5e7),xlabel="v_para [m/s]",ylabel="v_prep [m/s]", c_range = (1e-17,1e-11))
    colormap = :jet  # 可以选择任何Makie支持的颜色图
    n_colors = 256
    colors = resample_cmap(colormap, n_colors)

    ax.limits=(xlimit, ylimit)
    ax.ylabel=ylabel
    ax.xlabel=xlabel
    ax.ytickformat = "{:.1e}"
    ax.xtickformat = "{:.1e}"
    energy_t = energy .- potential
    PSD = zeros(length(pa[:,1]),length(energy))
    v_perp = zeros(length(pa[:,1]),length(energy))
    v_par  = zeros(length(pa[:,1]),length(energy))
    v0 = sqrt.(2*energy_t./me .* EV)
    for i = 1:length(pa[:,1])
        PSD[i,:] =  eflux2F.(energy_t[:], eflux[i,:])
        v_perp[i,:] = v0 .* sind.(pa[i,:])
        v_par[i,:]  = v0 .* cosd.(pa[i,:])
    end

    #
    LPSD_range = log10.(c_range)
    LPSD = log10.(PSD)
    println(minimum(LPSD))
    levels = (1:256) ./ 256 .* (maximum(LPSD_range) - minimum(LPSD_range))  .+ minimum(LPSD_range)
    rr = v0[:]
    for j = 1:length(rr)-1
        psi = pa[:,j]
        
        local_color_index = []
        for value in LPSD[:,j]
            index = findmin(abs.(levels .- value))[2]
            push!(local_color_index, index)
        end
        
        nan_index = findall(x -> x == -Inf, LPSD[:,j])
        local_colors = colors[local_color_index]
        local_colors[nan_index] .= RGBA{Float32}(1,1,1,1)

        extended_psi = [0; psi; 180]
        part_sizes = [(extended_psi[i+1]-extended_psi[i-1])/2 for i = 2:length(extended_psi)-1]
        part_sizes[1] = part_sizes[1] + psi[1]/2
        part_sizes[end] = part_sizes[end] + (180 - psi[end])/2

        pie!(ax, part_sizes.* RAD, inner_radius = rr[j] , radius = rr[j+1], strokewidth = 0 ,color =local_colors, overdraw=true,normalize=false)
    end
    # x,y,c = v_par,v_perp,  PSD
    # x = vec(x) ; y = vec(y) ; c = vec(c)
    # scatter!(ax, x,y, color = :black, overdraw = true)

    # pa_fitted = 0:180
    # PSD_fitted = zeros(length(pa_fitted),length(energy))
    # v_perp_fitted = zeros(length(pa_fitted),length(energy))
    # v_para_fitted = zeros(length(pa_fitted),length(energy))
    # x, y , c = v_para_fitted, v_perp_fitted, PSD_fitted

    # n=4
    # for i = 1:length(energy_t[:])
    #     x=pa[:,i]
    #     y=PSD[:,i]
    #     coefficients = polynomial_fit(x, y, n)
    #     PSD_fitted[:,i] =  exp.(Vandermonde(pa_fitted, n) * coefficients)
    #     v_perp_fitted[:,i] = v0[i] .* sind.(pa_fitted)
    #     v_para_fitted[:,i]  = v0[i] .* cosd.(pa_fitted)
    # end
    # x,y,c = v_para_fitted,v_perp_fitted,  PSD_fitted
    # x = vec(x) ; y = vec(y) ; c = vec(c)
    # scatter!(ax, x,y, colormap=:jet, color = c , colorrange=c_range , colorscale=log10)
    # itp = interpolate((x,y),c,Gridded(Linear()))
    # v_para_gridded = [-1.5e7:1e5:1.5e7;]
    # v_perp_gridded = [0:1e5:1.5e7;]
    # c_interp = zeros(length(v_para_gridded),length(v_perp_gridded))
    # for i = 1:length(v_para_gridded)
    #     for j = 1:length(v_perp_gridded)
    #         c_interp[i,j] = itp(v_para_gridded[i],v_perp_gridded[j])
    #     end
    # end
    # heatmap!(ax, v_para_gridded,v_perp_gridded,c_interp, colormap=:jet, colorrange=c_range , colorscale=log10)
    return ax
end
function time_frequncy(ax)
    
    heatmap!(ax,)
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
function vector_angle(a,b)
    a = a./norm(a)
    b = b./norm(b)
    angle = acos(dot(a,b))
    angle *= 180.0 / π
    return angle
end
function Vandermonde(x, n)
    return hcat([x.^i for i in 0:n]...)
end
function polynomial_fit(x, y, n)
    log_y = log.(y)
    mask = .!isnan.(log_y) .& .!isinf.(log_y) # 创建一个布尔掩码,其中x不是NaN的位置为true
    filtered_x = x[mask]
    filtered_y = log_y[mask]

    if length(filtered_y) <= n
        return error("Not enough data for a good fit.")
    end
    V = hcat([filtered_x.^i for i in 0:n]...)
    coefficients = V \ filtered_y
    return coefficients
end
function eflux2F(energy,eflux)
    M = me
    # E0=M*C^2/EV   #静止能量 eV
    #energy 与 eflux 一一对应
    # E0=M*C^2/EV
    γ=(energy * 1e-3 /E0 + 1)
    β=sqrt(1.0 - 1.0 / γ^2)
    P=γ *M * β *C        # kg m/s
    # V=β .* C
    F = (γ*M)^3 * eflux/energy *1e4 /EV / P^2
    return F
end
#bow-shock model
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
#magnetopause model
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

end