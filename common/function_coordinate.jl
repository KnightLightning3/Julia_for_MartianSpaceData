"""通用坐标系转换、向量旋转及球/笛卡尔坐标工具。"""

using LinearAlgebra
using StaticArrays
using Rotations

# 和坐标系变换有关的函数
"""
    slice2d_cal_rot(v1, v2) -> RotMatrix{3}

根据给定的两个向量 `v1`、`v2`，通过 Gram-Schmidt 正交化构造 **2D 切片局部坐标系**的 3D 旋转矩阵。

# 功能与算法概述
用 Gram-Schmidt 正交化构建切片局部坐标系（X 轴沿 `v1`，Z 轴为 `v1 × v2` 的法向，Y 轴由 `c × a` 补齐），并以 `SMatrix` 列主序零分配地组装为 `RotMatrix`。

# 参数说明
- `v1`: 切片平面的第一参考向量（决定局部 X 轴方向），任意长度为 3 的 `AbstractVector`。
- `v2`: 切片平面的第二参考向量，只需与 `v1` 不共线（无需归一化）。

# 返回值
- `RotMatrix{3}`: 旋转矩阵，可将全局坐标映射到该切片坐标系，使切片平面落在局部 `XY` 平面上；
  可与 `QuatRotation`、普通 3×3 矩阵互换使用。

# 注意事项
- `v1` 与 `v2` 共线时会抛出异常，调用方需保证两向量能够张成一个平面。
- 返回矩阵为**正交归一**矩阵，可直接参与 `rotation * vector` 运算。
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

# 四元数向量旋转已统一由 calculate_models.Quaternion_Rot / Quaternion_Rot_reverse 提供
# （基于 Rotations.QuatRotation，替代原先的 Quaternions 实现）。

"""
    pa_xyz2sphere(p::SVector{3,T}) -> SVector{3}

将**笛卡尔向量**转换为**俯仰角球坐标** `(r, theta, phi)`（角度制）。

# 功能与算法概述
`theta` 为与 +X 轴的夹角、`phi` 为 Y-Z 平面内自 +Y 向 +Z 的角度；`r = 0` 时返回零向量以避免 `0/0`。

# 参数说明
- `p::SVector{3,T}`: 待转换的笛卡尔向量 `(x, y, z)`，`T <: Real`。

# 返回值
- `SVector{3}`: `(r, theta, phi)`，角度为**角度制**。
- `SVector{3,T}`: 当 `r == 0` 时返回 `(0, 0, 0)`。

# 备注
- 与 `MINPA_xyz2sphere` 的差异在于**角度定义与量程约定**完全不同，两者不可混用。
"""
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

"""
    pa_sphere2xyz(p::SVector{3,T}) -> SVector{3}

将**俯仰角球坐标** `(r, theta, phi)` 转换为笛卡尔向量，是 `pa_xyz2sphere` 的逆变换。

# 功能与算法概述
`pa_xyz2sphere` 的逆变换：按俯仰角定义展开为 `x`、`R_yz = r·sind(θ)` 与 Y-Z 平面投影；`r = 0` 时返回零向量。

# 参数说明
- `p::SVector{3,T}`: `(r, theta, phi)`，其中 `theta ∈ [0°, 180°]`，`phi` 为 Y-Z 平面内角度。

# 返回值
- `SVector{3}`: 笛卡尔向量 `(x, y, z)`。
- `SVector{3,T}`: 当 `r == 0` 时返回 `(0, 0, 0)`。

# 备注
- 因 `sind(theta) ≥ 0`（`theta` 限定在 `[0°, 180°]`），`x` 的符号由 `cosd(theta)` 唯一决定。
"""
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

"""
    MINPA_sphere2xyz(p::SVector{3,T}) -> SVector{3}

将**天问一号 MINPA 仪器坐标系**的球坐标 `(r, θ, ϕ)` 转换为笛卡尔向量，并完成
"视场方向 → 粒子速度方向"的符号反转。

# 功能与算法概述
MINPA 原始数据给出的是**视场指向**，故先做 `theta = 90° − θ`、`phi = 360° − ϕ` 镜像，展开后再整体反号，把视线方向还原为粒子速度方向；输入输出均为 `SVector{3}`，支持广播批处理。

# 参数说明
- `p::SVector{3,T}`: `(r, θ, ϕ)`，其中 `θ` 为 MINPA 定义的极角、`ϕ` 为方位角（**角度制**）。

# 返回值
- `SVector{3}`: 已反转符号的笛卡尔速度方向分量 `(x, y, z)`。

# 参考
- MINPA 官方说明：<https://www.swl.ac.cn/minpa/#/home/overview>

# 备注
- 本函数（基于 `SVector` 入参、内置反号）与 `TW_data/TW_MINPA.MINPA_sphere2xyz`
  （基于三个标量入参、弧度制、需调用方自行 `*= -1`）**数学等价但接口不同**。
"""
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

"""
    MINPA_xyz2sphere(p::SVector{3,T}) -> SVector{3}

将笛卡尔向量反算为**天问一号 MINPA 仪器坐标系**球坐标 `(r, θ, ϕ)`（角度制），
是 `MINPA_sphere2xyz` 的逆变换。

# 功能与算法概述
`MINPA_sphere2xyz` 的逆变换：先整体反号，再由投影正弦 `st` 与 `ct` 用 `atand` 解出极角/方位角，最后反演回视场方向约定。

# 参数说明
- `p::SVector{3,T}`: 笛卡尔向量 `(x, y, z)`。

# 返回值
- `SVector{3}`: `(r, θ, ϕ)`，角度为**角度制**，`ϕ` 已归一化到 `[0°, 360°)`。

# 参考
- MINPA 官方说明：<https://www.swl.ac.cn/minpa/#/home/overview>

# 注意事项
- 当 `r == 0` 或 `r_st == 0`（向量位于 X 轴上）时将出现除零，得到 `NaN`；调用方应自行过滤退化输入。
- 与 `MINPA_sphere2xyz` 互为正逆变换，可用 `norm(sphere2xyz(xyz2sphere(p)) .- p)` 做自洽性验证。
"""
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

"""
    bowshock_zero(xshock) -> Float64

求解火星**弓激波曲面**在给定 Sun-Mars 轴向坐标处的圆柱半径，并把"曲面外"的输入钳制为 `0.0`。

# 功能与算法概述
与 `head.bowshock` 同用 Edberg et al. (2008) 的二次曲线模型，但把无定义的输入区域**钳制为 `0.0`**，以便外层做数值迭代/求根。

# 参数说明
- `xshock`: 日火连线方向（通常为 MSO/MSE 的 X 轴）坐标，单位 **火星半径 `R_Mars`**。

# 返回值
- `Float64`: 弓激波圆柱半径 `√(y²+z²)`（单位 `R_Mars`）；
- `0.0`: 当该 `x` 处曲面无定义（`temp < 0`）时返回。

# 参考文献
- Edberg N J T, Lester M, Cowley S W H, et al., 2008. *Statistical analysis of the location of the
  Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields* [J].
  Journal of Geophysical Research: Space Physics, 113(A8).
"""
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
