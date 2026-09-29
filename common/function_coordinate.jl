using LinearAlgebra
using StaticArrays
using Rotations

# 和坐标系变换有关的函数
"""
    slice2d_cal_rot(v1, v2) -> RotMatrix{3}

    根据给定的两个向量 `v1` 和 `v2`，计算构建 **2D 切片局部坐标系** 的 3D 旋转矩阵。

    # 几何原理
    该函数通过 Gram-Schmidt 正交化构建一个右手正交坐标系 \$(\\mathbf{a}, \\mathbf{b}, \\mathbf{c})\$：
    1. **主轴 \$a\$ (局部 X 轴)**：沿 `v1` 方向的单位向量。
    2. **法轴 \$c\$ (局部 Z 轴)**：垂直于 `v1` 与 `v2` 所确定的切片平面的法向量 (\$\\mathbf{a} \\times \\mathbf{v2}\$)。
    3. **辅轴 \$b\$ (局部 Y 轴)**：切片平面内垂直于 \$a\$ 的单位向量 (\$\\mathbf{c} \\times \\mathbf{a}\$)。

    # 返回值
- 返回 `RotMatrix{3}` 旋转矩阵，可直接用于将全局坐标映射到该切片坐标系（使得切片平面落在局部 \$XY\$ 平面上）。
"""
function slice2d_cal_rot(v1, v2)
    # 1. 局部 X 轴：v1 归一化
    a = normalize(v1)
    
    # 2. 局部 Z 轴（法向量）：直接计算 a × v2，节省一次 v2 的 normalize
    cross_av = cross(a, v2)
    norm_c = norm(cross_av)
    
    # 防崩溃保护：如果 v1 与 v2 平行，无法确定唯一切片平面
    if norm_c < 1e-8
        error("v1 与 v2 共线，无法唯一定义切片平面的法向量！")
    end
    c = cross_av / norm_c
    
    # 3. 局部 Y 轴：c × a 必然是单位向量，无需再次 normalize
    b = cross(c, a)
    
    # 4. 零内存分配构造 SMatrix（注意 SMatrix 构造函数按列主序填充）
    # 目标矩阵为 [a b c]'，即第一行为 a，第二行为 b，第三行为 c
    R_static = SMatrix{3,3,Float64,9}(
        a[1], b[1], c[1],  # 第一列
        a[2], b[2], c[2],  # 第二列
        a[3], b[3], c[3]   # 第三列
    )
    
    return RotMatrix(R_static)
end
# using LinearAlgebra
# using StaticArrays

# function generate_non_collinear_vectors()
#     # 1. 随机生成第一个向量 v1 (并归一化)
#     v1 = SVector{3}(normalize(rand(3)))
    
#     # 2. 随机生成第二个向量 v2，并确保它与 v1 非共线
#     v2_raw = SVector{3, Float64}(0.0, 0.0, 0.0)
    
#     # 循环确保叉积的模长大于一个非常小的阈值 (例如 1e-9)
#     # 叉积的模长为 0 意味着 v1 和 v2 共线
#     while norm(cross(v1, v2_raw)) < 1e-9
#         v2_raw = SVector{3}(rand(3))
#     end
    
#     # 3. 归一化 v2
#     v2 = normalize(v2_raw)
    
#     return v1, v2
# end

# # --- 验证示例 ---
# v_a, v_b = generate_non_collinear_vectors()
# slice2d_cal_rot(v_a, v_b)

function rotate_vector_with_Matrix(in_data,Rotation_Matrix) # inv
    out_data = Rotation_Matrix * in_data
    return out_data
end
# function rotate_vector_with_quat(u::AbstractVector, q::QuaternionF64)
#     local q_u = QuaternionF64(0, u[1], u[2], u[3])
#     local q_v = q * q_u * conj(q)
#     return [imag_part(q_v)...]
# end
# function rotate_vector_with_quat_reverse(u::AbstractVector, q::QuaternionF64)
#     local q_u = QuaternionF64(0, u[1], u[2], u[3])
#     local q_v = conj(q) * q_u * q
#     return [imag_part(q_v)...]
# end
function pa_xyz2sphere(p::SVector{3,T}) where T <: Real
    local r = norm(p)
    if iszero(r)
        return SVector{3,T}(zero(T), zero(T), zero(T))
    else
        # theta = get_angle(p,[1,0,0])
        local theta = acosd(p[1]/r)
        local phi = atand(p[3],p[2])
        return SVector{3}(r, theta, phi)
    end
end
function pa_sphere2xyz(p::SVector{3,T}) where T <: Real
    local r, theta_deg, phi_deg = p[1], p[2], p[3]
    if iszero(r)
        return SVector{3,T}(zero(T), zero(T), zero(T))
    else
        local x = r * cosd(theta_deg)
        # 计算 yz 平面上的投影长度 R_yz
        local R_yz = r * sind(theta_deg)
        # 计算 y 和 z
        # 注意: sind(theta) 总是非负的，因为 theta 在 [0°, 180°] 范围内
        local y = R_yz * cosd(phi_deg)
        local z = R_yz * sind(phi_deg)
        return SVector{3}(x,y,z)
    end
end
function STATIC_xyz2sphere(p::SVector{3,T}) where T <: Real
    local x,y,z = p[1],p[2],p[3]
    local r=sqrt(x^2 + y^2 + z^2)
    local theta = 90.0 - acosd(z/r)
    local phi = atand(y, x)
    return SVector{3}(r, theta, phi)
end
function STATIC_sphere2xyz(p::SVector{3,T}) where T <: Real
    local r,θ,ϕ = p[1],p[2],p[3]
    local ct = cosd(θ)
    local x = r * ct *  cosd(ϕ)
    local y = r * ct *  sind(ϕ)
    local z = r * sind(θ)
    return SVector{3}(x,y,z)
end;
function MINPA_sphere2xyz(p::SVector{3,T}) where T <: Real # 转换为仪器坐标系下的情况/ref: https://www.swl.ac.cn/minpa/#/home/overview
    local r,θ,ϕ = p
    local theta = 90.0 - θ #由于数据是视野方向，所以需要反向
    local phi = 360. - ϕ
    local ct = cosd(theta)
    local st = sind(theta)
    local cp = cosd(phi)
    local sp = sind(phi)

    # local x = r * ct * cp
    # local y = r * ct * sp
    # local z = r * st
    local x = r * ct
    local y = -r * st * cp
    local z = -r * st * sp

    return SVector{3}(-x,-y,-z) #反转之匹配速度
end
function MINPA_xyz2sphere(p::SVector{3,T}) where T <: Real # 转换为仪器坐标系下的情况/ref: https://www.swl.ac.cn/minpa/#/home/overview
    local p1 = -p # 反转之一
    local r = norm(p1)
    local st = norm(p[2:3]) / r
    local ct = p1[1] / r
    local r_st = r*st
    local cp = -p1[2]/r_st
    local sp = -p1[3]/r_st
    local θ = atand(st,ct) # 俯仰角
    local ϕ = atand(sp,cp) # 方位角

    local θ = 90.0 - θ #反转回仪器的视野方向
    local ϕ = (360.0 - ϕ) % 360

    return SVector{3}(r,θ,ϕ)
    
end
function bowshock_zero(xshock)
    xF = 0.55 # R_Mars
    ϵ = 1.05
    L = 2.10 # R_Mars
    rSD = 1.58
    temp = (ϵ^2-1.0)*(xshock-xF)^2-2ϵ*L*(xshock-xF)+L^2
    if temp>=0 
        return sqrt(temp)
    else
        return 0.0
    end
end
# include(Package_path * "TW_data/TW_MINPA.jl");import .TW_MINPA; #已经验证反变换的可靠性
# x1,y1,z1 = 1,10,-12
# r,t,p = TW_MINPA.MINPA_xyz2sphere(x1,y1,z1)
# x,y,z = TW_MINPA.MINPA_sphere2xyz(r,t,p)
# @show norm([x,y,z] .- [x1,y1,z1])