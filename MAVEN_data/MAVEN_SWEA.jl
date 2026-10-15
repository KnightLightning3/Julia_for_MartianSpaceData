# 处理 MAVEN SWEA 电子分析仪数据，包括分布数据转换与物理量计算。
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_SWEA
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
using .MarsCommon
using TimesDates, Dates
using Statistics
using Rotations
# -------------------------Export parts-------------------------
# export static_c6_mass_mean,static_c6_energy_mean
# export static_rotation,static_slip,static_slip_2_V,sta_v_4d
#---------------------------初始化-------------------------------- 由于SWIA的糟糕数据,需要对其读取后进行初始化处理
# function mvn_swe_getspec()

# end
# function convert_units(dat)
#     energy  = dat[:energy     ]       #[eV]
#     denergy = dat[:denergy    ]       #[eV]
#     gf      = dat[:gf]  .*dat[:eff]     #energy/angle dependent GF with MCP efficiency [cm2-ster-eV/eV]
#     dt      = dat[:integ_t ]          #integration time [sec] per energy/angle bin (unsummed)
#     dt_arr  = dat[:dt_arr     ]       ##energies * #anodes per bin for rate and dead time corrections
#     dtc     = dat[:dtc        ]       #dead time correction: 1. - (raw count rate)*dead time [1]


# end
"""
    n1d(dat; energy_range=[0,1e8], sc_pot=0) -> Vector{Float64}

由 SWEA 电子能谱计算电子数密度（cm⁻³）。

# 功能与算法概述
参考 SPEDAS 的 `mvn_swe_n1d`：对能谱乘立体角与能量幂律因子
`4π·1e-5·√(m/2)·dE·√(1−eΦ/E)·E^(-3/2)` 后沿能量维求和；假定电子为各向同性分布。

# 参数说明
- `dat`: SWEA 数据字典，需含 `:energy`（64 能道）、`:diff_en_fluxes`。
- `energy_range`: 能量窗（当前实现未用于掩膜，保留参数）。
- `sc_pot`: 航天器电位（eV），用于低能截断修正。

# 返回值
- `Vector{Float64}`: 各时刻的电子密度（cm⁻³）。

# 注意事项
- 能道间隔 `dE` 用相邻能道的半间距近似（首尾单侧）。
- 已删除死变量 `tiny = 1.0-31`（TASK-018）；`ff` 截断逻辑保留，数值结果不变。
"""
function n1d(dat;energy_range=[0,1e8],sc_pot=0) #projects/maven/swea/mvn_swe_n1d.pro

    mass = constants.me_eV_per_km_s2
    c1 = (mass/(2*π))^1.5
    c2 = (2e5/(mass*mass))
    c3 = 4.0*π*1e-5*sqrt(mass/2.0)  # assume isotropic electron distribution

    E = dat[:energy]
    dE = zeros(64)
    dE[1] = abs(E[2]-E[1])/2.0 
    dE[2:63] = abs.(E[3:64] .- E[1:62])./2.0
    dE[64] = abs(E[64]-E[63])
    eflux = dat[:diff_en_fluxes]

    E = reshape(E,1,64)
    dE = reshape(dE,1,64)

    #     ounits = mvn_swe_engy[0].units_name
    # mvn_swe_convert_units, mvn_swe_engy, 'eflux'
    # energy = mvn_swe_engy[tndx].energy
    # eflux = mvn_swe_engy[tndx].data
    # var = mvn_swe_engy[tndx].var
    # bkg = mvn_swe_engy[tndx].bkg
    # sc_pot = mvn_swe_engy[tndx].sc_pot

    # F = (eflux[*,i] - bkg[*,i]) > 0.
    F = eflux
    # S = sdev[*,i]
    pot = sc_pot
    prat = (pot./E)
    ff = x -> x > 1 ? 1.0 : x # prevent prat from going below tiny
    prat = ff.(prat)
    # prat = 0
    Enorm = c3.*dE.*sqrt.(1.0 .- prat) .*(E.^(-1.5))
    N_j = Enorm.*F
    #     S_j = Enorm*S[j]

    dens = sum(N_j,dims=2)[:,1] # sum over energy bins
    return dens
end
"""
    load_quat(filename::String) -> Matrix{Float64}

读取 IDL 导出的 CSV 姿态数据（ut + 4 个矩阵元素）。

# 功能与算法概述
先统计行数预分配 `n×5` 矩阵，再按固定字符列宽解析每行的 `ut` 与 4 个浮点数。

# 参数说明
- `filename::String`: 文件路径（格式 `(I10,1x,4(f14.10,1x),4(f14.10,1x))`）。

# 返回值
- `Matrix{Float64}`: `n×5`，各列为 `ut` 与 4 个矩阵元素。

# 注意事项
- 采用固定字符列宽切片解析，列位置须与 IDL 导出格式严格一致。
"""
function load_quat(filename::String)#读取idl导出的quat数据
    # 数据格式, filename = file.csv ut, scrotmat, msorotmat, format="(I10,1x,4(f14.10,1x),4(f14.10,1x))"
    # 统计行数以预分配矩阵
    n = 0
    open(filename) do io
        for _ in eachline(io)
            n += 1
        end
    end
    # 预分配矩阵，每行包含ut和8个浮点数
    data = Matrix{Float64}(undef, n, 5)
    # 逐行解析数据
    open(filename) do io
        for (i, line) in enumerate(eachline(io))
            # 提取各字段并转换为Float64
            ut = parse(Float64, SubString(line, 1, 10))
            mso1 = parse(Float64, SubString(line, 12, 25))
            mso2 = parse(Float64, SubString(line, 27, 40))
            mso3 = parse(Float64, SubString(line, 42, 55))
            mso4 = parse(Float64, SubString(line, 57, 70))
            
            # 填充数据到矩阵
            @inbounds data[i, :] .= (ut, mso1, mso2, mso3, mso4)
        end
    end
    
    return data
end
# ---------------------------------------------------------------------------
# SWEA shape parameter 能力（t25 自 MAVEN_data/MAVEN_load.jl 逐字迁入）
# 依赖：constants（本文件上方 include）与 MarsCommon.searchsortednearest（common 层，向下依赖）。
# ---------------------------------------------------------------------------
# SWEA shape parameter 计算相关的能量通道常量（TASK-022）
const SWEA_N_ENERGY_BINS = 64
const SWEA_SHAPE_FIRST_BIN = 13
const SWEA_SHAPE_LAST_BIN = SWEA_N_ENERGY_BINS
const SWEA_SHAPE_NBINS = SWEA_SHAPE_LAST_BIN - SWEA_SHAPE_FIRST_BIN + 1

"""
    SWEA_calc_shape_arr(dat; energy_range=[20,80], pad_range=[0,30], time_i=nothing) -> Vector{Float64}

计算 SWEA 指定俯仰角范围的 shape parameter。

# 功能与算法概述
参考 SPEDAS：先把 `pad_range` 内能谱按 `d_pa` 加权平均，再在 `energy_range` 内对
`log10(eflux)` 作数值一阶导，与电离层响应模板 `df_iono` 之差的绝对值求和即 shape parameter。

# 参数说明
- `dat`: SWEA PAD 字典，需含 `:num_dists`、`:diff_en_fluxes`、`:energy`、`:pa`、`:d_pa`、`:filename`。
- `energy_range`: 能量窗 `[lo, hi]`（eV）。
- `pad_range`: 俯仰角窗 `[lo, hi]`（度）。
- `time_i`: 时间索引范围，`nothing` 表示全部。

# 返回值
- `Vector{Float64}`: 各时刻的 shape parameter。

# 注意事项
- 由文件名判断分辨率（`arc` → 高分辨率模板）。
- 嵌套函数 `mvn_swe_calc_shape_arr` 与 `deriv` 分别做模板拟合与非均匀一阶差分。
- 模板匹配默认使用能量通道 `SWEA_SHAPE_FIRST_BIN:SWEA_SHAPE_LAST_BIN`
  （`$(SWEA_SHAPE_FIRST_BIN):$(SWEA_SHAPE_LAST_BIN)`，共 `SWEA_SHAPE_NBINS` 道）。
"""
function SWEA_calc_shape_arr(dat;energy_range = [20,80], pad_range = [0,30],time_i = nothing)# 计算指定pa范围的shape parameter,设置time_i后可以计算指定时间段的数据以增加运行速度
    """
        mvn_swe_calc_shape_arr(npts, fin, energy; hresflg=true, energy_range=[0.0, 100.0]) -> Vector{Float64}

    对对数能谱做一阶导并与电离层响应模板比较，得到 shape parameter。

    # 参数说明
    - `npts`: 样本数。
    - `fin`: 能谱矩阵（`npts×nenergy`）。
    - `energy`: 能量网格。
    - `hresflg`: 是否使用高分辨率模板。
    - `energy_range`: 能量窗 `[lo, hi]`。

    # 返回值
    - `Vector{Float64}`: 各样本的 shape parameter（无效谱为 `NaN`）。
    """
    function mvn_swe_calc_shape_arr(npts, fin, energy; hresflg=true, energy_range = [0.0, 100.0])
        """
            deriv(x, y) -> Vector

        对非均匀采样数据做数值一阶差分（仿 IDL `deriv`）。

        # 参数说明
        - `x`: 自变量网格。
        - `y`: 因变量。

        # 返回值
        - `Vector`: 同 `y` 长度的一阶导数。
        """
        function deriv(x, y)
            # ref deriv for idl
            # Ensure we have at least 3 points
            n = length(x)

            d = (circshift(x, -1) .- circshift(x, 1)) / 2.0
            d[1] = (-3.0 * x[1] + 4.0 * x[2] - x[3]) / 2.0
            d[end] = (3.0 * x[end] - 4.0 * x[end-1] + x[end-2]) / 2.0

            # Compute the shifts
            x0 = circshift(x, 1)
            x2 = circshift(x, -1)
            x01 = x0 .- x
            x02 = x0 .- x2
            x12 = x .- x2

            # Middle points calculation (flip sign of the last term so we can reuse x01)
            d = circshift(y, 1) .* (x12 ./ (x01 .* x02)) .+ y .* (1.0 ./ x12 .- 1.0 ./ x01) .- circshift(y, -1) .* (x01 ./ (x02 .* x12))

            # Formulae for the first and last points
            d[1] = y[1] * (x01[2] + x02[2]) / (x01[2] * x02[2]) - y[2] * x02[2] / (x01[2] * x12[2]) + y[3] * x01[2] / (x02[2] * x12[2])
            d[end] = -y[end-2] * x12[end-1] / (x01[end-1] * x02[end-1]) + y[end-1] * x02[end-1] / (x01[end-1] * x12[end-1]) - y[end] * (x02[end-1] + x12[end-1]) / (x02[end-1] * x12[end-1])
            return d
        end
        # ref projects\maven\swea\mvn_swe_calc_shape_arr.pro
        # Constants for ionospheric response
        df_lres = [ 0.0371289, 0.0179520, 0.0179520, 0.0356604, 0.0356604, 0.259604,
                    0.259604, 0.188697, 0.188697, -0.0261332, -0.0261332, 0.0849961,
                    0.0849961, 0.102494, 0.102494, 0.0595406, 0.0595406, 0.0591643,
                    0.0591643, 0.0459675, 0.0459675, 0.0296691, 0.0296691, 0.204077,
                    0.204077, 0.308229, 0.308229, 0.0962973, 0.0962973, 0.118876,
                    0.118876, 0.160658, 0.160658, 0.0387319, 0.0387319, 0.00507925,
                    0.00507925, 0.0866565, 0.0866565, 0.114288, 0.114288, 0.0612787,
                    0.0612787, 0.0209041, 0.0209041, -0.0567795, -0.0567795, -0.124904,
                    -0.124904, -0.123564, -0.123564, 0.123564]

        df_hres = [ -0.00621939, 0.144627, -0.00556159, 0.0933514, 0.101257, 0.186915,
                    0.479829, 0.401596, 0.0638178, -0.0410685, -0.0147899, 0.0405415,
                    0.120542, 0.129752, 0.0718670, 0.0592695, 0.0666794, 0.0681327,
                    0.0577553, 0.0493796, 0.0360952, 0.0234586, 0.0409702, 0.108591,
                    0.251231, 0.360782, 0.279757, 0.129745, 0.0748887, 0.0924677,
                    0.131181, 0.166274, 0.156800, 0.0917069, -0.0123766, -0.0285236,
                    0.0425429, 0.0720319, 0.0926143, 0.114485, 0.105823, 0.0707967,
                    0.0469701, 0.0305556, 0.00320172, -0.0334262, -0.0743820, -0.107133,
                    -0.127032, -0.128968, -0.118429, -0.120177]

        # Select df_iono based on hresflg
        df_iono = hresflg == 1 ? df_hres : df_lres

        # Select energy channels (TASK-022：用命名常量替换硬编码 13:64 / 52)
        n_e = SWEA_SHAPE_NBINS # Number of model energy channels
        indx = collect(SWEA_SHAPE_FIRST_BIN:SWEA_SHAPE_LAST_BIN)
        e = energy[indx]
        # Take the first derivative of log(eflux) w.r.t. log(E)
        f = log10.(fin[:,indx])

        emin, emax = energy_range[1], energy_range[2]
        endx = findall(x -> emin <= x <= emax, e)
        f = f[:, endx]
        df_ion = df_iono[endx]
        n_e = length(endx)

        # Filter out bad spectra (such as hot electron voids,if finite exit, if not, set to false)
        gndx = findall(x -> !(false in isfinite.(x)) ,eachrow(f[:, :]))
        par = Vector{Float64}(undef,npts)
        par .= NaN
        @inbounds for i in gndx
            df = deriv(1:n_e,f[i, :]) # First derivative
            par[i] = sum(abs.(df .- df_ion))
        end
        return par
    end
    ntimes = dat[:num_dists]
    if time_i == nothing
        time_i = 1:ntimes
    end
    npts = length(time_i)
    hresflg = 1
    flux = dat[:diff_en_fluxes][time_i,:,:]
    flux[isnan.(flux)] .= 0
    energy = dat[:energy]
    hresflg = dat[:filename][end-26:end-24] == "arc"
    pad = dat[:pa][time_i,:,:]
    d_pad = dat[:d_pa][time_i,:,:]

    mask_pad = pad_range[1] .<= pad .<= pad_range[2]
    flux_pad_mean = sum(flux .* mask_pad .* d_pad,dims=2)[:,1,:] ./ sum(mask_pad.* d_pad,dims=2)[:,1,:]
    par = mvn_swe_calc_shape_arr(npts,flux_pad_mean,energy; energy_range=energy_range, hresflg=hresflg)
    return par
end
"""
    SWEA_calc_shape_arr_mars_towrads(SWEA_dat, MAG_dat; energy_range=[0,100], time_i=nothing, pa_width=30)

计算 SWEA shape parameter 并区分"指向火星(toward)"与"背离火星(away)"。

# 功能与算法概述
由磁场方向与位置方向的夹角判断磁力线指向（用最近邻 MAG 时间匹配），
分别对平行/反平行与中间俯仰角窗调用 `SWEA_calc_shape_arr`，再按 `B_out` 组合出指向/背离结果。

# 参数说明
- `SWEA_dat`: SWEA PAD 数据字典。
- `MAG_dat`: MAG 数据字典，需含 `:epoch`、`:position`、`:B`、`:B_total`。
- `energy_range`: 能量窗 `[lo, hi]`（eV）。
- `time_i`: 时间索引范围。
- `pa_width`: 平行方向俯仰角窗宽度（度）。

# 返回值
- `(par_twd, par_away, par_mid)`: 指向、背离与中间分布的 shape parameter 向量。

# 注意事项
- 建议 MAG 使用 pc 坐标（ss 亦可）。
"""
function SWEA_calc_shape_arr_mars_towrads(SWEA_dat,MAG_dat;energy_range=[0,100],time_i = nothing,pa_width =30)#将sp计算为指向和指出火星,需要同时导入磁场,建议pc,ss理论上也可,pa_width为PAD角度范围,设置time_i后可以计算指定时间段的数据以增加运行速度; 指向和指出单纯由磁场Br的正负和平行或反平行决定.
    # ref projects\maven\swea\mvn_swe_shape_par_pad_l2.pro
    ntimes = SWEA_dat[:num_dists]
    if time_i == nothing
        time_i = 1:ntimes
    end
    npts = length(time_i)
    tb = MAG_dat[:epoch]
    pb = MAG_dat[:position]
    b = MAG_dat[:B]
    b_total = MAG_dat[:B_total]
    te = SWEA_dat[:epoch][time_i]
    #计算磁场方向
    tb_i = zeros(Int64,npts)
    for i in 1:npts
        tb_i[i] = MarsCommon.searchsortednearest(tb, te[i])
    end
    norm_b = b[tb_i,:] ./ reshape(b_total[tb_i],:,1)
    norm_p = pb[tb_i,:] ./ sqrt.(sum(pb[tb_i,:].^2,dims=2))
    B_angle = acos.(sum(norm_b .* norm_p,dims=2))[:,1]
    B_out = B_angle .> 0

    par_antipara  = SWEA_calc_shape_arr(SWEA_dat;pad_range=[180-pa_width,180],energy_range=energy_range,time_i = time_i)
    par_para = SWEA_calc_shape_arr(SWEA_dat;pad_range=[0,pa_width],energy_range=energy_range,time_i = time_i)
    par_mid = SWEA_calc_shape_arr(SWEA_dat;pad_range=[pa_width,180-pa_width],energy_range=energy_range,time_i = time_i)

    par_twd = zeros(npts)
    par_away = zeros(npts)
    par_twd[B_out] .= par_antipara[B_out]
    par_twd[.!B_out] .= par_para[.!B_out]

    par_away[B_out] .= par_para[B_out]
    par_away[.!B_out] .= par_antipara[.!B_out]
    return par_twd,par_away,par_mid
end
"""
    carclu_SWEA_pad(data; energy_range=[]) -> Dict{Symbol, Any}

对 SWEA PAD 数据按能量窗做加权归并。

# 功能与算法概述
`energy_range` 为标量时取最接近的单一能道；为区间时以 `g_pa`/`g_engy` 为权重把
窗内俯仰角与通量加权平均为单值，并把 `NaN` 置为 `1e-10`。

# 参数说明
- `data`: SWEA PAD 字典，需含 `:epoch`、`:pa`、`:energy`、`:diff_en_fluxes`、`:g_pa`、`:g_engy`。
- `energy_range`: 标量（单能道）或 `[lo, hi]`（能量窗）。

# 返回值
- `Dict`: 含 `:epoch`、`:pa`、`:diff_en_fluxes`、`:energy`、`:data_load_flag` 的字典。

# 注意事项
- 输出 `:energy` 在区间模式下为 `[E_lo, E_hi]` 两端值。
- t13 自 MAVEN_data/MAVEN_load.jl 整块迁入（example/*.jl 调用已改为限定名 MAVEN_SWEA.carclu_SWEA_pad）。
"""
function carclu_SWEA_pad(data; energy_range=[])  # SWEA PAD数据处理
    time = data[:epoch]
    pitch_angle = data[:pa]
    energy_arr = data[:energy]
    flux_arr = data[:diff_en_fluxes]
    g_pa = data[:g_pa]
    g_engy = data[:g_engy]
    if size(energy_range)[1] == 1
        _, index = findmin(abs.(energy_arr .- energy_range))
        index = index[1]
        energy_single = energy_arr[index]
        pitch_angle_PAD = pitch_angle[:, :, index]
        flux_PAD = flux_arr[:, :, index]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        return_data = Dict(
            :epoch => time,
            :pa => pitch_angle_PAD,
            :diff_en_fluxes => flux_PAD,
            :energy => energy_single,
            :data_load_flag => true
        )
        return return_data #[time,pitch_angle_PAD,flux_PAD,energy_single]
    else
        # mask = (energy_arr .>= energy_range[1]) .& (energy_arr .<= energy_range[2])
        # mapped_mask = zeros(1,1,64)
        # mapped_mask[1,1,:] = mask

        energy_i = findall(e -> energy_range[1] <= e <= energy_range[2], energy_arr)
        energy_double = [energy_arr[energy_i[1]], energy_arr[energy_i[end]]]
        pitch_angle_PADt = sum(pitch_angle[:, :, energy_i] .* g_pa[:, :, energy_i], dims=3) ./ sum(g_pa[:, :, energy_i], dims=3)
        pitch_angle_PAD = pitch_angle_PADt[:, :, 1]

        g_engy_t = zeros(1, 1, 64)
        g_engy_t[1, 1, :] = g_engy

        flux_PADt = sum(flux_arr[:, :, energy_i] .* g_engy_t[:, :, energy_i], dims=3) / sum(g_engy_t[:, :, energy_i])
        flux_PAD = flux_PADt[:, :, 1]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        # return_data = Dict(
        #     "Var name" => "time[Ntime], pitch_angle[Ntime,Npa], eflux[Ntime,Npa], energy_double[2]",
        #     "Vars"     => [time, pitch_angle_PAD, flux_PAD, energy_double],
        #     "flag"     => true
        # )
        return_data = Dict(
            :epoch => time,
            :pa => pitch_angle_PAD,
            :diff_en_fluxes => flux_PAD,
            :energy => energy_double,
            :data_load_flag => true
        )
        return return_data #[time,pitch_angle_PAD,flux_PAD,energy_double]
    end
end
end

# # -------------------------Test parts-------------------------
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath * "MAVEN_data/MAVEN_load.jl")
# import .MAVEN_load;
# import .MAVEN_SWEA;
# using Dates
# using CairoMakie
# using DataInterpolations
# time_range = [DateTime(2015,10,29,11),DateTime(2015,10,29,12)]
# time_range = [DateTime(2015,10,29,11,27),DateTime(2015,10,29,11,39)]
# MAVEN_load.change_kp_read_data(Dict(
#     :electorn_density => 2,
#     :sw_electorn_density => 23,
#     :Ne_quality_min => 3,
#     :Ne_quality_max => 4,
#     :GEO_x => 187,
#     :GEO_y => 188,
#     :GEO_z => 189,
#     :MSO_x => 190,
#     :MSO_y => 191,
#     :MSO_z => 192,
#     :Orbit_Number => 210,
#     :Shape_parameter => 39,
#     :H_flow_MSO_x => 43,
#     :H_flow_MSO_y => 45,
#     :H_flow_MSO_z => 47,
#     :Oiondensity => 56,
#     :O2iondensity => 58,
#     :iondensity16 => 172,
#     :iondensity32 => 163,
#     :iondensity44 => 167,
#     :OionTemperature => 62,
#     :O2ionTemperature => 64,
# ));
# dat0 = MAVEN_load.load_MAVEN_data(DateTime(2015,10,29); model_index=["SWEA_spec","KP","LPW_mrgscpot","LPW_lpnt","LPW_wn"])
# dat_swe=dat0["SWEA_spec"]
# dat_kp = dat0["KP"]
# dat_pot = dat0["LPW_mrgscpot"]
# func_on_zero = x -> isnan(x) ? 0.0 : x
# func_pot = CubicSpline(func_on_zero.(dat_pot[:data]),datetime2unix.(dat_pot[:epoch]),extrapolate=true)
# pots = func_pot.(datetime2unix.(dat_swe[:epoch]))

# dens = MAVEN_SWEA.n1d(dat_swe;sc_pot=pots)
# time_i_swe = findall(x ->time_range[2]>= x >= time_range[1], dat_swe[:epoch])

# time_i_kp = findall(x ->time_range[2]>= x >= time_range[1], dat_kp[:time])
# fig = Figure(resolution=(800, 600))
# ax = Axis(fig[1, 1], xlabel="time", ylabel="Density (1/cm^3)", title="MAVEN SWEA Density")
# lines!(ax, dat_swe[:epoch][time_i_swe], dens[time_i_swe], color=:blue, label="Density")
# lines!(ax, dat_kp[:time][time_i_kp], dat_kp[:sw_electorn_density][time_i_kp], color=:red, label="Kp Index")

# ax = Axis(fig[2, 1], xlabel="time", ylabel="Density (1/cm^3)", title="MAVEN SWEA Density",yscale=log10)

# time_i1 = findall(x ->time_range[2]>= x >= time_range[1], dat0["LPW_lpnt"][:epoch])
# scatter!(ax, dat0["LPW_lpnt"][:epoch][time_i1], dat0["LPW_lpnt"][:data][time_i1], color=:blue, label="Density")

# time_i2 = findall(x ->time_range[2]>= x >= time_range[1], dat0["LPW_wn"][:epoch])
# scatter!(ax, dat0["LPW_wn"][:epoch][time_i2], dat0["LPW_wn"][:data][time_i2], color=:red, label="Density")

# fig
