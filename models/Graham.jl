# 闭包扫描算法
struct Point
    x::Float64
    y::Float64
end
function graham_scan!(points::Vector{Point})
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