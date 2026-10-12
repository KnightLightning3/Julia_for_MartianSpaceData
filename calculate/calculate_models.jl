"""组合模型计算及常用坐标旋转、物理量派生函数。"""

module calculate_models
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
using Rotations
using StaticArrays

"""
    rotation_matrix(θ, φ) -> Matrix{Float64}

由天顶角与方位角生成坐标旋转矩阵。

# 功能与算法概述
先绕 Y 轴旋转 θ、再绕 Z 轴旋转 φ，返回组合矩阵 `Rz(φ)·Ry(θ)`。

# 参数说明
- `θ`: 绕 Y 轴转角（弧度）。
- `φ`: 绕 Z 轴转角（弧度）。

# 返回值
- `Matrix{Float64}`: 3×3 旋转矩阵。
"""
function rotation_matrix(θ, φ)
    # 创建绕z轴旋转φ的旋转矩阵
    Rz = [cos(φ) -sin(φ) 0;
          sin(φ)  cos(φ) 0;
          0       0      1]

    # 创建绕y轴旋转θ的旋转矩阵
    Ry = [cos(θ)  0  sin(θ);
          0       1  0;
         -sin(θ)  0  cos(θ)]

    # 计算总旋转矩阵，先绕y轴旋转，然后绕z轴旋转
    return Rz * Ry
end
"""
    Quaternion_Rot(u::AbstractVector, q::QuatRotation) -> AbstractVector

用旋转四元数对向量做正向坐标变换（等价 `q*u*conj(q)`）。

# 参数说明
- `u`: 待旋转向量。
- `q`: `Rotations.QuatRotation` 四元数。

# 返回值
- 旋转后的向量。
"""
function Quaternion_Rot(u::AbstractVector, q::QuatRotation)
    return q * u
end

"""
    Quaternion_Rot_reverse(u::AbstractVector, q::QuatRotation) -> AbstractVector

用旋转四元数对向量做逆向坐标变换（等价 `inv(q)*u`）。

# 参数说明
- `u`: 待旋转向量。
- `q`: `Rotations.QuatRotation` 四元数。

# 返回值
- 旋转后的向量。
"""
function Quaternion_Rot_reverse(u::AbstractVector, q::QuatRotation)
    return inv(q) * u
end
    """
        escape_energy(; nM=1, planet="Mars") -> Float64

    计算指定行星表面逃逸所需的最小粒子能量。

    # 功能与算法概述
    按 `E = ½·m·v_esc²` 计算并换算为 eV；`planet="Mars"` 时取逃逸速度 5.027 km/s。

    # 参数说明
    - `nM`: 质量数（AMU），默认 1。
    - `planet`: 行星名（当前仅支持 `"Mars"`）。

    # 返回值
    - `Float64`: 逃逸能量（eV）。

    # 注意事项
    - 若 `planet` 非 `"Mars"`，`v` 未定义会报错。
    """
    function escape_energy(;nM=1,planet="Mars")
    mass = nM * constants.mp
    # G = 6.67430e-11
    if planet == "Mars"
        v = 5.027e3
    end
    # v2 = 2 * G * mass / R
    E = 0.5 * mass * v^2 / constants.eV
    return E
end

    """
        cyclotron_radius(B, ek; nM=1, nQ=-1) -> (Float64, Float64, Float64)

    计算带电粒子的回旋频率、回旋半径与速度。

    # 功能与算法概述
    由 `B`（nT→T）得回旋角频率 `ω=qB/m`，结合能量换算的速度得回旋半径 `r_c = v/ω`，
    并返回 `f = ω/2π`。

    # 参数说明
    - `B`: 磁感应强度（nT）。
    - `ek`: 动能（eV）。
    - `nM`: 质量数，默认 1。
    - `nQ`: 电荷数，`-1` 表示电子。

    # 返回值
    - `(f, rc, v)`: 回旋频率（Hz）、回旋半径（m）、速度（m/s）。
    """
    function cyclotron_radius(B,ek;nM=1,nQ=-1)
    B1=B*1e-9  # 输入nT，转T
    if nQ == -1
        cc = constants.me /(B1*constants.e)
        v = MarsCommon.e_energy2v(ek)
    else
        cc = constants.mp*nM/(B1*constants.e*nQ)
        v = MarsCommon.ion_energy2v(ek, nM)
    end
    # γ=(energy * 1e-3 /E0 + 1)
    # β=sqrt(1.0 - 1.0 / γ^2)
    # V=β * C
    f = 1  / (cc *2*π)
    rc = cc * v
    return f,rc,v
end

    """
        cyclotron_frequency(B; nM=1, nQ=-1) -> Float64

    计算带电粒子的回旋频率。

    # 功能与算法概述
    由 `ω=qB/m`（`B` 由 nT 换算为 T）得 `f = ω/2π`。

    # 参数说明
    - `B`: 磁感应强度（nT）。
    - `nM`: 质量数，默认 1。
    - `nQ`: 电荷数，`-1` 表示电子。

    # 返回值
    - `Float64`: 回旋频率（Hz）。
    """
    function cyclotron_frequency(B;nM=1,nQ=-1)
    B1=B*1e-9  # 输入nT，转T
    if nQ == -1
        cc = constants.me /(B1*constants.e)
    else
        cc = constants.mp*nM/(B1*constants.e*nQ)
    end
    f = 1  / (cc *2*π)
    return f
end

    """
        Linear_fit(x::AbstractVector, y::AbstractVector) -> NamedTuple

    对一维数据做最小二乘线性拟合。

    # 功能与算法概述
    按闭式公式由均值与协方差求斜率 `P2`、截距 `P1`，并计算决定系数 `r_squared`，
    同时返回拟合函数闭包。

    # 参数说明
    - `x`, `y`: 等长的自变量与因变量向量。

    # 返回值
    - `NamedTuple`: 含 `P1`（截距）、`P2`（斜率）、`r_squared`（拟合优度）与 `fit_function`。

    # 注意事项
    - `x`、`y` 长度不一致、点数少于 2 或 `x` 全相同时抛错。
    """
    function Linear_fit(x::AbstractVector, y::AbstractVector)
    # 确保输入数据长度一致
    if length(x) != length(y)
        error("输入向量 x 和 y 的长度必须一致。")
    end
    
    n = length(x)
    if n < 2
        error("至少需要两个数据点进行线性拟合。")
    end

    # --- 1. 计算必要的统计量 (使用高效的求和) ---
    
    # 均值
    x_mean = sum(x) / n
    y_mean = sum(y) / n
    
    # 协方差的分子 (S_xy) 和 x 的方差的分子 (S_xx)
    S_xy = 0.0
    S_xx = 0.0
    
    # 循环一次计算所有差值的乘积和平方和
    for i in 1:n
        x_diff = x[i] - x_mean
        y_diff = y[i] - y_mean
        
        S_xy += x_diff * y_diff # ∑(xᵢ - x̄)(yᵢ - ȳ)
        S_xx += x_diff * x_diff # ∑(xᵢ - x̄)²
    end

    # --- 2. 计算斜率 (P₂) 和截距 (P₁) ---

    if S_xx ≈ 0.0
        # 如果 S_xx 接近于零，意味着所有 x 值都相同
        error("所有 x 值都相同 (S_xx ≈ 0)。无法计算唯一的斜率。")
    end

    # 斜率 (Slope): P₂
    P2 = S_xy / S_xx
    
    # 截距 (Intercept): P₁ (利用通过均值点 (x̄, ȳ) 的特性)
    P1 = y_mean - P2 * x_mean

    # --- 3. 计算拟合优度 (可选但推荐) ---
    
    # 总平方和 (SST) - y 的总变异性
    SST = sum((y .- y_mean).^2)
    
    # 残差平方和 (SSR)
    Y_predicted = P1 .+ P2 .* x
    SSR = sum((y .- Y_predicted).^2)
    
    # 决定系数 (R²)
    r_squared = (SST > eps()) ? (1.0 - (SSR / SST)) : 1.0

    # --- 4. 返回结果 ---
    return (
        P1 = P1, # 截距
        P2 = P2, # 斜率
        r_squared = r_squared, # 拟合优度
        # 返回拟合函数本身，方便后续计算预测值
        fit_function = new_x -> P1 .+ P2 .* new_x
    )
end
end # module

# import .calculate_models

# freq,rc,v = calculate_models.cyclotron_radius(200.0,100;nM=32,nQ=1)
# println([freq,rc/1000,v/1000])
# freq,rc,v = calculate_models.cyclotron_radius(200.0,100;nQ=-1)
# println([freq,rc/1000,v/1000])