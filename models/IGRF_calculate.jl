"""火星 IGRF/地壳磁场计算、坐标变换与磁力线追踪工具。"""

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
export pc2sphere, sphere2pc   # Bsphere2pc / Bpc2sphere 权威已迁 MarsCommon（经 using 绑定，本模块不再导出）
export IGRF_pc,IGRF_sphere
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
`(NIGRF+1)×(NIGRF+1)` 系数表，供全部 `ccall` 内核复用。

# 参数说明
- 无输入参数；依赖模块级常量 `NIGRF`（默认 110）。

# 返回值
- `(SS, REALK)`: 两个 `(NIGRF+1)×(NIGRF+1)` 的 `Matrix{Float64}` 元组。

# 注意事项
- 仅在模块初始化时调用一次，结果绑定为 `const`。
- 返回的是可变 `Matrix`（非静态数组），因为需作为 `Ptr{Float64}` 传入 Fortran。
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
- `GG`/`HH` 必须是**可变 `Matrix`**，因为会作为 `Ptr{Float64}` 传入 `ccall`；
  因此不可改为静态数组。
- 本函数在模块加载时被调用一次：`const GG, HH = read_gh()`；文件缺失会导致模块加载失败。
"""
function read_gh()
    f = FortranFile(gh_filename)
    GG = read(f, (Float64, NIGRF + 1, NIGRF + 1))
    HH = read(f, (Float64, NIGRF + 1, NIGRF + 1))
    return GG, HH
end
"""
    IGRF_fortran_free(r, θ, ϕ) -> (Br, Bθ, Bϕ, BB)

调用 Fortran 的 IGRF_FREE 内核计算球谐磁场，输入半径必须已归一化（除以 `R_Mars`）。

# 功能与算法概述
把归一化坐标、`GG/HH/REALK/SS` 及压缩场参数经 `ccall` 送入动态库的 110 阶
`IGRF_FREE` 例程（归一化可避免大数值精度损失），回读并解包球坐标三分量与总强度。

# 参数说明
- `r`: 归一化半径（**单位：火星半径**，需调用方先除 `R_Mars`）。
- `θ`: 天顶角/余纬（**弧度**）。
- `ϕ`: 经度（**弧度**）。

# 返回值
- `(Br, Bθ, Bϕ, BB)`: 球坐标磁场三分量与总强度（nT）。

# 注意事项
- 需 `IGRF_DLL.dll` 可用，且平台/ABI 匹配（本仓库目前为 Windows/x86-64 路径）。
- 与 `IGRF_fortran` 的区别在于**半径是否已归一化**；两者不可混用。
"""
function IGRF_fortran_free(r::Real, θ::Real, ϕ::Real)  #working on ,输入半径是归一化的,输入阶数
    B_result = Array{Float64}(undef, 4)  #[Br,Bt,Bp,abs(B)]
    DBs = Array{Float64}(undef, 3)
    path = Array{Float64}([r / constants.R_Mars, θ, ϕ])
    B_compress_in = Array{Float64}(B_compress)
    ii = Ref{Int32}(110)
    ccall(("IGRF_FREE_MODEL_mp_IGRF_FREE", IGRF_DLL_PATH), Cvoid,
        (Ref{Int32}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Float64}, Ptr{Float64}),
        ii, GG, HH, REALK, SS, B_compress_in,
        path, B_result, DBs)
    Br, Bθ, Bϕ, BB = B_result[1], B_result[2], B_result[3], B_result[4]
    return Br, Bθ, Bϕ, BB
end
"""
    IGRF_fortran(r, θ::Real, ϕ::Real) -> (Br, Bθ, Bϕ, BB)

调用 Fortran IGRF_110 内核计算球谐磁场，`r` 为未归一化的实际半径。

# 功能与算法概述
把 `[r, θ, ϕ]` 与系数矩阵经 `ccall` 送入动态库的 `IGRF_110` 例程，
回读球坐标三分量与总强度；`IGRF_sphere` 为它的别名。

# 参数说明
- `r`: 径向距离（**公里**，与 `IGRF_pc` / 磁力线追踪保持一致）。
- `θ`: 天顶角/余纬（**弧度**）。
- `ϕ`: 经度（**弧度**）。

# 返回值
- `(Br, Bθ, Bϕ, BB)`: 球坐标磁场三分量与总强度（nT）。

# 注意事项
- `IGRF_sphere` 是本函数的别名；`IGRF_pc` 依赖它做笛卡尔坐标下的场值计算。
- 与 `IGRF_fortran_free` 相比少一步归一化，是 **径向单位不同** 的两个入口。
"""
function IGRF_fortran(r::Real, θ::Real, ϕ::Real) #fortran计算核心,输入球坐标，返回球坐标,r不需要归一化
    B_result = Array{Float64}(undef, 4)  #[Br,Bt,Bp,abs(B)]
    path = Array{Float64}([r, θ, ϕ])
    B_compress_in = Array{Float64}(B_compress)
    ccall(("IGRF_110_MODEL_mp_IGRF_110", IGRF_DLL_PATH), Cvoid,
        (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Float64}),
        GG, HH, REALK, SS, B_compress_in,
        path, B_result)
    Br, Bθ, Bϕ, BB = B_result[1], B_result[2], B_result[3], B_result[4]
    return Br, Bθ, Bϕ, BB
end
"""
    RK4_Trace_fortran(r, θ, ϕ, h) -> (B_result, dB, path_next)

调用 Fortran RK4_STEP 内核执行一次定步长 RK4 磁力线步进。

# 功能与算法概述
以 `[r, θ, ϕ]` 为当前点、带符号步长 `h` 送入动态库单步例程，返回该点磁场、
误差估计 `dB` 与下一步位置，由调用方决定是否接受该步。

# 参数说明
- `r`: 当前球坐标半径（公里）。
- `θ`: 当前天顶角（**弧度**）。
- `ϕ`: 当前经度（**弧度**）。
- `h`: 步长（弧长，带符号）。

# 返回值
- `(B_result::Vector{Float64}, dB::Float64, path_next::Vector{Float64})`:
  当前点磁场 `[Br,Bθ,Bϕ]`、误差估计 `dB` 与下一步的位置。

# 注意事项
- 返回的 `B_result` / `path_next` 为复用缓冲区写出的新 `Array`；在密集循环中会产生分配。
- `dB` 可用于自适应步长控制（参见 `mag_trace_rk4`）。
"""
function RK4_Trace_fortran(r::Real, θ::Real, ϕ::Real, h::Real)
    # DYs = Array{Float64}(undef, 9)

    path = Array{Float64}([r, θ, ϕ])
    path_next = Array{Float64}(undef, 3)

    B_result = Array{Float64}(undef, 3)  #[Br,Bt,Bp,abs(B)]
    dB = Ref{Float64}(0.0)
    B_compress_in = Array{Float64}(B_compress)
    h_in = Ref{Float64}(h)
    # lib = "Megnetic_Model/IGRF_DLL.dll"
    # lib = raw"D:\CODE\Code_Library\Fortran\IGRF_DLL\x64\Release\IGRF_DLL.dll"

    ccall(("IGRF_110_MODEL_mp_RK4_STEP", IGRF_DLL_PATH), Cvoid,
        (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ref{Float64},
            Ref{Float64}),
        GG, HH, REALK, SS, B_compress_in,
        path, path_next,
        B_result, dB,
        h_in)
    return B_result, dB.x, path_next
end
IGRF_sphere = IGRF_fortran
"""
    IGRF_pc(x, y, z) -> (Bx, By, Bz)

在行星笛卡尔坐标处计算 IGRF/地壳磁场矢量（nT）。

# 功能与算法概述
先把位置转到球坐标，调用 `IGRF_fortran` 求球坐标分量，再经 `Bsphere2pc` 旋转回笛卡尔分量，
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
    Br, Bθ, Bϕ, _ = IGRF_fortran(r, θ, ϕ)
    Bx, By, Bz = Bsphere2pc(r, θ, ϕ, Br, Bθ, Bϕ)
    return Bx, By, Bz
end
"""
    IGRF(r, θ, ϕ) -> (BR, BT, BP, BB)

纯 Julia 参考实现的球谐磁场求值（无动态库依赖），供校验与教学使用。

# 功能与算法概述
以内源球谐展开递推关联 Legendre 函数及其导数，逐阶累加各分量再乘径向功率，
组装出球坐标磁场；生产路径请改用 `IGRF_fortran`。

# 参数说明
- `r`: 径向距离（公里，`R_Mars` 为参考半径）。
- `θ`: 天顶角/余纬（**弧度**）。
- `ϕ`: 经度（**弧度**）。

# 返回值
- `(BR, BT, BP, BB)`: 球坐标磁场三分量与总强度（nT）。

# 注意事项
- 作者注释标明"效率远远不及 fortran 内核, 弃用"；**生产路径请用 `IGRF_fortran`**。
- 传入 `B_compress` 的压缩场修正在本实现中被**注释掉**（仅计算内源场）。
- 函数内多处全局变量（`GG`/`HH`/`REALK`/`SS`）为 `const`，因此已消除装箱开销。
"""
function IGRF(r::Real, θ::Real, ϕ::Real) # r θ ϕ[BR,BT,BP,DBBDRR,DBBDTH,DBBDPH] # 效率远远不及fortran内核,弃用
    AA = constants.R_Mars
    AARR = zeros(NIGRF + 3)
    COSMPH = zeros(NIGRF + 1)
    SINMPH = zeros(NIGRF + 1)
    P = zeros(NIGRF + 1, NIGRF + 1)
    DP = zeros(NIGRF + 1, NIGRF + 1)
    #DDP = zeros(NIGRF+1, NIGRF+1)

    P[1, 1] = 1.0e0
    DP[1, 1] = 0.0e0 #; DDP[1,1] = 0.0e0
    # BR/BT/BP 为跨阶累加器：仅在此处初始化一次，循环内只做累加、切勿重新清零
    BR = 0.0e0
    BT = 0.0e0
    BP = 0.0e0
    # DBRDRR   = 0.0e0 ; DBTDRR   = 0.0e0 ; DBPDRR   = 0.0e0
    # DBRDTH   = 0.0e0 ; DBTDTH   = 0.0e0 ; DBPDTH   = 0.0e0
    # DBRDPH   = 0.0e0 ; DBTDPH   = 0.0e0 ; DBPDPH   = 0.0e0
    AARR[3] = (AA / r)^3
    COSTH = cos(θ)
    SINTH = sin(θ)
    # COTTH   = COSTH/SINTH

    @inbounds for N = 4:NIGRF+3
        AARR[N] = (AA / r) * AARR[N-1]
    end

    @inbounds for M = 0:NIGRF
        COSMPH[M+1] = cos(M * ϕ)
        SINMPH[M+1] = sin(M * ϕ)
    end

    @inbounds for N = 1:NIGRF
        XX = 0.0e0
        YY = 0.0e0
        ZZ = 0.0e0

        P[N+1, N+1] = SINTH * P[N, N]
        DP[N+1, N+1] = SINTH * DP[N, N] + COSTH * P[N, N]
        #   DDP[N+1,N+1] = SINTH*DDP[N,N]+COSTH* DP[N,N]*2.0-SINTH*  P[N,N]
        P[N+1, N] = COSTH * P[N, N]
        DP[N+1, N] = COSTH * DP[N, N] - SINTH * P[N, N]
        # DDP[N+1,N] = COSTH*DDP[N,N]-SINTH* DP[N,N]*2.0-COSTH*  P[N,N]

        @inbounds for M = N-2:-1:0
            P[N+1, M+1] = COSTH * P[N, M+1] - REALK[N+1, M+1] * P[N-1, M+1]
            DP[N+1, M+1] = COSTH * DP[N, M+1] - SINTH * P[N, M+1] - REALK[N+1, M+1] * DP[N-1, M+1]
            # DDP[N+1,M+1] = COSTH*DDP[N,M+1]-SINTH*    DP[N,M+1]*2.0-COSTH*    P[N,M+1]-REALK[N+1,M+1]*DDP[N-1,M+1]
        end

        @inbounds for M = 0:N
            PP = SS[N+1, M+1] * P[N+1, M+1]
            DPP = SS[N+1, M+1] * DP[N+1, M+1]
            # DDPP = SS[N+1,M+1]*DDP[N+1,M+1]

            GCHS = GG[N+1, M+1] * COSMPH[M+1] + HH[N+1, M+1] * SINMPH[M+1]
            GSHC = GG[N+1, M+1] * SINMPH[M+1] - HH[N+1, M+1] * COSMPH[M+1]

            XX = XX + GCHS * PP
            YY = YY + GCHS * DPP
            ZZ = ZZ + M * GSHC * PP
            # DXX = DXX +      GCHS*PP
            # DYX = DYX +      GCHS*DPP
            # DZX = DZX + M*   GSHC*PP
            # DXY = DXY +      GCHS*DPP
            # DYY = DYY +      GCHS*DDPP
            # DZY = DZY + M*   GSHC*(PP*COTTH-DPP)
            # DXZ = DXZ + M*   GSHC*PP
            # DYZ = DYZ + M*   GSHC*DPP
            # DZZ = DZZ + M^2 *GCHS*PP
        end

        BR = BR + (N + 1) * AARR[N+2] * XX
        BT = BT + AARR[N+2] * YY
        BP = BP + AARR[N+2] * ZZ
        # DBRDRR = DBRDRR + (N+1)*(N+2)*AARR[N+3]*DXX
        # DBTDRR = DBTDRR +       (N+2)*AARR[N+3]*DYX
        # DBPDRR = DBPDRR +       (N+2)*AARR[N+3]*DZX
        # DBRDTH = DBRDTH + (N+1)*      AARR[N+2]*DXY
        # DBTDTH = DBTDTH +             AARR[N+2]*DYY
        # DBPDTH = DBPDTH +             AARR[N+2]*DZY
        # DBRDPH = DBRDPH + (N+1)*      AARR[N+2]*DXZ
        # DBTDPH = DBTDPH +             AARR[N+2]*DYZ
        # DBPDPH = DBPDPH +             AARR[N+2]*DZZ
    end
    # CT=COSTH
    # ST=SINTH
    # CP=cos(ϕ)
    # SP=sin(ϕ)

    #BX,BY,BZ=  B_compress

    BR = BR                #+ ST*CP*BX + ST*SP*BY + CT*BZ
    BT = -BT                #+ CT*CP*BX + CT*SP*BY - ST*BZ
    BP = BP / SINTH  # -    SP*BX +    CP*BY

    # DBRDRR =-DBRDRR/AA        
    # DBTDRR = DBTDRR/AA        
    # DBPDRR =-DBPDRR/AA/SINTH  

    # DBRDTH = DBRDTH            + CT*CP*BX + CT*SP*BY - ST*BZ
    # DBTDTH =-DBTDTH            - ST*CP*BX - ST*SP*BY - CT*BZ
    # DBPDTH =-DBPDTH   /SINTH

    # DBRDPH =-DBRDPH            - ST*SP*BX + ST*CP*BY
    # DBTDPH = DBTDPH            - CT*SP*BX + CT*CP*BY
    # DBPDPH = DBPDPH   /SINTH   -    CP*BX -    SP*BY

    BBS = BR^2 + BT^2 + BP^2
    BB = sqrt(BBS)

    # DBBDRR = (BR*DBRDRR+BT*DBTDRR+BP*DBPDRR)/BBS
    # DBBDTH = (BR*DBRDTH+BT*DBTDTH+BP*DBPDTH)/BBS
    # DBBDPH = (BR*DBRDPH+BT*DBTDPH+BP*DBPDPH)/BBS

    # DYRDRR = (DBRDRR-BR*DBBDRR)/BB
    # DYTDRR = (DBTDRR-BT*DBBDRR)/BB
    # DYPDRR = (DBPDRR-BP*DBBDRR)/BB
    # DYRDTH = (DBRDTH-BR*DBBDTH)/BB
    # DYTDTH = (DBTDTH-BT*DBBDTH)/BB
    # DYPDTH = (DBPDTH-BP*DBBDTH)/BB
    # DYRDPH = (DBRDPH-BR*DBBDPH)/BB
    # DYTDPH = (DBTDPH-BT*DBBDPH)/BB
    # DYPDPH = (DBPDPH-BP*DBBDPH)/BB

    # dY=[DYRDRR,DYTDRR,DYPDRR,DYRDTH,DYTDTH,DYPDTH,DYRDPH,DYTDPH,DYPDPH]

    # dY=Dict(
    #   "dYdr" => [DYRDRR,DYTDRR,DYPDRR],
    #   "dYdθ" => [DYRDTH,DYTDTH,DYPDTH],
    #   "dYdϕ" => [DYRDPH,DYTDPH,DYPDPH]
    # )
    # dY=Dict(
    #   "dYdr" => [0,0,0],
    #   "dYdθ" => [0,0,0],
    #   "dYdϕ" => [0,0,0],
    # )
    return BR, BT, BP, BB
end
"""
    mag_trace_rk4_fortran_ADAPTIVE_STEP(r, θ, ϕ; dir=1.0, step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000, maxfac=30.0, minfac=0.5, tol=0.1)

用 Fortran 内核执行自适应步长 RK4 磁力线追踪，输入/输出均为球坐标。

# 功能与算法概述
把起点与步长控制参数经 `ccall` 送入动态库的 `ADAPTIVE_STEP_TRACE` 循环内核，
内核按误差容限自动细化/放粗步长并回写实际步数，返回时按步数截断轨迹。

# 参数说明
- `r`, `θ`, `ϕ`: 起始点球坐标（`r` 为公里，角度为**弧度**）。
- `dir`: 追踪方向，`+1.0` 顺场、`-1.0` 逆场。
- `step`: 初始弧长步长。
- `r_range`: 允许的径向范围（超出即终止），单位公里。
- `max_trace`: 最大步数上限（也是预分配行数）。
- `maxfac` / `minfac`: 步长放大/缩小的上下限倍率。
- `tol`: 步长控制的相对误差容限。

# 返回值
- `Matrix{Float64}`: `Nsteps×6`，列为 `[r, θ, ϕ, Br, Bθ, Bϕ]`（球坐标 + nT）。

# 注意事项
- 自适应步长在磁力线弯曲处自动细化，整体步数通常少于定步长版本。
- 预分配了 `max_trace×6` 的内存（`30000×6` 约 1.4 MB/次）；批量追踪时需留意内存峰值。
"""
function mag_trace_rk4_fortran_ADAPTIVE_STEP(r::Real, θ::Real, ϕ::Real; dir=1.0, step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000, maxfac=30.0, minfac=0.5, tol=0.1)  #RK4方法的可变步长磁力线追踪,输入球坐标，返回球坐标,fortran rk4循环内核
    B_data = Array{Float64}(undef, max_trace, 6)
    PATH = Array{Float64}([r, θ, ϕ])
    dir_in = Ref{Float64}(dir)
    step_in = Ref{Float64}(step)
    r_range_in = Array{Float64}(r_range)
    max_trace_in = Ref{Int64}(max_trace)
    maxfac_in = Ref{Float64}(maxfac)
    minfac_in = Ref{Float64}(minfac)
    tol_in = Ref{Float64}(tol)
    trace_conts = Ref{Int64}(0)
    B_compress_in = Array{Float64}(B_compress)
    # lib = "Megnetic_Model/IGRF_DLL.dll"
    # IGRF_DLL_PATH = raw"D:\CODE\Code_Library\Fortran\IGRF_DLL\x64\Release\IGRF_DLL.dll"

    ccall(("MAIN_mp_ADAPTIVE_STEP_TRACE", IGRF_DLL_PATH), Cvoid,
        (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Float64},
            Ref{Float64}, Ref{Float64}, Ref{Float64}, Ref{Float64}, Ref{Float64},
            Ptr{Float64},
            Ref{Int64}, Ref{Int64}),
        GG, HH, REALK, SS, B_compress_in,
        PATH, B_data,
        dir_in, step_in, maxfac_in, minfac_in, tol_in,
        r_range_in,
        max_trace_in, trace_conts)
    trace_conts = trace_conts.x
    return B_data[1:trace_conts, :]
end
"""
    mag_trace_rk4(r0, θ0, ϕ0; dir=1.0, step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000, maxfac=30.0, minfac=0.5, tol=0.1)

用 Julia 侧循环 + Fortran 单步内核执行带自适应步长的 RK4 磁力线追踪。

# 功能与算法概述
主循环反复调用 `RK4_Trace_fortran` 得到新点与误差估计，按标准 RK4 的五阶误差指数
`h_new = h·clamp((tol/error)^(1/5), minfac, maxfac)` 调整步长；作者称效率接近 Fortran 内置版本。

# 参数说明
- `r0`, `θ0`, `ϕ0`: 起始点球坐标（`r` 公里，角度**弧度**）。
- `dir`: 追踪方向（`±1.0`）。
- `step`: 初始步长。
- `r_range`: 终止径向区间（公里）。
- `max_trace`: 最大步数。
- `maxfac` / `minfac`: 步长缩放上下限。
- `tol`: 误差容限。

# 返回值
- `Matrix{Float64}`: `Nsteps×6`，列为 `[r, θ, ϕ, Br, Bθ, Bϕ]`。

# 注意事项
- `h` 的符号由 `dir` 决定，逆场追踪只需传 `dir = -1.0`。
- 每步会为 `RK4_Trace_fortran` 的返回值分配 3 个数组，是批量追踪的主要分配源。
"""
function mag_trace_rk4(r0::Real, θ0::Real, ϕ0::Real; dir=1.0, step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000, maxfac=30.0, minfac=0.5, tol=0.1)  #RK4方法的固定步长磁力线追踪,输入球坐标，返回球坐标,fortranIGRF内核  效率和fortran内置接近
    r, θ, ϕ = r0, θ0, ϕ0
    r_state = 500 + constants.R_Mars
    trace_steps = 0
    h = dir * step
    h_new = h
    B_data = Matrix{Float64}(undef, max_trace,6)#zeros(max_trace, 6)

    while r_state >= r_range[1] && r_state <= r_range[2] && trace_steps < max_trace
        B_result, dB, path_next = RK4_Trace_fortran(r, θ, ϕ, h_new)
        r, θ, ϕ = path_next[1], path_next[2], path_next[3]
        Br, Bθ, Bϕ = B_result[1], B_result[2], B_result[3]
        r_state = r
        trace_steps += 1
        @inbounds B_data[trace_steps, :] = [r, θ, ϕ, Br, Bθ, Bϕ]

        #自适应步长:
        error = abs(h / dB)
        h_new = h * min(maxfac, max(minfac, (tol / error)^(1 / 5)))
    end
    return B_data[1:trace_steps, :]
end
"""
    mag_trace_Euler_step(r0, θ0, ϕ0; dir=1.0, step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000)

用定步长一阶 Euler 法追踪磁力线（速度最快但精度最低）。

# 功能与算法概述
每步调 `IGRF_fortran` 得场矢量，沿单位场方向以弧长 `Δs = dir·step` 推进 `(r, θ, ϕ)`
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
- `trace_mag_line` 默认使用本函数（速度快），高精度场景请改用 `mag_trace_rk4*`。
"""
function mag_trace_Euler_step(r0::Real, θ0::Real, ϕ0::Real; dir=1.0, step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000)  #欧拉方法的固定步长磁力线追踪,输入球坐标，返回球坐标
    r, θ, ϕ = r0, θ0, ϕ0
    trace_steps = 0
    Δs = dir * step
    B_data = Matrix{Float64}(undef, max_trace,6)#zeros(max_trace, 6)
    trace_state = true
    while trace_state
        Br, Bθ, Bϕ, BB = IGRF_fortran(r, θ, ϕ)
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
"""
    trace_mag_line(p1, p2, p3; step=0.5, r_range=[R_Mars, 2R_Mars], max_trace=30000, input_frame="pc", output_frame="pc", method=:euler, maxfac=30.0, minfac=0.5, tol=0.1) -> Dict

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
- `method`: 追踪器选择，`:euler`（默认，一阶）/`:rk4`（四阶固定步长）/`:adaptive`（Fortran 自适应 RK4）。
- `maxfac`, `minfac`, `tol`: 仅 `method=:rk4` 或 `:adaptive` 时使用的步长控制参数。

# 返回值
- `Dict{Symbol,Any}`: 键为 `:position`（`N×3`）、`:B`（`N×3`）、`:num_steps`、`:step`、
  `:frame`、`:start_position`（起点行号）、`:method`。

# 注意事项
- **默认 `method=:euler` 保持与改动前逐位一致**；改为更高精度需科学负责人批准（03 §15 C1）。
- `:num_steps` 仅在 `output_frame == "pc"` 分支被赋值，其它情况下未定义。
"""
function trace_mag_line(p1::Real, p2::Real, p3::Real; step=0.5, r_range=[constants.R_Mars, constants.R_Mars * 2], max_trace=30000, input_frame="pc", output_frame="pc", method::Symbol=:euler, maxfac=30.0, minfac=0.5, tol=0.1) #追踪磁力线

    # trace_function = Dict(
    #     1 => mag_trace_Euler_step,
    #     2 => mag_trace_rk4,
    #     3 => mag_trace_rk4_fortran_ADAPTIVE_STEP,
    # )
    if input_frame == "pc"
        r0, θ0, ϕ0 = pc2sphere(p1, p2, p3)
    else
        r0, θ0, ϕ0 = p1, p2, p3
    end

    # C1 修复：暴露追踪器选择，默认保持 :euler 以兼容既有结果
    local tracer
    if method === :euler
        tracer = (r, θ, ϕ; dir, step, r_range, max_trace) -> mag_trace_Euler_step(r, θ, ϕ; dir=dir, step=step, r_range=r_range, max_trace=max_trace)
    elseif method === :rk4
        tracer = (r, θ, ϕ; dir, step, r_range, max_trace) -> mag_trace_rk4(r, θ, ϕ; dir=dir, step=step, r_range=r_range, max_trace=max_trace, maxfac=maxfac, minfac=minfac, tol=tol)
    elseif method === :adaptive
        tracer = (r, θ, ϕ; dir, step, r_range, max_trace) -> mag_trace_rk4_fortran_ADAPTIVE_STEP(r, θ, ϕ; dir=dir, step=step, r_range=r_range, max_trace=max_trace, maxfac=maxfac, minfac=minfac, tol=tol)
    else
        throw(ArgumentError("trace_mag_line: 不支持的 method=:$(method)，可选 :euler/:rk4/:adaptive"))
    end

    # B_data_1 = Matrix{Float64}(undef, max_trace,6)
    # B_data_2 = Matrix{Float64}(undef, max_trace,6)
    B_data_1 = tracer(r0, θ0, ϕ0; dir=1.0, step=step, r_range=r_range, max_trace=max_trace)
    B_data_2 = tracer(r0, θ0, ϕ0; dir=-1.0, step=step, r_range=r_range, max_trace=max_trace)
    B_data_2 = reverse(B_data_2, dims=1)
    n_source = length(B_data_2[:, 1])
    B_data = [B_data_2; B_data_1[2:end, :]]

    if output_frame == "pc"
        mag_line_num = length(B_data[:, 1])
        data = zeros(mag_line_num, 6)
        @inbounds for i in 1:mag_line_num
            x = B_data[i, :]
            px, py, pz = sphere2pc(x[1], x[2], x[3])
            Bx, By, Bz = Bsphere2pc(x[1], x[2], x[3], x[4], x[5], x[6])
            data[i, :] = [px, py, pz, Bx, By, Bz]
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
const NIGRF = 110
root_dir = dirname(@__FILE__)
gh_filename = root_dir * "/gh_gao"
const IGRF_DLL_PATH = root_dir * "/IGRF_DLL.dll"
# GG / HH 是大矩阵且直接作为 Ptr{Float64} 传入 ccall，必须保持为可变 Array；
# 声明为 const 可避免全局变量装箱，显著提升 ccall 参数访问性能。
const GG, HH = read_gh()
const SS, REALK = CALCULATE_SCHMIDT_COEFFICIENTS()
B_compress = [0.0, 0.0, 0.0]
"""
    set_B_compress(new_values) -> Vector{Float64}

更新模块全局的外源磁场压缩修正参数 `B_compress`。

# 功能与算法概述
通过 `global` 把模块级可变全局量 `B_compress` 重新绑定到传入向量，并返回该引用。

# 参数说明
- `new_values`: 新的压缩场参数，通常为 `[Bx, By, Bz]`（nT）。

# 返回值
- `Vector{Float64}`: 更新后的全局 `B_compress`。

# 注意事项
- 因为要支持**重新赋值**，`B_compress` 不能声明为 `const`（所以它保留为普通可变全局量，
  在逐次 ccall 中会有一次全局查找开销）。
- 修改在模块内全局生效，会影响后续所有 `IGRF_fortran*` / `RK4_Trace_fortran` 调用。
- **非线程安全**：并行追踪时不要中途修改。
"""
function set_B_compress(new_values)
    global B_compress
    B_compress = new_values
end
end; #moduel