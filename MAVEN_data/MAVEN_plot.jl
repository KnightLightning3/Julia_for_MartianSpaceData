module MAVEN_plot
using ColorTypes, CairoMakie
using Makie.GeometryBasics
using LaTeXStrings
using TimesDates, Dates
using DataFrames
using DataInterpolations
using LinearAlgebra
using Statistics
using Base.Iterators
using DelaunayTriangulation
using ProgressMeter
const EV = 1.602176487e-19
const C = 3.0e8
const me = 9.109e-31
const Rm = 3393.5  #km
const E0 = 511.0 # 电子静止能量KeV
const RAD = π / 180

# -------------------------Export parts-------------------------
export sta_heatmap, STA_2d_slip, SWEA_PAD_heatmap, WaveSpactra_heatmap, Orbit, PAD_slice, PAD_slice_polar, PAD_slice_velocity
export time2x, time_ticks, x_ticks
function vspan_plot(ax, x, y::Vector{Bool}; krawg...)
    # 转接vspan函数,y需要为bool值
    segments1 = []
    segments2 = []
    start_idx = nothing
    for (i, yi) in enumerate(y)
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
    vspan!(ax, segments1, segments2; krawg...)
    return ax
end
function sta_heatmap_test(ax, sta_data; unit="eflux", c_range=(1e4, 1e10), colormap=:viridis, colorscale=log10, overdraw=true,sc_correction = false,krawg...)
    swp_ind = sta_data[:swp_ind]; unique_swp_ind = unique(swp_ind)
    epoch = sta_data[:epoch] ; x, time_i = time2x(x0, x_range)
    eflux = sta_data[:eflux]
    energy = sta_data[:energy]
    sc_pot = sta_data[:sc_pot]
    nenergy = length(sta_data[:energy][:, 1])
    
    y = energy
    c = eflux[time_i,:,:]

    for element in unique_elements
        indices = findall(x -> x == element, swp_ind)
        if unit == "flux"
            c1 = c[indices, :] ./ reshape(y[:, element+1], 1, nenergy)
        else
            c1 = c[indices, :]
        end
        heatmap!(ax, x[indices], y[:, element+1], c1, colormap=colormap, colorscale=colorscale, colorrange=c_range, overdraw=overdraw, krawg...)
    end
    return ax
end
function sta_heatmap(ax, x, y, c, swp_ind; unit="eflux", c_range=(1e4, 1e10), colormap=:viridis, colorscale=log10, overdraw=true, sc_correction = false, sc_pot = nothing, krawg...)
    unique_elements = unique(swp_ind)
    if !sc_correction
        nenergy = length(y[:, 1])
        for element in unique_elements
            indices = findall(x -> x == element, swp_ind)
            n_time = length(indices)
            if unit == "flux"
                scale= 1.0 ./ reshape(y[:, element+1], 1, nenergy)
            else
                scale= 1.0
            end
            
            indices_sub = []
            start_idx = 1
            for i in 2:n_time
                if indices[i] != indices[i-1] + 1
                    push!(indices_sub, indices[start_idx:i-1])
                    start_idx = i
                end
            end
            push!(indices_sub, indices[start_idx:end])
            for indices_i in indices_sub
                x1 = x[indices_i]
                c1 = c[indices_i, :]
                heatmap!(ax, x1, y[:, element+1], c1.*scale; colormap=colormap, colorscale=colorscale, colorrange=c_range, krawg...)
            end
        end
        return ax
    else
        for ii in eachindex(swp_ind)
            if ii == length(swp_ind)
                break
            end
            y1 = y[:, swp_ind[ii]+1] .+ sc_pot[ii]
            e_ind = findall(x -> x > 0.5, y1)
            heatmap!(ax, x[ii:ii+1], y1[e_ind], c[ii:ii+1, e_ind]; colormap=colormap, colorscale=colorscale, colorrange=c_range, overdraw=overdraw, krawg...)
        end
    end
end
"""
    dat imported by MAVEN_load.static_slip_2_V     
    默认vbluk已经经过vsc修正     
    ROTATION: (case insensitive)     
             'xy': the x axis is v_x and the y axis is v_y. (DEFAULT)     
             'xz': the x axis is v_x and the y axis is v_z.
             'yz': the x axis is v_y and the y axis is v_z.
           rotations shown below require valid MAGF tag in the data structure     
             'bv': the x axis is v_para (to the magnetic field) and     
                   the bulk velocity is in the x-y plane.
             'be': the x axis is v_para (to the magnetic field) and     
                   the VxB direction is in the x-y plane.
             'perp': the x-y plane is perpendicular to the B field,     
                     while the x axis is the velocity projection on the plane.
             'perp_xy': the x-y plane is perpendicular to the B field,     
                        while the x axis is the x projection on the plane.
             'perp_xz': the x-y plane is perpendicular to the B field,     
                        while the x axis is the x projection on the plane.
             'perp_yz': the x-y plane is perpendicular to the B field,     
                        while the x axis is the y projection on the plane.
           ANGLE: the lower and upper angle limits of the slice selected to plot (DEFAULT [-20,20]).
"""
function STA_2d_slip(ax, dat; frame="xy", vsc=[0, 0, 0], vbluk=[0, 0, 0],magf=dat[:magf], colorrange=(1e-12, 1e0), angle_range=[-30, 30], ylabel="", xlabel="", plot_range=(-120, 120), return_rot_matrix=false, energy_range=[0, 1e6], colormap=:viridis, show_data=false,backgroundcolor = :gray80)
    function remove_repeat_points(x, y, z, c; angle=[-30, 30])
        points = [x y c]
        theta_xy = [asind(zi / norm([xi, yi, zi])) for (xi, yi, zi) in eachrow([x y z])]
        ind = findall(x -> angle[1] <= x <= angle[2], theta_xy)
        data1 = Dict()
        for (p1, p2, ci) in eachrow(points[ind, :])
            push!(get!(data1, (p1, p2), []), ci)
        end
        new_x = []
        new_y = []
        new_c = []
        for (key, val) in data1
            push!(new_x, key[1])
            push!(new_y, key[2])
            push!(new_c, mean(val))
        end
        new_x = convert(Array{Float64}, new_x)
        new_y = convert(Array{Float64}, new_y)
        new_c = convert(Array{Float64}, new_c)
        return new_x, new_y, new_c
    end
    function filter_points_optimized(x, y, c, r)  # 当无效点附近存在有效点,去除无效点
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
                # 如果附近没有有效点,则将此无效点标记为有效点
                if !nearby_valid
                    valid[i] = true
                end
            end
        end
        return x[valid], y[valid], c[valid]
    end
    function color_mapping(vars, color_range; scaler=nothing)
        if scaler == "log10"
            color_range_in = log10.(color_range)
            vars_in = log10.(vars)
        else
            color_range_in = color_range
            vars_in = vars
        end
        vars_mapped = round.(Int, ((vars_in .- color_range_in[1]) ./ (color_range_in[2] - color_range_in[1])) .* 255 .+ 1)
        vars_mapped[vars_mapped.>256] .= 256
        vars_mapped[vars_mapped.<1] .= 1
        return vars_mapped
    end
    function slice2d_cal_rot(v1, v2)
        a = normalize(v1)
        d = normalize(v2)
        c = cross(a, d)
        c = normalize(c)
        b = -cross(a, c)
        b = normalize(b)
        # rotinv[:, 1] = a
        # rotinv[:, 2] = b
        # rotinv[:, 3] = c
        rotinv = hcat(a, b, c)
        rot = inv(rotinv)
        return rot
    end
    bvec = magf
    vvec = vbluk
    rot = zeros(3, 3)
    if frame == "xy"
        rot = slice2d_cal_rot([1, 0, 0], [0, 1, 0])
    elseif frame == "xz"
        rot = slice2d_cal_rot([1, 0, 0], [0, 0, 1])
    elseif frame == "yz"
        rot = slice2d_cal_rot([0, 1, 0], [0, 0, 1])
    elseif frame == "bv"
        rot = slice2d_cal_rot(bvec, vvec)
    elseif frame == "be"
        rot = slice2d_cal_rot(bvec, cross(bvec, vvec))
    elseif frame == "perp"
        rot = slice2d_cal_rot(cross(cross(bvec, vvec), bvec), cross(bvec, vvec))
    elseif frame == "perp_xy"
        rot = slice2d_cal_rot(cross(cross(bvec, [1, 0, 0]), bvec), cross(cross(bvec, [0, 1, 0]), bvec))
    elseif frame == "perp_xz"
        rot = slice2d_cal_rot(cross(cross(bvec, [1, 0, 0]), bvec), cross(cross(bvec, [0, 0, 1]), bvec))
    elseif frame == "perp_yz"
        rot = slice2d_cal_rot(cross(cross(bvec, [0, 1, 0]), bvec), cross(cross(bvec, [0, 0, 1]), bvec))
    else
        println("Error occurred: bad rot frame")
        return ax
    end

    ax.ylabel = ylabel
    ax.xlabel = xlabel
    ax.limits = (plot_range, plot_range)
    df_data = dat[:df]
    v0 = dat[:v]
    nenergy = dat[:nenergy]
    nbins = dat[:nbins]
    # energy0 = dat[:energy]

    V = reshape(v0, nbins * nenergy, 3)
    df = reshape(df_data, nbins * nenergy)
    # energy = reshape(energy0, nbins * nenergy)
    V[:, 1] = V[:, 1] .+ vsc[1]
    V[:, 2] = V[:, 2] .+ vsc[2]
    V[:, 3] = V[:, 3] .+ vsc[3]

    new_v = V * rot'
    new_vbluk = rot * vbluk
    new_b = rot * bvec
    new_b = normalize(new_b)

    x, y, z, c = new_v[:, 1], new_v[:, 2], new_v[:, 3], df
    # ind_energy = (energy_range[1] .>= energy) .|| (energy .>= energy_range[2])
    # c[ind_energy] .= 0.0
    # x = vec(x) ; y = vec(y) ; z = vec(z); c = vec(c)
    # 去除0点
    ind_c = c .<= 0
    c[ind_c] .= 1e-20
    # ind_c = c .!= 1e-20
    # x = x[ind_c] ; y = y[ind_c] ; z = z[ind_c]; c = c[ind_c]
    x, y, c = remove_repeat_points(x, y, z, c; angle=angle_range)
    x, y, c = filter_points_optimized(x, y, c, 3.0)

    pts = hcat(x, y)'
    tri = triangulate(pts)
    scatter_colors = color_mapping(c, colorrange; scaler="log10")
    voronoiplot!(ax, voronoi(tri), color=scatter_colors, colormap=colormap, strokewidth=0, markersize=0)
    # tricontourf!(ax, tri, scatter_colors, colormap = colormap,bottom = :black,levels = 256)

    if show_data
        colormap = :viridis
        n_colors = 256
        colors = resample_cmap(colormap, n_colors)
        scatter_color = [colors[i] for i in scatter_colors]
        scatter!(ax, x, y, markersize=7, color=:black)
        scatter!(ax, x, y, markersize=5, color=scatter_color)
    end
    lines!(ax, [-1000, 1000], [0, 0], linestyle=:dash, color=:white)
    lines!(ax, [0, 0], [-1000, 1000], linestyle=:dash, color=:white)

    lines!(ax, [0, 1000 * new_b[1]], [0, 1000 * new_b[2]], linestyle=:dash, color=:green)
    scatter!(ax, new_vbluk[1], new_vbluk[2], color=:white, marker='X', markersize=20)
    v_max = maximum(abs.(sqrt.(sum(new_v[:, :] .^ 2; dims=2))))
    #遮盖超过v_max的部分  可以改成闭包?
    poly!(ax, Polygon(decompose(Point2f, Circle(Point2f(0), v_max * 2)), [decompose(Point2f, Circle(Point2f(0), v_max))]); color = backgroundcolor)
    if return_rot_matrix
        return ax, rot
    end
    return ax
end
function VDF_2d_slip(ax,velocity, data; 
    normal_vectors=[[1,0,0],[0,1,0]],vbluk=[0, 0, 0],magf=[1,0,0], vsc=[0,0,0],colorrange=(1e-12, 1e0), 
    angle_range=[-30, 30], # 角度范围的切法 
    r_range_rate = 0.1, # 垂直方向的切法
    ylabel="", xlabel="", plot_range=(-120, 120), return_rot_matrix=false, colormap=:viridis,show_data=false,backgroundcolor = :gray80)
    #绘制任何3d空间分布的饼状图，必需要满足： data为一维或多维数据,速度必须为n*3的格式
    function remove_repeat_points(x, y, z, c; angle=[-30, 30],r_range = 10)
        points = [x y c]
        theta_xy = [asind(zi / norm([xi, yi, zi])) for (xi, yi, zi) in eachrow([x y z])]
        # println("平行方向范围: $r_range")
        # r_xy = abs.(z) 
        ind1 = angle[1] .<= theta_xy .<= angle[2]
        # ind2 = r_xy .<= r_range
        ind = ind1 #.| ind2
        data1 = Dict()
        for (p1, p2, ci) in eachrow(points[ind, :])
            push!(get!(data1, (p1, p2), []), ci)
        end
        new_x = []
        new_y = []
        new_c = []
        for (key, val) in data1
            push!(new_x, key[1])
            push!(new_y, key[2])
            push!(new_c, mean(skipmissing(val)))
        end
        new_x = convert(Array{Float64}, new_x)
        new_y = convert(Array{Float64}, new_y)
        new_c = convert(Array{Float64}, new_c)
        return new_x, new_y, new_c, ind
    end
    function filter_points_optimized(x, y, c, r)  # 当无效点附近存在有效点,去除无效点
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
                # 如果附近没有有效点,则将此无效点标记为有效点
                if !nearby_valid
                    valid[i] = true
                end
            end
        end
        return x[valid], y[valid], c[valid]
    end
    function color_mapping(vars, color_range; scaler=nothing)
        if scaler == "log10"
            color_range_in = log10.(color_range)
            vars_in = log10.(vars)
        else
            color_range_in = color_range
            vars_in = vars
        end
        vars_mapped = round.(Int, ((vars_in .- color_range_in[1]) ./ (color_range_in[2] - color_range_in[1])) .* 255 .+ 1)
        vars_mapped[vars_mapped.>256] .= 256
        vars_mapped[vars_mapped.<1] .= 1
        return vars_mapped
    end
    function slice2d_cal_rot(v1, v2)
        a = normalize(v1)
        d = normalize(v2)
        c = cross(a, d)
        c = normalize(c)
        b = -cross(a, c)
        b = normalize(b)
        # rotinv[:, 1] = a
        # rotinv[:, 2] = b
        # rotinv[:, 3] = c
        rotinv = hcat(a, b, c)
        rot = inv(rotinv)
        return rot
    end
    bvec = magf
    vvec = vbluk
    rot = slice2d_cal_rot(normal_vectors[1], normal_vectors[2]) # xy的两个法向向量，默认为xy平面

    ax.ylabel = ylabel
    ax.xlabel = xlabel
    ax.limits = (plot_range, plot_range)

    local vsc_2d = reshape(vsc, 1, 3)
    local V = velocity .+ vsc_2d
    local v0 = sqrt.(sum(velocity.^2, dims=2))[:,1]
    local v_range = (minimum(v0), maximum(v0))

    new_v = V * rot'  # 新坐标系下的速度三维分布
    new_vsc = rot * vsc
    new_vbluk = rot * vvec
    new_b = rot * bvec
    new_b = normalize(new_b)
    x, y, z, c = new_v[:, 1], new_v[:, 2], new_v[:, 3], vec(data)
    c[c .<= 0 ] .= 1e-20
    x, y, c, ind_mask = remove_repeat_points(x, y, z, c; angle=angle_range,r_range=v_range[2]*0.05) # 以最大速度的上下1/10为z方向的限制
    x, y, c = filter_points_optimized(x, y, c, (plot_range[2]-plot_range[1])/50) #绘图部分0.02的分辨率

    scatter_colors = color_mapping(c, colorrange; scaler="log10")

    # pts = hcat(x, y)'
    pts = [Point2f(x[i],y[i]) for i in eachindex(x)]
    if length(pts) <= 3
        println("No enough data in the selected range.")
    else
        krawg = Dict{Symbol,Any}()
        # if lowclip != :automatic
        #     krawg[:lowclip] = :black
        # end
        # if highclip != :automatic
        #     krawg[:highclip] = highclip
        # end
        tri = voronoi(triangulate(pts))
        voronoiplot!(ax, tri, color=scatter_colors, colormap=colormap, strokewidth=0, markersize=0,krawg...)
    end
    if show_data
        n_colors = 256
        colors = resample_cmap(colormap, n_colors)
        scatter_color = [colors[i] for i in scatter_colors]
        inds = scatter_colors .!= 1
        # scatter!(ax, x[inds], y[inds], markersize=7, color=:black)
        scatter!(ax, x, y, markersize=7, color=:black)
        scatter!(ax, x[inds], y[inds], markersize=5, color=scatter_color[inds])
    end
    hlines!(ax, 0, linestyle=:dash, color=:white)
    vlines!(ax, 0, linestyle=:dash, color=:white)

    # lines!(ax, [0, 1000 * new_b[1]], [0, 1000 * new_b[2]], linestyle=:dash, color=:green)
    # scatter!(ax, new_vbluk[1], new_vbluk[2], color=:red, marker='X', markersize=20)

    # v_max = maximum(abs.(sqrt.(sum(new_v[:, :] .^ 2; dims=2))))
    #遮盖传入速度之外的部分  可以改成闭包?
    # poly!(ax, Polygon(decompose(Point2f, Circle(Point2f(new_vsc[1],new_vsc[2]), v_range[2] * 2)), [decompose(Point2f, Circle(Point2f(new_vsc[1],new_vsc[2]), v_range[2]))]); color=backgroundcolor)
    poly!(ax, Circle(Point2f(new_vsc[1],new_vsc[2]), v_range[1]); color=backgroundcolor)
    if return_rot_matrix
        return ax, rot, ind_mask # 对点的处理以及mask
    end
    return ax
end
function VDF_2d_mask(ax,range_data;rot=rot,vsc=vsc,backgroundcolor=:gray80)
    function ion_energy2v(energy,AMU) # 离子子能量对应速度(相对论),输入eV, 返回km/s
        E0 = 938313.53 * AMU  # 质子静止能量 MeV
        γ= energy*1e-3/E0 + 1.0
        β=sqrt(1.0 - 1.0 / γ^2)
        v = β * 3e5
        return v
    end
    function get_triangle_mesh(r_bounds, theta_bounds, phi_bounds; n_steps=12)
        triangles = [] # 每个元素都是一个包含3个顶点的数组
        r1, r2 = r_bounds
        theta1, theta2 = theta_bounds
        phi1, phi2 = phi_bounds

        # 细分 theta, phi 范围
        # rs = range(r1, r2, length=n_steps)
        thetas = range(theta1, theta2, length=n_steps)
        phis = range(phi1, phi2, length=n_steps)

        # 1. r=r1 和 r=r2 的两个曲面（球形网格）
        for i in 1:n_steps-1, j in 1:n_steps-1
            # 四个顶点
            v1 = Point3f(r1, thetas[i], phis[j])
            v2 = Point3f(r2, thetas[i], phis[j])
            v3 = Point3f(r2, thetas[i+1], phis[j])
            v4 = Point3f(r1, thetas[i+1], phis[j])

            # 四边形分解为两个三角形
            push!(triangles, [v1, v2, v3])
            push!(triangles, [v1, v3, v4])
        end

        return triangles
    end
    function rotate_func(p; translation_vector=0,rot=0) # 转为xyz坐标系
        r, θ, ϕ = p[1], p[2], p[3]
        ct = cosd(θ)
        x = r * ct *  cosd(ϕ)
        y = r * ct *  sind(ϕ)
        z = r * sind(θ)
        v = rot*([x,y,z] .+ translation_vector)
        return Point2f(v[1], v[2])
    end
    function graham_scan(points)
        N = length(points)
        if N <= 3
            return points
        end

        # 定义你的 ccw (逆时针) 辅助函数
        function ccw(a::Point2f, b::Point2f, c::Point2f)
            return ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]))
        end
        # 1. 找到最低最左的点 P0
        # argmin(f, a) 返回使得 f(a[i]) 最小的索引 i
        p0_point = argmin(p -> (p[2], p[1]), points)
        p0_index = findfirst(p -> isapprox(p[1], p0_point[1]) && isapprox(p[2], p0_point[2]), points)

        # 将最低点放到数组的开头
        points[1], points[p0_index] = points[p0_index], points[1]
        
        p0_point = points[1]

        # 2. 对其他点按极角排序
        # 使用 atan 来排序，这在你提供的函数中是正确的
        sorted_points = sort(points[2:end], by = item -> atan(item[2] - p0_point[2], item[1] - p0_point[1]))

        # 将排序后的点放回到原始数组中
        @inbounds for i in 1:length(sorted_points)
            points[i+1] = sorted_points[i]
        end

        # 3. 初始化栈（这里用 points 数组的前缀来模拟）
        # 第一个点总是凸包的一部分
        hull_points = Point[points[1]]

        # 4. 遍历剩下的点，构建凸包
        for i in 2:N
            # 移除栈顶的右转点
            while length(hull_points) >= 2 && ccw(hull_points[end-1], hull_points[end], points[i]) <= 0
                pop!(hull_points)
            end
            push!(hull_points, points[i])
        end

        return hull_points
    end
    function get_shadow_boundary_polar(projected_points; step_deg=1, overlap_deg=1.5)
        function cartesian_to_polar(x, y)
            r = sqrt(x^2 + y^2)
            theta = atan(y, x)
            if theta < 0
                theta += 2 * pi
            end
            return r, theta
        end

        # 1. 坐标转换并按角度排序
        polar_points = [cartesian_to_polar(p[1], p[2]) for p in projected_points]
        sort!(polar_points, by=p -> p[2])
        num_points = length(polar_points)

        # 2. 创建角度网格和数据结构
        step_rad = deg2rad(step_deg)
        overlap_rad = deg2rad(overlap_deg)
        num_steps = round(Int, 360 / step_deg)
        theta_grid = range(0, 2pi - step_rad, length=num_steps)
        
        r_max_data = zeros(num_steps)
        r_min_data = fill(Inf, num_steps)

        # 3. 遍历点，更新网格数据
        # 这里我们遍历所有点，并根据每个点更新它影响到的所有网格
        for (r, theta) in polar_points
            # 找到点所在的中心网格索引
            base_idx = floor(Int, theta / step_rad) + 1

            # 计算这个点的影响范围（窗口）
            window_start_rad = theta - overlap_rad
            window_end_rad = theta + overlap_rad
            
            # 找到影响范围内的起始和结束网格索引
            start_idx = floor(Int, window_start_rad / step_rad) + 1
            end_idx = floor(Int, window_end_rad / step_rad) + 1

            # 遍历影响范围内的网格并更新
            @inbounds for j in start_idx:end_idx
                # 处理索引越界和循环
                idx = mod(j - 1, num_steps) + 1
                
                r_max_data[idx] = max(r_max_data[idx], r)
                r_min_data[idx] = min(r_min_data[idx], r)
            end
        end

        # 4. 构建轮廓
        final_theta_min = theta_grid[r_min_data .!= Inf]
        final_r_min = r_min_data[r_min_data .!= Inf]
        
        outer_boundary = [Point2f(r * cos(t), r * sin(t)) for (r, t) in zip(r_max_data, theta_grid)]
        inner_boundary = [Point2f(r * cos(t), r * sin(t)) for (r, t) in zip(final_r_min, final_theta_min)]

        return outer_boundary, inner_boundary
    end
    # v_range = [(v1,v2)...etc]
    # 制作一个基于v和角度变化范围的掩码函数用于程序的遮掩
    # local v1 = ion_energy2v.(range_data[:energy],range_data[:m_int])
    # local v2 = ion_energy2v.(range_data[:energy] .+ range_data[:denergy],range_data[:m_int])
    local v1 = ion_energy2v.(range_data[:energy],range_data[:m_int])
    local v2 = ion_energy2v.(range_data[:energy] .+ range_data[:denergy],range_data[:m_int])

    local v_max = maximum(v2)
    local v_range = [(x1,x2) for (x1, x2) in zip(v1,v2)]
    local t_range = [(x1,x2) for (x1, x2) in zip(
        range_data[:theta] .- range_data[:dtheta]./2,
        range_data[:theta] .+ range_data[:dtheta]./2
        )]
    local p_range = [(x1,x2) for (x1, x2) in zip(
        range_data[:phi] .- range_data[:dphi]./2,
        range_data[:phi] .+ range_data[:dphi]./2
        )]

    local inds = eachindex(v_range)

    local ponits_all = [] # 所有体积元的顶点
    # print("计算顶点")
    @inbounds @showprogress desc="Computing boundray..." for i in inds
        local ponits_dV = [] # 同一个体积元的所有顶点
        local tris = get_triangle_mesh(v_range[i], t_range[i], p_range[i])
        for tri in tris
            local v1_xyz = rotate_func(tri[1]; translation_vector=vsc, rot=rot)
            local v2_xyz = rotate_func(tri[2]; translation_vector=vsc, rot=rot)
            local v3_xyz = rotate_func(tri[3]; translation_vector=vsc, rot=rot)
            push!(ponits_dV, v1_xyz)
            push!(ponits_dV, v2_xyz)
            push!(ponits_dV, v3_xyz)
        end
        # ponits_dV = graham_scan(ponits_dV)
        for i in ponits_dV
            push!(ponits_all, i)
        end
    end
    ponits_all1,ponits_all2 = get_shadow_boundary_polar(ponits_all)
    # scatter!(ax, ponits_all; color=:black, markersize=3)
    # scatter!(ax, ponits_all1; color=:red, markersize=3)
    # lines!(ax,ponits_all1,color=:red)
    # scatter!(ax, ponits_all2; color=:red, markersize=3)
    poly!(ax, Polygon(decompose(Point2f, Circle(Point2f(0), v_max * 2)), [decompose(Point2f, ponits_all1)]); color=backgroundcolor)
    poly!(ax, Polygon(decompose(Point2f, ponits_all2)); color=backgroundcolor)
    
    return ax
end
function SWEA_PAD_heatmap(ax, time, pa, eflux; c_range=(1e4, 1e10))
    ntime = length(time)
    for i = 1:3:ntime-3
        heatmap!(ax, time[i:i+3], pa[i, :], eflux[i:i+3, :], colormap=:viridis, colorscale=log10, colorrange=c_range, overdraw=true)
    end
    return ax
end
function WaveSpectra_heatmap(ax, time, freq, data; c_range=(1e-14, 1e-9),f_range = (1,1e5)) #强制绘制为对数轴
    ax.yscale = identity
    f_range_log = log10.(f_range)
    ylims!(ax,f_range_log)
    tick_func = x -> rich("10",superscript("$(round(x))"))
    num_list = 0:10
    x_i = num_list
    ticks = [tick_func(x) for x in num_list]
    ax.yticks = (x_i,ticks)
    x, y, c = time, log10.(freq), data
    nc = size(c)
    nx = nc[1]
    ny = nc[2]
    x = repeat(x, ny)
    x = reshape(x, nx, ny)
    x = vec(x)
    y = vec(y)
    c = vec(c)
    y[y.<0] .= 0
    df = DataFrame(X=x, Y=y, C=c)
    df_unique = unique(df, [:X, :Y])
    x = df_unique.X
    y = df_unique.Y
    c = df_unique.C
    bools = y .>= f_range_log[1] .&& y .<= f_range_log[2]
    heatmap!(ax, x[bools], y[bools], c[bools], colormap=:viridis, colorscale=log10, colorrange=c_range, overdraw=true)
    return ax
end
function Orbit(ax;pos_ss=[], shadowed=true, frame="x-yz",line_krawg_bow=Dict(:linestyle=>:dash,:linewidth=>3),line_krawg_mag=Dict(:linestyle=>:dash,:linewidth=>3),line_krawg_sc =Dict(:linestyle=>:solid,:linewidth=>3,:color=>:green))
    #绘制半球
    if shadowed
        theta = LinRange(pi, 2pi, 100)
        x = sin.(theta)
        y = cos.(theta)
        half_circle = [Point2f(x[i], y[i]) for i in eachindex(x)]
        lines!(ax, Circle(Point2f(0, 0), 1), color=:black, linewidth=3)
        poly!(ax, half_circle, color=:black)
    else
        lines!(ax, Circle(Point2f(0, 0), 1), color=:black, linewidth=3)
        lines!(ax, [Point2f(0, 1),Point2f(0, -1)], color=:black,linewidth=3)
    end
    if frame == "x-yz"
        func_trans = (x,y,z) -> Point2f(x/ Rm,sqrt(y ^2 + z ^ 2)/ Rm)
    elseif frame == "x-y"
        func_trans = (x,y,z) -> Point2f(x / Rm,y / Rm)
    elseif frame == "x-z"
        func_trans = (x,y,z) -> Point2f(x / Rm,z / Rm)
    end

    if pos_ss != []
        trace_points = func_trans.(pos_ss[:,1], pos_ss[:,2], pos_ss[:,3])
        lines!(ax, trace_points; label="Orbit", overdraw=true,line_krawg_sc...)
    end

    # bowshock
    x = -10:0.005:2
    yb = bowshock.(x)
    ym = magnetopause.(x)
    x1 = vcat(x, reverse(x))
    yb1 = vcat(yb, reverse(-yb))
    ym1 = vcat(ym, reverse(-ym))
    lines!(ax, x1, yb1; line_krawg_bow...)#label="bowshock"
    # magnetopause
    lines!(ax, x1, ym1; line_krawg_mag...)#label="magnetopause",
    return ax,func_trans
end
function PAD_slice(ax, pa, energy, eflux; potential=0.0, xlimit=(0, 180), ylimit=(1e-17, 1e-11), xlabel="pitch angle", ylabel="PSD", n=4)
    colormap = :viridis  # 可以选择任何Makie支持的颜色图
    n_colors = length(energy)
    colors = resample_cmap(colormap, n_colors)
    ax.limits = (xlimit, ylimit)
    ax.ylabel = ylabel
    ax.xlabel = xlabel
    ax.yscale = log10
    energy_t = energy .- potential
    for (index, e) in enumerate(energy_t)
        y = eflux[:, index]
        indext = findall(a -> a >= 1e-5, y)
        y = y[indext]
        x = pa[:, index]
        x = x[indext]
        color = colors[index]
        for (i_yy, yy) in enumerate(y)
            y[i_yy] = eflux2F.(e, yy)
        end
        scatter!(ax, x, y, label=string(round.(e, digits=1)), color=color)
        coefficients = polynomial_fit(x, y, n)
        # if length(x) >= 2
        # xfit=minimum(x):1:maximum(x)
        # else
        xfit = 0:1:180
        # end
        fitted_y = exp.(Vandermonde(xfit, n) * coefficients)
        lines!(ax, xfit, fitted_y, color=color)
    end
end
function PAD_slice_polar(ax, pa, energy, eflux; potential=0.0, ylimit=(0, 200), xlimit=(-200, 200), xlabel="Ek_para [eV]", ylabel="Ek_prep [eV]", c_range=(1e-17, 1e-11))
    colormap = :viridis  # 可以选择任何Makie支持的颜色图
    n_colors = 256
    colors = resample_cmap(colormap, n_colors)

    ax.limits = (xlimit, ylimit)
    ax.ylabel = ylabel
    ax.xlabel = xlabel
    ax.ytickformat = "{:.1f}"
    ax.xtickformat = "{:.1f}"
    energy_t = energy .- potential
    PSD = zeros(length(pa[:, 1]), length(energy))
    Ek_perp = zeros(length(pa[:, 1]), length(energy))
    Ek_par = zeros(length(pa[:, 1]), length(energy))
    Ek0 = energy_t .* 1.0
    for i = 1:length(pa[:, 1])
        PSD[i, :] = eflux2F.(energy_t[:], eflux[i, :])
        Ek_perp[i, :] = Ek0 .* sind.(pa[i, :])
        Ek_par[i, :] = Ek0 .* cosd.(pa[i, :])
    end

    LPSD_range = log10.(c_range)
    LPSD = log10.(PSD)
    println(minimum(LPSD))
    levels = (1:256) ./ 256 .* (maximum(LPSD_range) - minimum(LPSD_range)) .+ minimum(LPSD_range)
    rr = Ek0[:]
    for j = 1:length(rr)-1
        psi = pa[:, j]

        local_color_index = []
        for value in LPSD[:, j]
            index = findmin(abs.(levels .- value))[2]
            push!(local_color_index, index)
        end

        nan_index = findall(x -> x == -Inf, LPSD[:, j])
        local_colors = colors[local_color_index]
        local_colors[nan_index] .= RGBA{Float32}(1, 1, 1, 1)

        extended_psi = [0; psi; 180]
        part_sizes = [(extended_psi[i+1] - extended_psi[i-1]) / 2 for i = 2:length(extended_psi)-1]
        part_sizes[1] = part_sizes[1] + psi[1] / 2
        part_sizes[end] = part_sizes[end] + (180 - psi[end]) / 2

        pie!(ax, part_sizes .* RAD, inner_radius=rr[j], radius=rr[j+1], strokewidth=0, color=local_colors, overdraw=true, normalize=false)
    end
    return ax
end
function PAD_slice_velocity(ax, pa, energy, eflux; potential=0.0, xlimit=(-1.5e7, 1.5e7), ylimit=(0, 1.5e7), xlabel="v_para [m/s]", ylabel="v_prep [m/s]", c_range=(1e-17, 1e-11))
    colormap = :viridis  # 可以选择任何Makie支持的颜色图
    n_colors = 256
    colors = resample_cmap(colormap, n_colors)

    ax.limits = (xlimit, ylimit)
    ax.ylabel = ylabel
    ax.xlabel = xlabel
    ax.ytickformat = "{:.1e}"
    ax.xtickformat = "{:.1e}"
    energy_t = energy .- potential
    PSD = zeros(length(pa[:, 1]), length(energy))
    v_perp = zeros(length(pa[:, 1]), length(energy))
    v_par = zeros(length(pa[:, 1]), length(energy))
    v0 = sqrt.(2 * energy_t ./ me .* EV)
    for i = 1:length(pa[:, 1])
        PSD[i, :] = eflux2F.(energy_t[:], eflux[i, :])
        v_perp[i, :] = v0 .* sind.(pa[i, :])
        v_par[i, :] = v0 .* cosd.(pa[i, :])
    end

    #
    LPSD_range = log10.(c_range)
    LPSD = log10.(PSD)
    println(minimum(LPSD))
    levels = (1:256) ./ 256 .* (maximum(LPSD_range) - minimum(LPSD_range)) .+ minimum(LPSD_range)
    rr = v0[:]
    for j = 1:length(rr)-1
        psi = pa[:, j]

        local_color_index = []
        for value in LPSD[:, j]
            index = findmin(abs.(levels .- value))[2]
            push!(local_color_index, index)
        end

        nan_index = findall(x -> x == -Inf, LPSD[:, j])
        local_colors = colors[local_color_index]
        local_colors[nan_index] .= RGBA{Float32}(1, 1, 1, 1)

        extended_psi = [0; psi; 180]
        part_sizes = [(extended_psi[i+1] - extended_psi[i-1]) / 2 for i = 2:length(extended_psi)-1]
        part_sizes[1] = part_sizes[1] + psi[1] / 2
        part_sizes[end] = part_sizes[end] + (180 - psi[end]) / 2

        pie!(ax, part_sizes .* RAD, inner_radius=rr[j], radius=rr[j+1], strokewidth=0, color=local_colors, overdraw=true, normalize=false)
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
    # scatter!(ax, x,y, colormap=:viridis, color = c , colorrange=c_range , colorscale=log10)
    # itp = interpolate((x,y),c,Gridded(Linear()))
    # v_para_gridded = [-1.5e7:1e5:1.5e7;]
    # v_perp_gridded = [0:1e5:1.5e7;]
    # c_interp = zeros(length(v_para_gridded),length(v_perp_gridded))
    # for i = 1:length(v_para_gridded)
    #     for j = 1:length(v_perp_gridded)
    #         c_interp[i,j] = itp(v_para_gridded[i],v_perp_gridded[j])
    #     end
    # end
    # heatmap!(ax, v_para_gridded,v_perp_gridded,c_interp, colormap=:viridis, colorrange=c_range , colorscale=log10)
    return ax
end
function time2x(time, range;t0 = 0.0,convert = true) # 将时间转为unix时间戳并且range限制时间范围
    if convert
        range_data = range
        time_i = findall(t -> range_data[1] <= t <= range_data[2], time)
        x = time[time_i]
        x = Dates.datetime2unix.(x)
    else
        range_data = Dates.datetime2unix.(range)
        time_i = findall(t -> range_data[1] <= t <= range_data[2], time)
        x = time[time_i]
    end
    x = x .- t0
    return x, time_i
end
function time_ticks(time_range; step=Dates.Minute(20), format="HH:MM:SS",model = "unix",t0 = 0.0) # 取得time_range 对应步长的时间刻度
    xd = range(time_range[1], time_range[2], step=step)
    if model == "unix"
        x_i = Dates.datetime2unix.(xd)
    elseif model == "julian"
        x_i = Dates.datetime2julian.(xd)
    end
    x_i = x_i .- t0
    xtimes = (x_i,Dates.format.(xd, format))
    return xtimes, x_i
end
function interpolate_x_ticks(xd,x,y;format_func = x -> convert(Int64,round(x;digits=0)),output_func=false)
    """
    interpolate_x_ticks(xd,x,y;format_func = x -> round(x;digits=1) )
    xd: 插值后的x, 对应要替代的原x值
    将y通过插值映射到xd上
    """
    # 初始化结果
    yd = zeros(length(xd))  # 用 0 初始化，表示未插值的点
    #单调区间分解
    function find_monotonic_intervals(x)
        intervals = []
        n = length(x)
        start_idx = 1
        for i in 1:n-2
            # 判断单调性是否改变
            if (x[i+1] - x[i])*(x[i+2] - x[i+1]) < 0
                push!(intervals, start_idx:i+1)
                start_idx = i+1
            end
        end
        push!(intervals, start_idx:n)  # 添加最后一个区间
        return intervals
    end
    intervals = find_monotonic_intervals(x)
    # 对每个单调区间进行插值
    for interval in intervals
        x_interval = x[interval]
        y_interval = y[interval]
        # 找到当前区间中包含的 xd
        xd_in_interval = findall(xdi -> xdi >= minimum(x_interval) && xdi <= maximum(x_interval), xd)
        if isempty(xd_in_interval)
            continue
        end
        sort_xd_in_interval = sortperm(x_interval)
        y_interval = y_interval[sort_xd_in_interval]
        x_interval = x_interval[sort_xd_in_interval]
        if length(x_interval) == 2
            func = LinearInterpolation(y_interval, x_interval)
        else
            func = CubicSpline(y_interval, x_interval)
        end
        yd[xd_in_interval] = func.(xd[xd_in_interval])
    end
    ym = string.(format_func.(yd))
    if output_func
        return (xd,ym),format_func
    end
    return (xd,ym)
end
function logticks(num_list;tick_func = x -> rich("10",superscript("$(round(x))")))
    x_i = 10 .^num_list
    ticks = [tick_func(x) for x in num_list]
    return (x_i,ticks)
end
# function x_ticks(ax, xticks; xticklabelpad=3)
#     ax.xticklabelpad = xticklabelpad
#     hidespines!(ax)
#     hideydecorations!(ax)
#     ax.xticks = xticks
#     return ax
# end
function vector_angle(a, b)
    a1 = normalize(a)
    b1 = normalize(b)
    return acosd(dot(a1, b1))
end
function Vandermonde(x, n)
    return hcat([x .^ i for i in 0:n]...)
end
function polynomial_fit(x, y, n)
    log_y = log.(y)
    mask = .!isnan.(log_y) .& .!isinf.(log_y) # 创建一个布尔掩码,其中x不是NaN的位置为true
    filtered_x = x[mask]
    filtered_y = log_y[mask]

    if length(filtered_y) <= n
        return error("Not enough data for a good fit.")
    end
    V = hcat([filtered_x .^ i for i in 0:n]...)
    coefficients = V \ filtered_y
    return coefficients
end
function eflux2F(energy, eflux)
    M = me
    # E0=M*C^2/EV   #静止能量 eV
    #energy 与 eflux 一一对应
    # E0=M*C^2/EV
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    P = γ * M * β * C        # kg m/s
    # V=β .* C
    F = (γ * M)^3 * eflux / energy * 1e4 / EV / P^2
    return F
end
# Edberg, N. J. T., M. Lester, S. W. H. Cowley, and A. I. Eriksson (2008), Statistical analysis of the location of the Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields, J. Geophys. Res., 113, A08206, doi:10.1029/2008JA013096.
#bow-shock model
function bowshock(xshock)
    xF = 0.55 # R_Mars
    ϵ = 1.05
    L = 2.10 # R_Mars
    rSD = 1.58
    temp = (ϵ^2-1.0)*(xshock-xF)^2-2ϵ*L*(xshock-xF)+L^2
    if temp>=0 
        return sqrt(temp)
    else
        return NaN64
    end
end
#magnetopause model
function magnetopause(xmp)
    rSD = 1.33
	xF = 0.86
	ϵ = 0.92
	L = 0.90
    temp = (ϵ^2-1.0)*(xmp-xF)^2-2ϵ*L*(xmp-xF)+L^2
    if temp>=0 
        return sqrt(temp)
    else
        return NaN64
    end
end

end