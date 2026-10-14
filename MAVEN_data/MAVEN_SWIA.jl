# 处理MAVEN的SWIA数据
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_SWIA
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
using TimesDates, Dates
using Statistics
using Rotations
using DataInterpolations
using CommonDataFormat
# -------------------------Export parts-------------------------
# export static_c6_mass_mean,static_c6_energy_mean
# export static_rotation,static_slip,static_slip_2_V,sta_v_4d
#---------------------------初始化-------------------------------- 由于SWIA的糟糕数据,需要对其读取后进行初始化处理
"""
    get_3dc!(dat; quat_data=nothing) -> Dict{Symbol, Any}

把 SWIA coarse 3D 原始数据整理为标准四维（time×anode×deflect×energy）网格。

# 功能与算法概述
按衰减状态选择 `theta_coarse`/`theta_atten_coarse`，用中心差分求 `dtheta`，
预计算立体角 `domega` 并写入维度、能量、角度与质子质量等规范化字段；
提供 `quat_data` 时按最近邻时间匹配姿态四元数并标记质量。

# 参数说明
- `dat`: SWIA coarse 数据字典，需含 `:epoch`、`:energy_coarse`、`:phi_coarse`、`:theta_coarse`、`:theta_atten_coarse`、`:atten_state`、`:diff_en_fluxes`、`:time_unix` 等。
- `quat_data`: 可选姿态数据字典（含 `:time_unix`、`:quat`）；缺省或未加载时跳过。

# 返回值
- `Dict{Symbol, Any}`: 已就地补全 `:energy`、`:theta`、`:dtheta`、`:domega`、`:phi`、`:mass`、`:quat_mso`、`:quat_quality` 的同一字典。

# 注意事项
- 直接原地修改 `dat`（函数名带 `!`）。
- 姿态时间偏差超过 4 s 时对应时刻 `:quat_quality` 置 `false`。
"""
function get_3dc!(dat;quat_data = nothing)#projects/maven/swia/mvn_swia_get_3dc.pro,直接处理dat,需要SWIA coarse data 3D
    local ntime = length(dat[:epoch])
    local nanode = 16
    local ndeflect = 4
    local nbins = 64
    local nenergy = 48

    local energy= reshape(dat[:energy_coarse],1,48)
    local denergy = energy .* 0.15 #dat[:de_over_e_coarse]

    local phi = dat[:phi_coarse]
    local dphi = 22.5
    local atten = dat[:atten_state]
    local theta_coarse =  dat[:theta_coarse] # : dat[:theta_atten_coarse]
    local theta_atten_coarse = dat[:theta_atten_coarse]

    local theta = zeros(ntime,ndeflect,nenergy)

    for i in 1:ntime
        if atten[i] <= 1
            theta[i,:,:] = theta_coarse[:,:]
        else
            theta[i,:,:] = theta_atten_coarse[:,:]
        end
    end

    local dtheta = (circshift(theta,(0,-1,0)) - circshift(theta,(0,1,0)))/2
    dtheta[:,1,:] = theta[:,2,:] - theta[:,1,:]
    dtheta[:,end,:] = theta[:,end,:] - theta[:,end-1,:]
    local theta = reshape(theta,ntime,4,48)
    local dtheta = reshape(dtheta,ntime,4,48)

    local domega = 2.0*deg2rad(dphi)*cosd.(theta).*sind.(0.5*dtheta)

    dat[:ntime] = ntime
    dat[:nbins] = nbins

    dat[:nenergy] = nenergy
    dat[:energy] = energy
    dat[:denergy] = denergy

    dat[:ndeflect] = ndeflect
    dat[:ntheta] = ndeflect
    dat[:theta] = theta
    dat[:dtheta] = dtheta

    dat[:nanode] = nanode
    dat[:nphi] = nanode
    dat[:phi] = phi
    dat[:dphi] = dphi
    
    dat[:domega] = domega
    dat[:mass] = constants.mp_eV_per_km_s2

    # 处理quat数据
    if quat_data === nothing || quat_data[:data_load_flag] == false
        @warn "No quat data used"
        dat[:quat_quality] = fill(false,ntime)
        return dat
    end
    local time_dat  = dat[:time_unix]
    local time_quat = quat_data[:time_unix]
    local dat[:quat_mso] = fill(one(QuatRotation),ntime)
    local dat[:quat_quality] = fill(true,ntime)
    @inbounds for i in 1:ntime
        local idx = MarsCommon.searchsortednearest(time_quat, time_dat[i])
        local dt = abs(time_quat[idx] - time_dat[i])
        if dt > 4
            # @warn "存在时间偏差过大的quat值, t = $(dat[:epoch][i]), dt = $(round(dt))秒，请检查:quat_quality项"
            dat[:quat_quality][i]=false
            # continue
        end
        dat[:quat_mso][i] = quat_data[:quat][idx]
    end
    return dat
    # [:filename, :theta_coarse, :theta_atten_coarse, :g_phi_atten_coarse, :g_theta_atten_coarse, :g_phi_coarse, :energy_coarse, :time_unix, :time_met, :diff_en_fluxes, :atten_state, :g_theta_coarse, :counts, :phi_coarse, :data_load_flag, :dindex, :num_accum, :grouping, :epoch]
end
"""
    get_3df!(dat; quat_data=nothing) -> Dict{Symbol, Any}

把 SWIA fine 3D 原始数据整理为标准四维网格（含能量/偏转步数裁剪）。

# 功能与算法概述
按每时刻的 `dstep_first`/`estep_first` 抽取 12×48 的角度/能量子块，按衰减状态选择
`theta_fine`/`theta_atten_fine`，中心差分求 `dtheta` 并预计算 `domega`，写入规范化字段；
`quat_data` 的处理同 `get_3dc!`。

# 参数说明
- `dat`: SWIA fine 数据字典，需含 `:epoch`、`:energy_fine`、`:phi_fine`、`:theta_fine`、`:theta_atten_fine`、`:atten_state`、`:estep_first`、`:dstep_first`、`:de_over_e_fine`、`:diff_en_fluxes`、`:time_unix` 等。
- `quat_data`: 可选姿态数据字典。

# 返回值
- `Dict{Symbol, Any}`: 已就地补全 `:energy`、`:theta`、`:dtheta`、`:domega`、`:phi`、`:mass`、`:quat_mso`、`:quat_quality` 的同一字典。

# 注意事项
- 直接原地修改 `dat`；fine 网格的角元数固定为 12×48。
"""
function get_3df!(dat;quat_data = nothing) #projects/maven/swia/mvn_swia_get_3df.pro,直接处理dat,需要SWIA fine data 3D
    # keys(dat) = [:geom_factor, :filename, :theta_fine, :theta_atten_fine, :time_unix, :time_met, :diff_en_fluxes, :g_theta_fine, :atten_state, :estep_first, :phi_fine, :g_phi_fine, :eindex, :num_dists, :energy_fine, :dstep_first, :counts, :data_load_flag, :g_phi_atten_fine, :accum_time_fine, :g_theta_atten_fine, :dindex, :grouping, :de_over_e_fine, :epoch]
    local ntime = length(dat[:epoch])
    local nanode = 10
    local ndeflect = 12
    local nbins = 120
    local nenergy = 48

    # startt = dat[:time_unix]
	local atten = dat[:atten_state]
	# infind = dat[:info_index]
	local estepf = dat[:estep_first]
	local dstepf = dat[:dstep_first]
    # dt_int  = dat[:dt_int]
    # dt_arr = ones(1,nenergy,nbins)

    local phi = dat[:phi_fine]
    local dphi = 4.5
    local atten = dat[:atten_state]
    local theta_fine =  dat[:theta_fine] # : dat[:theta_atten_fine]
    local theta_atten_fine = dat[:theta_atten_fine]

    local energy = zeros(ntime,nenergy)
    local theta = zeros(ntime,ndeflect,nenergy)

    for i in 1:ntime
        ti = dstepf[i]+1:dstepf[i]+12
        ei = estepf[i]+1:estepf[i]+48
        energy[i,:] = dat[:energy_fine][ei]
        if atten[i] <= 1
            theta[i,:,:] = theta_fine[ti,ei]
        else
            theta[i,:,:] = theta_atten_fine[ti,ei]
        end
    end
    local denergy = energy .* dat[:de_over_e_fine]

    local dtheta = (circshift(theta,(0,-1,0)) - circshift(theta,(0,1,0)))/2
    dtheta[:,1,:] = theta[:,2,:] - theta[:,1,:]
    dtheta[:,end,:] = theta[:,end,:] - theta[:,end-1,:]
    local theta = reshape(theta,ntime,1,ndeflect,nenergy)
    local dtheta = reshape(dtheta,ntime,1,ndeflect,nenergy)

    local domega = 2.0*deg2rad(dphi)*cosd.(theta).*sind.(0.5*dtheta)

    dat[:ntime] = ntime
    dat[:nbins] = nbins

    dat[:nenergy] = nenergy
    dat[:energy] = energy
    dat[:denergy] = denergy

    dat[:ndeflect] = ndeflect
    dat[:ntheta] = ndeflect
    dat[:theta] = theta
    dat[:dtheta] = dtheta

    dat[:nanode] = nanode
    dat[:nphi] = nanode
    dat[:phi] = phi
    dat[:dphi] = dphi
    
    dat[:domega] = domega
    dat[:mass] = constants.mp_eV_per_km_s2

   # 处理quat数据
    if quat_data === nothing || quat_data[:data_load_flag] == false
        @warn "No quat data used"
        dat[:quat_quality] = fill(false,ntime)
        return dat
    end
    local time_dat  = dat[:time_unix]
    local time_quat = quat_data[:time_unix]
    local dat[:quat_mso] = fill(one(QuatRotation),ntime)
    local dat[:quat_quality] = fill(true,ntime)
    @inbounds for i in 1:ntime
        local idx = MarsCommon.searchsortednearest(time_quat, time_dat[i])
        local dt = abs(time_quat[idx] - time_dat[i])
        if dt > 4
            # @warn "存在时间偏差过大的quat值, t = $(dat[:epoch][i]), dt = $(round(dt))秒，请检查:quat_quality项"
            dat[:quat_quality][i] = false
            # continue
        end
        dat[:quat_mso][i] = quat_data[:quat][idx]
    end
    return dat
    # [:filename, :theta_coarse, :theta_atten_coarse, :g_phi_atten_coarse, :g_theta_atten_coarse, :g_phi_coarse, :energy_coarse, :time_unix, :time_met, :diff_en_fluxes, :atten_state, :g_theta_coarse, :counts, :phi_coarse, :data_load_flag, :dindex, :num_accum, :grouping, :epoch]
end
"""
    n_3d(dat, time_ind; energy_range=[0.1,1e8]) -> Vector{Float64}

按指定的时间索引计算 SWIA 质子密度（cm⁻³）。

# 功能与算法概述
参考 SPEDAS 的 `n_3d`：对 `diff_en_fluxes` 乘立体角并在阳极/偏转维求和，
再乘能量幂律因子 `dE·E^(-3/2)`（系数 `7.2246e-7`）沿能量维积分得密度；假定所有离子为质子。

# 参数说明
- `dat`: 经 `get_3dc!`/`get_3df!` 处理的数据字典。
- `time_ind`: 时间索引（标量或范围）。
- `energy_range`: 能量窗 `[lo, hi]`（eV）。

# 返回值
- `Vector{Float64}`: 各时刻的密度（cm⁻³）。

# 注意事项
- SWIA 只区分质子，重离子会被计入质子密度。
"""
function n_3d(dat,time_ind;energy_range=[0.1,1e8])# 计算SWIA的密度, SWIA假设所有离子为质子,需要get_3d系列
    # general/science/n_3d.pro // projects/maven/swia/mvn_swia_get_3dc.pro 参考

    local ntime_local = length(time_ind)
    # ntime = dat[:ntime]  
    # nbins = dat[:nbins]  

    local nenergy = dat[:nenergy]  
    local energy = dat[:energy]
    local denergy = dat[:denergy]

    local ndeflect = dat[:ndeflect]  
    # theta = reshape(dat[:theta][time_ind,:,:],ntime_local,1,ndeflect,nenergy)
    # dtheta = reshape(dat[:dtheta][time_ind,:,:],ntime_local,1,ndeflect,nenergy)

    local nanode = dat[:nanode]  
    # local phi = reshape(dat[:phi],1,nanode,1,1)
    # dphi = dat[:dphi]  
    
    local domega = reshape(dat[:domega][time_ind,:,:],ntime_local,1,ndeflect,nenergy)
    # mass = dat[:mass]
    local data0 = reshape(dat[:diff_en_fluxes][time_ind,:,:,:],ntime_local,nanode,ndeflect,nenergy)

    local mask = reshape(energy_range[1] .<= energy[1,:] .<= energy_range[2],1,1,1,nenergy)

    local data = data0.*mask

    # mass = dat[:mass]
    # data = dat[:diff_en_fluxes][time_ind,:,:,:]

    sumdata = sum(data.*domega,dims=2:3)[:,1,1,:]

    Const = 7.224566339926571e-7
    density = Const*sum(denergy.*(energy.^(-1.5)).*sumdata,dims=2)[:,1]
    return density
end
"""
    j_3d(dat, time_ind; energy_range=[0.1,1e8]) -> Matrix{Float64}

按指定的时间索引计算 SWIA 质子通量矢量（cm⁻²s⁻¹）。

# 功能与算法概述
参考 SPEDAS 的 `j_3d`：在阳极/偏转维以方向余弦加权求和得到通量三分量，
再乘 `dE/E` 沿能量维积分；假定所有离子为质子。

# 参数说明
- `dat`: 经 `get_3dc!`/`get_3df!` 处理的数据字典。
- `time_ind`: 时间索引（标量或范围）。
- `energy_range`: 能量窗 `[lo, hi]`（eV）。

# 返回值
- `Matrix{Float64}`: `ntime×3` 的通量三分量（cm⁻²s⁻¹）。

# 注意事项
- SWIA 只区分质子。
"""
function j_3d(dat,time_ind;energy_range=[0.1,1e8])# 计算SWIA的通量, SWIA假设所有离子为质子,需要SWIA coarse data 3D, 
    # general/science/j_3d.pro // projects/maven/swia/mvn_swia_get_3dc.pro 参考, 单位cm^-2s^-1
    local ntime_local = length(time_ind)
    # ntime = dat[:ntime]  
    # nbins = dat[:nbins]  

    local nenergy = dat[:nenergy]  
    local energy = dat[:energy]
    local denergy = dat[:denergy]

    local ndeflect = dat[:ndeflect]  
    local theta = reshape(dat[:theta][time_ind,:,:],ntime_local,1,ndeflect,nenergy)
    # local dtheta = reshape(dat[:dtheta][time_ind,:,:],ntime_local,1,ndeflect,nenergy)

    local nanode = dat[:nanode]  
    local phi = reshape(dat[:phi],1,nanode,1,1)
    # local dphi = dat[:dphi]  
    
    local domega = reshape(dat[:domega][time_ind,:,:],ntime_local,1,ndeflect,nenergy)
    # mass = dat[:mass]
    local data0 = reshape(dat[:diff_en_fluxes][time_ind,:,:,:],ntime_local,nanode,ndeflect,nenergy)

    local mask = reshape(energy_range[1] .<= energy[1,:] .<= energy_range[2],1,1,1,nenergy)

    local data = data0.*mask

    Const = 1.0

    sumdatax = sum(data.*cosd.(phi).*domega.*cosd.(theta),dims=2:3)[:,1,1,:]
    sumdatay = sum(data.*sind.(phi).*domega.*cosd.(theta),dims=2:3)[:,1,1,:]
    sumdataz = sum(data.*domega.*sind.(theta),dims=2:3)[:,1,1,:]
    dnrg=Const.*denergy./energy
    
    dnrg=denergy./energy

    flux3dx = sum(dnrg.*sumdatax,dims=2)[:,1]
    flux3dy = sum(dnrg.*sumdatay,dims=2)[:,1]
    flux3dz = sum(dnrg.*sumdataz,dims=2)[:,1]
    return hcat(flux3dx,flux3dy,flux3dz)
end
"""
    v_3d(dat, time_ind; energy_range=[0.1,1e8]) -> (Matrix, Matrix, Matrix)

按指定的时间索引计算 SWIA 质子速度、通量与密度（已通过校验）。

# 功能与算法概述
同时计算密度（同 `n_3d`）与通量三分量（同 `j_3d`），再由 `vel = 1e-5·flux/density`
归一化得速度；假定所有离子为质子。

# 参数说明
- `dat`: 经 `get_3dc!`/`get_3df!` 处理的数据字典。
- `time_ind`: 时间索引（标量或范围）。
- `energy_range`: 能量窗 `[lo, hi]`（eV）。

# 返回值
- `(vel, flux, density)`: 速度 `ntime×3`（km/s）、通量 `ntime×3`（cm⁻²s⁻¹）、密度 `ntime×1`（cm⁻³）。

# 注意事项
- SWIA 只区分质子；作者注释称本函数"已经过检验，可以正常工作"。
- **C5 修复**：`theta`/`domega` 支持 coarse 3D（`(ntime, ndeflect, nenergy)`）与 fine 4D
  （`(ntime, 1, ndeflect, nenergy)`）两种输入；非法维度会抛出带实际形状的清晰报错。
"""
function v_3d(dat,time_ind;energy_range=[0.1,1e8])# 计算SWIA的速度, SWIA假设所有离子为质子,需要SWIA coarse data 3D, 经过检验，可以正常工作
    # general/science/v_3d.pro // projects/maven/swia/mvn_swia_get_3dc.pro 参考，已经经过检验，速度单位km/s
    local ntime_local = length(time_ind)
    # ntime = dat[:ntime]
    # nbins = dat[:nbins]

    local nenergy = dat[:nenergy]
    local energy = dat[:energy]
    local denergy = dat[:denergy]

    local ndeflect = dat[:ndeflect]
    local nanode = dat[:nanode]

    # --- C5 修复：theta/domega 可能是 coarse 3D 或 fine 4D，按 ndims 分支索引 ---
    local theta_raw = dat[:theta]
    local domega_raw = dat[:domega]
    local theta, domega
    if ndims(theta_raw) == 3
        size(theta_raw, 1) >= maximum(time_ind) ||
            error("v_3d: theta 时间维长度 $(size(theta_raw,1)) 小于最大索引 $(maximum(time_ind))")
        size(theta_raw, 2) == ndeflect ||
            error("v_3d: coarse theta 的第二维 $(size(theta_raw,2)) 不等于 ndeflect=$(ndeflect)")
        size(theta_raw, 3) == nenergy ||
            error("v_3d: coarse theta 的第三维 $(size(theta_raw,3)) 不等于 nenergy=$(nenergy)")
        size(domega_raw) == size(theta_raw) ||
            error("v_3d: domega 形状 $(size(domega_raw)) 与 theta 形状 $(size(theta_raw)) 不一致")
        theta  = reshape(theta_raw[time_ind,:,:],  ntime_local, 1, ndeflect, nenergy)
        domega = reshape(domega_raw[time_ind,:,:], ntime_local, 1, ndeflect, nenergy)
    elseif ndims(theta_raw) == 4
        size(theta_raw, 1) >= maximum(time_ind) ||
            error("v_3d: theta 时间维长度 $(size(theta_raw,1)) 小于最大索引 $(maximum(time_ind))")
        size(theta_raw, 3) == ndeflect ||
            error("v_3d: fine theta 的偏转维 $(size(theta_raw,3)) 不等于 ndeflect=$(ndeflect)")
        size(theta_raw, 4) == nenergy ||
            error("v_3d: fine theta 的能量维 $(size(theta_raw,4)) 不等于 nenergy=$(nenergy)")
        size(domega_raw) == size(theta_raw) ||
            error("v_3d: domega 形状 $(size(domega_raw)) 与 theta 形状 $(size(theta_raw)) 不一致")
        theta  = reshape(theta_raw[time_ind,:,:,:],  ntime_local, 1, ndeflect, nenergy)
        domega = reshape(domega_raw[time_ind,:,:,:], ntime_local, 1, ndeflect, nenergy)
    else
        error("v_3d: theta 维度 $(ndims(theta_raw)) 不被支持，应为 3（coarse）或 4（fine）")
    end
    # local dtheta = reshape(dat[:dtheta][time_ind,:,:],ntime_local,1,ndeflect,nenergy)

    local phi = reshape(dat[:phi],1,nanode,1,1)
    # local dphi = dat[:dphi]
    local data0 = reshape(dat[:diff_en_fluxes][time_ind,:,:,:],ntime_local,nanode,ndeflect,nenergy)

    local mask = reshape(energy_range[1] .<= energy[1,:] .<= energy_range[2],1,1,1,nenergy)

    local data = data0.*mask

    local sumdata = sum(data.*domega,dims=2:3)[:,1,1,:]

    # C11 疑点：系数 7.224566339926571e-7 无推导注释。
    # 出处待验证：该值是否等于 sqrt(m_p/2)/某个单位换算？与 SPEDAS/IDL mvn_swia_get_3dc.pro 是否一致？
    # 状态：不改值，仅留此处待人类复核（03 §15 C11）。
    local Const = 7.224566339926571e-7
    density = Const*sum(denergy.*(energy.^(-1.5)).*sumdata,dims=2)

    local Const = 1.0

    local sumdatax = sum(data.*cosd.(phi).*domega.*cosd.(theta),dims=2:3)[:,1,1,:]
    local sumdatay = sum(data.*sind.(phi).*domega.*cosd.(theta),dims=2:3)[:,1,1,:]
    local sumdataz = sum(data.*domega.*sind.(theta)            ,dims=2:3)[:,1,1,:]
    local dnrg=Const.*denergy./energy

    local flux3dx = sum(dnrg.*sumdatax,dims=2)[:,1]
    local flux3dy = sum(dnrg.*sumdatay,dims=2)[:,1]
    local flux3dz = sum(dnrg.*sumdataz,dims=2)[:,1]
    flux = hcat(flux3dx,flux3dy,flux3dz)
    vel = 1.e-5*flux./density
    return vel,flux,density
end
"""
    n_1d(dat0; energy_range=[0.1,1e8], time_ind=1:10) -> Vector{Float64}

由 SWIA svy spec（一维能谱）计算质子密度（cm⁻³）。

# 功能与算法概述
对能谱按 `energy_range` 把窗外通道置零，再乘 `dE·E^(-3/2)`
（系数 `√(m/2E_eV)·8.8`）沿能量积分得密度；假定所有离子为质子。

# 参数说明
- `dat0`: 含 `:spectra_diff_en_fluxes`、`:energy_spectra`、`:de_over_e_spectra` 的 svy spec 字典。
- `energy_range`: 能量窗 `[lo, hi]`（eV）。
- `time_ind`: 时间索引，默认 `1:10`。

# 返回值
- `Vector{Float64}`: 各时刻的密度（cm⁻³）。

# 注意事项
- 内部对输入做 `deepcopy`，不修改原字典。
"""
function n_1d(dat0;energy_range=[0.1,1e8],time_ind=1:10)# 计算SWIA的密度, SWIA假设所有离子为质子,需要SWIA svy spec data 3D
    local dat= deepcopy(dat0)
    flux = dat[:spectra_diff_en_fluxes][time_ind,:]
    energy = reshape(dat[:energy_spectra],1,48)
    energy_ind = findall(x->x <= energy_range[1] || x >= energy_range[2],dat[:energy_spectra])
    flux[:,energy_ind] .= 0.0
    denergy = energy.*dat[:de_over_e_spectra]
    mass = constants.mp_g
    # C11 疑点：系数 8.8 乘在 sqrt(m_p/(2*erg_per_eV)) 上，无推导注释。
    # 出处待验证：SPEDAS/IDL mvn_swia_get_spectrum.pro 中该系数是否为仪器几何因子或单位换算？
    # 状态：不改值，仅留此处待人类复核（03 §15 C11）。
    Const = sqrt(mass/(2.0*constants.erg_per_eV)) * 8.8
    density = Const*sum(denergy.*(energy.^(-1.5)).*flux,dims=2)[:,1]
    return density
end
end