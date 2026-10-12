module MarsCommon
using ..constants
using StaticArrays

export instrument_sphere_to_cartesian,
    instrument_cartesian_to_sphere,
    spherical_to_cartesian,
    rotate_vector,
    position_altitude,
    position_local_time,
    position_latitude,
    ion_energy2v,
    ion_speed_to_energy,
    e_energy2v,
    electron_eflux_to_psd,
    ion_eflux_to_psd,
    ion_eflux_to_psd_approx,
    eflux_to_df!,
    doppler_shift,
    searchsortednearest,
    searchsortednearest_range

"""
    instrument_sphere_to_cartesian(r, theta, phi) -> SVector{3}

将**仪器坐标系**下的球坐标（半径、仰角、方位角）转换为笛卡尔分量 `(x, y, z)`。

# 功能与算法概述
按“仰角自 X-Y 平面起算”的标准球坐标展开，角度一律按**角度制**解释；返回 `SVector{3}`，支持广播且无堆分配。

# 参数说明
- `r`: 径向距离（标量；单位由调用方约定，通常为 km 或 m）。
- `theta`: 仰角（**角度制**），`0°` 指向 X-Y 平面、`+90°` 指向 +Z 轴。
- `phi`: 方位角（**角度制**），在 X-Y 平面内自 +X 轴按逆时针量取。

# 返回值
- `SVector{3}`: 笛卡尔分量 `(x, y, z)`，元素类型由三个输入的公共类型提升决定。
"""
function instrument_sphere_to_cartesian(r, theta, phi)
    x = r .* cosd.(theta) .* cosd.(phi)
    y = r .* cosd.(theta) .* sind.(phi)
    z = r .* sind.(theta)
    return SVector(x, y, z)
end

"""
    instrument_cartesian_to_sphere(x, y, z) -> SVector{3}

将笛卡尔分量 `(x, y, z)` 反算为**仪器坐标系**球坐标（半径、仰角、方位角），是
`instrument_sphere_to_cartesian` 的逆变换。

# 功能与算法概述
`instrument_sphere_to_cartesian` 的逆变换：由 `acosd(z/r)` 得与 +Z 轴夹角后反算仰角；对 `z/r` 做 `clamp(−1,1)` 以防浮点误差使 `acosd` 返回 `NaN`。

# 参数说明
- `x`: 笛卡尔 X 分量。
- `y`: 笛卡尔 Y 分量。
- `z`: 笛卡尔 Z 分量。

# 返回值
- `SVector{3}`: `(r, theta, phi)`，其中 `theta`、`phi` 同为**角度制**。
"""
function instrument_cartesian_to_sphere(x, y, z)
    r = sqrt.(x .^ 2 .+ y .^ 2 .+ z .^ 2)
    theta = 90.0 .- acosd.(clamp.(z ./ r, -1.0, 1.0))
    phi = atand.(y, x)
    return SVector(r, theta, phi)
end

"""
    spherical_to_cartesian(r, theta, phi) -> SVector{3}

将**常规球坐标**（余纬自 +Z 轴起算）转换为笛卡尔分量 `(x, y, z)`。

# 功能与算法概述
将余纬（自 +Z 轴起算）定义下的球坐标展开为笛卡尔分量；角度按**角度制**解释，返回 `SVector{3}`。

# 参数说明
- `r`: 径向距离。
- `theta`: 余纬 / 天顶角（**角度制**），`0°` 指向 +Z 轴、`90°` 落在 X-Y 平面。
- `phi`: 方位角（**角度制**），自 +X 轴逆时针量取。

# 返回值
- `SVector{3}`: 笛卡尔分量 `(x, y, z)`。

# 备注
- 与 `instrument_sphere_to_cartesian` 的区别仅在 `theta` 的起算轴不同（+Z 轴 vs X-Y 平面），
  因此两者仅当 `theta_instrument = 90° − theta_spherical` 时才等价。
"""
function spherical_to_cartesian(r, theta, phi)
    x = r .* sind.(theta) .* cosd.(phi)
    y = r .* sind.(theta) .* sind.(phi)
    z = r .* cosd.(theta)
    return SVector(x, y, z)
end

"""
    rotate_vector(data, rotation_matrix)

使用旋转矩阵对**单个向量或按行堆叠的向量数组**执行坐标变换。

# 功能与算法概述
直接调用旋转矩阵（或 Rotations.jl 的旋转对象）与数据的**矩阵乘法**，由多重派发适配向量或按行堆叠的向量矩阵。

# 参数说明
- `data`: 待旋转的向量（长度 3）或向量矩阵（`N×3`）。
- `rotation_matrix`: 旋转矩阵 / 旋转对象，尺寸须与 `data` 的最后一维匹配。

# 返回值
- 旋转后的向量或矩阵，类型由 `data` 与 `rotation_matrix` 的乘积结果决定。
"""
rotate_vector(data, rotation_matrix) = rotation_matrix * data

"""
    position_altitude(position) -> Vector

由**按行堆叠**的行星笛卡尔位置计算每行对应的海拔高度（单位与输入一致，通常为 km）。

# 功能与算法概述
对每行求径向距离后扣除参考球半径 `constants.R_Mars`（3393.5 km）。

# 参数说明
- `position::AbstractMatrix`: `N×3` 的位置矩阵，每行 `(x, y, z)`，单位须与 `R_Mars` 一致（km）。

# 返回值
- `Vector`: 长度 `N` 的海拔高度序列，地表以下为负值。
"""
function position_altitude(position)
    return sqrt.(sum(position .^ 2, dims=2))[:, 1] .- constants.R_Mars
end

"""
    position_local_time(position) -> Vector

由行星笛卡尔位置计算**地方时（Local Solar Time, LST）**，单位小时（0–24 h）。

# 功能与算法概述
由 X-Y 平面方位角线性映射到 24 小时制，使 `+X` 轴（日下点方向）对应正午 12:00。

# 参数说明
- `position::AbstractMatrix`: `N×3` 的位置矩阵，通常为 MSO 坐标系（`+X` 指向太阳）。

# 返回值
- `Vector`: 长度 `N` 的地方时序列，单位 **小时**（0–24）。

# 备注
- 该计算隐含假设行星自转轴与 `+Z` 轴平行，忽略自转轴倾角带来的季节性偏差。
"""
function position_local_time(position)
    return atan.(position[:, 2], position[:, 1]) ./ π .* 12.0 .+ 12.0
end

"""
    position_latitude(position) -> Vector

由行星笛卡尔位置计算**行星纬度**，单位度（−90°–90°）。

# 功能与算法概述
由水平投影半径与 Z 分量反算纬度（`atand`），北纬为正。

# 参数说明
- `position::AbstractMatrix`: `N×3` 的位置矩阵，通常为 MSO 坐标系。

# 返回值
- `Vector`: 长度 `N` 的行星纬度序列，单位 **度**。

# 备注
- 同样假设行星自转轴与 `+Z` 轴平行。
"""
function position_latitude(position)
    return atan.(position[:, 3], sqrt.(sum(position[:, 1:2] .^ 2, dims=2))) ./ π .* 180.0
end

"""
    ion_energy2v(energy, mass_amu) -> Float64 / AbstractArray

将离子动能（自**静质量起算**）换算为**相对论速度**，单位 m/s。

# 功能与算法概述
采用**相对论**能量–速度关系 `γ = E/(mc²) + 1`、`β = √(1 − 1/γ²)`，而非低能的 `√(2E/m)` 近似。

# 参数说明
- `energy`: 离子动能（单位 **eV**），标量或数组。
- `mass_amu`: 离子质量数（单位 **AMU**），标量。

# 返回值
- 相对论速度（**m/s**），形状与 `energy` 一致（标量输入返回标量）。

# 备注
- 非相对论极限下该式退化为 `v ≈ √(2E/m)`，与 `sqrt(2*e*E/(mp*m))` 的经典写法在低能时一致，
  但在高能区该实现更精确。
"""
function ion_energy2v(energy, mass_amu)
    rest_energy_kev = constants.KEV_PER_AMU * mass_amu
    gamma = energy .* 1e-3 ./ rest_energy_kev .+ 1.0
    beta = sqrt.(1.0 .- 1.0 ./ gamma .^ 2)
    return beta .* constants.c
end

"""
    ion_speed_to_energy(speed, mass_amu) -> Float64 / AbstractArray

将离子**相对论速度**反算为动能，单位 eV。是 `ion_energy2v` 的逆运算。

# 功能与算法概述
由 `β = v/c` 得 `γ = 1/√(1 − β²)`，再按 `E = (γ − 1)mc²` 反算动能。

# 参数说明
- `speed`: 离子速度（**m/s**），标量或数组。
- `mass_amu`: 离子质量数（**AMU**），标量。

# 返回值
- 离子动能（**eV**），形状与 `speed` 一致。

# 备注
- 若 `speed ≥ c`，`1 − β²` 将为非正数从而产生 `NaN`/`Inf`，调用方需保证输入为物理速度。
"""
function ion_speed_to_energy(speed, mass_amu)
    rest_energy_kev = constants.KEV_PER_AMU * mass_amu
    beta = speed ./ constants.c
    gamma = 1.0 ./ sqrt.(1.0 .- beta .^ 2)
    return (gamma .- 1.0) .* rest_energy_kev .* 1e3
end

"""
    e_energy2v(energy) -> Float64 / AbstractArray

将电子动能（自**静质量起算**）换算为**相对论速度**，单位 m/s。

# 功能与算法概述
以电子静能 511 keV 为基准的相对论能量–速度转换，电子质量固定为 `constants.me`。

# 参数说明
- `energy`: 电子动能（单位 **eV**），标量或数组。

# 返回值
- 相对论电子速度（**m/s**），形状与 `energy` 一致。
"""
function e_energy2v(energy)
    gamma = energy .* 1e-3 ./ constants.E0_electron_keV .+ 1.0
    beta = sqrt.(1.0 .- 1.0 ./ gamma .^ 2)
    return beta .* constants.c
end

"""
    electron_eflux_to_psd(energy, eflux) -> Float64 / AbstractArray

将**电子能通量（energy flux）**转换为**相空间密度（Phase Space Density, PSD）**。

# 功能与算法概述
基于相对论动量 `p = γmₑβc` 的能通量→相空间密度换算，含 `cm⁻²→m⁻²` 与 `eV→J` 的单位修正。

# 参数说明
- `energy`: 电子能量（**eV**），标量或数组。
- `eflux`: 电子能通量，与 `energy` 形状兼容。

# 返回值
- 相空间密度（单位 `s³·m⁻⁶` 量级，取决于输入的单位约定），形状与输入一致。

# 备注
- 该函数是 `ion_eflux_to_psd` 的电子版；离子版本额外需要质量参数。
"""
function electron_eflux_to_psd(energy, eflux)
    gamma = energy .* 1e-3 ./ constants.E0_electron_keV .+ 1.0
    beta = sqrt.(1.0 .- 1.0 ./ gamma .^ 2)
    momentum = gamma .* constants.me .* beta .* constants.c
    return (gamma .* constants.me) .^ 3 .* eflux ./ energy .* 1e4 ./ constants.eV ./ momentum .^ 2
end

"""
    ion_eflux_to_psd(energy, eflux, mass_amu) -> Float64 / AbstractArray

将**离子能通量**转换为**相空间密度（PSD）**，使用精确的相对论动量公式。

# 功能与算法概述
基于相对论动量 `p = γmv` 的能通量→相空间密度换算，离子静能由“电子静能 × 质量比”给出。

# 参数说明
- `energy`: 离子能量（**eV**），标量或数组。
- `eflux`: 离子能通量，与 `energy` 形状兼容。
- `mass_amu`: 离子质量数（**AMU**），标量。

# 返回值
- 相空间密度，形状与输入一致。

# 备注
- 与 `ion_eflux_to_psd_approx` 相比，本函数显式使用相对论动量 `p = γmv`，在高能区更准确。
"""
function ion_eflux_to_psd(energy, eflux, mass_amu)
    mass = mass_amu * constants.mp
    rest_energy_kev = constants.E0_electron_keV * mass_amu * constants.AMU_TO_PROTON_MASS_RATIO
    gamma = energy .* 1e-3 ./ rest_energy_kev .+ 1.0
    beta = sqrt.(1.0 .- 1.0 ./ gamma .^ 2)
    momentum = gamma .* mass .* beta .* constants.c
    return (gamma .* mass) .^ 3 .* eflux ./ energy .* 1e4 ./ constants.eV ./ momentum .^ 2
end

"""
    ion_eflux_to_psd_approx(energy, eflux, mass_to_charge) -> Float64 / AbstractArray

使用**速度幂次近似式**将离子能通量换算为相空间密度（PSD），与仪器（SWIA/STATIC）常用的
简化写法保持一致。

# 功能与算法概述
仪器端常用的简化公式 `PSD ≈ 2·eflux·1e4 / v⁴`，用速度四次方代替完整相对论动量项。

# 参数说明
- `energy`: 离子能量（**eV**），标量或数组。
- `eflux`: 离子能通量，与 `energy` 形状兼容。
- `mass_to_charge`: 质荷比参数（STATIC 中的 `m_int`，同时用于质量数与电荷数）。

# 返回值
- 相空间密度（近似值），形状与输入一致。

# 备注
- 该近似在非相对论极限下与 `ion_eflux_to_psd` 一致，但在高能区会低估 PSD。
"""
function ion_eflux_to_psd_approx(energy, eflux, mass_to_charge)
    rest_energy_kev = constants.E0_electron_keV * mass_to_charge * constants.AMU_TO_PROTON_MASS_RATIO
    gamma = energy .* 1e-3 ./ rest_energy_kev .+ 1.0
    beta = sqrt.(1.0 .- 1.0 ./ gamma .^ 2)
    speed = beta .* constants.c
    return 2 .* eflux .* 1e4 ./ speed .^ 4
end

"""
    eflux_to_df!(data) -> Dict{Symbol, Any}

**原地**为 SWIA / SWEA 数据字典补充分布函数 `:df`（由微分能通量换算得到）。

# 功能与算法概述
**原地**由微分能通量按 `df = eflux/(E² · 2/m² · 1e5)` 计算分布函数，写入 `data[:df]`。

# 参数说明
- `data::Dict{Symbol, Any}`: 至少包含键 `:energy`（能量序列）、`:mass`（质量数）
  与 `:diff_en_fluxes`（微分方向通量）的数据字典。

# 返回值
- `Dict{Symbol, Any}`: 已注入 `:df` 键的同一字典对象（原地修改）。

# 注意事项
- 函数带 `!`，会**修改入参**；如需保留原始数据请先 `deepcopy`。
"""
function eflux_to_df!(data)
    energy = reshape(data[:energy], 1, 1, 1, length(data[:energy]))
    mass = data[:mass]
    data[:df] = data[:diff_en_fluxes] ./ (energy .^ 2 .* 2.0 ./ mass ./ mass .* 1e5)
    return data
end

"""
    doppler_shift(frequency, spacecraft_speed, wave_number, angle) -> Float64 / AbstractArray

计算考虑**航天器运动**后的等离子体波频率（多普勒修正），返回**角频率**。

# 功能与算法概述
对观测角频率施加一阶多普勒修正 `ω_obs = ω − k·v_sc·cos α`。

# 参数说明
- `frequency`: 波的频率（Hz，通常是航天器静止系或等离子体静止系下的频率约定，由调用方确定）。
- `spacecraft_speed`: 航天器速度（m/s）。
- `wave_number`: 波数 `k`（rad/m）。
- `angle`: 波矢 `k` 与航天器速度方向之间的夹角（**弧度**）。

# 返回值
- 修正后的角频率 `ω_obs`（rad/s），形状由广播规则决定。

# 备注
- 返回的是**角频率**而非普通频率，若需 `f_obs` 请再除以 `2π`。
"""
function doppler_shift(frequency, spacecraft_speed, wave_number, angle)
    observed_angular_frequency = frequency .* 2 .* π
    return observed_angular_frequency .- wave_number .* spacecraft_speed .* cos.(angle)
end

"""
    searchsortednearest(x, x0) -> Int

在**已排序的时序数据轴** `x` 中查找与目标时刻 `x0` 最接近的元素下标。

# 适用范围（重要）
- **本函数只能用于时序数据查找**：要求输入 `x` 是**单调递增（已按时间排序）**的时间轴。
- 在空间数据处理中，所有被读取的数据除非特别说明，其时间轴都是排序后的时序数据；
  因此对时间轴的最近邻查找一律使用本函数（二分查找），**不要**使用 `findmin(abs.(x .- x0))`（线性扫描）。
- **严禁**对未排序数组、能量轴、色标 levels 等非时序数据调用本函数。

# 功能与算法概述
用二分查找（`searchsortedfirst`，`O(log N)`）定位第一个 `>= x0` 的下标，再与其左邻比较距离取更近者；两端越界直接短路返回。

# 参数说明
- `x`: 单调递增的时间数组（`Vector{DateTime}`、`Vector{Float64}` 等可比较类型，**必须已排序**）。
- `x0`: 目标时刻，类型需与 `x` 的元素可比较。

# 返回值
- `Int`: `x` 中最接近 `x0` 的元素下标（1-based）。

# 性能
- 时间复杂度 `O(log N)`，优于 `findmin(abs.(x .- x0))` 的 `O(N)` 且不产生临时数组。

# 备注
- 当 `x0` 恰位于两个元素正中时，返回**较大**的下标。
- 输入 `x` 必须已排序，否则结果无意义。
"""
function searchsortednearest(x, x0)
    N = length(x)
    if x0 <= x[1]
        return 1
    elseif x0 >= x[N]
        return N
    end
    idx_upper = searchsortedfirst(x, x0)
    idx_lower = idx_upper - 1
    if abs(x[idx_upper] - x0) <= abs(x[idx_lower] - x0)
        return idx_upper
    else
        return idx_lower
    end
end

"""
    searchsortednearest_range(x, time_range) -> UnitRange{Int}

把时间区间转换成时间轴 `x` 上的连续索引范围（内部用 `searchsortednearest` 二分定位两端）。

同 `searchsortednearest`，**仅适用于已排序的时序数据轴**。
"""
function searchsortednearest_range(x, time_range)
    return searchsortednearest(x, time_range[1]):searchsortednearest(x, time_range[2])
end

end
