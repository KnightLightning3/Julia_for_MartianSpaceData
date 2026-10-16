"""火星 IGRF/地壳磁场计算、坐标变换与磁力线追踪工具（纯 Julia 实现，不依赖 Fortran/DLL）。"""


module IGRF_calculate
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
using FortranFiles
using LinearAlgebra
using Statistics

# 通用坐标 / 磁场分量坐标变换的**权威**在 common 层（MarsCommon 的 marscommon/geometry.jl）。
# 这里只做必要依赖绑定，不保留本地副本、不做兼容转发。两档复用：
#   ① 父模块已有 MarsCommon → `const` 复用父实例。注册表 `:IGRF_calculate` 的 deps 已补
#      `:MarsCommon`（真实依赖），载入器会先备好规范实例，故**注册表载入路径同样走本档**，
#      实测 `IGRF_calculate.MarsCommon === MarsData.MarsCommon`、B 系列函数对象亦同一；
#   ② 否则（脚本直接 include 且父级没有该绑定）→ 自包含 include，保证独立可运行。
if isdefined(parentmodule(@__MODULE__), :MarsCommon)
    const MarsCommon = parentmodule(@__MODULE__).MarsCommon
else
    include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
end
using .MarsCommon: Bsphere2pc, Bpc2sphere

# -----------------export part -----------------------
# pc2sphere / sphere2pc remain internal for IGRF's hot paths; Bsphere2pc / Bpc2sphere are MarsCommon bindings.
export IGRF_pc,IGRF!
export trace_mag_line
#返回nT
# function linear_fit_mag(data,datam) #使用最小二乘法给模型三个维度加一个常数[a,b,c]来拟合模型和实际数据
#     x = data[:,1:3]
#     x1 = datam[:,1:3]
#     dx = x1 .- x
#     A = [ones(size(x1)[1]) x1[:,1] x1[:,2] x1[:,3]]
#     B = dx

# end
########### 以下函数只能计算单个点的关系
"""
    pc2sphere(x, y, z) -> (r, θ, ϕ)

将行星笛卡尔坐标转为球坐标 `(r, θ, ϕ)`（θ 为与 +Z 轴的夹角，即天顶角/余纬）。

# 功能与算法概述
以 `hypot` 求半径避免中间平方溢出，再由 `acos(z/r)` 得余纬、`atan(y, x)` 得经度（保留象限），
与 `sphere2pc` 互为正逆变换。

# 参数说明
- `x`: 笛卡尔 X 分量。
- `y`: 笛卡尔 Y 分量。
- `z`: 笛卡尔 Z 分量。

# 返回值
- `(r, θ, ϕ)`: 半径与两个**弧度制**角（元组，非数组，无堆分配）。

# 注意事项
- 方程与 `sphere2pc` 互为正逆变换；`r = 0` 时 `θ`/`ϕ` 未定义。
"""
function pc2sphere(x::Real, y::Real, z::Real)
    r = hypot(x, y, z)
    # θ = π/2 - atan(z,sqrt(x^2+y^2))
    θ = acos(z / r) # [0,π]
    ϕ = atan(y, x)  # (-π/2, π/2)
    return r, θ, ϕ
end
"""
    sphere2pc(r, θ, ϕ) -> (x, y, z)

将行星球坐标转为笛卡尔坐标，是 `pc2sphere` 的逆变换。

# 功能与算法概述
一次预计算 `sinθ/cosθ/sinϕ/cosϕ` 后按标准展开式算出 `(x, y, z)`（θ 为天顶角），
全程为标量运算，无堆分配。

# 参数说明
- `r`: 径向距离（单位与 `x`/`y`/`z` 一致，IGRF 模型中通常归一化为 `r/R_Mars`）。
- `θ`: 天顶角/余纬（**弧度**，`0` 指向 +Z）。
- `ϕ`: 经度（**弧度**）。

# 返回值
- `(x, y, z)`: 笛卡尔坐标元组（无堆分配）。
"""
function sphere2pc(r::Real, θ::Real, ϕ::Real)
    sinθ = sin(θ)
    cosθ = cos(θ)
    sinϕ = sin(ϕ)
    cosϕ = cos(ϕ)
    x = r * sinθ * cosϕ
    y = r * sinθ * sinϕ
    z = r * cosθ
    return x, y, z
end
###########
"""
    CALCULATE_SCHMIDT_COEFFICIENTS() -> (Matrix, Matrix)

预计算 IGRF 球谐展开所需的 Schmidt 准归一化因子 `SS` 与 Legendre 递推系数 `REALK`。

# 功能与算法概述
按 Schmidt 准归一化公式与关联 Legendre 函数的相邻阶递推关系，一次性生成两张
`(NIGRF+1)×(NIGRF+1)` 系数表，供球谐内核复用。

# 参数说明
- 无输入参数；依赖模块级常量 `NIGRF`（默认 110）。

# 返回值
- `(SS, REALK)`: 两个 `(NIGRF+1)×(NIGRF+1)` 的 `Matrix{Float64}` 元组。

# 注意事项
- 仅在模块初始化时调用一次，结果绑定为 `const`。
- 返回的是可变 `Matrix`（非静态数组），与 `GG`/`HH` 一致，便于按需原地更新系数。
- `NIGRF` 不变时结果完全确定。
"""
function CALCULATE_SCHMIDT_COEFFICIENTS()
    SS = zeros(NIGRF + 1, NIGRF + 1)
    REALK = zeros(NIGRF + 1, NIGRF + 1)
    SS[1, 1] = 1e0
    @inbounds for N = 1:NIGRF
        SS[N+1, 1] = (2 * N - 1) / (1 * N) * SS[N, 1]
        SS[N+1, 2] = sqrt(2 * N / (N + 1)) * SS[N+1, 1]
        for M = 2:N
            SS[N+1, M+1] = sqrt((N - M + 1) / (N + M)) * SS[N+1, M]
        end
    end
    @inbounds for N = 0:NIGRF
        for M = 0:NIGRF
            REALK[N+1, M+1] = ((N - 1)^2 - M^2) / ((2 * N - 3) * (2 * N - 1))
        end
    end
    return SS, REALK
end
"""
    read_gh() -> (Matrix, Matrix)

从 Fortran 无格式文件 `gh_gao` 中读取 IGRF 高斯球谐系数 `GG`、`HH`。

# 功能与算法概述
用 `FortranFile` 打开模块常量给出的文件，按 `(Float64, NIGRF+1, NIGRF+1)` 形状
顺序读出两张系数矩阵并以元组返回，避免外层额外分配。

# 参数说明
- 无参数；依赖模块级常量 `gh_filename` 与 `NIGRF`。

# 返回值
- `(GG, HH)`: 两个 `(NIGRF+1)×(NIGRF+1)` 的 `Matrix{Float64}` 元组。

# 注意事项
- `GG`/`HH` 必须是**可变 `Matrix`**（与 `set_B_compress` 的原地语义一致），
  便于按需原地更新系数（如换历元、重载系数表）。
- 本函数在模块加载时被调用一次：`const GG, HH = read_gh()`；文件缺失会导致模块加载失败。
"""
function read_gh()
    f = FortranFile(gh_filename)
    GG = read(f, (Float64, NIGRF + 1, NIGRF + 1))
    HH = read(f, (Float64, NIGRF + 1, NIGRF + 1))
    return GG, HH
end
"""
    rebuild_derived_tables!() -> Nothing

根据 `GG`/`HH`/`SS`/`REALK` 重建纯 Julia 球谐内核使用的派生系数表。

# 功能与算法概述
生成三张「次数 M 为第一下标」的 `(NIGRF+1)×(NIGRF+1)` 表，下标为 `[M+1, N+1]`：
`GS_T = SS.*GG`、`HS_T = SS.*HH`（Schmidt 因子已预乘进系数）、`REALK_T`（`REALK` 的转置）。
内核对固定阶数 N 沿 M 方向循环，M 连续存放后访存连续，编译器才能做 SIMD 向量化；
预乘则省掉内循环里每项两次乘法。

# 参数说明
- 无参数；依赖模块级常量 `GG`、`HH`、`SS`、`REALK`、`NIGRF`。

# 返回值
- `nothing`（原地写入 `GS_T`/`HS_T`/`REALK_T`）。

# 注意事项
- 模块加载时已调用一次。若之后**原地修改**了 `GG`/`HH`（更换系数、历元插值等），
  必须再调用本函数，否则纯 Julia 的 `IGRF` 仍使用旧系数。
- 只影响本模块的纯 Julia 内核；`GG`/`HH`/`SS`/`REALK` 的布局不变。
"""
function rebuild_derived_tables!()
    @inbounds for N = 0:NIGRF
        for M = 0:NIGRF
            GS_T[M+1, N+1] = SS[N+1, M+1] * GG[N+1, M+1]
            HS_T[M+1, N+1] = SS[N+1, M+1] * HH[N+1, M+1]
            REALK_T[M+1, N+1] = REALK[N+1, M+1]
        end
    end
    return nothing
end
"""
    IGRF_pc(x, y, z) -> (Bx, By, Bz)

在行星笛卡尔坐标处计算 IGRF/地壳磁场矢量（nT）。

# 功能与算法概述
先把位置转到球坐标，调用纯 Julia `IGRF` 求球坐标分量，再经 `Bsphere2pc` 旋转回笛卡尔分量，
是磁力线追踪/单粒子轨道的外部接口。

# 参数说明
- `x`: 笛卡尔 X 分量（**公里**）。
- `y`: 笛卡尔 Y 分量（**公里**）。
- `z`: 笛卡尔 Z 分量（**公里**）。

# 返回值
- `(Bx, By, Bz)`: 笛卡尔坐标系下的磁场分量（**nT**）。

# 注意事项
- 常用调用形式：`B_field = x -> IGRF_pc(x[1]/1e3, x[2]/1e3, x[3]/1e3) .* 1e-9`（转 T）。
"""
function IGRF_pc(x::Real, y::Real, z::Real)
    r, θ, ϕ = pc2sphere(x, y, z)
    Br, Bθ, Bϕ, _ = IGRF(r, θ, ϕ)
    Bx, By, Bz = Bsphere2pc(r, θ, ϕ, Br, Bθ, Bϕ)
    return Bx, By, Bz
end
"""
    IGRFWorkspace()

纯 Julia 球谐内核的可复用工作区：预分配的勒让德函数滚动行（P、DP、DDP 各三行）与 cos(mϕ)/sin(mϕ) 表。

# 功能与算法概述
`IGRF!`/`IGRF_dB!` 每次求值都需要若干长度 `NIGRF+1` 的临时向量。把它们放进工作区后，反复求值不再分配内存。
工作区内容只是草稿区：内核每次调用都「先写后读」，不依赖上一次遗留的内容，因此无需清零。

# 参数说明
- 无参数。

# 返回值
- `IGRFWorkspace`: 含 11 个长度 `NIGRF+1` 的 `Vector{Float64}`（约 10 KB）。

# 注意事项
- **同一时刻一个工作区只能被一个任务/线程使用**；多线程时每个任务各建一个（`IGRF_batch!` 已自动这样做）。
- 不要用 `Threads.threadid()` 去索引一个全局工作区池：任务可能在线程间迁移，会造成数据竞争。
"""
struct IGRFWorkspace
    Pm2::Vector{Float64}
    Pm1::Vector{Float64}
    Pc::Vector{Float64}
    DPm2::Vector{Float64}
    DPm1::Vector{Float64}
    DPc::Vector{Float64}
    DDPm2::Vector{Float64}
    DDPm1::Vector{Float64}
    DDPc::Vector{Float64}
    COSMPH::Vector{Float64}
    SINMPH::Vector{Float64}
end

IGRFWorkspace() = IGRFWorkspace(ntuple(_ -> zeros(NIGRF + 1), Val(11))...)

# cos(mϕ)/sin(mϕ) 递推的精确刷新间隔：每 TRIG_BLOCK 项用 sincos 重新算一次，块内用角度和递推。
const TRIG_BLOCK = 8

"""
    _fill_trig!(COSMPH, SINMPH, ϕ, sϕ, cϕ) -> nothing

填充 `COSMPH[m+1] = cos(mϕ)`、`SINMPH[m+1] = sin(mϕ)`（m = 0..NIGRF）。

# 功能与算法概述
每隔 `TRIG_BLOCK` 项重新精确计算一次（锚点），块内用角度和公式
`cos((m+1)ϕ) = cos(mϕ)cosϕ - sin(mϕ)sinϕ`、`sin((m+1)ϕ) = sin(mϕ)cosϕ + cos(mϕ)sinϕ` 递推。
锚点处先把 `m*ϕ` 拆成 `hi + lo`（`hi = m*ϕ` 的舍入结果，`lo` 用 `fma` 精确求得的舍入误差），
再按 `sin(hi+lo) ≈ sin(hi) + cos(hi)*lo`、`cos(hi+lo) ≈ cos(hi) - sin(hi)*lo` 修正，
消除乘积舍入带来的相位误差（`ϕ` 接近 ±π、m 接近 110 时可达约 3e-14 弧度）。
块内递推的舍入误差最多累积 `TRIG_BLOCK-1` 步（约 1e-15），同时避免了 222 次独立三角函数调用。

# 参数说明
- `COSMPH`, `SINMPH`: 长度 `NIGRF+1` 的输出向量。
- `ϕ`: 经度（弧度）；`sϕ`, `cϕ`: 调用方已算好的 `sin(ϕ)`、`cos(ϕ)`。

# 返回值
- `nothing`。

# 注意事项
- 参考实现（Fortran 与旧版）用 `cos(M*ϕ)` 直接求值，大 m 时乘积 `M*ϕ` 本身带最多约 3e-14 弧度的相位舍入，
  它们自身的误差就在该量级；本实现已对锚点做补偿，与参考实现的差异预期主要来自参考实现一侧。
- `fma` 在无硬件 FMA 的 CPU 上会退化为较慢的软件实现（每点 14 次），现代 x86-64/ARM 不受影响。
"""
function _fill_trig!(COSMPH::Vector{Float64}, SINMPH::Vector{Float64}, ϕ::Float64, sϕ::Float64, cϕ::Float64)
    @inbounds for M0 = 0:TRIG_BLOCK:NIGRF
        m0 = Float64(M0)
        hi = m0 * ϕ
        lo = fma(m0, ϕ, -hi)                  # m0*ϕ = hi + lo 中的 lo（精确）
        s, c = sincos(hi)
        s, c = s + c * lo, c - s * lo         # 一阶修正；lo 约 1e-14，二阶项可忽略
        COSMPH[M0+1] = c
        SINMPH[M0+1] = s
        for M = M0+1:min(M0 + TRIG_BLOCK - 1, NIGRF)
            c, s = c * cϕ - s * sϕ, s * cϕ + c * sϕ
            COSMPH[M+1] = c
            SINMPH[M+1] = s
        end
    end
    return nothing
end

"""
    IGRF!(ws, r, θ, ϕ) -> (BR, BT, BP, BB)

使用预分配工作区求值纯 Julia 球谐磁场（含 `B_compress` 均匀场项），稳态调用零分配。

# 功能与算法概述
与已移除的 Fortran `IGRF_110` 内核等价：沿阶数 N 递推关联 Legendre 函数 P/DP（只保留滚动三行），逐阶累加后乘径向因子
`(AA/r)^(N+2)`，最后叠加笛卡尔均匀场 `B_compress` 在球坐标下的投影。
- cos(mϕ)/sin(mϕ) 用分块递推（见 `_fill_trig!`）。
- 系数使用「M 连续」派生表 `GS_T`/`HS_T`/`REALK_T`（见 `rebuild_derived_tables!`），内层 M 循环 `@simd` 向量化。

# 参数说明
- `ws`: `IGRFWorkspace`，调用方独占使用。
- `r`: 径向距离（km）。
- `θ`: 余纬（**弧度**）；不要取 0 或 π（公式含 1/sinθ，与旧 Fortran 内核相同）。
- `ϕ`: 经度（**弧度**）。

# 返回值
- `NTuple{4,Float64}`: `(BR, BT, BP, BB)`，球坐标磁场三分量与总强度（nT）。

# 注意事项
- 读取模块级 `B_compress`；批量或并行期间不要修改它（`set_B_compress` 非线程安全）。
- 非 `Float64` 的实数参数会先转换为 `Float64`。
- 与已移除的 Fortran `IGRF_110` 内核相比实测差异约 1e-14～1e-13（相对 |B|），来源是参考实现用 `cos(M*ϕ)` 直接求值的相位舍入（见 models/test.jl 第 1 节）。
"""
function IGRF!(ws::IGRFWorkspace, r::Float64, θ::Float64, ϕ::Float64)
    AA = Float64(constants.R_Mars)
    bx = B_compress[1]
    by = B_compress[2]
    bz = B_compress[3]
    Pm2 = ws.Pm2
    Pm1 = ws.Pm1
    Pc = ws.Pc
    DPm2 = ws.DPm2
    DPm1 = ws.DPm1
    DPc = ws.DPc
    COSMPH = ws.COSMPH
    SINMPH = ws.SINMPH

    sϕ, cϕ = sincos(ϕ)
    SINTH, COSTH = sincos(θ)
    _fill_trig!(COSMPH, SINMPH, ϕ, sϕ, cϕ)

    # 滚动三行：Pm2 = 第 N-2 行，Pm1 = 第 N-1 行，Pc = 当前第 N 行；下标 M+1 对应次数 M。
    Pm1[1] = 1.0e0     # P[0,0]：第 0 行，供 N=1 使用
    DPm1[1] = 0.0e0    # DP[0,0]
    BR = 0.0e0
    BT = 0.0e0
    BP = 0.0e0
    AAr = AA / r
    AARRN = AAr^3      # (AA/r)^(N+2)，N=1 起；逐阶 ×(AA/r) 滚动更新

    @inbounds for N = 1:NIGRF
        XX = 0.0e0
        YY = 0.0e0
        ZZ = 0.0e0

        # 对角元 P[N,N]、次对角元 P[N,N-1]：只依赖上一行的对角元 P[N-1,N-1]（下标 N）
        Pc[N+1] = SINTH * Pm1[N]
        DPc[N+1] = SINTH * DPm1[N] + COSTH * Pm1[N]
        Pc[N] = COSTH * Pm1[N]
        DPc[N] = COSTH * DPm1[N] - SINTH * Pm1[N]

        # 递推：固定 N 时各 M 互相独立；Pc/DPc 与 Pm1/Pm2/DPm1/DPm2 是互不重叠的不同数组，
        # 故用 @simd ivdep 声明无循环携带依赖。
        @simd ivdep for M = 0:N-2
            k = REALK_T[M+1, N+1]
            Pc[M+1] = COSTH * Pm1[M+1] - k * Pm2[M+1]
            DPc[M+1] = COSTH * DPm1[M+1] - SINTH * Pm1[M+1] - k * DPm2[M+1]
        end

        # 求和：XX/YY/ZZ 是归约，@simd 允许编译器重排加法顺序。GS_T/HS_T 已含 Schmidt 因子。
        @simd for M = 0:N
            gs = GS_T[M+1, N+1]
            hs = HS_T[M+1, N+1]
            c = COSMPH[M+1]
            s = SINMPH[M+1]
            GCHS = gs * c + hs * s
            GSHC = gs * s - hs * c
            XX = XX + GCHS * Pc[M+1]
            YY = YY + GCHS * DPc[M+1]
            ZZ = ZZ + MFLOAT[M+1] * GSHC * Pc[M+1]
        end

        BR = BR + (N + 1) * AARRN * XX
        BT = BT + AARRN * YY
        BP = BP + AARRN * ZZ

        AARRN = AAr * AARRN
        Pm2, Pm1, Pc = Pm1, Pc, Pm2         # 行轮换：只交换引用，旧 Pm2 的内存成为下一阶的 Pc
        DPm2, DPm1, DPc = DPm1, DPc, DPm2
    end

    # 均匀场 B_compress（笛卡尔 -> 球坐标）的投影，与 Fortran 公式一致
    BR = BR + SINTH * cϕ * bx + SINTH * sϕ * by + COSTH * bz
    BT = -BT + COSTH * cϕ * bx + COSTH * sϕ * by - SINTH * bz
    BP = BP / SINTH - sϕ * bx + cϕ * by

    BB = sqrt(BR^2 + BT^2 + BP^2)
    return (BR, BT, BP, BB)
end

IGRF!(ws::IGRFWorkspace, r::Real, θ::Real, ϕ::Real) = IGRF!(ws, Float64(r), Float64(θ), Float64(ϕ))

"""
    IGRF_dB!(ws, r, θ, ϕ) -> NamedTuple

在 `IGRF!` 基础上同时给出磁场对 (r, θ, ϕ) 的全部偏导，字段与已移除的 Fortran `IGRF_for_RK4_dB` 内核一一对应。

# 功能与算法概述
额外递推二阶导 `DDP`（同样只保留滚动三行），并累加 7 个和式（`XX,YY,ZZ,DYY,DZY,DYZ,DZZ`）。
旧 Fortran 内核中 `DXX,DYX,DZX,DXY,DXZ` 与 `XX,YY,ZZ` 相同，这里直接复用，不重复累加。

# 参数说明
- `ws`, `r`, `θ`, `ϕ`: 同 `IGRF!`。

# 返回值
`NamedTuple`，字段（nT、km、弧度）：
- `BR, BT, BP, BB`: 磁场三分量与总强度。
- `DRDS, DTDS, DPDS`: 沿磁力线单位弧长的 dr/ds、dθ/ds、dϕ/ds（即 `B_norm`，磁力线追踪的方向场）。
- `DBBDRR, DBBDTH, DBBDPH`: ln|B| 对 r、θ、ϕ 的偏导；`DB` 为其模（RK4 自适应步长用的误差指标）。
- `DBRDRR, DBTDRR, DBPDRR, DBRDTH, DBTDTH, DBPDTH, DBRDPH, DBTDPH, DBPDPH`: 各分量对 r、θ、ϕ 的偏导
  （命名为 `DB<分量>D<变量>`；对 r 的单位 nT/km，对角度的单位 nT/rad，**不含** 1/r 缩放）。

# 注意事项
- 含 `cotθ` 与 1/sinθ，极点附近发散（与旧 Fortran 内核相同）。
- 比 `IGRF!` 慢（多一组二阶导递推和 4 个和式），只在需要导数时使用。
- `B_compress` 的偏导项已按 Fortran 公式包含在内。
"""
function IGRF_dB!(ws::IGRFWorkspace, r::Float64, θ::Float64, ϕ::Float64)
    AA = Float64(constants.R_Mars)
    bx = B_compress[1]
    by = B_compress[2]
    bz = B_compress[3]
    Pm2 = ws.Pm2
    Pm1 = ws.Pm1
    Pc = ws.Pc
    DPm2 = ws.DPm2
    DPm1 = ws.DPm1
    DPc = ws.DPc
    DDPm2 = ws.DDPm2
    DDPm1 = ws.DDPm1
    DDPc = ws.DDPc
    COSMPH = ws.COSMPH
    SINMPH = ws.SINMPH

    sϕ, cϕ = sincos(ϕ)
    SINTH, COSTH = sincos(θ)
    COTTH = COSTH / SINTH
    _fill_trig!(COSMPH, SINMPH, ϕ, sϕ, cϕ)

    Pm1[1] = 1.0e0
    DPm1[1] = 0.0e0
    DDPm1[1] = 0.0e0
    BR = 0.0e0
    BT = 0.0e0
    BP = 0.0e0
    DBRDRR = 0.0e0
    DBTDRR = 0.0e0
    DBPDRR = 0.0e0
    DBRDTH = 0.0e0
    DBTDTH = 0.0e0
    DBPDTH = 0.0e0
    DBRDPH = 0.0e0
    DBTDPH = 0.0e0
    DBPDPH = 0.0e0
    AAr = AA / r
    AARRN = AAr^3

    @inbounds for N = 1:NIGRF
        XX = 0.0e0
        YY = 0.0e0
        ZZ = 0.0e0
        DYY = 0.0e0
        DZY = 0.0e0
        DYZ = 0.0e0
        DZZ = 0.0e0

        Pc[N+1] = SINTH * Pm1[N]
        DPc[N+1] = SINTH * DPm1[N] + COSTH * Pm1[N]
        DDPc[N+1] = SINTH * DDPm1[N] + COSTH * DPm1[N] * 2.0e0 - SINTH * Pm1[N]
        Pc[N] = COSTH * Pm1[N]
        DPc[N] = COSTH * DPm1[N] - SINTH * Pm1[N]
        DDPc[N] = COSTH * DDPm1[N] - SINTH * DPm1[N] * 2.0e0 - COSTH * Pm1[N]

        @simd ivdep for M = 0:N-2
            k = REALK_T[M+1, N+1]
            Pc[M+1] = COSTH * Pm1[M+1] - k * Pm2[M+1]
            DPc[M+1] = COSTH * DPm1[M+1] - SINTH * Pm1[M+1] - k * DPm2[M+1]
            DDPc[M+1] = COSTH * DDPm1[M+1] - SINTH * DPm1[M+1] * 2.0e0 - COSTH * Pm1[M+1] - k * DDPm2[M+1]
        end

        @simd for M = 0:N
            gs = GS_T[M+1, N+1]
            hs = HS_T[M+1, N+1]
            c = COSMPH[M+1]
            s = SINMPH[M+1]
            GCHS = gs * c + hs * s
            GSHC = gs * s - hs * c
            mf = MFLOAT[M+1]
            PP = Pc[M+1]
            DPP = DPc[M+1]
            DDPP = DDPc[M+1]
            XX = XX + GCHS * PP
            YY = YY + GCHS * DPP
            ZZ = ZZ + mf * GSHC * PP
            DYY = DYY + GCHS * DDPP
            DZY = DZY + mf * GSHC * (PP * COTTH - DPP)
            DYZ = DYZ + mf * GSHC * DPP
            DZZ = DZZ + mf * mf * GCHS * PP
        end

        A2 = AARRN            # (AA/r)^(N+2)
        A3 = AAr * AARRN      # (AA/r)^(N+3)
        n1 = N + 1
        n2 = N + 2
        BR = BR + n1 * A2 * XX
        BT = BT + A2 * YY
        BP = BP + A2 * ZZ
        DBRDRR = DBRDRR + n1 * n2 * A3 * XX
        DBTDRR = DBTDRR + n2 * A3 * YY
        DBPDRR = DBPDRR + n2 * A3 * ZZ
        DBRDTH = DBRDTH + n1 * A2 * YY
        DBTDTH = DBTDTH + A2 * DYY
        DBPDTH = DBPDTH + A2 * DZY
        DBRDPH = DBRDPH + n1 * A2 * ZZ
        DBTDPH = DBTDPH + A2 * DYZ
        DBPDPH = DBPDPH + A2 * DZZ

        AARRN = A3
        Pm2, Pm1, Pc = Pm1, Pc, Pm2
        DPm2, DPm1, DPc = DPm1, DPc, DPm2
        DDPm2, DDPm1, DDPc = DDPm1, DDPc, DDPm2
    end

    BR = BR + SINTH * cϕ * bx + SINTH * sϕ * by + COSTH * bz
    BT = -BT + COSTH * cϕ * bx + COSTH * sϕ * by - SINTH * bz
    BP = BP / SINTH - sϕ * bx + cϕ * by

    DBRDRR = -DBRDRR / AA
    DBTDRR = DBTDRR / AA
    DBPDRR = -DBPDRR / AA / SINTH

    DBRDTH = DBRDTH + COSTH * cϕ * bx + COSTH * sϕ * by - SINTH * bz
    DBTDTH = -DBTDTH - SINTH * cϕ * bx - SINTH * sϕ * by - COSTH * bz
    DBPDTH = -DBPDTH / SINTH + 0.0e0

    DBRDPH = -DBRDPH - SINTH * sϕ * bx + SINTH * cϕ * by
    DBTDPH = DBTDPH - COSTH * sϕ * bx + COSTH * cϕ * by
    DBPDPH = DBPDPH / SINTH - cϕ * bx - sϕ * by

    BBS = BR^2 + BT^2 + BP^2
    BB = sqrt(BBS)

    DRDS = BR / BB
    DTDS = BT / (BB * r)
    DPDS = BP / (BB * r * SINTH)

    DBBDRR = (BR * DBRDRR + BT * DBTDRR + BP * DBPDRR) / BBS
    DBBDTH = (BR * DBRDTH + BT * DBTDTH + BP * DBPDTH) / BBS
    DBBDPH = (BR * DBRDPH + BT * DBTDPH + BP * DBPDPH) / BBS
    DB = sqrt(DBBDRR^2 + DBBDTH^2 + DBBDPH^2)

    return (BR=BR, BT=BT, BP=BP, BB=BB,
        DRDS=DRDS, DTDS=DTDS, DPDS=DPDS,
        DBBDRR=DBBDRR, DBBDTH=DBBDTH, DBBDPH=DBBDPH, DB=DB,
        DBRDRR=DBRDRR, DBTDRR=DBTDRR, DBPDRR=DBPDRR,
        DBRDTH=DBRDTH, DBTDTH=DBTDTH, DBPDTH=DBPDTH,
        DBRDPH=DBRDPH, DBTDPH=DBTDPH, DBPDPH=DBPDPH)
end

IGRF_dB!(ws::IGRFWorkspace, r::Real, θ::Real, ϕ::Real) = IGRF_dB!(ws, Float64(r), Float64(θ), Float64(ϕ))

"""
    IGRF(r, θ, ϕ) -> (BR, BT, BP, BB)

便捷接口：内部临时创建工作区后调用 `IGRF!`（每次调用分配约 10 KB）。

# 功能与算法概述
等价于 `IGRF!(IGRFWorkspace(), r, θ, ϕ)`；含 `B_compress` 均匀场项（与旧 Fortran 内核对齐）。

# 参数说明
- `r`: 径向距离（km）；`θ`: 余纬（弧度）；`ϕ`: 经度（弧度）。

# 返回值
- `(BR, BT, BP, BB)`: 球坐标磁场三分量与总强度（nT）。

# 注意事项
- 循环或批量求值请自行创建一个 `IGRFWorkspace` 并用 `IGRF!`，或直接用 `IGRF_batch!`，避免反复分配。
"""
IGRF(r::Real, θ::Real, ϕ::Real) = IGRF!(IGRFWorkspace(), Float64(r), Float64(θ), Float64(ϕ))

"""
    IGRF_dB(r, θ, ϕ) -> NamedTuple

便捷接口：临时创建工作区后调用 `IGRF_dB!`，返回值字段见 `IGRF_dB!`。
"""
IGRF_dB(r::Real, θ::Real, ϕ::Real) = IGRF_dB!(IGRFWorkspace(), Float64(r), Float64(θ), Float64(ϕ))

"""
    IGRF_batch!(out, rs, θs, ϕs; min_chunk=256) -> out

多线程批量求值磁场：`out[i] = IGRF!(ws, rs[i], θs[i], ϕs[i])`。

# 功能与算法概述
把点集均分成不超过 `Threads.nthreads()` 个连续块（每块至少约 `min_chunk` 个点），每块起一个任务，任务内创建独占的
`IGRFWorkspace` 并串行求值；点数不足两块时直接串行。各点计算互不依赖，结果与线程数、分块方式无关（逐位相同）。

# 参数说明
- `out`: 预分配的输出向量，元素类型 `NTuple{4,Float64}`，长度须与输入一致。
- `rs`, `θs`, `ϕs`: 等长的坐标向量（km、弧度、弧度）。
- `min_chunk`: 每个任务至少处理的点数。任务过多时线程唤醒与调度的固定开销会盖过收益
  （64 线程 Windows 实测：`min_chunk=1` 时固定开销约 12～15 ms，且与点数几乎无关），所以块数被限制为 `cld(n, min_chunk)`。

# 返回值
- `out`（原地写入）。

# 注意事项
- 需用 `julia -t N`（或 `-t auto`）启动才有并行加速；单线程时退化为串行。
- 批量期间不要修改 `B_compress`。
- 每次调用只为每个任务分配一个工作区，与点数无关。
"""
function IGRF_batch!(out::AbstractVector{NTuple{4,Float64}}, rs::AbstractVector{<:Real}, θs::AbstractVector{<:Real}, ϕs::AbstractVector{<:Real}; min_chunk::Int=256)
    n = length(rs)
    (length(θs) == n && length(ϕs) == n && length(out) == n) || throw(DimensionMismatch("IGRF_batch!: out/rs/θs/ϕs 长度必须一致"))
    n == 0 && return out
    nchunk = min(Threads.nthreads(), cld(n, max(min_chunk, 1)))
    if nchunk <= 1
        # 点数太少：直接在当前线程串行，省掉任务创建与线程唤醒的固定开销。
        # 注意：本分支的工作区变量名不能叫 ws —— 闭包捕获的是变量而非值，
        # 与下面 @spawn 块内同名会让所有任务共用同一个工作区，产生数据竞争。
        ws_serial = IGRFWorkspace()
        @inbounds for i in 1:n
            out[i] = IGRF!(ws_serial, rs[i], θs[i], ϕs[i])
        end
        return out
    end
    csize = cld(n, nchunk)
    @sync for c in 1:nchunk
        lo = (c - 1) * csize + 1
        hi = min(c * csize, n)
        lo > hi && continue
        Threads.@spawn begin
            ws = IGRFWorkspace()
            @inbounds for i in lo:hi
                out[i] = IGRF!(ws, rs[i], θs[i], ϕs[i])
            end
        end
    end
    return out
end

"""
    IGRF_batch(rs, θs, ϕs) -> Vector{NTuple{4,Float64}}

`IGRF_batch!` 的分配输出版本。
"""
IGRF_batch(rs::AbstractVector{<:Real}, θs::AbstractVector{<:Real}, ϕs::AbstractVector{<:Real}; kwargs...) =
    IGRF_batch!(Vector{NTuple{4,Float64}}(undef, length(rs)), rs, θs, ϕs; kwargs...)
"""
    mag_trace_Euler_step(r0, θ0, ϕ0; dir=1.0, step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000)

用定步长一阶 Euler 法追踪磁力线（速度最快但精度最低）。

# 功能与算法概述
每步调纯 Julia `IGRF!` 得场矢量，沿单位场方向以弧长 `Δs = dir·step` 推进 `(r, θ, ϕ)`
（`θ`/`ϕ` 分别除以 `r`、`r·sinθ` 折算为角增量）。

# 参数说明
- `r0`, `θ0`, `ϕ0`: 起始点球坐标（`r` 公里，角度**弧度**）。
- `dir`: 追踪方向（`±1.0`）。
- `step`: 定步长（弧长）。
- `r_range`: 终止径向区间（公里）。
- `max_trace`: 最大步数。

# 返回值
- `Matrix{Float64}`: `Nsteps×6`，列为 `[r, θ, ϕ, Br, Bθ, Bϕ]`。

# 注意事项
- 一阶精度要求**很小的步长**才能避免径向漂移；宏现效果是磁力线会慢慢偏离真实轨迹。
- 磁赤道附近 `sinθ → 0`，`ϕ` 的推进量会放大，需注意数值稳定性。
- 一阶精度低（相对高精度参考线最大偏差约 1 km），高精度场景请用默认的 `:dp5`（`mag_trace_dp5`）。
"""
function mag_trace_Euler_step(r0::Real, θ0::Real, ϕ0::Real; dir=1.0, step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000)  #欧拉方法的固定步长磁力线追踪,输入球坐标，返回球坐标
    r, θ, ϕ = r0, θ0, ϕ0
    trace_steps = 0
    Δs = dir * step
    B_data = Matrix{Float64}(undef, max_trace,6)#zeros(max_trace, 6)
    ws = IGRFWorkspace()      # 纯 Julia 内核：一次分配、循环内零分配
    trace_state = true
    while trace_state
        Br, Bθ, Bϕ, BB = IGRF!(ws, r, θ, ϕ)
        trace_steps += 1
        @inbounds B_data[trace_steps, :] = [r, θ, ϕ, Br, Bθ, Bϕ]
        r, θ, ϕ = r + Br / BB * Δs, θ + Bθ / BB * Δs / r, ϕ + Bϕ / BB * Δs / r / sin(θ)
        r_state = r
        trace_state = r_state >= r_range[1] && r_state <= r_range[2] && trace_steps < max_trace
    end
    return B_data[1:trace_steps, :]
end
"""
    combina_two_dir_trace(B_data_1, B_data_2; to_pc=false) -> Matrix{Float64}

把两个相反方向追踪得到的磁力线段拼接为一条完整磁力线。

# 功能与算法概述
把第二段按行反序后与第一段纵向拼接（`[B_data_2; B_data_1]`）使两段在起点相接；
`to_pc = true` 时逐行把球坐标位置与磁场分量都转为笛卡尔。

# 参数说明
- `B_data_1`: 正向追踪结果（`N1×6`，列为 `[r,θ,ϕ,Br,Bθ,Bϕ]`）。
- `B_data_2`: 反向追踪结果（`N2×6`，同列序）。
- `to_pc`: 是否输出笛卡尔坐标（默认 `false`，即保持球坐标）。

# 返回值
- `Matrix{Float64}`: `(N2+N1)×6` 的拼接后磁力线数据。

# 注意事项
- **C2 修复**：模块内部已改为裸名 `sphere2pc` / `Bsphere2pc`，不再使用 `IGRF_calculate.` 前缀，
  避免 `to_pc=true` 时出现 `UndefVarError`。
- 两段的重叠起点会被保留两次（拼接处有重复行）。
"""
function combina_two_dir_trace(B_data_1, B_data_2; to_pc=false) # 翻转第二个，获得指向磁场方向的磁力线
    B_data_2 = reverse(B_data_2, dims=1)
    B_data = [B_data_2; B_data_1]
    if to_pc
        mag_line_num = length(B_data[:, 1])
        data = zeros(mag_line_num, 6)
        @inbounds for i in 1:mag_line_num
            x = B_data[i, :]
            # C2 修复：模块内部直接使用裸名，不再通过 IGRF_calculate. 前缀自引用
            px, py, pz = sphere2pc(x[1], x[2], x[3])
            Bx, By, Bz = Bsphere2pc(x[1], x[2], x[3], x[4], x[5], x[6])
            data[i, :] = [px, py, pz, Bx, By, Bz]
        end
        B_data = data
    end
    return B_data
end
"""
    get_mag_line_s(data) -> Dict

为磁力线结果字典原地补充沿线的弧长、海拔与磁场总强度。

# 功能与算法概述
对 `:position` 逐行累计欧氏距离得弧长 `:S`（首元素为 0），并额外写入
距参考半径的海拔 `:alt` 与 `"B"` 的模长 `:B_total`。

# 参数说明
- `data::Dict`: 标准磁力线结果字典，需含 `:position`（`N×3`）与 `"B"`（`N×3`）。

# 返回值
- `Dict`: 已注入 `:S`、`:alt`、`:B_total` 的同一字典（原地修改）。

# 注意事项
- 磁场键使用的是**字符串键** `"B"`（而其它键为 Symbol）；若传入字典只有 `:B` 键，
  优先读 `:B`，缺失时回退 `"B"`。
- 弧长基于笛卡尔坐标点间欧氏距离，与追踪步长（弧长参数）不完全一致。
"""
function get_mag_line_s(data) #取得磁力线的长度关系,需要标准磁力线数据结构
    position = data[:position]
    mag_line_num = length(position[:, 1])
    s = zeros(mag_line_num)
    s[1] = 0
    @inbounds for i in 2:mag_line_num
        x1 = position[i-1, 1:3]
        x2 = position[i, 1:3]
        s[i] = s[i-1] + norm(x2 - x1)
    end
    data[:S] = s
    data[:alt] = [norm(x) for x in eachrow(position)] .- constants.R_Mars
    B = get(data, :B, nothing)
    if B === nothing
        B = get(data, "B", nothing)
    end
    data[:B_total] = [norm(x) for x in eachrow(B)]
    return data
end
# ---------------- Dormand–Prince 5(4) 系数（FSAL，含稠密输出）----------------
const DP_A21 = 1 / 5
const DP_A31 = 3 / 40
const DP_A32 = 9 / 40
const DP_A41 = 44 / 45
const DP_A42 = -56 / 15
const DP_A43 = 32 / 9
const DP_A51 = 19372 / 6561
const DP_A52 = -25360 / 2187
const DP_A53 = 64448 / 6561
const DP_A54 = -212 / 729
const DP_A61 = 9017 / 3168
const DP_A62 = -355 / 33
const DP_A63 = 46732 / 5247
const DP_A64 = 49 / 176
const DP_A65 = -5103 / 18656
const DP_B1 = 35 / 384          # 五阶解权重（b2 = b7 = 0）
const DP_B3 = 500 / 1113
const DP_B4 = 125 / 192
const DP_B5 = -2187 / 6784
const DP_B6 = 11 / 84
const DP_E1 = 71 / 57600        # 五阶与四阶解之差（误差估计）
const DP_E3 = -71 / 16695
const DP_E4 = 71 / 1920
const DP_E5 = -17253 / 339200
const DP_E6 = 22 / 525
const DP_E7 = -1 / 40
const DP_D1 = -12715105075 / 11282082432   # 四阶稠密输出（Hairer, dopri5）
const DP_D3 = 87487479700 / 32700410799
const DP_D4 = -10690763975 / 1880347072
const DP_D5 = 701980252875 / 199316789632
const DP_D6 = -1453857185 / 822651844
const DP_D7 = 69997945 / 29380423

"""
    _cart_to_sph(x) -> (r, θ, ϕ)

笛卡尔位置转球坐标（km、弧度）。

# 功能与算法概述
`θ = atan(ρ, z)`（ρ 为到极轴的距离）在极轴附近比 `acos(z/r)` 更准确；θ 被限制在 `[1e-8, π-1e-8]`，
使恰好落在极轴上的点不会触发场内核中的 `1/sinθ` 除零。

# 参数说明
- `x`: `NTuple{3,Float64}`，笛卡尔坐标（km）。

# 返回值
- `(r, θ, ϕ)`: 半径（km）、余纬（弧度）、经度（弧度，范围 `(-π, π]`）。

# 注意事项
- 仅供 `mag_trace_dp5` 内部使用。
"""
function _cart_to_sph(x::NTuple{3,Float64})
    ρ = hypot(x[1], x[2])
    r = hypot(ρ, x[3])
    θ = clamp(atan(ρ, x[3]), 1e-8, π - 1e-8)
    ϕ = atan(x[2], x[1])
    return r, θ, ϕ
end

"""
    _bhat!(ws, x, dirn) -> NTuple{3,Float64}

笛卡尔位置 `x` 处的单位磁场方向（乘以 `dirn = ±1`），即磁力线按弧长参数化的 ODE 右端项。

# 功能与算法概述
`x` 转球坐标 → 调 `IGRF!` 得球坐标磁场 → 转回笛卡尔 → 归一化。ODE 在笛卡尔坐标下积分，
避免了球坐标 `dϕ/ds = Bϕ/(B r sinθ)` 在极点处的奇异。

# 参数说明
- `ws`: 调用方独占的 `IGRFWorkspace`。
- `x`: `NTuple{3,Float64}`，笛卡尔位置（km）。
- `dirn`: `+1.0` 顺场，`-1.0` 逆场。

# 返回值
- `NTuple{3,Float64}`: 单位切向量（场为零时含 `Inf/NaN`，由调用方的误差检查捕获）。

# 注意事项
- 仅供 `mag_trace_dp5` 内部使用；读取模块级 `B_compress`。
"""
function _bhat!(ws::IGRFWorkspace, x::NTuple{3,Float64}, dirn::Float64)
    r, θ, ϕ = _cart_to_sph(x)
    Br, Bθ, Bϕ, BB = IGRF!(ws, r, θ, ϕ)
    sθ, cθ = sincos(θ)
    sϕ, cϕ = sincos(ϕ)
    bx = sθ * cϕ * Br + cθ * cϕ * Bθ - sϕ * Bϕ
    by = sθ * sϕ * Br + cθ * sϕ * Bθ + cϕ * Bϕ
    bz = cθ * Br - sθ * Bθ
    f = dirn / BB
    return (f * bx, f * by, f * bz)
end

"""
    mag_trace_dp5(r0, θ0, ϕ0; dir=1.0, step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000, xtol=1e-3, hmax=25.0, h0=1.0, threaded_output=false, thread_min=5000) -> Matrix{Float64}

纯 Julia 的自适应高阶磁力线追踪：Dormand–Prince 5(4) + 笛卡尔坐标 + 弧长参数化，按固定弧长间隔输出。

# 功能与算法概述
- 积分 `dx/ds = ±B(x)/|B(x)|`（`s` 为弧长，笛卡尔坐标），用 Dormand–Prince 5(4) 嵌入式 RK（FSAL，每个接受步 6 次场求值）。
- 步长按「五阶解与四阶解之差的模 / `xtol`」控制：`h_new = h·clamp(0.9·err^(-1/5), 0.2, 5)`，被拒绝的步按同一公式缩小并重算，`h ≤ hmax`。
- 输出点取在弧长 `k·step`（`k = 1, 2, ...`），位置由 DP5 的四阶稠密输出插值得到（不增加场求值），
  各输出点处的磁场再由 `IGRF!` 精确求值（点数较多时用 `IGRF_batch!` 多线程）。
- 首行恒为起点本身；遇到第一个落在 `r_range` 之外的输出点即终止（该点不输出），行数达到 `max_trace` 也终止。
  与 `mag_trace_Euler_step` 的终止约定一致。

# 参数说明
- `r0`, `θ0`, `ϕ0`: 起点球坐标（km、弧度、弧度）。
- `dir`: `+1.0` 顺场、`-1.0` 逆场（其余值按符号取 ±1）。
- `step`: 输出点的弧长间隔（km）；它**不是**积分步长。
- `r_range`: 允许的径向范围（km），超出即终止。
- `max_trace`: 最大输出行数（含起点）。
- `xtol`: **单步**位置误差容限（km），默认 1e-3（1 m）。全线偏差会随步数累积：实测约为 `xtol` 的 1～10 倍
  （步长被 `hmax` 限制、容差不起作用时约 1 倍；`hmax` 放大或线很长时更大）。要保证全线偏差不超过 ε，取 `xtol ≈ ε/10`。
- `hmax`: 积分步长上限（km）。默认 25 是折中：在实测数据上放大到 50～100 只快 20～30%，全线偏差却增大 5～14 倍。
- `h0`: 初始试探步长（km）。
- `threaded_output`: 输出点较多时是否用多线程求值磁场。默认 `false`：本函数常在外层已并行（`trace_mag_lines`）时被调用，嵌套并行只会争抢线程；单线单独调用且输出点数远超 `thread_min` 时可显式开启（修复数据竞争后实测 `IGRF_batch!` 在 1 万点以上比串行快约一个数量级）。
- `thread_min`: 单个方向的输出点数不少于该值才启用多线程求值。`IGRF_batch!` 有固定启动开销：在 64 线程的 Windows
  机器上，2000 点以下多线程反而更慢，约 1 万点起才有明显收益，所以默认取 5000；合适的值与机器有关，可用测试脚本第 6 节标定。

# 返回值
- `Matrix{Float64}`: `Nsteps×6`，列为 `[r, θ, ϕ, Br, Bθ, Bϕ]`（km、弧度、nT），与其它追踪器格式相同。

# 注意事项
- 与 Euler 的差别：Euler 的位置误差随步数累积（0.5 km 步长时可达 km 量级），本方法由 `xtol` 控制；
  但每个输出点仍需一次场求值，因此要显著减少计算量应增大 `step`。
- 起点或中途点落在极轴上时 θ 被夹到 `[1e-8, π-1e-8]`（位置偏移约 3 cm），不会出现 NaN；磁力线穿过极点也能正常积分。
  因此起点恰在极轴上时，首行输出的 θ 是夹后的值，而不是输入值。
- 输出的 `ϕ` 已折叠到 `(-π, π]`（Euler 版的 `ϕ` 是累加的、可能越界），转笛卡尔后一致。
- 场为零（磁零点）或数值异常时提前终止，返回已得到的行。
- 读取模块级 `B_compress`；追踪期间不要修改它。
"""
function mag_trace_dp5(r0::Real, θ0::Real, ϕ0::Real; dir=1.0, step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000, xtol=1e-3, hmax=25.0, h0=1.0, threaded_output::Bool=false, thread_min::Int=5000)
    stepf = Float64(step)
    xtolf = Float64(xtol)
    hmaxf = Float64(hmax)
    (stepf > 0 && xtolf > 0 && hmaxf > 0) || throw(ArgumentError("mag_trace_dp5: step、xtol、hmax 必须为正"))
    rmin = Float64(r_range[1])
    rmax = Float64(r_range[2])
    dirn = dir >= 0 ? 1.0 : -1.0

    ws = IGRFWorkspace()
    rs = Float64[]
    θs = Float64[]
    ϕs = Float64[]
    sizehint!(rs, min(max_trace, 4096))
    sizehint!(θs, min(max_trace, 4096))
    sizehint!(ϕs, min(max_trace, 4096))
    θ0c = clamp(Float64(θ0), 1e-8, π - 1e-8)       # 起点恰在极轴上时避免 1/sinθ 除零
    push!(rs, Float64(r0))
    push!(θs, θ0c)
    push!(ϕs, Float64(ϕ0))

    sθ0, cθ0 = sincos(θ0c)
    sϕ0, cϕ0 = sincos(Float64(ϕ0))
    x = (Float64(r0) * sθ0 * cϕ0, Float64(r0) * sθ0 * sϕ0, Float64(r0) * cθ0)
    k1 = _bhat!(ws, x, dirn)
    s = 0.0
    kout = 1                       # 下一个输出点序号，对应弧长 kout*step
    h = min(hmaxf, Float64(h0))
    done = max_trace <= 1
    nsteps = 0
    max_steps = 20 * max_trace

    while !done && nsteps < max_steps && h > 1e-10
        nsteps += 1
        # ---- Dormand–Prince 5(4) 一步 ----
        k2 = _bhat!(ws, x .+ h .* (DP_A21 .* k1), dirn)
        k3 = _bhat!(ws, x .+ h .* (DP_A31 .* k1 .+ DP_A32 .* k2), dirn)
        k4 = _bhat!(ws, x .+ h .* (DP_A41 .* k1 .+ DP_A42 .* k2 .+ DP_A43 .* k3), dirn)
        k5 = _bhat!(ws, x .+ h .* (DP_A51 .* k1 .+ DP_A52 .* k2 .+ DP_A53 .* k3 .+ DP_A54 .* k4), dirn)
        k6 = _bhat!(ws, x .+ h .* (DP_A61 .* k1 .+ DP_A62 .* k2 .+ DP_A63 .* k3 .+ DP_A64 .* k4 .+ DP_A65 .* k5), dirn)
        xn = x .+ h .* (DP_B1 .* k1 .+ DP_B3 .* k3 .+ DP_B4 .* k4 .+ DP_B5 .* k5 .+ DP_B6 .* k6)
        k7 = _bhat!(ws, xn, dirn)                     # FSAL：接受后即下一步的 k1
        e = h .* (DP_E1 .* k1 .+ DP_E3 .* k3 .+ DP_E4 .* k4 .+ DP_E5 .* k5 .+ DP_E6 .* k6 .+ DP_E7 .* k7)
        errn = sqrt(e[1]^2 + e[2]^2 + e[3]^2) / xtolf
        isfinite(errn) || break                       # 磁零点或数值异常：停止

        if errn <= 1.0
            # ---- 接受：用稠密输出填充 [s, s+h] 内的全部输出点 ----
            ydiff = xn .- x
            bspl = h .* k1 .- ydiff
            r4 = ydiff .- h .* k7 .- bspl
            r5 = h .* (DP_D1 .* k1 .+ DP_D3 .* k3 .+ DP_D4 .* k4 .+ DP_D5 .* k5 .+ DP_D6 .* k6 .+ DP_D7 .* k7)
            while kout * stepf <= s + h
                t = (kout * stepf - s) / h
                u = 1.0 - t
                xo = x .+ t .* (ydiff .+ u .* (bspl .+ t .* (r4 .+ u .* r5)))
                ro, θo, ϕo = _cart_to_sph(xo)
                if !(rmin <= ro <= rmax)
                    done = true
                    break
                end
                push!(rs, ro)
                push!(θs, θo)
                push!(ϕs, ϕo)
                kout += 1
                if length(rs) >= max_trace
                    done = true
                    break
                end
            end
            s += h
            x = xn
            k1 = k7
            fac = errn == 0.0 ? 5.0 : min(5.0, 0.9 * errn^(-0.2))
        else
            fac = max(0.2, 0.9 * errn^(-0.2))          # 拒绝：缩小步长重算
        end
        h = min(hmaxf, h * fac)
    end

    # ---- 输出点处的磁场（精确求值）----
    n = length(rs)
    Bs = Vector{NTuple{4,Float64}}(undef, n)
    if threaded_output && n >= thread_min
        IGRF_batch!(Bs, rs, θs, ϕs)
    else
        @inbounds for i in 1:n
            Bs[i] = IGRF!(ws, rs[i], θs[i], ϕs[i])
        end
    end
    out = Matrix{Float64}(undef, n, 6)
    @inbounds for i in 1:n
        out[i, 1] = rs[i]
        out[i, 2] = θs[i]
        out[i, 3] = ϕs[i]
        out[i, 4] = Bs[i][1]
        out[i, 5] = Bs[i][2]
        out[i, 6] = Bs[i][3]
    end
    return out
end
"""
    trace_mag_line(p1, p2, p3; step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000, input_frame="pc", output_frame="pc", method=:dp5, xtol=1e-3, hmax=25.0, threaded_output=false, thread_min=5000) -> Dict

顶层磁力线追踪接口：从给定起点沿磁场双向追踪并拼接成完整磁力线。

# 功能与算法概述
按 `input_frame` 统一到球坐标后，根据 `method` 选择追踪器以 `dir = ±1.0` 双向追踪，
反序拼接两段并按 `output_frame` 决定是否转回笛卡尔，最终封装为标准结果字典。

# 参数说明
- `p1`, `p2`, `p3`: 起点坐标；根据 `input_frame` 解释为笛卡尔或球坐标。
- `step`: 追踪步长（弧长）。
- `r_range`: 终止径向区间（公里）。
- `max_trace`: 单方向最大步数。
- `input_frame`: `"pc"`（笛卡尔）或其它值（球坐标）。
- `output_frame`: `"pc"`（笛卡尔）或其它值（球坐标）。
- `method`: 追踪器选择，`:dp5`（默认，纯 Julia 自适应 Dormand–Prince 5(4)，见 `mag_trace_dp5`）/`:euler`（一阶定步长、纯 Julia 内核，精度低，仅作对照）。
- `xtol`, `hmax`, `threaded_output`, `thread_min`: 仅 `method=:dp5` 使用：单步位置误差容限（km）、积分步长上限（km）、输出点磁场是否多线程求值及其最小点数。

# 返回值
- `Dict{Symbol,Any}`: 键为 `:position`（`N×3`）、`:B`（`N×3`）、`:num_steps`、`:step`、
  `:frame`、`:start_position`（起点行号）、`:method`。

# 注意事项
- `:num_steps` 现在对任意 `output_frame` 都有定义（修复：此前 `output_frame != "pc"` 会抛 `UndefVarError`）。
- 后处理循环改为类型稳定、无逐行分配；`output_frame="pc"` 路径的数值与改动前逐位一致。
"""
function trace_mag_line(p1::Real, p2::Real, p3::Real; step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000, input_frame="pc", output_frame="pc", method::Symbol=:dp5, xtol=1e-3, hmax=25.0, threaded_output::Bool=false, thread_min::Int=5000) #追踪磁力线

    if input_frame == "pc"
        r0, θ0, ϕ0 = pc2sphere(p1, p2, p3)
    else
        r0, θ0, ϕ0 = p1, p2, p3
    end

    # 暴露追踪器选择；默认 :dp5（纯 Julia 自适应 DP5，见 mag_trace_dp5）
    local tracer
    if method === :euler
        tracer = (r, θ, ϕ; dir, step, r_range, max_trace) -> mag_trace_Euler_step(r, θ, ϕ; dir=dir, step=step, r_range=r_range, max_trace=max_trace)
    elseif method === :dp5
        tracer = (r, θ, ϕ; dir, step, r_range, max_trace) -> mag_trace_dp5(r, θ, ϕ; dir=dir, step=step, r_range=r_range, max_trace=max_trace, xtol=xtol, hmax=hmax, threaded_output=threaded_output, thread_min=thread_min)
    else
        throw(ArgumentError("trace_mag_line: 不支持的 method=:$(method)，可选 :dp5/:euler"))
    end

    # 双向追踪：正向与反向各一条
    # 类型断言：tracer 是几种不同闭包的并集，不加断言时下游循环会退化为动态分派（每行约 28 次分配）
    B_data_1 = tracer(r0, θ0, ϕ0; dir=1.0, step=step, r_range=r_range, max_trace=max_trace)::Matrix{Float64}
    B_data_2 = tracer(r0, θ0, ϕ0; dir=-1.0, step=step, r_range=r_range, max_trace=max_trace)::Matrix{Float64}
    B_data_2 = reverse(B_data_2, dims=1)
    n_source = size(B_data_2, 1)
    B_data = [B_data_2; B_data_1[2:end, :]]
    mag_line_num = size(B_data, 1)          # 修复：原先只在 output_frame == "pc" 分支赋值，球坐标输出会 UndefVarError

    if output_frame == "pc"
        data = zeros(mag_line_num, 6)
        # 与原循环调用相同的函数、相同的实参，只是不再为每行分配临时向量；结果逐位不变
        @inbounds for i in 1:mag_line_num
            px, py, pz = sphere2pc(B_data[i, 1], B_data[i, 2], B_data[i, 3])
            Bx, By, Bz = Bsphere2pc(B_data[i, 1], B_data[i, 2], B_data[i, 3], B_data[i, 4], B_data[i, 5], B_data[i, 6])
            data[i, 1] = px
            data[i, 2] = py
            data[i, 3] = pz
            data[i, 4] = Bx
            data[i, 5] = By
            data[i, 6] = Bz
        end
        B_data = data
    end
    result = Dict{Symbol,Any}(
        :position => B_data[:, 1:3],
        :B => B_data[:, 4:6],
        :num_steps => mag_line_num,
        :step => step,
        :frame => output_frame,
        :start_position => n_source,    # 起点的坐标
        :method => method,
    )
    return result
end
"""
    trace_mag_lines(starts; method=:dp5, kwargs...) -> Vector{Dict{Symbol,Any}}

多线程批量追踪多条磁力线：每条线一个任务，调度器自动均衡长短不一的磁力线。

# 功能与算法概述
对 `starts` 中每个起点并行调用 `trace_mag_line`（内部令 `threaded_output=false`，避免嵌套并行爆出海量任务）。
各条线互不依赖，结果与串行逐条调用逐位一致。

# 参数说明
- `starts`: 起点向量，每个元素可下标取 `[1]`、`[2]`、`[3]`（元组或向量），含义由 `input_frame` 决定（默认笛卡尔 km）。
- `method`: 目前只支持 `:dp5`（纯 Julia，线程安全）。
- `kwargs...`: 原样传给 `trace_mag_line`（`step`、`r_range`、`max_trace`、`xtol`、`hmax`、`input_frame`、`output_frame` 等）。

# 返回值
- `Vector{Dict{Symbol,Any}}`: 与 `starts` 等长，元素为 `trace_mag_line` 的结果字典。

# 注意事项
- 纯 Julia 实现，无动态库依赖；本接口按「每条线一个任务」并行，线程安全。
- 需用 `julia -t N` 启动才有并行加速；批量期间不要修改 `B_compress`。
- 所有结果同时驻留内存：条数 × 行数 × 6 个 Float64（30000 行约 1.4 MB/条）。
"""
function trace_mag_lines(starts::AbstractVector; method::Symbol=:dp5, kwargs...)
    method === :dp5 || throw(ArgumentError("trace_mag_lines: 目前只支持 method=:dp5"))
    n = length(starts)
    out = Vector{Dict{Symbol,Any}}(undef, n)
    @sync for i in 1:n
        Threads.@spawn begin
            p = starts[i]
            out[i] = trace_mag_line(p[1], p[2], p[3]; method=:dp5, threaded_output=false, kwargs...)
        end
    end
    return out
end
const NIGRF = 110
const root_dir = dirname(@__FILE__)
const gh_filename = root_dir * "/gh_gao"
# GG / HH 是大矩阵；保持为可变 Array 以便按需原地更新系数。
# 声明为 const 可避免全局变量装箱，内核可在编译期确定类型。
const GG, HH = read_gh()
const SS, REALK = CALCULATE_SCHMIDT_COEFFICIENTS()
# 纯 Julia 内核用的派生系数表（M 连续布局、Schmidt 因子已预乘）。
const GS_T = zeros(NIGRF + 1, NIGRF + 1)
const HS_T = zeros(NIGRF + 1, NIGRF + 1)
const REALK_T = zeros(NIGRF + 1, NIGRF + 1)
const MFLOAT = Float64.(0:NIGRF)
rebuild_derived_tables!()
# B_compress 为 const 绑定的定长 Vector{Float64}，只允许原地修改（见 set_B_compress），不再重新绑定。
const B_compress = zeros(3)
"""
    set_B_compress(new_values) -> Vector{Float64}

更新模块级外源磁场压缩修正参数 `B_compress`。

# 功能与算法概述
`B_compress` 是 `const` 绑定的长度 3 `Vector{Float64}`；本函数把 `new_values` 的三个分量
**原地写入**该向量（不重新绑定），并返回该向量。

# 参数说明
- `new_values`: 新的压缩场参数，长度必须为 3，通常为 `[Bx, By, Bz]`（nT）。

# 返回值
- `Vector{Float64}`: 更新后的模块级 `B_compress`（是值拷贝，与传入向量不是同一对象）。

# 注意事项
- 因为是原地写入而非重新绑定，`B_compress` 才能声明为 `const`；函数内读取时类型已知，
  没有全局查找/装箱开销。
- 不要在模块外对 `IGRF_calculate.B_compress` 重新赋值；需要修改请调用本函数。
- 修改在模块内全局生效，会影响后续所有 `IGRF` / `IGRF!` / 追踪器调用。
- **非线程安全**：并行追踪时不要中途修改。
"""
function set_B_compress(new_values)
    length(new_values) == 3 || throw(ArgumentError("set_B_compress: new_values 长度必须为 3，实际为 $(length(new_values))"))
    B_compress .= new_values
    return B_compress
end
end; #moduel