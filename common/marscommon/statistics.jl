# common/marscommon/statistics.jl —— MarsCommon 能力子文件：统计与掩码辅助
#
# 纯迁入：函数体逐字取自 5f225db 的源文件（源实现本次不删除，调用方与源清理由最终集成单元处理）。
# 仅声明本子文件必需的标准库；`constants` 与 `StaticArrays` 由父模块 common/MarsCommon.jl 提供。
#
# 逐函数来源（source_hash = 源文件函数块全文 SHA-256 前 16 位，见 validation/migrations/common.toml）：
#   safe_log_mean              <- common/head.jl                   sha16 372B280DA64669F1
#   skipnan                    <- common/head.jl                   sha16 00E0003ECA7316AA
#   nozeros                    <- common/head.jl                   sha16 D81A0A057D5A6DFD
#   geomean                    <- common/head.jl                   sha16 B363DBB8AB297D45
#   find_range                 <- common/head.jl                   sha16 661D4D87F3830BF3
#
using Statistics

"""
    safe_log_mean(x) -> Float64

计算**正值数据的对数均值**，对 `0`、`NaN`、`Inf` 等无效值具有容错能力。

# 功能与算法概述
先剔除 `≤0` 与非有限元素，再对剩余正值取几何平均（`10^mean(log10, ·)`）；无有效元素时返回 `0.0` 而不报错。

# 参数说明
- `x`: 待统计的数值数组（可含 `0`、`NaN`、`Inf`）。

# 返回值
- `Float64`: 有效元素的几何平均值；若不存在有效元素则返回 `0.0`。

# 备注
- 几何平均对量级跨越多个数量级的数据（如等离子体密度、通量）比算术平均更稳健。
- 与 `geomean` 的区别：本函数会**丢弃**非正/非有限值，而 `geomean` 不做筛选。
"""
function safe_log_mean(x)
    # 筛选出大于 0 的有效值
    valid_elements = Base.filter(v -> v > 0 && isfinite(v), x)
    
    if isempty(valid_elements)
        return 0.0  # 如果全是 0 或无效值，返回0.0
    else
        return 10 ^mean(log10, valid_elements)#median(valid_elements)#
    end
end

"""
    skipnan(x) -> Vector

移除数组中的 `NaN` 元素，返回仅含有限值的紧凑向量。

# 功能与算法概述
用 `.!isnan.(x)` 生成布尔掩码后索引，返回去除 `NaN` 的新数组（原数组不被修改）。

# 参数说明
- `x`: 一维数值数组。

# 返回值
- `Vector`: 不含 `NaN` 的新数组（长度 ≤ `length(x)`）。

# 注意事项
- 返回的是**新数组**，不修改入参；元素顺序保持不变，但原索引信息会丢失。
- 若要保留索引，请改用 `findall(!isnan, x)`。
"""
function skipnan(x) # 移除NaN的filter
    ind = .!isnan.(x)
    return x[ind]
end;

"""
    nozeros(x) -> Vector

**原地**把数组中的 `0` 替换为一个极小数 `1e-20`，用于规避对数/除法运算中的奇点。

# 功能与算法概述
定位 `iszero` 的元素并**原地**改写为 `1e-20`，使数据仍可用于对数/除法运算而不产生奇点。

# 参数说明
- `x`: 数值数组（需支持 `setindex!`，即非 `SVector` 等不可变容器）。

# 返回值
- `Vector`: 与入参**同一对象**（原地修改后返回）。

# 注意事项
- 函数名未带 `!` 但**会修改入参**，调用前请对需要保留的原始数据做 `copy`/`deepcopy`。
- 仅处理 `0`，不处理 `NaN` 或负值。
"""
function nozeros(x) # 消0点为1e-20
    x[iszero.(x)] .= 1e-20
    return x
end;

"""
    geomean(x; dims=1) -> AbstractArray

计算数组的**几何平均值** `exp(mean(log(x)))`，支持沿指定维度归约。

# 功能与算法概述
在对数域求均值再指数还原（`exp(mean(log(x)))`），支持沿 `dims` 归约；不对无效值做筛选。

# 参数说明
- `x`: 数值数组（所有参与归约的元素必须 **> 0**）。
- `dims`: 归约维度，默认 `1`。

# 返回值
- 与 `x` 在非归约维度上形状一致的几何平均值数组。

# 注意事项
- 与 `safe_log_mean` 不同，本函数**不筛选**无效值：含有 `0` 或负值会产生 `−Inf`/`NaN`。
- 几何平均适合量级跨度大的物理量（密度、通量），可抑制极端值影响。
"""
function geomean(x; dims=1) # 几何平均
    # local flag = x .== 0
    return exp.(mean(log.(x); dims=dims))
end;

"""
    find_range(x, xr) -> BitVector

生成布尔掩码，标记数值数组中落入闭区间 `xr` 的元素。

# 功能与算法概述
用两个比较结果按位与（`.&`）生成闭区间 `[xr[1], xr[2]]` 的布尔掩码。

# 参数说明
- `x`: 数值数组。
- `xr`: 长度为 2 的区间 `(下限, 上限)`。

# 返回值
- `BitVector`: 与 `x` 同形状的布尔掩码，`true` 表示该元素在区间内。

# 备注
- 可直接用于 `x[mask]` 提取子集，或与其它掩码做逻辑运算。
- 若 `xr[1] > xr[2]`，结果全为 `false`。
"""
function find_range(x,xr)
    ind = (x .>= xr[1]) .& (x .<= xr[2])
    return ind
end

