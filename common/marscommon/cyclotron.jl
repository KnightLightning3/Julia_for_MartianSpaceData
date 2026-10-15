# common/marscommon/cyclotron.jl —— MarsCommon 能力子文件：回旋频率/半径
#
# 纯迁入：函数体逐字取自 5f225db 的源文件（源实现本次不删除，调用方与源清理由最终集成单元处理）。
# 仅声明本子文件必需的标准库；`constants` 与 `StaticArrays` 由父模块 common/MarsCommon.jl 提供。
#
# 逐函数来源（source_hash = 源文件函数块全文 SHA-256 前 16 位，见 validation/migrations/common.toml）：
#   cyclotron_radius           <- calculate/calculate_models.jl    sha16 EC8EB0985D1CD3A4
#   cyclotron_frequency        <- calculate/calculate_models.jl    sha16 DA10321ACC76A0E0
#   cyclotron_frequency_kg     <- MAVEN_data/MAVEN_load.jl         sha16 4217EBD26D701769
#   cyclotron_radius_velocity  <- MAVEN_data/MAVEN_load.jl         sha16 5379C5E4E929C865

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
    cyclotron_frequency_kg(B; mass=constants.me) -> Float64

计算带电粒子的回旋频率。

# 功能与算法概述
按 `f = qB/(2πm)` 计算（`B` 由 nT 换算为 T）。

# 参数说明
- `B`: 磁感应强度（nT）。
- `mass`: 粒子质量（kg），默认电子质量。

# 返回值
- `Float64`: 回旋频率（Hz）。
"""
function cyclotron_frequency_kg(B; mass=constants.me)
    # 计算离子子的回旋频率, 默认电子, B nT
    f = constants.e * B*1e-9 / (2 * π * mass)
    return f
end

"""
    cyclotron_radius_velocity(v, B; mass=constants.me) -> Float64

计算带电粒子的回旋半径。

# 功能与算法概述
按 `R = v/(ω_c·2π)` 计算。

# 参数说明
- `v`: 粒子速度（m/s）。
- `B`: 磁感应强度（nT）。
- `mass`: 粒子质量（kg），默认电子质量。

# 返回值
- `Float64`: 回旋半径（m）。
"""
function cyclotron_radius_velocity(v, B; mass=constants.me)
    # 计算离子子的回旋半径, 默认电子,v m/s B nT
    R = v / (cyclotron_frequency_kg(B; mass) * 2 * π) # m
    return R
end

