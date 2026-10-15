"""用于空间区域边界表示与快速空间查询的八叉树实现。"""

using GLMakie
using GeometryBasics
using StaticArrays

# 八叉树节点和构建函数 (与上一个回答中的代码相同)
mutable struct OctreeNode
    center::Vector{Float64}
    half_size::Float64
    is_leaf::Bool
    is_inside::Bool
    children::Vector{OctreeNode}
    
    """
        OctreeNode(center::Vector{Float64}, half_size::Float64) -> OctreeNode

    以**中心点**与**半边长**构造一个空的八叉树节点（叶子标志位初始为 `false`，子节点列表为空）。

    # 功能与算法概述
    初始化节点几何字段，并将其标记为非叶子（`is_leaf = false`）、区域内状态待定，同时准备好空的子节点容器。

    # 参数说明
    - `center`: 节点中心的三维坐标（`Vector{Float64}`，长度 3）。
    - `half_size`: 节点**半边长**（立方体边长的一半）。

    # 返回值
    - `OctreeNode`: 新构造的节点对象。

    # 备注
    - 本类型为 `mutable struct`，且 `center` 字段为普通 `Vector`，因此单个节点不是位类型；
      但子节点列表是类型稳定的，避免了抽象容器开销。
    """
    function OctreeNode(center::Vector{Float64}, half_size::Float64)
        new(center, half_size, false, false, Vector{OctreeNode}())
    end
end

"""
    build_octree!(node::OctreeNode, is_inside::Function, ϵ::Float64) -> Nothing

根据区域判定函数**递归细分**八叉树节点，标记哪些节点位于目标区域内部。

# 功能与算法概述
递归细分八叉树：对每个节点检查立方体 8 个顶点的内外状态，全内/全外或已到尺寸下限时停止，否则按八象限递归子节点。

# 参数说明
- `node::OctreeNode`: 当前待处理节点（`center` 为三维坐标、`half_size` 为半边长）。
- `is_inside::Function`: 区域判定函数，签名为 `(x, y, z) -> Bool`，用于判定点是否在目标区域内。
- `ϵ::Float64`: **最小半边长**（分辨率下限）；节点尺寸小于该值即停止细分。

# 返回值
- `Nothing`: 函数通过**原地修改** `node` 及其后代节点的 `is_leaf` / `is_inside` / `children` 字段生效。

# 性能
- 复杂度随细分层数呈指数增长；`ϵ` 越小、边界越复杂，节点数越多。
- 叶子节点数大致与边界面积成正比，适用于不规则区域的快速空间查询。

# 注意事项
- 本函数带 `!`，会**修改入参**节点树。
- 若 `is_inside` 代价高昂，可考虑减少递归深度（增大 `ϵ`）。
"""
function build_octree!(node::OctreeNode, is_inside::Function, ϵ::Float64)
    # 获取节点的八个顶点（定长 8×3，使用静态数组避免堆分配）
    local ctr = node.center
    local hs = node.half_size
    corners = SVector(
        SVector(ctr[1] - hs, ctr[2] - hs, ctr[3] - hs),
        SVector(ctr[1] + hs, ctr[2] - hs, ctr[3] - hs),
        SVector(ctr[1] - hs, ctr[2] + hs, ctr[3] - hs),
        SVector(ctr[1] + hs, ctr[2] + hs, ctr[3] - hs),
        SVector(ctr[1] - hs, ctr[2] - hs, ctr[3] + hs),
        SVector(ctr[1] + hs, ctr[2] - hs, ctr[3] + hs),
        SVector(ctr[1] - hs, ctr[2] + hs, ctr[3] + hs),
        SVector(ctr[1] + hs, ctr[2] + hs, ctr[3] + hs),
    )

    all_inside = all(is_inside(c[1], c[2], c[3]) for c in corners)
    all_outside = !any(is_inside(c[1], c[2], c[3]) for c in corners)

    if node.half_size <= ϵ || all_inside || all_outside
        node.is_leaf = true
        node.is_inside = all_inside
        return
    end

    node.is_leaf = false
    new_half_size = node.half_size / 2
    for i in 1:8
        offset = [
            (i & 1) * 2 - 1,
            (i >> 1 & 1) * 2 - 1,
            (i >> 2 & 1) * 2 - 1
        ] .* new_half_size
        
        child_center = node.center + offset
        child_node = OctreeNode(child_center, new_half_size)
        push!(node.children, child_node)
        
        build_octree!(child_node, is_inside, ϵ)
    end
end

"""
    get_min_bounding_box(is_inside, ϵ, initial_center, initial_size) -> SVector{6}

根据区域判定函数，用八叉树搜索并返回目标的**最小轴对齐包围盒**（AABB）。

# 功能与算法概述
先用八叉树递归细分空间，再收集“紧贴区域外侧”的叶子中心，对其逐维求极值并外扩一个节点尺寸后得到轴对齐包围盒。

# 参数说明
- `is_inside::Function`: 区域判定函数，签名为 `(x, y, z) -> Bool`。
- `ϵ::Float64`: 八叉树细分的最小半边长（分辨率）。
- `initial_center::Vector{Float64}`: 初始立方体中心（长度 3）。
- `initial_size::Float64`: 初始立方体**边长**。

# 返回值
- `SVector{6}`: `(min_x, max_x, min_y, max_y, min_z, max_z)`，即轴对齐包围盒。
  调用方可直接索引 `bbox[1]…bbox[6]`，也可用 `Point3f(bbox[1], bbox[3], bbox[5])` 取角点。

# 注意事项
- 包围盒精度受 `ϵ` 控制：`ϵ` 越小结果越紧致，但建树成本越高。
- 仅在 `is_inside` 能正确区分内外且区域**有界**时有效。
"""
function get_min_bounding_box(is_inside::Function, ϵ::Float64, 
                                initial_center::Vector{Float64}, initial_size::Float64)
    root = OctreeNode(initial_center, initial_size / 2)
    build_octree!(root, is_inside, ϵ)
    
    boundary_centers = Vector{Vector{Float64}}()
    """
        find_boundaries(node::OctreeNode) -> Nothing

    递归收集八叉树中**紧贴区域边界**的叶子节点中心，供 `get_min_bounding_box` 使用。

    # 功能与算法概述
    深度优先遍历八叉树，把“不在区域内但尺寸已达 `ϵ`”的叶子中心收集到闭包捕获的 `boundary_centers`。

    # 参数说明
    - `node::OctreeNode`: 当前遍历到的八叉树节点。

    # 返回值
    - `Nothing`: 结果通过**闭包捕获**的 `boundary_centers` 向量累积返回。

    # 注意事项
    - 内层函数依赖外层 `get_min_bounding_box` 作用域中的 `boundary_centers` 与 `ϵ`，
      不可独立调用。
    """
    function find_boundaries(node)
        if node.is_leaf
            if !node.is_inside && node.half_size <= ϵ
                push!(boundary_centers, node.center)
            end
        else
            for child in node.children
                find_boundaries(child)
            end
        end
    end
    find_boundaries(root)
    
    if isempty(boundary_centers)
        return SVector(initial_center[1] - initial_size / 2, initial_center[1] + initial_size / 2,
                initial_center[2] - initial_size / 2, initial_center[2] + initial_size / 2,
                initial_center[3] - initial_size / 2, initial_center[3] + initial_size / 2)
    end

    min_coords = boundary_centers[1]
    max_coords = boundary_centers[1]
    
    for center in boundary_centers
        min_coords = min.(min_coords, center)
        max_coords = max.(max_coords, center)
    end
    
    min_x = min_coords[1] - root.half_size + ϵ
    max_x = max_coords[1] + root.half_size + ϵ
    min_y = min_coords[2] - root.half_size + ϵ
    max_y = max_coords[2] + root.half_size + ϵ
    min_z = min_coords[3] - root.half_size + ϵ
    max_z = max_coords[3] + root.half_size + ϵ
    
    return SVector(min_x, max_x, min_y, max_y, min_z, max_z)
end


# --- 验证部分 ---

# 1. 定义球体
"""
    is_sphere(x, y, z) -> Bool

判断给定点是否位于**单位球**内（本文件用于验证八叉树的示例区域判定函数）。

# 功能与算法概述
直接比较 `x² + y² + z² ≤ 1`；作为八叉树接口的示例 `is_inside` 谓词。

# 参数说明
- `x`: 点的 X 坐标。
- `y`: 点的 Y 坐标。
- `z`: 点的 Z 坐标。

# 返回值
- `Bool`: `true` 表示点位于单位球内（含球面），否则为 `false`。

# 备注
- 本函数签名与 `build_octree!` / `get_min_bounding_box` 要求的 `is_inside` 回调一致
  `(x, y, z) -> Bool`；传递更复杂的区域时只需替换为同签名的谓词函数。
"""
function is_sphere(x, y, z)
    return x^2 + y^2 + z^2 <= 1.0
end

initial_center = [0.0, 0.0, 0.0]
initial_size = 5.0
epsilon = 0.05

# 2. 找到边界立方体
bbox = get_min_bounding_box(is_sphere, epsilon, initial_center, initial_size)

println("计算得到的边界框 (x, y, z):")
println("x: [", bbox[1], ", ", bbox[2], "]")
println("y: [", bbox[3], ", ", bbox[4], "]")
println("z: [", bbox[5], ", ", bbox[6], "]")

# # 3. 可视化
# fig = Figure()
# ax = Axis3(fig[1, 1])

# # 绘制球体
# sphere = Sphere(Point3f(0,0,0), 1)
# mesh!(ax, sphere, color = (:dodgerblue, 0.5), shading = false)

# # 绘制边界立方体
# min_p = Point3f(bbox[1], bbox[3], bbox[5])
# max_p = Point3f(bbox[2], bbox[4], bbox[6])

# # 获取立方体的所有顶点
# v1 = min_p
# v2 = Point3f(max_p[1], min_p[2], min_p[3])
# v3 = Point3f(max_p[1], max_p[2], min_p[3])
# v4 = Point3f(min_p[1], max_p[2], min_p[3])
# v5 = Point3f(min_p[1], min_p[2], max_p[3])
# v6 = Point3f(max_p[1], min_p[2], max_p[3])
# v7 = max_p
# v8 = Point3f(min_p[1], max_p[2], max_p[3])

# # 定义立方体的边
# edges = [
#     (v1, v2), (v2, v3), (v3, v4), (v4, v1),
#     (v5, v6), (v6, v7), (v7, v8), (v8, v5),
#     (v1, v5), (v2, v6), (v3, v7), (v4, v8)
# ]

# # 绘制立方体的线框
# linesegments!(ax, edges, color = :red, linewidth = 2)

# fig