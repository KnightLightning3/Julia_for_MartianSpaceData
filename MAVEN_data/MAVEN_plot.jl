"""MAVEN 科学数据的绘图工具与常用图形构造函数。"""

module MAVEN_plot
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
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
# -------------------------Export parts-------------------------
export sta_heatmap, STA_2d_slip, SWEA_PAD_heatmap, WaveSpactra_heatmap, Orbit, PAD_slice, PAD_slice_polar, PAD_slice_velocity
export time2x, time_ticks, x_ticks
"""
    vspan_plot(ax, x, y::Vector{Bool}; krawg...) -> Axis

根据布尔时间序列在坐标轴上绘制区间色带。

# 功能与算法概述
提取 `y` 中连续 `true` 段，用 `vspan!` 以半透明色带标出这些时间区间。

# 参数说明
- `ax`: Makie 坐标轴。
- `x`: 横坐标（时间或数值）。
- `y::Vector{Bool}`: 逐点布尔掩膜。
- `krawg...`: 透传给 `vspan!` 的关键字参数。

# 返回值
- `Axis`: 传入的坐标轴。
"""
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
"""
    sta_heatmap_test(ax, sta_data; unit="eflux", c_range=(1e4,1e10), colormap=:viridis, colorscale=log10, overdraw=true, sc_correction=false, krawg...) -> Axis

从 STATIC 数据字典绘制能量分布热图。

# 功能与算法概述
按 `swp_ind` 分组，对每组能量网格绘制 `eflux` 热图；`unit=="flux"` 时按能量归一化。

# 参数说明
- `ax`: Makie 坐标轴。
- `sta_data`: STATIC 数据字典（需含 `:swp_ind`、`:epoch`、`:eflux`、`:energy`、`:sc_pot`）。
- `unit`: `"eflux"` 或 `"flux"`。
- `c_range` / `colormap` / `colorscale` / `overdraw`: 配色与绘制参数。
- `sc_correction`: 是否按航天器电位修正能量。
- `krawg...`: 透传给 `heatmap!`。

# 返回值
- `Axis`: 传入的坐标轴。

# 注意事项
- 函数体引用了未定义的 `x0`、`x_range`、`unique_elements`、`time_i`，当前版本可能无法直接运行。
"""
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
"""
    sta_heatmap(ax, x, y, c, swp_ind; unit="eflux", c_range=(1e4,1e10), colormap=:viridis, colorscale=log10, overdraw=true, sc_correction=false, sc_pot=nothing, krawg...) -> Axis

绘制已准备好的 STATIC 能谱热图数据。

# 功能与算法概述
按 `swp_ind` 分组并把同组内连续时间分段，逐段用 `heatmap!` 绘制；`sc_correction=true` 时
对相邻时刻按 `sc_pot` 修正能量并滤除低能点。

# 参数说明
- `ax`: Makie 坐标轴。
- `x`, `y`, `c`: 横坐标、能量网格与颜色数据。
- `swp_ind`: 各时刻的扫参索引。
- `unit`: `"eflux"` 或 `"flux"`。
- `c_range` / `colormap` / `colorscale` / `overdraw`: 配色与绘制参数。
- `sc_correction` / `sc_pot`: 是否做航天器电位修正及其数值。
- `krawg...`: 透传给 `heatmap!`。

# 返回值
- `Axis`: 传入的坐标轴。
"""
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
#= 原始 IDL 文档（保留供参考）:
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
=#

"""
    STA_2d_slip(ax, dat; frame="xy", vsc=[0,0,0], vbluk=[0,0,0], magf=dat[:magf], colorrange=(1e-12,1e0), angle_range=[-30,30], ylabel="", xlabel="", plot_range=(-120,120), return_rot_matrix=false, energy_range=[0,1e6], colormap=:viridis, show_data=false, backgroundcolor=:gray80)

在指定二维切面上绘制 STATIC 速度分布（df）切片。

# 功能与算法概述
由 `frame` 构造旋转矩阵把速度空间投影到切片平面，筛选 `angle_range` 内的点、
合并重复点并做邻域过滤，再用 Voronoi 图着色绘制；可选叠加磁场方向、体速度标记与数据点。

# 参数说明
- `ax`: Makie 坐标轴。
- `dat`: 速度分布字典（需含 `:df`、`:v`、`:nenergy`、`:nbins`、`:magf`）。
- `frame`: 切片平面（见下）。
- `vsc` / `vbluk`: 航天器速度与体速度（km/s，默认 vbluk 已含 vsc 修正）。
- `magf`: 磁场方向。
- `colorrange` / `colormap` / `angle_range` / `plot_range`: 配色、切片角窗与绘图范围。
- `return_rot_matrix`: 是否额外返回旋转矩阵。
- `energy_range` / `show_data` / `backgroundcolor`: 能量窗、是否显示散点与背景色。

# 返回值
- `Axis`；`return_rot_matrix=true` 时返回 `(Axis, rot)`。

# 注意事项
- `frame` 取 `"xy"`/`"xz"`/`"yz"`（笛卡尔）；或依赖磁场方向：`"bv"`、`"be"`、`"perp"`、`"perp_xy"`、`"perp_xz"`、`"perp_yz"`（大小写不敏感）。
"""
function STA_2d_slip(ax, dat; frame="xy", vsc=[0, 0, 0], vbluk=[0, 0, 0],magf=dat[:magf], colorrange=(1e-12, 1e0), angle_range=[-30, 30], ylabel="", xlabel="", plot_range=(-120, 120), return_rot_matrix=false, energy_range=[0, 1e6], colormap=:viridis, show_data=false,backgroundcolor = :gray80)
    """
        remove_repeat_points(x, y, z, c; angle=[-30,30]) -> (Vector, Vector, Vector)

    合并 `(x,y)` 重复点并对重复点的颜色取平均，先按 `angle` 筛选切片角范围。

    # 参数说明
    - `x`, `y`, `z`: 投影坐标。
    - `c`: 颜色（df）值。
    - `angle`: 切片角窗 `[lo, hi]`（度）。

    # 返回值
    - `(new_x, new_y, new_c)`: 去重后的坐标与平均值。
    """
    function remove_repeat_points(x, y, z, c; angle=[-30, 30])
        points = [x y c]
        theta_xy = [asind(zi / hypot(xi, yi, zi)) for (xi, yi, zi) in eachrow([x y z])]
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
    """
        filter_points_optimized(x, y, c, r) -> (Vector, Vector, Vector)

    去除无效点：若无效点邻域半径 `r` 内存在有效点则剔除之。

    # 参数说明
    - `x`, `y`, `c`: 坐标与颜色（`1e-20` 视为无效）。
    - `r`: 邻域半径。

    # 返回值
    - `(x, y, c)`: 过滤后的子集。
    """
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
    """
        color_mapping(vars, color_range; scaler=nothing) -> Vector{Int}

    把数值按 `color_range` 线性映射到 1–256 的颜色索引。

    # 参数说明
    - `vars`: 待映射数值。
    - `color_range`: 色标范围。
    - `scaler`: `"log10"` 时先取对数。

    # 返回值
    - `Vector{Int}`: 颜色索引（截断到 1–256）。
    """
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
    """
        slice2d_cal_rot(v1, v2) -> Matrix{Float64}

    由两方向向量构造右手正交基并求其逆矩阵作为旋转矩阵。

    # 参数说明
    - `v1`, `v2`: 切片平面的两个参考方向。

    # 返回值
    - `Matrix{Float64}`: 3×3 旋转矩阵。
    """
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
"""
    VDF_2d_slip(ax, velocity, data; normal_vectors=[[1,0,0],[0,1,0]], vbluk=[0,0,0], magf=[1,0,0], vsc=[0,0,0], colorrange=(1e-12,1e0), angle_range=[-30,30], r_range_rate=0.1, ylabel="", xlabel="", plot_range=(-120,120), return_rot_matrix=false, colormap=:viridis, show_data=false, backgroundcolor=:gray80)

把任意三维速度分布投影到指定二维切面绘制。

# 功能与算法概述
把速度平移到以航天器速度为中心后，用两法向向量构造旋转矩阵投影，筛选角窗内的点、
合并重复点并做邻域过滤，再用 Voronoi 图着色；`return_rot_matrix=true` 时额外返回掩膜。

# 参数说明
- `ax`: Makie 坐标轴。
- `velocity`: `n×3` 速度数组。
- `data`: 与速度对应的分布值。
- `normal_vectors`: 定义切片平面的两个法向向量。
- `vbluk` / `magf` / `vsc`: 体速度、磁场与航天器速度。
- `colorrange` / `colormap` / `angle_range` / `plot_range`: 配色、切片角窗与绘图范围。
- `r_range_rate`: 垂直方向切片宽度比例。
- `return_rot_matrix` / `show_data` / `backgroundcolor`: 返回矩阵、散点显示与背景色。

# 返回值
- `Axis`；`return_rot_matrix=true` 时返回 `(Axis, rot, ind_mask)`。
"""
function VDF_2d_slip(ax,velocity, data; 
    normal_vectors=[[1,0,0],[0,1,0]],vbluk=[0, 0, 0],magf=[1,0,0], vsc=[0,0,0],colorrange=(1e-12, 1e0), 
    angle_range=[-30, 30], # 角度范围的切法 
    r_range_rate = 0.1, # 垂直方向的切法
    ylabel="", xlabel="", plot_range=(-120, 120), return_rot_matrix=false, colormap=:viridis,show_data=false,backgroundcolor = :gray80)
    #绘制任何3d空间分布的饼状图，必需要满足： data为一维或多维数据,速度必须为n*3的格式
    """
        remove_repeat_points(x, y, z, c; angle=[-30,30], r_range=10) -> (Vector, Vector, Vector, Vector{Bool})

    合并投影点并对重复点颜色取平均，返回角窗掩膜 `ind`。

    # 参数说明
    - `x`, `y`, `z`: 投影坐标。
    - `c`: 颜色（df）值。
    - `angle`: 切片角窗 `[lo, hi]`（度）。
    - `r_range`: 垂直方向范围（当前未启用）。

    # 返回值
    - `(new_x, new_y, new_c, ind)`: 去重后的坐标、均值与筛选掩膜。
    """
    function remove_repeat_points(x, y, z, c; angle=[-30, 30],r_range = 10)
        points = [x y c]
        theta_xy = [asind(zi / hypot(xi, yi, zi)) for (xi, yi, zi) in eachrow([x y z])]
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
    """
        filter_points_optimized(x, y, c, r) -> (Vector, Vector, Vector)

    去除无效点：若无效点邻域半径 `r` 内存在有效点则剔除之。

    # 参数说明
    - `x`, `y`, `c`: 坐标与颜色（`1e-20` 视为无效）。
    - `r`: 邻域半径。

    # 返回值
    - `(x, y, c)`: 过滤后的子集。
    """
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
    """
        color_mapping(vars, color_range; scaler=nothing) -> Vector{Int}

    把数值按 `color_range` 线性映射到 1–256 的颜色索引。

    # 参数说明
    - `vars`: 待映射数值。
    - `color_range`: 色标范围。
    - `scaler`: `"log10"` 时先取对数。

    # 返回值
    - `Vector{Int}`: 颜色索引（截断到 1–256）。
    """
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
    """
        slice2d_cal_rot(v1, v2) -> Matrix{Float64}

    由两方向向量构造右手正交基并求其逆矩阵作为旋转矩阵。

    # 参数说明
    - `v1`, `v2`: 切片平面的两个参考方向。

    # 返回值
    - `Matrix{Float64}`: 3×3 旋转矩阵。
    """
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
"""
    VDF_2d_mask(ax, range_data; rot=rot, vsc=vsc, backgroundcolor=:gray80) -> Axis

绘制速度范围遮罩与投影边界。

# 功能与算法概述
把各体积元的球坐标范围细分为三角网格，逐点平移旋转投影到绘图平面，
用极坐标分格统计内外边界后以 `poly!` 遮罩超出可测速度范围的区域。

# 参数说明
- `ax`: Makie 坐标轴。
- `range_data`: 含 `:energy`、`:denergy`、`:theta`、`:dtheta`、`:phi`、`:dphi`、`:m_int` 的范围字典。
- `rot` / `vsc`: 旋转矩阵与航天器速度平移。
- `backgroundcolor`: 遮罩颜色。

# 返回值
- `Axis`: 传入的坐标轴。
"""
function VDF_2d_mask(ax,range_data;rot=rot,vsc=vsc,backgroundcolor=:gray80)
    """
        get_triangle_mesh(r_bounds, theta_bounds, phi_bounds; n_steps=12) -> Vector{Vector{Point3f}}

    按球坐标范围生成三角网格面片。

    # 参数说明
    - `r_bounds`, `theta_bounds`, `phi_bounds`: 半径、天顶角、方位角范围 `(lo, hi)`。
    - `n_steps`: 角度细分步数。

    # 返回值
    - 三角形顶点列表（每个元素为 3 个 `Point3f`）。
    """
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
    """
        rotate_func(p; translation_vector=0, rot=0) -> Point2f

    将球坐标点平移、旋转并投影到绘图平面。

    # 参数说明
    - `p`: 球坐标点 `(r, θ, ϕ)`（θ、ϕ 单位为度）。
    - `translation_vector`: 平移向量。
    - `rot`: 旋转矩阵。

    # 返回值
    - `Point2f`: 投影到 `(x, y)` 平面的点。
    """
    function rotate_func(p; translation_vector=0,rot=0) # 转为xyz坐标系
        r, θ, ϕ = p[1], p[2], p[3]
        ct = cosd(θ)
        x = r * ct *  cosd(ϕ)
        y = r * ct *  sind(ϕ)
        z = r * sind(θ)
        v = rot*([x,y,z] .+ translation_vector)
        return Point2f(v[1], v[2])
    end
    """
        graham_scan(points) -> Vector

    用 Graham 扫描法对投影点集求凸包边界。

    # 参数说明
    - `points`: 二维点列表。

    # 返回值
    - 凸包顶点（逆时针顺序）。
    """
    function graham_scan(points)
        N = length(points)
        if N <= 3
            return points
        end

        # 定义你的 ccw (逆时针) 辅助函数
        """
            ccw(a::Point2f, b::Point2f, c::Point2f) -> Float64

        判断二维三点的转向方向（叉积符号）。

        # 参数说明
        - `a`, `b`, `c`: 三个二维点。

        # 返回值
        - `Float64`: 叉积值，`>0` 为逆时针、`<0` 为顺时针、`=0` 共线。
        """
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
    """
        get_shadow_boundary_polar(projected_points; step_deg=1, overlap_deg=1.5) -> (Vector{Point2f}, Vector{Point2f})

    根据投影点生成极坐标表示的遮挡边界（外边界与内边界）。

    # 功能与算法概述
    把投影点转极坐标后按角度分格，用重叠窗口统计各格半径的最大/最小值，还原为笛卡尔边界点。

    # 参数说明
    - `projected_points`: 投影点集。
    - `step_deg`: 角格步长（度）。
    - `overlap_deg`: 相邻格重叠角（度）。

    # 返回值
    - `(outer_boundary, inner_boundary)`: 外边界与内边界点集。
    """
    function get_shadow_boundary_polar(projected_points; step_deg=1, overlap_deg=1.5)
        """
            cartesian_to_polar(x, y) -> (Float64, Float64)

        将二维笛卡尔坐标转换为极坐标。

        # 参数说明
        - `x`, `y`: 平面坐标。

        # 返回值
        - `(r, θ)`: 半径与角度（θ 归一化到 `[0, 2π)`）。
        """
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
    local v1 = MarsCommon.ion_energy2v.(range_data[:energy], range_data[:m_int]) ./ 1e3
    local v2 = MarsCommon.ion_energy2v.(range_data[:energy] .+ range_data[:denergy], range_data[:m_int]) ./ 1e3

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
"""
    SWEA_PAD_heatmap(ax, time, pa, eflux; c_range=(1e4,1e10)) -> Axis

绘制 SWEA 俯仰角分布随时间变化的热图。

# 功能与算法概述
按时间每 3 点一段逐段用 `heatmap!` 绘制，纵轴为俯仰角、颜色为能量通量（对数色标）。

# 参数说明
- `ax`: Makie 坐标轴。
- `time`: 时间轴。
- `pa`: 俯仰角矩阵（时间为行）。
- `eflux`: 能量通量矩阵。
- `c_range`: 色标范围。

# 返回值
- `Axis`: 传入的坐标轴。
"""
function SWEA_PAD_heatmap(ax, time, pa, eflux; c_range=(1e4, 1e10))
    ntime = length(time)
    for i = 1:3:ntime-3
        heatmap!(ax, time[i:i+3], pa[i, :], eflux[i:i+3, :], colormap=:viridis, colorscale=log10, colorrange=c_range, overdraw=true)
    end
    return ax
end
"""
    WaveSpectra_heatmap(ax, time, freq, data; c_range=(1e-14,1e-9), f_range=(1,1e5)) -> Axis

绘制给定频率范围内的波动功率谱热图（强制对数纵轴）。

# 功能与算法概述
把频率取 `log10` 去重后按 `f_range` 裁剪，用 `heatmap!` 绘制功率谱，纵轴刻度用 `10^n` 标注。

# 参数说明
- `ax`: Makie 坐标轴。
- `time`: 时间轴。
- `freq`: 频率数组。
- `data`: 功率谱矩阵。
- `c_range`: 色标范围。
- `f_range`: 频率显示范围。

# 返回值
- `Axis`: 传入的坐标轴。
"""
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
"""
    Orbit(ax; pos_ss=[], shadowed=true, frame="x-yz", line_krawg_bow=Dict(...), line_krawg_mag=Dict(...), line_krawg_sc=Dict(...)) -> (Axis, Function)

绘制航天器轨道、火星投影及弓形激波/磁层顶边界。

# 功能与算法概述
在给定投影面上绘制火星圆盘（可选半球阴影），把 SS 坐标位置经径向投影为二维轨道线，
并叠加 `bowshock`/`magnetopause` 模型边界。

# 参数说明
- `ax`: Makie 坐标轴。
- `pos_ss`: 航天器 SS 位置数组（`N×3`，单位 km）。
- `shadowed`: 是否绘制夜侧半球阴影。
- `frame`: 投影面 `"x-yz"`（柱对称）、`"x-y"` 或 `"x-z"`。
- `line_krawg_bow` / `line_krawg_mag` / `line_krawg_sc`: 三条线的样式。

# 返回值
- `(Axis, func_trans)`: 坐标轴与所用投影函数。
"""
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
        func_trans = (x,y,z) -> Point2f(x / constants.R_Mars, sqrt(y ^ 2 + z ^ 2) / constants.R_Mars)
    elseif frame == "x-y"
        func_trans = (x,y,z) -> Point2f(x / constants.R_Mars, y / constants.R_Mars)
    elseif frame == "x-z"
        func_trans = (x,y,z) -> Point2f(x / constants.R_Mars, z / constants.R_Mars)
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
"""
    PAD_slice(ax, pa, energy, eflux; potential=0.0, xlimit=(0,180), ylimit=(1e-17,1e-11), xlabel="pitch angle", ylabel="PSD", n=4) -> Nothing

绘制能量分箱下的俯仰角相空间密度切片。

# 功能与算法概述
对每个能道，把方向通量转为 PSD 后散点绘制，并用多项式（Vandermonde 基）拟合出随俯仰角变化的曲线。

# 参数说明
- `ax`: Makie 坐标轴。
- `pa`: 俯仰角矩阵（`npa×nenergy`）。
- `energy`: 能量数组。
- `eflux`: 方向通量矩阵。
- `potential` / `xlimit` / `ylimit` / `xlabel` / `ylabel`: 电位修正、坐标范围与标签。
- `n`: 多项式阶数。

# 返回值
- `Nothing`: 直接绘制到 `ax`。

# 注意事项
- 依赖 `polynomial_fit` 与 `Vandermonde`；对数纵轴。
"""
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
            y[i_yy] = MarsCommon.electron_eflux_to_psd.(e, yy)
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
"""
    PAD_slice_polar(ax, pa, energy, eflux; potential=0.0, ylimit=(0,200), xlimit=(-200,200), xlabel="Ek_para [eV]", ylabel="Ek_prep [eV]", c_range=(1e-17,1e-11)) -> Axis

以极坐标（能量分量）绘制俯仰角分布切片。

# 功能与算法概述
把各能道能量在 `(Ek_para, Ek_prep)` 平面展开为同心圆环，按 PSD 对数色标分段用
`pie!` 绘制，得到二维能量空间中的角分布饼图。

# 参数说明
- `ax`: Makie 坐标轴。
- `pa`: 俯仰角矩阵。
- `energy`: 能量数组。
- `eflux`: 方向通量矩阵。
- `potential` / `xlimit` / `ylimit` / `xlabel` / `ylabel`: 电位修正、坐标范围与标签。
- `c_range`: PSD 色标范围。

# 返回值
- `Axis`: 传入的坐标轴。
"""
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
        PSD[i, :] = MarsCommon.electron_eflux_to_psd.(energy_t[:], eflux[i, :])
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

        pie!(ax, part_sizes .* constants.RAD, inner_radius=rr[j], radius=rr[j+1], strokewidth=0, color=local_colors, overdraw=true, normalize=false)
    end
    return ax
end
"""
    PAD_slice_velocity(ax, pa, energy, eflux; potential=0.0, xlimit=(-1.5e7,1.5e7), ylimit=(0,1.5e7), xlabel="v_para [m/s]", ylabel="v_prep [m/s]", c_range=(1e-17,1e-11)) -> Axis

将俯仰角分布映射到平行/垂直速度平面绘图。

# 功能与算法概述
把各能道速度在 `(v_para, v_prep)` 平面展开为同心圆环，按 PSD 对数色标用 `pie!` 分段绘制。

# 参数说明
- `ax`: Makie 坐标轴。
- `pa`: 俯仰角矩阵。
- `energy`: 能量数组。
- `eflux`: 方向通量矩阵。
- `potential` / `xlimit` / `ylimit` / `xlabel` / `ylabel`: 电位修正、坐标范围与标签。
- `c_range`: PSD 色标范围。

# 返回值
- `Axis`: 传入的坐标轴。
"""
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
    v0 = sqrt.(2 * energy_t ./ constants.me .* constants.eV)
    for i = 1:length(pa[:, 1])
        PSD[i, :] = MarsCommon.electron_eflux_to_psd.(energy_t[:], eflux[i, :])
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

        pie!(ax, part_sizes .* constants.RAD, inner_radius=rr[j], radius=rr[j+1], strokewidth=0, color=local_colors, overdraw=true, normalize=false)
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
"""
    time2x(time, range; t0=0.0, convert=true) -> (Vector{Float64}, Vector{Int})

把时间序列裁剪到指定范围并转为相对 Unix 时间戳。

# 功能与算法概述
按 `range` 筛出时间子集：`convert=true` 时直接转 Unix 时间戳，否则把 `range` 也转为
时间戳后再筛选；最后统一减去偏移 `t0`。

# 参数说明
- `time`: `DateTime` 时间数组。
- `range`: 时间范围（`DateTime` 或 Unix 时间戳，视 `convert`）。
- `t0`: 时间戳偏移。
- `convert`: `range` 是否已是 Unix 时间戳。

# 返回值
- `(x, time_i)`: 相对时间戳数组与所选索引。
"""
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
"""
    time_ticks(time_range; step=Dates.Minute(20), format="HH:MM:SS", model="unix", t0=0.0) -> ((Vector, Vector), Vector)

生成时间范围内以固定步长取样的刻度位置与标签。

# 功能与算法概述
按 `step` 在 `time_range` 内均匀取 `DateTime`，转成 Unix 或 Julian 时间戳并减去 `t0`，
标签按 `format` 格式化。

# 参数说明
- `time_range`: 起止 `DateTime`。
- `step`: 刻度步长。
- `format`: 标签时间格式。
- `model`: `"unix"` 或 `"julian"`。
- `t0`: 时间戳偏移。

# 返回值
- `(xtimes, x_i)`: 刻度 `(位置, 标签)` 与位置数组。
"""
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
"""
    interpolate_x_ticks(xd, x, y; format_func=..., output_func=false)

把 `y` 通过分段插值映射到新的横坐标 `xd` 上，用于把刻度标签映射到非单调的时间轴。

# 功能与算法概述
先把 `x` 拆成单调区间，逐区间用线性（2 点）或三次样条（≥3 点）插值出 `xd` 处的值，
再用 `format_func` 生成字符串标签。

# 参数说明
- `xd`: 目标横坐标（对应要替代的原 `x` 值）。
- `x`, `y`: 原始横坐标与数值。
- `format_func`: 数值到标签字符串的格式化函数。
- `output_func`: 是否额外返回格式化函数。

# 返回值
- `(xd, ym)`；`output_func=true` 时返回 `((xd, ym), format_func)`。

# 注意事项
- 内部辅助 `find_monotonic_intervals` 负责按单调性切分区间。
"""
function interpolate_x_ticks(xd,x,y;format_func = x -> convert(Int64,round(x;digits=0)),output_func=false)
    # 初始化结果
    yd = zeros(length(xd))  # 用 0 初始化，表示未插值的点
    #单调区间分解
    """
        find_monotonic_intervals(x) -> Vector{UnitRange}

    按单调性把数组切分为若干连续区间。

    # 参数说明
    - `x`: 一维数组。

    # 返回值
    - 各单调区间的索引范围列表。
    """
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
"""
    logticks(num_list; tick_func=x->rich("10",superscript("\$(round(x))"))) -> (Vector, Vector)

生成以 10 为底的指数刻度位置与标签。

# 功能与算法概述
位置取 `10 .^ num_list`，标签由 `tick_func` 生成（默认渲染为 `10^n`）。

# 参数说明
- `num_list`: 指数列表。
- `tick_func`: 指数到标签的函数。

# 返回值
- `(x_i, ticks)`: 刻度位置与标签。
"""
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
"""
    vector_angle(a, b) -> Float64

计算两个向量之间的夹角（度）。

# 功能与算法概述
对两向量归一化后取点积的反余弦。

# 参数说明
- `a`, `b`: 输入向量。

# 返回值
- `Float64`: 夹角（度，`0`–`180`）。
"""
function vector_angle(a, b)
    a1 = normalize(a)
    b1 = normalize(b)
    return acosd(dot(a1, b1))
end
"""
    Vandermonde(x, n) -> Matrix{Float64}

构造指定阶数的 Vandermonde 矩阵。

# 功能与算法概述
把 `x` 的 `0:n` 次幂按列拼接成设计矩阵，用于多项式拟合。

# 参数说明
- `x`: 自变量数组。
- `n`: 最高阶数。

# 返回值
- `Matrix{Float64}`: `length(x)×(n+1)` 的 Vandermonde 矩阵。
"""
function Vandermonde(x, n)
    return hcat([x .^ i for i in 0:n]...)
end
"""
    polynomial_fit(x, y, n) -> Vector{Float64}

对 `y` 的对数用 n 阶多项式拟合 `x`。

# 功能与算法概述
先对 `y` 取自然对数并剔除 `NaN`/`Inf`，用 Vandermonde 最小二乘求解系数
（用于拟合指数衰减形式的谱）。

# 参数说明
- `x`: 自变量。
- `y`: 因变量（正值）。
- `n`: 多项式阶数。

# 返回值
- `Vector{Float64}`: `n+1` 个多项式系数。

# 注意事项
- 有效点数不超过 `n` 时抛错。
"""
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
# Edberg, N. J. T., M. Lester, S. W. H. Cowley, and A. I. Eriksson (2008), Statistical analysis of the location of the Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields, J. Geophys. Res., 113, A08206, doi:10.1029/2008JA013096.
#bow-shock model
"""
    bowshock(xshock) -> Float64

返回绘图用弓形激波模型边界（Edberg 2008）的纵坐标。

# 功能与算法概述
按二次型模型 `y = √((ϵ²−1)(x−xF)² − 2ϵL(x−xF) + L²)` 计算；根号内为负时返回 `NaN`。

# 参数说明
- `xshock`: 归一化日下点坐标（`R_Mars`）。

# 返回值
- `Float64`: 边界纵坐标（`R_Mars`）或 `NaN`。
"""
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
"""
    magnetopause(xmp) -> Float64

返回绘图用磁层顶模型边界的纵坐标。

# 功能与算法概述
按二次型模型 `y = √((ϵ²−1)(x−xF)² − 2ϵL(x−xF) + L²)` 计算；根号内为负时返回 `NaN`。

# 参数说明
- `xmp`: 归一化日下点坐标（`R_Mars`）。

# 返回值
- `Float64`: 边界纵坐标（`R_Mars`）或 `NaN`。
"""
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