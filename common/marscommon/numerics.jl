# common/marscommon/numerics.jl —— MarsCommon 能力子文件：数值求解与拟合
#
# 纯迁入：函数体逐字取自 5f225db 的源文件（源实现本次不删除，调用方与源清理由最终集成单元处理）。
# 仅声明本子文件必需的标准库；`constants` 与 `StaticArrays` 由父模块 common/MarsCommon.jl 提供。
#
# 逐函数来源（source_hash = 源文件函数块全文 SHA-256 前 16 位，见 validation/migrations/common.toml）：
#   solve_func                 <- common/head.jl                   sha16 18C47F0EE8C3FF4F
#   Vandermonde                <- MAVEN_data/MAVEN_plot.jl         sha16 DCD786C148C47322
#   polynomial_fit             <- MAVEN_data/MAVEN_plot.jl         sha16 A03ED9780AECBCE5
#   Linear_fit                 <- calculate/calculate_models.jl    sha16 B6BB50D4EA66866A

"""
    solve_func(x, y0, func) -> Float64

用**二分法**求解方程 `func(x) − y0 = 0`，用于求弓激波/磁堆积边界曲面在给定圆柱半径处的
轴向坐标。

# 功能与算法概述
在给定区间上用**二分法**迭代求解 `func(x) = y0`，收敛容差固定为 `1e-6`；端点同号时直接返回 `NaN64`。

# 参数说明
- `x`: 长度为 2 的搜索区间 `[x0, x1]`，要求 `func` 在端点异号。
- `y0`: 目标函数值（如弓激波在该处的圆柱半径）。
- `func`: 单参数函数（如 `bowshock`、`magnetopause`）。

# 返回值
- `Float64`: 方程 `func(x) = y0` 的根。
- `NaN64`: 当区间端点同号（区间内可能无根）时返回。

# 注意事项
- 收敛容差固定为 `1e-6`（绝对量），对于 `R_Mars` 量级坐标约合 `3.4 m` 分辨率。
- 仅在区间内函数单调且变号时结果可靠；多根情形下只返回其中一个。
"""
function solve_func(x,y0,func) # 二分法解方程
    # x = [x0,x1]
    # func = bowshock
    x0 = x[1]
    x1 = x[2]
    f0 = func(x0) - y0
    f1 = func(x1) - y0
    if f0*f1 > 0
        return NaN64
    end
    while abs(x1-x0) > 1e-6
        xmid = (x0+x1)/2.0
        fmid = func(xmid) - y0
        if fmid*f0 < 0
            x1 = xmid
            f1 = fmid
        else
            x0 = xmid
            f0 = fmid
        end
    end
    return (x0+x1)/2.0
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

