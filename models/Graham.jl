# 闭包扫描算法
struct Point
    x::Float64
    y::Float64
end
"""
    graham_scan!(points::Vector{Point}) -> Vector{Point}

对二维点集执行 **Graham 扫描（凸包算法）**，**原地**重排 `points` 并返回凸包顶点序列。

# 功能与算法概述
经典 Graham 扫描：以最低点为基准做极角排序，再用单调栈（`ccw` 判转向）剔除凹点得到凸包。

# 参数说明
- `points::Vector{Point}`: 二维点集。**会被原地排序**，调用后原数组的排列已被改变。

# 返回值
- `Vector{Point}`: 凸包顶点序列（逆时针），是 `points` 的前 `M` 个元素的视图副本。

# 注意事项
- 函数带 `!`，会**修改入参**；如需保留原始点集请先 `copy`。
- 算法使用 `atan` 排序，若点集共线可能得到退化的两点"凸包"。
- `Point` 为 `Float64` 二维点结构体，定义于本文件顶部。
"""
function graham_scan!(points::Vector{Point})
    """
        ccw(a::Point, b::Point, c::Point) -> Float64

    计算有向面积形式的**叉积**，用于判定三点 `a → b → c` 的转向（凸包扫描的内层判定）。

    # 功能与算法概述
    二维叉积 `(b−a)×(c−a)`，符号即三点转向（正为逆时针左转、负为顺时针）

    # 参数说明
    - `a`: 起点。
    - `b`: 中间点。
    - `c`: 终点。

    # 返回值
    - `Float64`: 叉积值（两倍三角形有向面积），符号表示转向方向。
    """
    function ccw(a::Point, b::Point, c::Point)
        return ((b.x - a.x)*(c.y - a.y) - (b.y - a.y)*(c.x - a.x))
    end
    N = length(points)

    # Place the lowest point at the start of the array
    sort!(points, by = item -> item.y)

    # Sort all other points according to angle with that point
    other_points = sort(points[2:end], by = item -> atan(item.y - points[1].y,
                                                         item.x - points[1].x))

    # Place points sorted by angle back into points vector
    for i in 1:length(other_points)
        points[i+1] = other_points[i]
    end

    # M will be the point on the hull
    M = 2
    for i = 1:N
        while (ccw(points[M-1], points[M], points[i]) <= 0)
            if (M > 2)
                M -= 1
            # All points are collinear
            elseif (i == N)
                break
            else
                i += 1
            end
        end

        # ccw point found, updating hull and swapping points
        M += 1
        points[i], points[M] = points[M], points[i]
    end

    return points[1:M]
end
"""
    graham_scan_for_orbit(P) -> (Vector{Float64}, Vector{Float64})

从轨道位置序列中提取**二维凸包**，返回可用于绘图的多边形边界点坐标。

# 功能与算法概述
取轨迹矩阵前两列作为二维点集，调用 `graham_scan!` 求凸包后拆回两条坐标向量。

# 参数说明
- `P`: `N×≥2` 的位置矩阵，仅使用前两列。

# 返回值
- `(x_hull, y_hull)`: 两个等长向量，按逆时针顺序给出凸包顶点坐标。

# 注意事项
- 内部对**临时构造的 `points` 数组**做原地排序，不会修改入参 `P`。
- 若轨迹退化为直线或单点，返回的凸包可能只含 1–2 个点。
"""
function graham_scan_for_orbit(P)
    # x = atan.(P_MAVEN[:,2],P_MAVEN[:,1])
    # y = sqrt.(P_MAVEN[:,1].^2 + P_MAVEN[:,2].^2)
    x = P[:,1]
    y = P[:,2]
    points = [Point(x_i,y_i) for (x_i,y_i) in zip(x,y)]
    hull = graham_scan!(points)
    x_hull = [point.x for point in hull]  # 获取所有x坐标
    y_hull = [point.y for point in hull]  # 获取所有y坐标
    
    # x = atan.(P_MAVEN[:,2],P_MAVEN[:,1])
    # y = sqrt.(P_MAVEN[:,1].^2 + P_MAVEN[:,2].^2)
    # points = [Point(x_i,y_i) for (x_i,y_i) in zip(x,y)]
    # hull = graham_scan!(points)
    # x = [point.x for point in hull]  # 获取所有x坐标
    # y = [point.y for point in hull]  # 获取所有y坐标
    # x_hull_s = y .* cos.(x)
    # y_hull_s = y .* sin.(x);
    # x_hull = [x_hull;x_hull_s]
    # y_hull = [y_hull;y_hull_s];
    hull = [x_hull y_hull];
    hull_point2f = [Point2f(x_i,y_i) for (x_i,y_i) in zip(x_hull, y_hull)]
    return hull,hull_point2f
end