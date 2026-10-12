"""冷等离子体色散关系、波矢、相速度与共振能量计算。"""

module Cold_Plasma_Dispersion_Relation
include(joinpath(@__DIR__, "..", "common", "constants.jl"))

global Nparticles
global Ω_n
global Π_2
# 暂时只支持单解的波
"""
    set_particles(; ion_rate=[], ion_mass=[]) -> Nothing

配置多成分**冷等离子体**的成分列表，并初始化本模块的全局归一化参数（回旋频率与等离子体频率平方）。

# 功能与算法概述
根据输入的各离子相对数密度（`ion_rate`）与质量数（`ion_mass`），自动补全电子基准项并构建多成分等离子体矩阵，为后续色散关系求解提供全局物理常数。

# 参数说明
- `ion_rate`: 各离子相对**电子数密度**的比例数组（无单位），长度 `N_i`。
- `ion_mass`: 各离子的**质量数**（AMU），与 `ion_rate` 一一对应。

# 返回值
- `Nothing`: 本函数为内部状态初始化函数，通过副作用直接设置模块全局变量 (`Nparticles`, `Ω_n`, `Π_2`)。

# 注意事项
- 必须在调用 `Dispersion_Relation` 之前执行。
- **非线程安全**：会直接覆盖上一次设置的全局状态。
- **示例**：`set_particles(ion_rate=[0.4, 0.6], ion_mass=[16, 32])` 表示 O⁺/O₂⁺ 混合等离子体。
"""
function set_particles(;ion_rate=[],ion_mass=[])
  ion_rate = ion_rate
  ion_mass = ion_mass
  particles= 1.0 ./ [1.0,ion_mass...]
  particles_rate = [1.0,ion_rate...]
  global Nparticles=length(particles)
  # 以电子回旋频率归一化  fce 为负值
  global Ω_n = fill(constants.me/constants.mp,Nparticles) ; Ω_n[1] = -1.0 ; Ω_n = Ω_n .* particles
  global Π_2 = fill(constants.me/constants.mp,Nparticles) ; Π_2[1] = 1.0 ; Π_2 = Π_2  .* particles_rate .* particles
end

# set_particles(ion_rate=[0.4,0.6],ion_mass=[16,32]) / 默认值

"""
    get_Πe(Ne; unit="Hz") -> Real

由电子数密度计算**电子等离子体频率** `Πe`。

# 功能与算法概述
采用经验换算 `Πe = 8890.0·√Ne`（`Ne` 以 cm⁻³ 计时直接得到 Hz）；`unit` 非 `"Hz"` 时返回角频率。

# 参数说明
- `Ne`: 电子数密度（**cm⁻³**），标量或数组。
- `unit`: `"Hz"` 返回普通频率；其它值返回角频率（`2π` 倍）。

# 返回值
- 电子等离子体频率（Hz），形状与 `Ne` 一致。

# 注意事项
- 不依赖 `set_particles` 设置的全局状态。
"""
function get_Πe(Ne; unit="Hz")
  Πe = sqrt(Ne)*8890.0
  if unit == "Hz"
    return Πe
  else 
    return Πe * 2 * π
  end
end

"""
    Dispersion_Relation(θ, freq, Πe, Ωe) -> Real

求解**冷等离子体色散关系**，返回给定传播角与频率下的**折射率（实部）** `μ`。

# 功能与算法概述
以电子回旋频率 `−Ωe` 归一化，按 Stix 参数（`R`/`L`/`P`）构造 Appleton–Hartree 二次式并取较大根；在截止区（`μ² < 0`）安全返回 `0` 而非报错。

# 参数说明
- `θ`: 波矢与背景磁场夹角（**弧度**，直接传入 `sin`/`cos`）。
- `freq`: 探测波频率（Hz）。
- `Πe`: 电子等离子体频率（Hz）。
- `Ωe`: 电子回旋频率（Hz，带负号）。

# 返回值
- `Real`: 折射率实部 `μ`（无量纲，`μ ≥ 0`；截止区为 `0`）。

# 注意事项
- 必须先调用 `set_particles` 初始化全局量。
- 本文件顶部注释称"默认为分度制"，实现实际按**弧度**处理。
- 仅取单分支较大根，不做 X/O 模式的光滑追踪。
"""
function Dispersion_Relation(θ,freq,Πe,Ωe)  #返回折光率,与frep一一对应.

  Πe_n = Πe / (-Ωe)
  freq_n = freq / (-Ωe) 
  Π_2_local = Π_2 * Πe_n^2 

  #计算介电常数
  R=1.0
  L=1.0
  P=1.0
  for i=1:Nparticles
    R=R-Π_2_local[i]/freq_n^2*( freq_n / (freq_n+Ω_n[i]) )
    L=L-Π_2_local[i]/freq_n^2*( freq_n / (freq_n-Ω_n[i]) )
    P=P-Π_2_local[i]/freq_n^2
  end
  
  S=(R+L)/2.
  A=S*sin(θ)^2+P*cos(θ)^2
  B=R*L*sin(θ)^2+P*S*(1+cos(θ)^2)
  C=P*R*L
  D=(R-L)/2.
  #计算折光率μ  (μ^2=real)
  F=sqrt(abs(B^2 - A*C*4.))
  μ=[B+F,B-F]/2.0/A
  # polar=(μ .- S ) ./D
  μm=max(μ[1],μ[2])
  μ=real(sqrt(complex(μm,0)))
  return μ
end

"""
    DR_wave_vector(μ, freq)

由**折射率**与频率计算波的**波数（波矢大小）** `k`。

# 功能与算法概述
按 `k = μω/c` 换算波数，标量/数组均可广播。

# 参数说明
- `μ`: 折射率（无量纲，来自 `Dispersion_Relation`）。
- `freq`: 波频率（**Hz**）。

# 返回值
- 波数 `k`（**rad/m**），形状由广播规则决定。
"""
function DR_wave_vector(μ , freq)
  wave_vector=μ* freq / constants.c
  return wave_vector
end

"""
    DR_phase_velocity(μ)

由折射率计算波的**相速度**。

# 功能与算法概述
按真空光速与折射率之比换算相速度，支持标量/数组。

# 参数说明
- `μ`: 折射率（无量纲，须 > 0）。

# 返回值
- 相速度（**m/s**），形状与 `μ` 一致。

# 注意事项
- `μ = 0`（截止区）返回 `Inf`，调用方应先过滤 `μ ≤ 0` 的点。
"""
function DR_phase_velocity(μ)
  phase_velocity = constants.c / μ
  return phase_velocity
end

"""
    carculate_minimum_energy(θ, freq, Πe, Ωe, n)

计算满足**回旋共振条件**的粒子**最小能量** `E_min`。

# 功能与算法概述
用多普勒共振条件 `ω − nΩe = k·v∥`（`k` 由色散关系给出）解出平行速度，再按非相对论动能 `E = ½mₑv∥²` 换算为 eV。

# 参数说明
- `θ`: 波矢与背景磁场夹角（**弧度**）。
- `freq`: 波频率（Hz）。
- `Πe`: 电子等离子体频率（Hz）。
- `Ωe`: 电子回旋频率（Hz，带符号）。
- `n`: 共振阶数（`0` 为 Landau 共振，`±1, ±2…` 为回旋共振）。

# 返回值
- 共振粒子的最小能量（**eV**）。

# 注意事项
- 需先调用 `set_particles`；当前实现为单点计算。
- `cos θ → 0`（垂直传播）时结果发散至 `Inf`。
- 函数名 `carculate` 为 `calculate` 的拼写笔误，为兼容沿用。
"""
function carculate_minimum_energy(θ,freq,Πe,Ωe,n)
  # 默认所有输入皆为分度制
  # 单点计算
  # if degree_measure
  #   θ*=RAD
  #   freq =freq*2*π
  #   Πe   =Πe*2*π
  #   Ωe   =Ωe*2*π
  # end
  # NΠ=length(Πe)
  # Nf=length(freq)
  # Emin=zeros(Nf,NΠ)

  μ = Dispersion_Relation(θ,freq,Πe,Ωe)
  wave_vector = DR_wave_vector(μ , freq)
  v_para = (freq-n*Ωe)/wave_vector/cos(θ)
  Emin   = 0.5 * constants.me * v_para^2 / constants.eV
  return Emin
end
"""
    alfven_weve(B, ρ)

由磁场强度与等离子体**质量密度**计算 **Alfvén 速度** `v_A`。

# 功能与算法概述
采用理想 MHD 关系 `v_A = B/√(μ₀ρ)`（`μ₀` 取自 `constants.μ0`）。

# 参数说明
- `B`: 磁场强度（**T**，SI 单位）。
- `ρ`: 等离子体质量密度（**kg/m³**）。

# 返回值
- Alfvén 速度（**m/s**），标量或数组。

# 注意事项
- 输入须为 SI 单位；`B` 以 nT 给出时需先乘 `1e-9`。
- 仅适用于离子惯性尺度。
- 函数名 `weve` 为 `wave` 的拼写笔误，为兼容沿用。
"""
function alfven_weve(B,ρ)
  v = B/sqrt(constants.μ0*ρ)
  return v
end

end # module Cold_Plasma_Dispersion_Relation