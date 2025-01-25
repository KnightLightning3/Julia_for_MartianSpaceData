module IGRF_calculate
using FortranFiles
using LinearAlgebra
using Statistics

# -----------------export part -----------------------
export pc2sphere, sphere2pc, Bsphere2pc, Bpc2sphere
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
function pc2sphere(x::Real, y::Real, z::Real)
    r = norm([x, y, z])
    # θ = π/2 - atan(z,sqrt(x^2+y^2))
    θ = acos(z / r) # [0,π]
    ϕ = atan(y, x)  # (-π/2, π/2)
    return r, θ, ϕ
end
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
function Bpc2sphere(x::Real, y::Real, z::Real, bx::Real, by::Real, bz::Real)
    r = norm([x, y, z])
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
###########
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
function read_gh()
    f = FortranFile(gh_filename)
    GG = read(f, (Float64, NIGRF + 1, NIGRF + 1))
    HH = read(f, (Float64, NIGRF + 1, NIGRF + 1))
    return [GG, HH]
end
function IGRF_fortran_free(r::Real, θ::Real, ϕ::Real)  #working on ,输入半径是归一化的,输入阶数
    B_result = Array{Float64}(undef, 4)  #[Br,Bt,Bp,abs(B)]
    DBs = Array{Float64}(undef, 3)
    path = Array{Float64}([r / 3393.5, θ, ϕ])
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
function IGRF_pc(x::Real, y::Real, z::Real)
    r, θ, ϕ = pc2sphere(x, y, z)
    Br, Bθ, Bϕ, _ = IGRF_fortran(r, θ, ϕ)
    Bx, By, Bz = Bsphere2pc(r, θ, ϕ, Br, Bθ, Bϕ)
    return Bx, By, Bz
end
function IGRF(r::Real, θ::Real, ϕ::Real) # r θ ϕ[BR,BT,BP,DBBDRR,DBBDTH,DBBDPH] # 效率远远不及fortran内核,弃用
    AA = Rm
    AARR = zeros(NIGRF + 3)
    COSMPH = zeros(NIGRF + 1)
    SINMPH = zeros(NIGRF + 1)
    P = zeros(NIGRF + 1, NIGRF + 1)
    DP = zeros(NIGRF + 1, NIGRF + 1)
    #DDP = zeros(NIGRF+1, NIGRF+1)

    P[1, 1] = 1.0e0
    DP[1, 1] = 0.0e0 #; DDP[1,1] = 0.0e0
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
        # DXX = 0.0e0 ; DYX = 0.0e0 ; DZX = 0.0e0
        # DXY = 0.0e0 ; DYY = 0.0e0 ; DZY = 0.0e0
        # DXZ = 0.0e0 ; DYZ = 0.0e0 ; DZZ = 0.0e0

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
function mag_trace_rk4_fortran_ADAPTIVE_STEP(r::Real, θ::Real, ϕ::Real; dir=1.0, step=0.5, r_range=[Rm, Rm * 2], max_trace=30000, maxfac=30.0, minfac=0.5, tol=0.1)  #RK4方法的可变步长磁力线追踪,输入球坐标，返回球坐标,fortran rk4循环内核
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
function mag_trace_rk4(r0::Real, θ0::Real, ϕ0::Real; dir=1.0, step=0.5, r_range=[Rm, Rm * 2], max_trace=30000, maxfac=30.0, minfac=0.5, tol=0.1)  #RK4方法的固定步长磁力线追踪,输入球坐标，返回球坐标,fortranIGRF内核  效率和fortran内置接近
    r, θ, ϕ = r0, θ0, ϕ0
    r_state = 500 + Rm
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
function mag_trace_Euler_step(r0::Real, θ0::Real, ϕ0::Real; dir=1.0, step=0.5, r_range=[Rm, Rm * 2], max_trace=30000)  #欧拉方法的固定步长磁力线追踪,输入球坐标，返回球坐标
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
function combina_two_dir_trace(B_data_1, B_data_2; to_pc=false) # 翻转第二个，获得指向磁场方向的磁力线
    B_data_2 = reverse(B_data_2, dims=1)
    B_data = [B_data_2; B_data_1]
    if to_pc
        mag_line_num = length(B_data[:, 1])
        data = zeros(mag_line_num, 6)
        @inbounds for i in 1:mag_line_num
            x = B_data[i, :]
            px, py, pz = IGRF_calculate.sphere2pc(x[1], x[2], x[3])
            Bx, By, Bz = IGRF_calculate.Bsphere2pc(x[1], x[2], x[3], x[4], x[5], x[6])
            data[i, :] = [px, py, pz, Bx, By, Bz]
        end
        B_data = data
    end
    return B_data
end
function get_mag_line_s(data) #取得磁力线的长度关系,需要标准磁力线数据结构
    position = data["position"]
    mag_line_num = length(position[:, 1])
    s = zeros(mag_line_num)
    s[1] = 0
    @inbounds for i in 2:mag_line_num
        x1 = position[i-1, 1:3]
        x2 = position[i, 1:3]
        s[i] = s[i-1] + norm(x2 - x1)
    end
    data["S"] = s
    data["alt"] = [norm(x) for x in eachrow(position)] .- 3393.5
    data["B_strenth"] = [norm(x) for x in eachrow(data["B"])]
    return data
end
function trace_mag_line(p1::Real, p2::Real, p3::Real; step=0.5, r_range=[Rm, Rm * 2], max_trace=30000, input_frame="pc", output_frame="pc") #追踪磁力线

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
    # B_data_1 = Matrix{Float64}(undef, max_trace,6)
    # B_data_2 = Matrix{Float64}(undef, max_trace,6)
    B_data_1 = mag_trace_Euler_step(r0, θ0, ϕ0; r_range=r_range, step=step, dir=1.0, max_trace=max_trace)
    B_data_2 = mag_trace_Euler_step(r0, θ0, ϕ0; r_range=r_range, step=step, dir=-1.0, max_trace=max_trace)
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
    result = Dict(
        "position" => B_data[:, 1:3],
        "B" => B_data[:, 4:6],
        "num_steps" => mag_line_num,
        "step" => step,
        "frame" => output_frame,
        "start_position" => n_source    # 起点的坐标
    )
    return result
end
#global
NIGRF = 110
Rm = 3393.5
root_dir = dirname(@__FILE__)
gh_filename = root_dir * "/gh_gao"
IGRF_DLL_PATH = root_dir * "/IGRF_DLL.dll"
GG, HH = read_gh()
SS, REALK = CALCULATE_SCHMIDT_COEFFICIENTS()
B_compress = [0.0, 0.0, 0.0]
function set_B_compress(new_values)
    global B_compress
    B_compress = new_values
end
end; #moduel