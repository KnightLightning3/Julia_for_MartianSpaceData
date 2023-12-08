module IGRF_carculate
using OffsetArrays
using DelimitedFiles
#返回nT
function pc2sphere(x,y,z)
    r = sqrt.(x.^2 .+ y.^2 .+ z.^2)
    θ = π/2 .- atan.(z,sqrt.(x.^2+y.^2))
    ϕ = atan.(y,x) 
    return [r,θ,ϕ]
end
function sphere2pc(r, θ, ϕ)
    x = r * sin(θ) * cos(ϕ)
    y = r * sin(θ) * sin(ϕ)
    z = r * cos(θ)
    return [x, y, z]
end
function Bsphere2pc(r,θ,ϕ, Br, Bθ, Bϕ)
    sinθ = sin.(θ)
    cosθ = cos.(θ)
    sinϕ = sin.(ϕ)
    cosϕ = cos.(ϕ)
    Bx = sinθ .* cosϕ .* Br .+ cosθ .* cosϕ .* Bθ .- sinϕ .* Bϕ
    By = sinθ .* sinϕ .* Br .+ cosθ .* sinϕ .* Bθ .+ cosϕ .* Bϕ
    Bz = cosθ         .* Br .- sinθ         .* Bθ
    return [Bx,By,Bz]
end
function CALCULATE_SCHMIDT_COEFFICIENTS()
    SS = OffsetArray(zeros(NIGRF+1, NIGRF+1), 0:NIGRF, 0:NIGRF)
    REALK =  OffsetArray(zeros(NIGRF+1, NIGRF+1), 0:NIGRF, 0:NIGRF)
    SS[0,0]=1e0
    for N=1:NIGRF
        SS[N,0]=(2*N-1)/(1*N)*SS[N-1,0]
        SS[N,1]=sqrt( 2*N/(N+1) )*SS[N,0]
        for M=2:N
            SS[N,M]=sqrt( (N-M+1)/(N+M) )*SS[N,M-1]
        end
    end
    for N=0:NIGRF
        for M=0:NIGRF
            REALK[N,M]    = ((N-1)^2-M^2)/((2*N-3)*(2*N-1))
        end
    end
    return SS,REALK
end
function read_gh(filename)
    data = readdlm(filename,header=false)
    raw1=data[1:111*111]
    raw2=data[111*111+1:end]
    GG = reshape(raw1, 111, 111)
    HH = reshape(raw2, 111, 111)    
    GG = OffsetArray(GG, 0:NIGRF, 0:NIGRF)
    HH = OffsetArray(HH, 0:NIGRF, 0:NIGRF)
    return [GG,HH]
end
function IGRF(r,θ,ϕ) # r θ ϕ[BR,BT,BP,DBBDRR,DBBDTH,DBBDPH]
        AA = Rm
      AARR = OffsetArray(zeros(NIGRF+1), 3:NIGRF+3)
    COSMPH = OffsetArray(zeros(NIGRF+1), 0:NIGRF)
    SINMPH = OffsetArray(zeros(NIGRF+1), 0:NIGRF)
      P = OffsetArray(zeros(NIGRF+1, NIGRF+1), 0:NIGRF, 0:NIGRF)
     DP = OffsetArray(zeros(NIGRF+1, NIGRF+1), 0:NIGRF, 0:NIGRF)
    DDP = OffsetArray(zeros(NIGRF+1, NIGRF+1), 0:NIGRF, 0:NIGRF)
    
      P[0,0] = 1.0e0 ;  DP[0,0] = 0.0e0 ; DDP[0,0] = 0.0e0
    BR       = 0.0e0 ; BT       = 0.0e0 ; BP       = 0.0e0
    DBRDRR   = 0.0e0 ; DBTDRR   = 0.0e0 ; DBPDRR   = 0.0e0
    DBRDTH   = 0.0e0 ; DBTDTH   = 0.0e0 ; DBPDTH   = 0.0e0
    DBRDPH   = 0.0e0 ; DBTDPH   = 0.0e0 ; DBPDPH   = 0.0e0
    AARR[3] = (AA/r)^3
    COSTH   = cos(θ)
    SINTH   = sin(θ)
    COTTH   = COSTH/SINTH
    
    for N=4:NIGRF+3
        AARR[N] = (AA/r)*AARR[N-1]
    end
    
    for M=0:NIGRF
        COSMPH[M] = cos(M*ϕ)
        SINMPH[M] = sin(M*ϕ)
    end
    
    for N=1:NIGRF
         XX = 0.0e0 ; YY  = 0.0e0 ; ZZ  = 0.0e0
        DXX = 0.0e0 ; DYX = 0.0e0 ; DZX = 0.0e0
        DXY = 0.0e0 ; DYY = 0.0e0 ; DZY = 0.0e0
        DXZ = 0.0e0 ; DYZ = 0.0e0 ; DZZ = 0.0e0
    
            P[N,N] = SINTH*  P[N-1,N-1]
           DP[N,N] = SINTH* DP[N-1,N-1]+COSTH*  P[N-1,N-1]
          DDP[N,N] = SINTH*DDP[N-1,N-1]+COSTH* DP[N-1,N-1]*2.0-SINTH*  P[N-1,N-1]
          P[N,N-1] = COSTH*  P[N-1,N-1]
         DP[N,N-1] = COSTH* DP[N-1,N-1]-SINTH*  P[N-1,N-1]
        DDP[N,N-1] = COSTH*DDP[N-1,N-1]-SINTH* DP[N-1,N-1]*2.0-COSTH*  P[N-1,N-1]
        
        for M=N-2:-1:0
              P[N,M] = COSTH*  P[N-1,M]-REALK[N,M]*P[N-2,M]
             DP[N,M] = COSTH* DP[N-1,M]-SINTH*     P[N-1,M]-REALK[N,M]  *DP[N-2,M]
            DDP[N,M] = COSTH*DDP[N-1,M]-SINTH*    DP[N-1,M]*2.0-COSTH*    P[N-1,M]-REALK[N,M]*DDP[N-2,M]
        end
        
        for M=0:N
            PP   = SS[N,M]*  P[N,M]
            DPP  = SS[N,M]* DP[N,M]
            DDPP = SS[N,M]*DDP[N,M]
            
            GCHS    = GG[N,M]*COSMPH[M] + HH[N,M]*SINMPH[M]
            GSHC    = GG[N,M]*SINMPH[M] - HH[N,M]*COSMPH[M]
            
            XX  = XX  +      GCHS*PP
            YY  = YY  +      GCHS*DPP
            ZZ  = ZZ  + M*   GSHC*PP
            DXX = DXX +      GCHS*PP
            DYX = DYX +      GCHS*DPP
            DZX = DZX + M*   GSHC*PP
            DXY = DXY +      GCHS*DPP
            DYY = DYY +      GCHS*DDPP
            DZY = DZY + M*   GSHC*(PP*COTTH-DPP)
            DXZ = DXZ + M*   GSHC*PP
            DYZ = DYZ + M*   GSHC*DPP
            DZZ = DZZ + M^2 *GCHS*PP
        end
        
        BR     = BR     + (N+1)*      AARR[N+2]*XX 
        BT     = BT     +             AARR[N+2]*YY 
        BP     = BP     +             AARR[N+2]*ZZ 
        DBRDRR = DBRDRR + (N+1)*(N+2)*AARR[N+3]*DXX
        DBTDRR = DBTDRR +       (N+2)*AARR[N+3]*DYX
        DBPDRR = DBPDRR +       (N+2)*AARR[N+3]*DZX
        DBRDTH = DBRDTH + (N+1)*      AARR[N+2]*DXY
        DBTDTH = DBTDTH +             AARR[N+2]*DYY
        DBPDTH = DBPDTH +             AARR[N+2]*DZY
        DBRDPH = DBRDPH + (N+1)*      AARR[N+2]*DXZ
        DBTDPH = DBTDPH +             AARR[N+2]*DYZ
        DBPDPH = DBPDPH +             AARR[N+2]*DZZ
    end
    CT=COSTH
    ST=SINTH
    CP=cos(ϕ)
    SP=sin(ϕ)
    
    BX,BY,BZ=  B_compress
    
    BR     = BR                + ST*CP*BX + ST*SP*BY + CT*BZ
    BT     =-BT                + CT*CP*BX + CT*SP*BY - ST*BZ
    BP     = BP       /SINTH   -    SP*BX +    CP*BY
    
    # DBRDRR =-DBRDRR/AA        
    # DBTDRR = DBTDRR/AA        
    # DBPDRR =-DBPDRR/AA/SINTH  
    
    # DBRDTH = DBRDTH            + CT*CP*BX + CT*SP*BY - ST*BZ
    # DBTDTH =-DBTDTH            - ST*CP*BX - ST*SP*BY - CT*BZ
    # DBPDTH =-DBPDTH   /SINTH
    
    # DBRDPH =-DBRDPH            - ST*SP*BX + ST*CP*BY
    # DBTDPH = DBTDPH            - CT*SP*BX + CT*CP*BY
    # DBPDPH = DBPDPH   /SINTH   -    CP*BX -    SP*BY
    
    # BBS    = BR^2+BT^2+BP^2
    # BB     = sqrt(BBS)
    
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
    
    # dY=Dict(
    #   "dYdr" => [DYRDRR,DYTDRR,DYPDRR],
    #   "dYdθ" => [DYRDTH,DYTDTH,DYPDTH],
    #   "dYdϕ" => [DYRDPH,DYTDPH,DYPDPH]
    # )
    dY=Dict(
      "dYdr" => [0,0,0],
      "dYdθ" => [0,0,0],
      "dYdϕ" => [0,0,0],
    )
    return BR,BT,BP,dY
end
function mag_trace_rk4(start_pos, step_size)
    # 初始化路径和磁场分量
    path = []
    B_components = []  # 保存磁场的球坐标系分量
    S = 0.0  # 磁力线长度

    # 定义追踪函数
    function trace_direction(pos, direction)
        r, θ, ϕ = pos

        while r <= max_r && r >= min_r
            # 使用IGRF计算导数
            Br, Bθ, Bϕ, dY = IGRF(r, θ, ϕ)
            DBrDr, DBθDr, DBϕDr = dY["dYdr"]
            DBrDθ, DBθDθ, DBϕDθ = dY["dYdθ"]
            DBrDϕ, DBθDϕ, DBϕDϕ = dY["dYdϕ"]

            # 记录位置和磁场分量
            push!(path, [r, θ, ϕ])
            push!(B_components, [Br, Bθ, Bϕ])

            # sum_dB=[
            #     DBrDr + DBrDθ + DBrDϕ,
            #     DBθDr + DBθDθ + DBθDϕ,
            #     DBϕDr + DBϕDθ + DBϕDϕ,
            #     ]
            sum_dB=[
                DBrDr,
                DBθDθ,
                DBϕDϕ,
                ]
            h=sum_dB.*step_size
            d=direction * step_size
            # RK4步骤
            k1 = d * [Br, Bθ, Bϕ]
            k2 = d * [Br, Bθ, Bϕ] + 0.5*h
            k3 = d * [Br, Bθ, Bϕ] + 0.5*h
            k4 = d * [Br, Bθ, Bϕ] + h

            new_pos = pos + (k1 + 2*k2 + 2*k3 + k4) / 6
            r, θ, ϕ = new_pos
            S += direction * step_size  # 更新磁力线长度
        end
    end

    # 追踪磁力线的两个方向
    trace_direction(start_pos, 1)   # 正方向
    trace_direction(start_pos, -1)  # 逆方向

    # 转换为笛卡尔坐标系中的磁场分量
    cartesian_B_components = [Bsphere2pc(pos..., comp...) for (pos, comp) in zip(path, B_components)]
    cartesian_path = [sphere2pc(pos...) for pos in path]
    return cartesian_path, cartesian_B_components, S
end
function mag_trace_ds(start_pos, step_size)
    # 初始化路径和磁场分量
    path = []
    B_components = []  # 保存磁场的球坐标系分量
    S = 0.0  # 磁力线长度

    # 定义追踪函数
    function trace_direction(pos, direction)
        r, θ, ϕ = pos

        while r <= max_r && r >= min_r
            # 使用IGRF计算导数
            Br, Bθ, Bϕ, dY = IGRF(r, θ, ϕ)
            DBrDr, DBθDr, DBϕDr = dY["dYdr"]
            DBrDθ, DBθDθ, DBϕDθ = dY["dYdθ"]
            DBrDϕ, DBθDϕ, DBϕDϕ = dY["dYdϕ"]

            # 记录位置和磁场分量
            push!(path, [r, θ, ϕ])
            push!(B_components, [Br, Bθ, Bϕ])

            # sum_dB=[
            #     DBrDr + DBrDθ + DBrDϕ,
            #     DBθDr + DBθDθ + DBθDϕ,
            #     DBϕDr + DBϕDθ + DBϕDϕ,
            #     ]
            sum_dB=[
                DBrDr,
                DBθDθ,
                DBϕDϕ,
                ]
            h=sum_dB.*step_size
            d=direction * step_size
            # RK4步骤
            k1 = d * [Br, Bθ, Bϕ]
            k2 = d * [Br, Bθ, Bϕ] + 0.5*h
            k3 = d * [Br, Bθ, Bϕ] + 0.5*h
            k4 = d * [Br, Bθ, Bϕ] + h

            new_pos = pos + (k1 + 2*k2 + 2*k3 + k4) / 6
            r, θ, ϕ = new_pos
            S += direction * step_size  # 更新磁力线长度
        end
    end

    # 追踪磁力线的两个方向
    trace_direction(start_pos, 1)   # 正方向
    trace_direction(start_pos, -1)  # 逆方向

    # 转换为笛卡尔坐标系中的磁场分量
    cartesian_B_components = [Bsphere2pc(pos..., comp...) for (pos, comp) in zip(path, B_components)]
    cartesian_path = [sphere2pc(pos...) for pos in path]
    return cartesian_path, cartesian_B_components, S
end

#global
NIGRF=110
Rm=3393.5
max_r = Rm*2.0
min_r = Rm+170.0
gh_filename="D:/CODE/Package_for_Julia/gh.txt"
GG,HH = read_gh(gh_filename);
SS, REALK = CALCULATE_SCHMIDT_COEFFICIENTS();
B_compress = [0.0,0.0,0.0]
function set_B_compress(new_values)
    global B_compress
    B_compress = new_values
end
end; #moduel