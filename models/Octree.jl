using GLMakie
using GeometryBasics

# 八叉树节点和构建函数 (与上一个回答中的代码相同)
mutable struct OctreeNode
    center::Vector{Float64}
    half_size::Float64
    is_leaf::Bool
    is_inside::Bool
    children::Vector{OctreeNode}
    
    function OctreeNode(center::Vector{Float64}, half_size::Float64)
        new(center, half_size, false, false, Vector{OctreeNode}())
    end
end

function build_octree!(node::OctreeNode, is_inside::Function, ϵ::Float64)
    # 获取节点的八个顶点
    corners = [
        node.center + [-node.half_size, -node.half_size, -node.half_size],
        node.center + [ node.half_size, -node.half_size, -node.half_size],
        node.center + [-node.half_size,  node.half_size, -node.half_size],
        node.center + [ node.half_size,  node.half_size, -node.half_size],
        node.center + [-node.half_size, -node.half_size,  node.half_size],
        node.center + [ node.half_size, -node.half_size,  node.half_size],
        node.center + [-node.half_size,  node.half_size,  node.half_size],
        node.center + [ node.half_size,  node.half_size,  node.half_size],
    ]

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

function get_min_bounding_box(is_inside::Function, ϵ::Float64, 
                                initial_center::Vector{Float64}, initial_size::Float64)
    root = OctreeNode(initial_center, initial_size / 2)
    build_octree!(root, is_inside, ϵ)
    
    boundary_centers = Vector{Vector{Float64}}()
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
        return [initial_center[1] - initial_size / 2, initial_center[1] + initial_size / 2,
                initial_center[2] - initial_size / 2, initial_center[2] + initial_size / 2,
                initial_center[3] - initial_size / 2, initial_center[3] + initial_size / 2]
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
    
    return [min_x, max_x, min_y, max_y, min_z, max_z]
end


# --- 验证部分 ---

# 1. 定义球体
function is_sphere(x, y, z)
    return x^2 + y^2 + z^2 <= 1.0
end

initial_center = [0.0, 0.0, 0.0]
initial_size = 2.0
epsilon = 0.05

# 2. 找到边界立方体
bbox = get_min_bounding_box(is_sphere, epsilon, initial_center, initial_size)

println("计算得到的边界框 (x, y, z):")
println("x: [", bbox[1], ", ", bbox[2], "]")
println("y: [", bbox[3], ", ", bbox[4], "]")
println("z: [", bbox[5], ", ", bbox[6], "]")

# 3. 可视化
fig = Figure()
ax = Axis3(fig[1, 1])

# 绘制球体
sphere = Sphere(Point3f(0,0,0), 1)
mesh!(ax, sphere, color = (:dodgerblue, 0.5), shading = false)

# 绘制边界立方体
min_p = Point3f(bbox[1], bbox[3], bbox[5])
max_p = Point3f(bbox[2], bbox[4], bbox[6])

# 获取立方体的所有顶点
v1 = min_p
v2 = Point3f(max_p[1], min_p[2], min_p[3])
v3 = Point3f(max_p[1], max_p[2], min_p[3])
v4 = Point3f(min_p[1], max_p[2], min_p[3])
v5 = Point3f(min_p[1], min_p[2], max_p[3])
v6 = Point3f(max_p[1], min_p[2], max_p[3])
v7 = max_p
v8 = Point3f(min_p[1], max_p[2], max_p[3])

# 定义立方体的边
edges = [
    (v1, v2), (v2, v3), (v3, v4), (v4, v1),
    (v5, v6), (v6, v7), (v7, v8), (v8, v5),
    (v1, v5), (v2, v6), (v3, v7), (v4, v8)
]

# 绘制立方体的线框
linesegments!(ax, edges, color = :red, linewidth = 2)

fig