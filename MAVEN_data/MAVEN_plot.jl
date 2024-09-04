module MAVEN_plot
using ColorTypes, CairoMakie
using LaTeXStrings
using TimesDates, Dates
using DataFrames
using Interpolations
using LinearAlgebra
using Statistics
using DelaunayTriangulation
using PyCall; griddata = pyimport("scipy.interpolate").griddata;
const EV=1.602176487e-19
const C=3.0e8
const me=9.109e-31
const Rm = 3393.5  #km
const E0 = 511.0 # 电子静止能量KeV
const RAD = π / 180

function vspan_plot(ax,x,y::Vector{Bool};krawg...)
    # 转接vspan函数,y需要为bool值
    segments1 = []
    segments2 = []
    start_idx = nothing
    for (i,yi) in enumerate(y)
        if yi
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
    vspan!(ax,segments1,segments2;krawg...)
    return ax
end
function sta_heatmap(ax, x, y, c, swp_ind; c_range=(1e4, 1e10), ylabel="energy", colormap=:jet, colorscale=log10, overdraw=true, krawg...)
    ax.ylabel = ylabel
    unique_elements = unique(swp_ind)
    for element in unique_elements
        indices = findall(x -> x == element, swp_ind)
        heatmap!(ax, x[indices], y[:, element+1], c[indices, :], colormap=colormap, colorscale=colorscale, colorrange=c_range, overdraw=overdraw, krawg...)
    end
    return ax
end
function STA_2d_slip(ax,dat;frame="xy",vsc=[0,0,0],vbluk=[0,0,0],colorrange=(1e-12,1e0),angle_range=[-30,30],ylabel = "",xlabel = "",plot_range=(-120,120),return_rot_matrix = false,energy_range=[0,1e4],colormap=:jet,show_data=false) 
    # dat imported by MAVEN_load.static_slip_2_V
    #默认vbluk已经经过vsc修正
    # ROTATION: (case insensitive)
    # ;         'xy': the x axis is v_x and the y axis is v_y. (DEFAULT)
    # ;         'xz': the x axis is v_x and the y axis is v_z.
    # ;         'yz': the x axis is v_y and the y axis is v_z.
    # ;       rotations shown below require valid MAGF tag in the data structure
    # ;         'bv': the x axis is v_para (to the magnetic field) and
    # ;               the bulk velocity is in the x-y plane.
    # ;         'be': the x axis is v_para (to the magnetic field) and
    # ;               the VxB direction is in the x-y plane.
    # ;         'perp': the x-y plane is perpendicular to the B field,
    # ;                 while the x axis is the velocity projection on the plane.
    # ;         'perp_xy': the x-y plane is perpendicular to the B field,
    # ;                    while the x axis is the x projection on the plane.
    # ;         'perp_xz': the x-y plane is perpendicular to the B field,
    # ;                    while the x axis is the x projection on the plane.
    # ;         'perp_yz': the x-y plane is perpendicular to the B field,
    # ;                    while the x axis is the y projection on the plane.
    # ;       ANGLE: the lower and upper angle limits of the slice selected to plot (DEFAULT [-20,20]).
    function remove_repeat_points(x,y,z,c;angle = [-30,30])
        points = [x y c]
        theta_xy = [asind(zi / norm([xi,yi,zi]) ) for (xi,yi,zi) in eachrow([x y z])]
        ind = findall(x -> angle[1] <= x <= angle[2], theta_xy)
        data1 = Dict()
        for (p1, p2 ,ci) in eachrow(points[ind,:])
            push!(get!(data1, (p1, p2), []), ci)
        end
        new_x =[]
        new_y =[]
        new_c =[]
        for (key,val) in data1
            push!(new_x,key[1])
            push!(new_y,key[2])
            push!(new_c,mean(val))
        end 
        new_x = convert(Array{Float64},new_x)
        new_y = convert(Array{Float64},new_y)
        new_c = convert(Array{Float64},new_c)
        return new_x,new_y,new_c
    end
    function filter_points_optimized(x, y, c, r)  # 当无效点附近存在有效点，去除无效点
        valid = c .!= 1e-20
        # 遍历所有无效点
        for i in 1:length(c)
            if !valid[i]
                nearby_valid = false
                # 检查在距离 r 内是否有有效点
                for j in 1:length(c)
                    if valid[j]
                        dist = sqrt((x[i] - x[j])^2 + (y[i] - y[j])^2)
                        if dist <= r
                            nearby_valid = true
                            break
                        end
                    end
                end
                # 如果附近没有有效点，则将此无效点标记为有效点
                if !nearby_valid
                    valid[i] = true
                end
            end
        end
        return x[valid],y[valid],c[valid]
    end
    function color_mapping(vars,color_range;scaler=nothing)
        if scaler == "log"
            color_range_in = log10.(color_range)
            vars_in = log10.(vars)
        else
            color_range_in = color_range
            vars_in = vars
        end
        vars_mapped = round.(Int, ((vars_in .- color_range_in[1]) ./ (color_range_in[2] - color_range_in[1])) .* 255 .+ 1)
        vars_mapped[vars_mapped .> 256] .= 256
        vars_mapped[vars_mapped .< 1] .= 1
        return vars_mapped
    end
    function slice2d_cal_rot(v1,v2)
        a = normalize(v1)
        d = normalize(v2)
        c = cross(a,d)
        c = normalize(c)
        b = -cross(a,c)
        b = normalize(b)
        rotinv = zeros(3,3)
        rotinv[:,1] = a
        rotinv[:,2] = b
        rotinv[:,3] = c
        rot = inv(rotinv)
        return rot
    end
    bvec = dat["magf"]
    vvec = vbluk
    rot = zeros(3,3)
    if frame == "xy"
        rot = slice2d_cal_rot([1,0,0], [0,1,0])
        elseif frame == "xz"
            rot = slice2d_cal_rot([1,0,0], [0,0,1])
        elseif frame == "yz"
            rot = slice2d_cal_rot([0,1,0], [0,0,1])
        elseif frame == "bv"
            rot = slice2d_cal_rot(bvec, vvec)
        elseif frame == "be"    
            rot = slice2d_cal_rot(bvec, cross(bvec,vvec))
        elseif frame == "perp"
            rot = slice2d_cal_rot( cross(cross(bvec,vvec),bvec), cross(bvec,vvec))
        elseif frame == "perp_xy"
            rot = slice2d_cal_rot( cross(cross(bvec,[1,0,0]),bvec), cross(cross(bvec,[0,1,0]),bvec) )
        elseif frame == "perp_xz"
            rot = slice2d_cal_rot( cross(cross(bvec,[1,0,0]),bvec), cross(cross(bvec,[0,0,1]),bvec))
        elseif frame == "perp_yz"
            rot = slice2d_cal_rot( cross(cross(bvec,[0,1,0]),bvec), cross(cross(bvec,[0,0,1]),bvec))
        else
            println("Error occurred: bad rot frame")
            return ax
    end

    ax.ylabel = ylabel
    ax.xlabel = xlabel
    ax.limits = (plot_range,plot_range)
    df_data = dat["dF"]
    v0 = dat["v"]
    m_int = ["mass"]
    nenergy  = dat["nenergy"]
    nbins    = dat["nbins"]
    energy0 = dat["energy"]

    V = reshape(v0,nbins*nenergy,3)
    df = reshape(df_data,nbins*nenergy)
    energy = reshape(energy0,nbins*nenergy)
    V[:,1] = V[:,1] .+ vsc[1]
    V[:,2] = V[:,2] .+ vsc[2]
    V[:,3] = V[:,3] .+ vsc[3]

    new_v =  V * rot'
    new_vbluk = rot * vbluk
    new_b = rot * bvec
    new_b = normalize(new_b)

    x,y,z,c = new_v[:,1],new_v[:,2],new_v[:,3],df
    ind_energy = (energy_range[1] .> energy) .|| (energy .> energy_range[2])
    c[ind_energy] .= 0.0
    # x = vec(x) ; y = vec(y) ; z = vec(z); c = vec(c)
    # 去除0点
    ind_c = c .<= 0
    c[ind_c] .= 1e-20
    # ind_c = c .!= 1e-20
    # x = x[ind_c] ; y = y[ind_c] ; z = z[ind_c]; c = c[ind_c]
    x,y,c = remove_repeat_points(x,y,z,c;angle = angle_range)
    x,y,c = filter_points_optimized(x,y,c, 3.0)

    # points = cat(x,y,dims=2)
    # xi = collect(LinRange(plot_range[1], plot_range[2],200))
    # yi = collect(LinRange(plot_range[1], plot_range[2],200))
    # grid_x = repeat(yi, 1, length(xi))
    # grid_y = repeat(xi', length(yi), 1)
    # grid_z = griddata(points, log10.(c), (grid_x, grid_y), method="cubic")  #The interpolant is constructed by triangulating the input data with Qhull [1], and constructing a piecewise cubic interpolating Bezier polynomial on each triangle, using a Clough-Tocher scheme [CT]. The interpolant is guaranteed to be continuously differentiable.
    # heatmap!(ax,xi, yi, grid_z, colormap = colormap,bottom = :white,colorrange=log10.(colorrange))
    # contourf!(ax,xi, yi, grid_z, colormap = colormap,levels=LinRange(log10.(colorrange)...,20),extendlow = :auto)#,

    pts = hcat(x, y)' ; tri = triangulate(pts) ;
    scatter_colors = color_mapping(c,colorrange;scaler="log")
    voronoiplot!(ax, voronoi(tri)  ,color = scatter_colors, colormap = colormap,strokewidth=0 ,markersize=0 )
    # tricontourf!(ax, tri, scatter_colors, colormap = colormap,bottom = :black,levels = 256)

    if show_data
        colormap = :jet
        n_colors = 256
        colors = resample_cmap(colormap, n_colors)
        scatter_color = [colors[i] for i in scatter_colors]
        scatter!(ax,x,y,markersize = 7,color = :black)
        scatter!(ax,x,y,markersize = 5,color = scatter_color)
    end
    lines!(ax,[-1000,1000],[0,0],linestyle=:dash,color=:white)
    lines!(ax,[0,0],[-1000,1000],linestyle=:dash,color=:white)

    lines!(ax,[0,1000*new_b[1]],[0,1000*new_b[2]],linestyle=:dash,color=:green)
    # scatter!(ax,new_vbluk[1],new_vbluk[2],color=:white,marker = :rect,markersize = 20)
    if return_rot_matrix
        return ax,rot
    end
    return ax
end
function SWEA_PAD_heatmap(ax,time,pa,eflux;c_range=(1e4,1e10),ylabel="Pitch Angle [deg]")
    ax.ylabel = ylabel
    ntime=length(time)
    for i=1:3:ntime-3
        heatmap!(ax,time[i:i+3],pa[i,:],eflux[i:i+3,:],colormap=:jet,colorscale=log10,colorrange=c_range,overdraw=true)
    end
    return ax
end
function WaveSpactra_heatmap(ax,time,freq,data; c_range=(1e-14,1e-9),ylabel = "freq")
    ax.ylabel=ylabel
    # ax.yscale=log10
    x,y,c = time,freq,data
    nc=size(c) ; nx=nc[1]; ny=nc[2]
    x = repeat(x,ny) ; x = reshape(x,nx,ny)
    x = vec(x) ; y = vec(y) ; c = vec(c)
    y[y .< 1] .= 1
    df = DataFrame(X=x, Y=y, C=c)
    df_unique = unique(df, [:X, :Y])
    x = df_unique.X ; y = df_unique.Y ; c = df_unique.C
    heatmap!(ax,x,y,c,colormap=:jet,colorscale=log10,colorrange=c_range,overdraw=true)
    return ax
end
function Orbit(ax,position_ss; xlimit=(-5,4), ylimit=(0,3),obs_position = [-0.5,0,0],times = ([],[]),frame = "x-yz")
    ax.limits = (xlimit, ylimit)
    ax.xreversed=true
    p_mso = position_ss./Rm
    x=p_mso[:,1]
    if frame == "x-yz"
        y= sqrt.(p_mso[:,2].^2 .+ p_mso[:,3].^2)
    elseif frame == "x-y"
        y= p_mso[:,2]
    elseif frame == "x-z"
        y= p_mso[:,3]
    end

    lines!(ax,x,y,label="Orbit",overdraw=true)

    # if times != ([],[])
    #     times_t = times[2]
    #     time_index = times[1]
    #     colormap = :tab10
    #     n_colors = length(time_index)
    #     colors = resample_cmap(colormap, n_colors)
    #     for (it,i) in enumerate(time_index)
    #         poly!(ax,Circle(Point2f(x[i], y[i]), 0.1),color=colors[it],label = times_t[it])
    #         # text!(ax, 0.98, 0.95-it*0.95/(n_colors+1), text = times_t[it], font = :bold, align = (:center, :center), space = :relative, fontsize = 15, color=colors[it])
    #     end
    # end
    
    p_obs  = obs_position./Rm
    x=p_obs[1]
    if frame == "x-yz"
        y= sqrt.(p_obs[2].^2 .+ p_obs[3].^2)
    elseif frame == "x-y"
        y= p_obs[2]
    elseif frame == "x-z"
        y= p_obs[3]
    end

    poly!(ax,Circle(Point2f(x, y), 0.1),color=:red)

    theta = LinRange(pi, 2pi, 100)
    x = sin.(theta)
    y = cos.(theta)
    half_circle = [Point2f(x[i], y[i]) for i in 1:length(x)]
    poly!(ax,Circle(Point2f(0, 0), 1),color=:white,strokewidth = 2,strokecolor =:black)
    poly!(ax, half_circle, color=:black)

    # bowshock
    x = -10:0.01:2
    lines!(ax,x,bowshock.(x);linestyle=:dash)#label="bowshock"
    # magnetopause
    lines!(ax,x,magnetopause.(x); linestyle=:dash)#label="magnetopause",
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
function time2x(time,range)
    time_i = findall(t -> range[1] <= t <= range[2], time)
    x = time[time_i]
    x = Dates.datetime2julian.(x)
    return x,time_i
end
function time_ticks(time_range; step=Dates.Minute(20),format = "HH:MM:SS") # 取得time_range 对应步长的
    xd = range(time_range[1], time_range[2], step=step)
    x_i=Dates.datetime2julian.(xd)
    xtimes = (x_i, Dates.format.(xd, format))
    return xtimes,x_i
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
    # rSD = 1.25
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