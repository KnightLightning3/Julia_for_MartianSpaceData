# common/marscommon/geometry.jl —— MarsCommon 能力子文件：向量几何
#
# 纯迁入：函数体逐字取自 5f225db 的源文件（源实现本次不删除，调用方与源清理由最终集成单元处理）。
# 仅声明本子文件必需的标准库；`constants` 与 `StaticArrays` 由父模块 common/MarsCommon.jl 提供。
#
# 逐函数来源（source_hash = 源文件函数块全文 SHA-256 前 16 位，见 validation/migrations/common.toml）：
#   get_normal_plane           <- common/head.jl                   sha16 7E46872BEE953502
#   get_angle                  <- common/head.jl                   sha16 2B8AF46FBA428949
#   vector_angle               <- MAVEN_data/MAVEN_plot.jl         sha16 B23A7DDB080CE71F
#
using LinearAlgebra

"""
    get_normal_plane(vec) -> (SVector{3}, SVector{3})

由平面的**法向量**构造该平面的两个基向量（用于把三维切片投影到二维绘图平面）。

# 功能与算法概述
由平面方程 `a·x + b·y + c·z = 0` 反解出 `z = −(a·x + b·y)/c`，分别取 `(x,y) = (1,0)` 与 `(0,1)` 得到平面内两条线性无关的基向量。

# 参数说明
- `vec`: 长度为 3 的法向量 `(a, b, c)`，要求 `c ≠ 0`（即平面不垂直于 X-Y 平面）。

# 返回值
- `(v1, v2)`: 两个 `SVector{3}` 平面内基向量，两者线性无关，可张成该平面。

# 注意事项
- 当 `c == 0` 时发生除零，结果为 `±Inf`；调用方需保证法向量有非零 Z 分量。
- 返回的基向量**未归一化**，如需正交归一基请再做 Gram-Schmidt。
- 本函数当前在仓库内无调用者（保留供切片绘图扩展使用）。
"""
function get_normal_plane(vec)# 通过法向向量制作平面函数
    a,b,c = vec[1],vec[2],vec[3]
    local func_plane = (x,y) -> (a*x + b*y) / -c
    v1 = func_plane(1.0,0.0)
    v2 = func_plane(0.0,1.0)
    v1 = SVector(1.0, 0.0, v1)
    v2 = SVector(0.0, 1.0, v2)
    return v1,v2
end

"""
    get_angle(v1, v2) -> Real

计算两个三维向量之间的**夹角**，输出**角度制**，在极小夹角下仍具有极高数值精度。

# 功能与算法概述
使用双参数反正切 `atand(‖v1×v2‖, v1·v2)`，等价于 `atan(sinθ, cosθ)`，相比 `acos(dot/(n₁n₂))` **不损失小角度精度**，且无需预先归一化。

# 参数说明
- `v1`: 第一个三维向量（`AbstractVector`，含 `SVector{3}`）。
- `v2`: 第二个三维向量。

# 返回值
- `Real`: 夹角（**角度制**），理论范围 `[0°, 180°]`；退化为零向量时返回 `NaN`。

# 备注
- 对于高精度需求场景，本实现严格优于 `rad2deg(acos(clamp(dot/(n1*n2), -1, 1)))` 的经典写法。
"""
function get_angle(v1, v2)
    return atand(norm(cross(v1, v2)), dot(v1, v2))
end

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
    Bsphere2pc(r, θ, ϕ, Br, Bθ, Bϕ) -> (Bx, By, Bz)

将球坐标系下的磁场分量转换为笛卡尔分量（纯旋转变换，不改变大小）。

# 功能与算法概述
以球基矢量 `(r̂, θ̂, ϕ̂)` 到 `(x̂, ŷ, ẑ)` 的方向余弦作正交旋转变换，故磁场大小不变。

# 参数说明
- `r`: 径向距离（仅用于保持接口一致，不参与公式）。
- `θ`: 天顶角/余纬（**弧度**）。
- `ϕ`: 经度（**弧度**）。
- `Br`: 径向磁场分量。
- `Bθ`: 天顶角方向磁场分量（指向 θ 增大方向）。
- `Bϕ`: 经度方向磁场分量（指向 ϕ 增大方向）。

# 返回值
- `(Bx, By, Bz)`: 笛卡尔坐标系下的磁场分量元组。

# 来源
t36 自 models/IGRF_calculate.jl（5f225db 时位于 Magnetic_Model/IGRF_calculate.jl）**逐字迁入**；
仓内唯一一份，权威归 common 层（MarsCommon），原模块经 `using .MarsCommon` 绑定，不再自持副本。
"""
function Bsphere2pc(r::Real, θ::Real, ϕ::Real, Br::Real, Bθ::Real, Bϕ::Real)
    sinθ = sin(θ)
    cosθ = cos(θ)
    sinϕ = sin(ϕ)
    cosϕ = cos(ϕ)
    Bx = sinθ * cosϕ * Br + cosθ * cosϕ * Bθ - sinϕ * Bϕ
    By = sinθ * sinϕ * Br + cosθ * sinϕ * Bθ + cosϕ * Bϕ
    Bz = cosθ * Br - sinθ * Bθ
    return Bx, By, Bz
end
"""
    Bpc2sphere(x, y, z, bx, by, bz) -> (Br, Bθ, Bϕ)

将笛卡尔坐标系下的磁场分量转换为球坐标分量，是 `Bsphere2pc` 的逆变换。

# 功能与算法概述
由观测点位置求出球基矢量 `(r̂, θ̂, ϕ̂)`，再与笛卡尔分量做点积投影；变换为正交旋转，`‖B‖` 不变。
半径用 `hypot` 计算，中间量不上溢（数值稳健版，见 `Bpc2sphere_naive` 的对照说明）。

# 参数说明
- `x`, `y`, `z`: 观测点的笛卡尔坐标。
- `bx`, `by`, `bz`: 笛卡尔坐标系下的磁场分量。

# 返回值
- `(Br, Bθ, Bϕ)`: 球坐标系下的磁场分量元组（旋转不改变 `‖B‖`）。

# 来源
t36 自 models/IGRF_calculate.jl（5f225db 时位于 Magnetic_Model/IGRF_calculate.jl）**逐字迁入**：
函数体与 `::Real` 标注均未改，保留 `hypot` 半径算法。
"""
function Bpc2sphere(x::Real, y::Real, z::Real, bx::Real, by::Real, bz::Real)
    r = hypot(x, y, z)
    θ = acos(z / r)
    ϕ = atan(y, x)

    sinθ = sin(θ)
    cosθ = cos(θ)
    sinϕ = sin(ϕ)
    cosϕ = cos(ϕ)

    Br = sinθ * cosϕ * bx + sinθ * sinϕ * by + cosθ * bz
    Bθ = cosθ * cosϕ * bx + cosθ * sinϕ * by - sinθ * bz
    Bϕ = -sinϕ * bx + cosϕ * by

    return Br, Bθ, Bϕ
end
"""
    Bpc2sphere_naive(x, y, z, bx, by, bz) -> (Br, Bθ, Bϕ)

**非等价变体**（保留原算法，不改为 `hypot`）：笛卡尔磁场分量 → 球坐标分量，半径用
`sqrt(x^2 + y^2 + z^2)` 计算。

# 功能与算法概述
公式体与 `Bpc2sphere` 相同，唯一差异是半径算法。`x^2` 的中间量在 `|x| ≳ 1.34e154`
（≈ `sqrt(floatmax)`）时上溢 ⇒ `r = Inf` ⇒ `θ = acos(0) = π/2`，球坐标分量随之失真；
`Bpc2sphere`（`hypot` 版）无此上溢。原签名无类型标注（更宽松，可接受非 `Real` 输入），一并保留。

# 参数说明
- `x`, `y`, `z`: 观测点笛卡尔坐标。
- `bx`, `by`, `bz`: 笛卡尔磁场分量。

# 返回值
- `(Br, Bθ, Bϕ)`: 球坐标磁场分量元组。

# 来源与命名
t36 自 MAVEN_data/MAVEN_load.jl（loader 层原 `Bpc2sphere`）整块迁入并**显式改名**
`Bpc2sphere_naive`：与 `Bpc2sphere` 实测在 `|坐标| ≤ 1e153` 逐位相同、`≥ 1e154` 分歧，
属真实数值差异而非风格差异，故按团队“不等价不同名保留”的既有授权保留两份，不做合并。
"""
function Bpc2sphere_naive(x, y, z, bx, by, bz)
    r = sqrt(x^2 + y^2 + z^2)
    θ = acos(z / r)
    ϕ = atan(y, x)

    sinθ = sin(θ)
    cosθ = cos(θ)
    sinϕ = sin(ϕ)
    cosϕ = cos(ϕ)

    Br = sinθ * cosϕ * bx + sinθ * sinϕ * by + cosθ * bz
    Bθ = cosθ * cosϕ * bx + cosθ * sinϕ * by - sinθ * bz
    Bϕ = -sinϕ * bx + cosϕ * by

    return Br, Bθ, Bϕ
end
