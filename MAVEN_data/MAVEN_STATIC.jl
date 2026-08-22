# 处理MAVEN的STATIC数据
# STATIC中的theta值在球坐标系下,应当为90-Theta.
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_STATIC
using TimesDates, Dates
using Statistics
using CommonDataFormat

# -------------------------Export parts-------------------------
# export static_c6_mass_mean,static_c6_energy_mean
# export static_rotation,static_slip,static_slip_2_V,sta_v_4d
# export ion_energy2v,ion_v2energy


ion_mass_range = Dict{String,Any}( # 由于STATIC仪器本身的分辨问题，仪器组建议以以下质量范围为离子的参考，m_int为比荷
    "H+" => (
        mass = 1,
        m_int = 1,
        mass_range = [0,1.55],
    ),
    "He2+" => ( # 同H2+
        mass = 4,
        m_int = 2,
        mass_range = [1.55,2.7],
    ),
    "H2+" => ( # 同H2+
        mass = 2,
        m_int = 2,
        mass_range = [1.55,2.7],
    ),
    "O+" => (
        mass = 16,
        m_int = 16,
        mass_range = [14,20],
    ),
    "O2+" => (
        mass = 32,
        m_int = 16,
        mass_range = [24,40],
    ),
    "CO2+" => (
        mass = 44,
        m_int = 22,
        mass_range = [40,60],
    )
)

function static_c6_mass_mean(data;mass_range=[0,200])  # static 3d数据处理(不包括角度信息)
    # energy_spec为在mass维度做求和,得到eflux,energy谱
    # 默认计算所有的mass_range,设置mass_range后会计算对应范围的值
    # mass_range单位AMU
    #:time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    local epoch   = data[:epoch]
    local energy  = data[:energy]
    local denergy = data[:denergy]
    local eflux   = data[:eflux]
    local swp_ind = data[:swp_ind]
    local apid    = data[:apid]
    local mass_arr = data[:mass_arr]
    local ntime    = data[:num_dists]
    local nmass    = data[:nmass]
    local nswp    = data[:nswp]
    local nenergy = data[:nenergy]

    local eflux_mass   = zeros(ntime,nenergy)
    local energy_mass  = zeros(nenergy,nswp)
    
    local mask = (mass_arr .>= mass_range[1]) .& (mass_arr .<= mass_range[2])
    local energy_mass[:,:] = sum(energy.* denergy .* mask , dims=1)  ./ sum(denergy.* mask, dims=1)

    local mapped_mass_arr = zeros(ntime,nmass,nenergy)
    @inbounds for i in 1:ntime
        mapped_mass_arr[i,:,:] = mass_arr[:,:,swp_ind[i]+1]
    end

    mask = (mapped_mass_arr .>= mass_range[1]) .& (mapped_mass_arr .<= mass_range[2])
    eflux_mass[:,:]=sum(eflux.*mask,dims=2)
    # end

    if :df in keys(data)
        local df = data[:df]
        local df_mass    = zeros(ntime,nenergy)
        local df_mass[:,:] = sum(df.*mask,dims=2)
        return_data = Dict{Symbol,Any}(
           :apid          => apid,
           :epoch         => epoch,
           :energy        => energy_mass,
           :eflux         => eflux_mass,
           :df            => df_mass,
           :swp_ind       => swp_ind,
           :data_load_flag=> true
        )
    else
        return_data = Dict{Symbol,Any}(
           :apid          => apid,
           :epoch         => epoch,
           :energy        => energy_mass,
           :eflux         => eflux_mass,
           :swp_ind       => swp_ind,
           :data_load_flag=> true
        )
    end
    return return_data
end
function static_c6_energy_mean(data;energy_range=[0,1e6])  # static 3d数据处理(不包括角度信息)
    # 在energy维度做求和,得到eflux,mass谱
    # energy_range单位energy,不设置时默认计算所有energy的值
    #:time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    local epoch   = data[:epoch]
    local energy  = data[:energy]
    local eflux   = data[:eflux]
    local swp_ind = data[:swp_ind]
    local apid    = data[:apid]
    local mass_arr = data[:mass_arr]
    local ntime    = data[:num_dists]
    local nmass    = data[:nmass]
    local nswp    = data[:nswp]
    local nenergy = data[:nenergy]

    local eflux_out   = zeros(ntime,nmass)
    local mass_out    = zeros(nmass,nswp)

    local mask = (energy .>= energy_range[1]) .& (energy .<= energy_range[2])
    local mass_out[:,:] = mean(mass_arr.*mask, dims=2)

    local mapped_energy = zeros(ntime,nmass,nenergy)
    @inbounds for i in 1:ntime
        mapped_energy[i,:,:] = energy[:,:,swp_ind[i]+1]
    end

    local mask = (mapped_energy .>= energy_range[1]) .& (mapped_energy .<= energy_range[2])
    local eflux_out[:,:]=sum(eflux.*mask,dims=3)

    if :df in keys(data)
        local df = data[:df]
        local df_out    = zeros(ntime,nmass)
        df_out[:,:] = sum(df.*mask,dims=3)
        return_data = Dict{Symbol,Any}(
           :apid          => apid,
           :epoch         => epoch,
           :mass          => mass_out,
           :eflux         => eflux_out,
           :df            => df_out,
           :swp_ind       => swp_ind,
           :data_load_flag=> true
        )
    else
        return_data = Dict{Symbol,Any}(
           :apid          => apid,
           :epoch         => epoch,
           :mass          => mass_out,
           :eflux         => eflux_out,
           :swp_ind       => swp_ind,
           :data_load_flag=> true
        )
    end
    return return_data
end
# UNITS计算  
# STA_ 系列的单位转换代码源于SPEDAS的"projects\maven\sta\mvn_sta_functions\mvn_sta_convert_units.pro", 其默认输出单位并非IS单位, 此程序中的速度等计算无特殊声明则默认使用以下单位制:
#  'COUNTS' :  units = '#/sample'                        ;counts in a sample
#   'RATE'   :  units = '#/s'                             ;count rate
#   'CRATE'  :  units = '#/sec, corrected for dead time'  ;dead-time corrected rate
#   'EFLUX'  :  units = 'eV/cm^2-sec-sr-eV'               ;energy flux in angular bin
#   'E2FLUX' :  units = 'eV^2/cm^2-sec-sr-eV'             ;energy^2 flux in angular bin
#   'E3FLUX' :  units = 'eV^3/cm^2-sec-sr-eV'             ;energy^3 flux in angular bin
#   'FLUX'   :  units = '#/cm^2-sec-sr-eV'                ;particle flux in angular bin
#   'DF'     :  units = '1/(cm^3-(km/s)^3)'               ;particle distribution function in 6 dimensional (3 spatial, 3 velocity) phase space; note that MMS uses 1/(km^6/cm^3)

# 使用一个变量记录(ntime,nbin,nenergy,nmass)的数据,计算时根据情况将数据转为对应4D数据
function STA_count2df(dat) #计算df,需要导入static_slip取得的切片
    local nbins   = dat[:nbins]::Int16
    local nenergy = dat[:nenergy]::Int16
    local energy = dat[:energy]

    local gf = reshape(dat[:gf], 1, nbins,nenergy)
    local eff = dat[:eff]
    local geom = dat[:geom_factor]
    # local G = dat[:geom_factor].*eff.*gf
    local dt = dat[:time_integ]
    local mass = dat[:mass]
    local mass_arr = dat[:mass_arr]
    local dead = dat[:dead]						# dead time array usec for STATIC
    local bkg = dat[:bkg]					# background array usec for STATIC
    local tmp = dat[:data]

    local const_part = (mass * mass) / (dt * 2.0 * 1e5)

    local df_t = @. (tmp - bkg) * dead * const_part / (geom * eff * gf * energy^2)
    
    dat[:df_mass_mass] = df_t
    dat[:df] = @. df_t * mass_arr^2

    # local tmp = (tmp .- bkg ).*dead
    # local scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    # local df_t = scale .* tmp
    # dat[:df] = df_t .*mass_arr.^2
    # dat[:df_mass_mass] = df_t # 没有乘以质量的平方
    return dat
end
function STA_count2df_all(dat0) #计算df,对非时间切片数据，此处程序开销极大，考虑替换掉
    local dat = deepcopy(dat0)
    local ntime   = dat[:num_dists]

    local nmass   = dat[:nmass]
    local nbins   = dat[:nbins]
    local nenergy = dat[:nenergy]
    local energy  = dat[:energy]
    local dims4 = (ntime,nmass,nbins,nenergy) 
    if nbins == 1
        local gf     = zeros(ntime,1,nenergy)
        local eff    = zeros(ntime,nmass,nenergy)
        local mass   = zeros(ntime,nmass,nenergy)
        local energy = zeros(ntime,nmass,nenergy)
        local dt   = reshape(dat[:time_integ],ntime, 1,  1)
    
        local dead = dat[:dead]
        local bkg = dat[:bkg]
        local tmp = dat[:data]
    
        @inbounds for i in 1:ntime
            local swp_ind = dat[:swp_ind][i]
            local att_ind = dat[:att_ind][i]
            local eff_ind = dat[:eff_ind][i]
            gf[i,:,:]   = dat[:gf][att_ind+1,:,swp_ind+1]
            eff[i,:,:]  = dat[:eff][:,:,eff_ind+1]
            mass[i,:,:] = dat[:mass].*dat[:mass_arr][:,:,swp_ind+1]
            energy[i,:,:] = dat[:energy][:,:,swp_ind+1]
        end
    else
        local gf     = zeros(ntime,1,nbins,nenergy)
        local eff    = zeros(ntime,nmass,nbins,nenergy)
        local mass   = zeros(ntime,nmass,nbins,nenergy)
        local energy = zeros(ntime,nmass,nbins,nenergy)
        local dt   = reshape(dat[:time_integ],ntime, 1, 1, 1)

        local dead = dat[:dead]
        local bkg = dat[:bkg]
        local tmp = dat[:data]

        @inbounds for i in 1:ntime
            local swp_ind = dat[:swp_ind][i]
            local att_ind = dat[:att_ind][i]
            local eff_ind = dat[:eff_ind][i]
            gf[i,:,:,:]   = dat[:gf][att_ind+1,:,:,swp_ind+1]
            eff[i,:,:,:]  = dat[:eff][:,:,:,eff_ind+1]
            mass[i,:,:,:] = dat[:mass].*dat[:mass_arr][:,:,:,swp_ind+1]
            energy[i,:,:,:] = dat[:energy][:,:,:,swp_ind+1]
        end
    end

    local G = dat[:geom_factor].*eff.*gf

    local tmp = (tmp .- bkg ).*dead
    # scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    local scale = 1 ./(dt.* G .* energy.^2 .* 2 .*1e5)
    dat[:df] = scale .* tmp .* mass.^2
    dat[:df_mass_mass] = scale .* tmp .* dat[:mass]^2
    return dat
end
function STA_count2eflux_all(dat) #计算df,对非时间切片数据
    local ntime   = dat[:num_dists]

    local nmass   = dat[:nmass]
    local nbins   = dat[:nbins]
    local nenergy = dat[:nenergy]
    local natt = dat[:natt]
    local nswp = dat[:nswp]
    local neff = dat[:neff]
    # dims4 = (ntime,nmass,nbins,nenergy) 

    local gf     = zeros(ntime,1,nbins,nenergy)
    local eff    = zeros(ntime,nmass,nbins,nenergy)
    local dt   = reshape(dat[:time_integ],ntime, 1, 1, 1)

    local dead = reshape(dat[:dead],ntime,nmass,nbins,nenergy)
    local bkg  = reshape(dat[:bkg],ntime,nmass,nbins,nenergy)
    local tmp  = reshape(dat[:data],ntime,nmass,nbins,nenergy)

    local gf0  = reshape(dat[:gf], natt,1,nbins,nenergy,nswp)
    local eff0 = reshape(dat[:eff], nmass,nbins,nenergy,neff)
    @inbounds for i in 1:ntime
        local swp_ind = dat[:swp_ind][i]
        local att_ind = dat[:att_ind][i]
        local eff_ind = dat[:eff_ind][i]
        gf[i,:,:,:]   = gf0[att_ind+1,:,:,:,swp_ind+1]
        eff[i,:,:,:]  = eff0[:,:,:,eff_ind+1]
    end

    local G = dat[:geom_factor].*eff.*gf

    local tmp = (tmp .- bkg ).*dead
    local scale = 1 ./(dt.* G)
    dat[:eflux_from_count] = scale .* tmp
    return dat
end
function STA_count2eflux(dat;m_int=m_int)
    local nbins   = dat[:nbins]
    local nenergy = dat[:nenergy]
    # energy = dat[:energy]   				# in eV     (n_e,nbins,n_m)
    local gf = reshape(dat[:gf], 1, nbins,nenergy)
    local eff = dat[:eff]
    local G = dat[:geom_factor].*eff.*gf
    local dt = dat[:time_integ]
    # mass = dat[:mass].*m_int
    local dead = dat[:dead]						# dead time array usec for STATIC
    local bkg = dat[:bkg]						# background array usec for STATIC
    local tmp = dat[:data]

    local tmp = (tmp .- bkg ).*dead
    local scale = 1 ./(dt.* G)
    dat[:eflux] = scale .* tmp
    return dat
end
function STA_eflux2df(dat;m_int=m_int)
    local energy = dat[:energy]
    local mass = dat[:mass].*m_int
    local scale = 1 ./(energy.^2 .* 2 ./mass./mass.*1e5)
    dat[:df] = scale .* dat[:eflux]
    return dat
end
#数据切片
function static_slip(dat,time_ind) #取得static在指定时刻的切片,time_ind 为对应时刻的坐标; 平滑的时间会有插值的问题,所以不考虑
    local dat_slip =Dict{Symbol,Any}()
    for key in keys(dat)
        dat_slip[key] = dat[key]
    end
    local swp_ind = dat[:swp_ind][time_ind]+1
    local att_ind = dat[:att_ind][time_ind]+1
    local eff_ind = dat[:eff_ind][time_ind]+1

    dat_slip[:epoch]        = dat[:epoch][time_ind]
    dat_slip[:eflux]        = @views dat[:eflux][time_ind,:,:,:]
    dat_slip[:data]         = @views dat[:data][time_ind,:,:,:]
    dat_slip[:bkg]          = @views dat[:bkg][time_ind,:,:,:]
    dat_slip[:epoch]        = dat[:epoch][time_ind]
    dat_slip[:time_integ]   = dat[:time_integ][time_ind]
    dat_slip[:swp_ind]      = dat[:swp_ind][time_ind]
    dat_slip[:att_ind]      = dat[:att_ind][time_ind]
    dat_slip[:eff_ind]      = dat[:eff_ind][time_ind]
    dat_slip[:sc_pot]       = dat[:sc_pot][time_ind]
    dat_slip[:quality_flag] = dat[:quality_flag][time_ind]
    dat_slip[:dead]         = @views dat[:dead][time_ind,:,:,:]
    dat_slip[:mode]         = dat[:mode][time_ind]
    dat_slip[:bins_sc]      = @views dat[:bins_sc][time_ind,:] # 重要: 此为飞行器遮挡视野的数组, 当一个角度中超过一半的部分被遮挡, 此数组出现.
    dat_slip[:quat_mso]     = @views dat[:quat_mso][time_ind,:]
    dat_slip[:quat_sc]      = @views dat[:quat_sc][time_ind,:]
    dat_slip[:magf]         = @views dat[:magf][time_ind,:]
    dat_slip[:pos_sc_mso]   = @views dat[:pos_sc_mso][time_ind,:]
    
    dat_slip[:energy]   = @views dat[:energy][:,:,:,swp_ind]
    dat_slip[:denergy]  = @views dat[:denergy][:,:,:,swp_ind]
    dat_slip[:theta]    = @views dat[:theta][:,:,:,swp_ind]
    dat_slip[:phi]      = @views dat[:phi][:,:,:,swp_ind]
    dat_slip[:dtheta]   = @views dat[:dtheta][:,:,:,swp_ind]
    dat_slip[:dphi]     = @views dat[:dphi][:,:,:,swp_ind]
    dat_slip[:mass_arr] = @views dat[:mass_arr][:,:,:,swp_ind]
    dat_slip[:gf]       = @views dat[:gf][att_ind,:,:,swp_ind]
    dat_slip[:eff]      = @views dat[:eff][:,:,:,eff_ind]

    if haskey(dat, :df_mass_mass)
        dat_slip[:df_mass_mass] = dat[:df_mass_mass][time_ind,:,:,:]
    end
    if haskey(dat, :df)
        dat_slip[:df] = dat[:df][time_ind,:,:,:]
    end
    # # time:			tt1,					
    # # end_time:		tt2,					
    # delta_t = dat[:endtime][time_ind] - dat[:time_unix][time_ind]		
    # dt_cor = 3.89/4.0
    # dat_slip[:integ_t]=delta_t/(dat[:nenergy]*dat[:ndef])*dt_cor

    return dat_slip
end
# 速度计算
function sta_v_4d(dat;energy_range=[0,1e5],mass_range=[10,20],m_int = 16,unit ="eflux", unit_cover=true)#计算离子速度,流速，密度，需要导入static_slip取得的切片,单位km/s,cm^-3
    if dat[:valid] == 0
        println("Invalid Data")
        return [NaN,NaN,NaN],[NaN,NaN,NaN],NaN
    end
    # Use distribution function
    # if unit !=:df
    #     if unit ==:eflux"
    #         dat = STA_eflux2df(dat;m_int=m_int)
    #     elseif unit ==:counts"
    #         dat = STA_count2df(dat;m_int=m_int)
    #     end
    # end
    if unit_cover
        dat = STA_count2df(dat)
        data0 = dat[:df] #取得相空间密度
    else
        data0=dat[:df_mass_mass] .*m_int^2  #取得相空间密度
    end
    
    local denergy = dat[:denergy]
    local theta = dat[:theta].*inv_RADG
    local phi = dat[:phi] .*inv_RADG
    local dtheta = dat[:dtheta] .*inv_RADG
    local dphi = dat[:dphi] .*inv_RADG
    local mass_arr = dat[:mass_arr]
    local pot = dat[:sc_pot]

    local mass=dat[:mass]*m_int
    
    local Const = 2.0/mass/mass*1e5
    local energy=copy(dat[:energy]) .+ pot		# energy/charge analyzer, require positive energy
    local energy[energy .< 0.0] .=0.0

    local masked_data = data0.*(mass_range[1] .<= mass_arr .<= mass_range[2] .&& energy_range[1] .<= energy .<= energy_range[2])

    local flux0 = Const.*denergy.*energy.*masked_data
    local theta0 = (dtheta./2.0.+cos.(2.0.*theta).*sin.(dtheta)./2.0).*2.0.*sin.(dphi./2.0)
    local flux3dx = sum(flux0.*theta0.*cos.(phi))
    local flux3dy = sum(flux0.*theta0.*sin.(phi))
    local flux3dz = sum(flux0.*(2.0.*sin.(theta).*cos.(theta).*sin.(dtheta./2.0).*cos.(dtheta./2.0)).*dphi)
    #units are 1/cm^2-s
    local Const = mass^(-1.5)*2.0^(0.5)
    local density = sum(Const.*denergy.*sqrt.(energy).*masked_data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi)
    #units are 1/cm^3
    local flux = [flux3dx,flux3dy,flux3dz]
    local vel = 1e-5 .* flux ./(density .+ 1e-10)
    #units are km/s
    return vel,flux,density
end
function sta_v_4d_new(dat; energy_range=[0,1e5], mass_range=[10,20], m_int=16, unit_cover=true)
    # 1. 快速非法检查
    dat[:valid] == 0 && return [NaN,NaN,NaN],[NaN,NaN,NaN],NaN

    # 2. 提取数据并显式转换类型 (Type Anchoring)
    # 使用 @views 配合类型声明，确保后续索引不产生拷贝且编译器已知类型
    @views begin
        data0    = (unit_cover ? dat[:df] : dat[:df_mass_mass] .* (m_int^2))::AbstractArray{Float64, 3}
        energy   = dat[:energy]::AbstractArray{Float32, 3}
        denergy  = dat[:denergy]::AbstractArray{Float32, 3}
        theta    = dat[:theta]::AbstractArray{Float32, 3}
        phi      = dat[:phi]::AbstractArray{Float32, 3}
        dtheta   = dat[:dtheta]::AbstractArray{Float32, 3}
        dphi     = dat[:dphi]::AbstractArray{Float32, 3}
        mass_arr = dat[:mass_arr]::AbstractArray{Float32, 3}
        pot      = dat[:sc_pot]::Float32
        mass     = (dat[:mass] * m_int)::Float32
    end

    # 3. 预计算常数 (减少循环内除法和乘法)
    const_flux = 2.0 / (mass * mass) * 1e5
    const_den  = (mass^(-1.5)) * (2.0^(0.5))
    inv_RADG   = 1.0 / RADG  # 提前算好 1/RADG

    # 4. 初始化累加器
    density = 0.0
    f3dx = 0.0
    f3dy = 0.0
    f3dz = 0.0

    # 5. 单次循环：这是 Threadripper 最喜欢的“高计算密度”模式
    @inbounds for i in eachindex(data0)
        # 直接读取，避免创建 Mask 数组
        m_val = mass_arr[i]
        e_val = energy[i]
        e_corr = max(0.0, e_val + pot)
        
        # 过滤条件
        if (mass_range[1] <= m_val <= mass_range[2]) && (energy_range[1] <= e_corr <= energy_range[2])
            
            # --- 物理计算部分 ---
            
            t_val  = theta[i] * inv_RADG
            p_val  = phi[i] * inv_RADG
            dt_val = dtheta[i] * inv_RADG
            dp_val = dphi[i] * inv_RADG
            
            # 公共中间项：data * denergy * dphi
            # 提取公共项可以减少 CPU 乘法指令次数
            common_term = data0[i] * denergy[i] * dp_val
            
            # 密度累加 (Density contribution)
            # 公式: Const * denergy * sqrt(energy) * data * 2.0 * cos(theta) * sin(dtheta/2.0) * dphi
            density += const_den * sqrt(e_corr) * common_term * 2.0 * cos(t_val) * sin(dt_val / 2.0)
            
            # 通量公共项 (Flux contribution)
            # 公式: Const * denergy * energy * data * theta0
            # theta0 = (dtheta/2.0 + cos(2.0*theta)*sin(dtheta)/2.0) * 2.0*sin(dphi/2.0)
            theta0 = (dt_val / 2.0 + cos(2.0 * t_val) * sin(dt_val) / 2.0) * 2.0 * sin(dp_val / 2.0)
            flux_val = const_flux * e_corr * data0[i] * denergy[i] * theta0
            
            f3dx += flux_val * cos(p_val)
            f3dy += flux_val * sin(p_val)
            f3dz += const_flux * e_corr * common_term * (2.0 * sin(t_val) * cos(t_val) * sin(dt_val / 2.0) * cos(dt_val / 2.0))
        end
    end

    # 6. 计算最终速度
    flux = [f3dx, f3dy, f3dz]
    vel  = 1e-5 .* flux ./ (density + 1e-10)

    return vel, flux, density
end
function sta_n_4d(dat;energy_range=[0,1e5],mass_range=[10,20],m_int = 16,unit_cover =false)#计算离子速度,流速，密度，需要导入static_slip取得的切片,单位cm^-3
    if dat[:valid] == 0
        println("Invalid Data")
        return NaN
    end

    if unit_cover
        dat = STA_count2df(dat)
        data0 = dat[:df] #取得相空间密度
    else
        data0=dat[:df_mass_mass] .*m_int^2  #取得相空间密度
    end

    local denergy = dat[:denergy] 
    local theta = dat[:theta].*inv_RADG
    # local phi = dat[:phi] .*inv_RADG
    local dtheta = dat[:dtheta] .*inv_RADG
    local dphi = dat[:dphi] .*inv_RADG
    local mass_arr = dat[:mass_arr]
    local pot = dat[:sc_pot]

    
    
    local mass=dat[:mass]*m_int
    
    local energy=copy(dat[:energy]) .+ pot		# energy/charge analyzer, require positive energy
    local energy[energy .< 0.0] .=0.0

    local mask1 =  energy_range[1] .<= energy .<= energy_range[2]
    local mask2 =  mass_range[1] .<= mass_arr .<= mass_range[2]
    local mask = mask1 .& mask2
    local masked_data = data0.*mask

    local Const = mass^(-1.5)*2.0^(0.5)
    local density = sum(Const.*denergy.*sqrt.(energy).*masked_data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi)
    #units are 1/cm^3
    return density
end
function static_rotation(dat;frame="MSO") #将STATIC数据在某时刻的切片旋转到对应坐标系,仅限3D数据(mass,bins,energy)，需要STA_slip产生的切片
    function sphere2xyz_for_static_rotation(θ,ϕ)
        x = cosd(θ) *  cosd(ϕ)
        y = cosd(θ) *  sind(ϕ)
        z = sind(θ)
        return [x,y,z]
    end;
    function xyz2sphere_for_static_rotation(xyz)
        x,y,z=xyz[1],xyz[2],xyz[3]
        z = clamp(z, -1, 1) # avoid numerical error
        theta = 90. - acosd(z)
        phi = atand(y, x)
        return theta,phi
    end
    local dat2
    dat2 = dat
    theta = dat2[:theta]
    phi = dat2[:phi]
    magf = dat2[:magf]
    n_m = dat2[:nmass]
    n_b = dat2[:nbins]
    n_e = dat2[:nenergy]
    if frame == "MSO"
        frame_t = :quat_mso
    elseif frame == "SC"
        frame_t = :quat_sc
    end

    # quat = QuaternionF64(dat2[frame_t][1],dat2[frame_t][2],dat2[frame_t][3],dat2[frame_t][4]) # 弃用此方法
    quat = QuatRotation(dat2[frame_t])

    xyz = sphere2xyz_for_static_rotation.(theta,phi);
    xyz_mso = quat * xyz
    sphere_mso = xyz2sphere_for_static_rotation.(xyz_mso)

    thetaT=zeros(n_m,n_b,n_e)
    phiT=zeros(n_m,n_b,n_e)

    for (i,var) in enumerate(sphere_mso)
        phiT[i] = var[2]
        thetaT[i] = var[1]
    end
    magfT = quat * magf
    dat2[:theta] = thetaT
    dat2[:phi] = phiT
    dat2[:magf] = magfT
    return dat2
end
function static_slip_2_V(dat;mass_range=[10,20],m_int = 16,vsc=[0,0,0]) #use slip_data
    local nenergy  = dat[:nenergy]
    local nbins    = dat[:nbins]
    local energy   = dat[:energy]      
    local phi      = dat[:phi]        
    local theta    = dat[:theta]         
    local mass_arr = dat[:mass_arr]   
    local sc_pot   = dat[:sc_pot]     

    # dat = STA_count2df(dat;m_int=m_int)
    # dat = STA_eflux2df(dat;m_int=m_int)
    local df_data = dat[:df]
    local ef_data = dat[:eflux]

    local mask = (mass_arr .>= mass_range[1]) .& (mass_arr .<= mass_range[2])
    local energy_mass = energy[1,:,:]
    local phi_mass = phi[1,:,:]
    local theta_mass = theta[1,:,:]

    local df_data1 = sum(df_data.*mask,dims=1)[1,:,:]
    local ef_data1 = sum(ef_data.*mask,dims=1)[1,:,:]
    
    local V_ = zeros(nbins,nenergy,3)
    
    local energy_t = energy_mass .+ sc_pot
    energy_t[energy_t .<= 0] .= 0.001
    
    local v0 = ion_energy2v.(energy_t,m_int) ./1e3
    
    local APP_position = sphere2xyz_for_STATIC.(v0,theta_mass,phi_mass)
    
    V_[:,:,1] = [x[1] for x in APP_position]
    V_[:,:,2] = [x[2] for x in APP_position]
    V_[:,:,3] = [x[3] for x in APP_position]

    local vsc1 = reshape(vsc,1,1,3)

    V_ =V_ .+ vsc1
    
    local return_data = Dict{Symbol,Any}(
        :df=> df_data1,
        :eflux=> ef_data1,
        :v => V_,
        :mass=> m_int,
        :nbins=>nbins,
        :energy=>energy_t,
        :nenergy=>nenergy,
        :magf => dat[:magf],
    )
    return return_data
end

#-----------------基于c6数据包的3d(time,energy,mass)计算
function STA_count3df(dat) #计算c6数据的df,必须有时间轴
    ntime = dat[:num_dists]
    nenergy = dat[:nenergy]
    nmass = dat[:nmass]

    swp_indices = dat[:swp_ind] .+ 1
    att_indices = dat[:att_ind] .+ 1
    eff_indices = dat[:eff_ind] .+ 1

    function expand_3d(src_key)
        src = dat[src_key]
        res = src[:, :, swp_indices]
        return permutedims(res, (3, 1, 2)) # 变为 (ntime, nmass, nenergy)
    end

    dat[:energy3d]   = expand_3d(:energy)
    dat[:denergy3d]  = expand_3d(:denergy)
    dat[:mass_arr3d] = expand_3d(:mass_arr)
    dat[:phi3d]      = expand_3d(:phi)
    dat[:dphi3d]     = expand_3d(:dphi)
    dat[:theta3d]    = expand_3d(:theta)
    dat[:dtheta3d]   = expand_3d(:dtheta)

    dat[:eff3d] = dat[:eff][:, :, eff_indices] |> p -> permutedims(p, (3, 1, 2))

    # gf 需要三轴索引映射，逻辑稍复杂，保持循环但优化性能
    gf_3d = zeros(eltype(dat[:gf]), ntime, 1, nenergy)
    for i in 1:ntime
        @views gf_3d[i, 1, :] .= dat[:gf][att_indices[i], :, swp_indices[i]]
    end
    dat[:gf3d] = gf_3d

    G    = dat[:geom_factor].*dat[:eff3d].*dat[:gf3d]
    dt   = dat[:time_integ]
    dead = dat[:dead]						# dead time array usec for STATIC
    bkg = dat[:bkg]					# background array usec for STATIC
    tmp = dat[:data]

    scale = dat[:mass]^2*5e-6
    dat[:df_mass_mass] = @.scale *(tmp - bkg) * dead / (dt * G * dat[:energy3d]^2)# 没有乘以质量数的平方
    dat[:df] = @. dat[:df_mass_mass] *dat[:mass_arr3d]^2

    return dat
end
function sta_v_1d(dat;energy_range=[0,1e5],mass_range=[10,20],m_int = 16)#使用c6数据计算一维离子速度,流速，密度，需要导入STA_count3df取得的相空间密度,单位km/s,cm^-3 time_ind暂时无效，计算全域数据
    # local dat= deepcopy(dat0)
    local ntime = dat[:num_dists]
    
    local data0=dat[:df_mass_mass] .*m_int^2
    local denergy = dat[:denergy3d]
    local theta = dat[:theta3d].*inv_RADG
    # local phi = dat[:phi3d] .*inv_RADG
    local dtheta = dat[:dtheta3d] .*inv_RADG
    local dphi = dat[:dphi3d] .*inv_RADG
    local mass_arr = dat[:mass_arr3d]
    local pot = reshape(dat[:sc_pot],ntime,1,1)
    
    local mass=dat[:mass]*m_int
    
    local Const = 2.0/mass/mass*1e5
    local energy=copy(dat[:energy3d]) .+ pot		# energy/charge analyzer, require positive energy
    local energy[energy .< 0.0] .=0.0

    local mask1 =  energy_range[1] .<= energy .<= energy_range[2]
    local mask2 =  mass_range[1] .<= mass_arr .<= mass_range[2]
    local masked_data = data0.*(mask1 .& mask2)

    local flux0 = Const.*denergy.*energy.*masked_data .*4π # 4PI为去除全向
    local flux =  sum(flux0;dims=2:3)[:,1,1] # units are 1/cm^2-s

    local Const = mass^(-1.5)*2.0^(0.5)
    local density = sum(Const.*denergy.*sqrt.(energy).*masked_data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi;dims=2:3)[:,1,1]
    local vel = 1e-5 .* flux ./(density .+ 1e-10)

    local valid  = dat[:valid] .== 0
    local vel[valid] .= NaN
    local flux[valid] .= NaN
    local density[valid] .= NaN

    return vel,flux,density
end
function get_quality_flag(x)
    #取得二进制的质量标志，Int转二进制
    # flags = [i == '1' for i in string(x, base=2)] |> reverse
    flags = Vector{Bool}(undef, 16)
    for i in 0:15
        # (x >> i) & 1 取出第 i 位的值（0 或 1）
        # 然后检查是否等于 1 转换为布尔值
        flags[i+1] = ( (x >> i) & 1 ) == 1
    end
    return flags
end
function compare_quality(flag::Integer;bad_flags=[5,6,7,8])
    #比较质量标志是否包含某个标志
    # qf = [
    #     "test pulser on", 
    #     "diagnostic mode", 
    #     "dead time correction >2 flag", 
    #     "detector droop correction >2 flag", 
    #     "dead time correction not at event time",
    #     "electrostatic attenuator problem", 
    #     "attenuator change during accumulation",
    #     "mode change during accumulation", 
    #     "LPW interference with data", 
    #     "high background", 
    #     "no background subtraction array", 
    #     "missing spacecraft potential", 
    #     "inflight calibration incomplete", 
    #     "geometric factor problem" ,
    #     "ion suppression problem" ,
    #     "0",
    # ]
    #     ;		bit 0	test pulser on					- testpulser header bit set
    # ;			bit 1	diagnostic mode					- diagnostic header bit set
    # ;			bit 2	dead time correction >2 flag			- deadtime correction > 2
    # ;			bit 3	detector droop correction >2 flag 		- mcp droop flagged if correction > 2
    # ;			bit 4	dead time correction not at event time		- missing data quantity for deadtime
    # ;			bit 5	electrostatic attenuator failing at low energy	- attE on and eprom_ver<2
    # ;			bit 6   attenuator change during accumulation		- att 1->2 or 2->1 transition (one measurement)	
    # ;			bit 7	mode change during accumulation			- only needed for packets that average data during mode transition
    # ;			bit 8	lpw sweeps interfering with data 		- lpw mode not dust mode
    # ;			bit 9	high background 		 		- minimum value in DA > 10000 Hz
    # ;			bit 10	no background subtraction array		 	- dat.bkg = 0		- may not be needed
    # ;			bit 11	missing spacecraft potential			- dat.sc_pot = 0	- may not be needed	
    # ;			bit 12	inflight calibration incomplete			- date determined, set to 1 until calibration finalized
    # ;			bit 13	geometric factor problem			- 
    # ;			bit 14	ion suppression problem				- low energy ions <6eV have wrong geometric factor
    # ;			bit 15	not used =0
    # ax4.yticks = (0:15,qf)
    # 构造掩码：将我们关心的位全部置为 1
    # 例如：(1 << 5) 表示第 5 位为 1，其余为 0
    mask = sum(1 << b for b in bad_flags)
    # 按位与运算：检查 flag 中对应的位是否有任何一个是 1
    return (flag & mask) != 0
end
function rotate_vector_with_Matrix(in_data,Rotation_Matrix) # inv
    out_data = Rotation_Matrix * in_data
    return out_data
end
function ion_eflux2F(energy,eflux;m_int=1)  # 离子eflux转PSD, 使用IS单位制, 与STA方法差了1e3倍
    # M = m_int * Mp
    # E0 = 511.0 * m_int * 1836.23 # 离子静止能量
    # #energy 与 eflux 一一对应
    # γ=(energy * 1e-3 /E0 + 1)
    # β=sqrt(1.0 - 1.0 / γ^2)
    # P=γ *M * β *C        # kg m/s
    # # V=β .* C
    # F = (γ*M)^3 * eflux/energy *1e4 /EV / P^2 

    # M = m_int * Mp
    # V2 = energy * EV / M *2  # m/s
    # F = 2* eflux / V2^2*1e4

    local E0 = 511.0 * m_int * 1836.23
    local γ =(energy * 1e-3 /E0 + 1)
    local β =sqrt(1.0 - 1.0 / γ^2)
    local V = β * C
    # F = 2 * eflux *1e4 / V^4
    return 2 * eflux *1e4 / V^4
end
function sphere2xyz_for_STATIC(r,θ,ϕ) #spedas_6_1\general\science\sphere_to_cart.pro
    local ct = cosd(θ)
    local x = r * ct *  cosd(ϕ)
    local y = r * ct *  sind(ϕ)
    local z = r * sind(θ)
    return [x,y,z]
end;
function xyz2sphere_for_STATIC(x,y,z)
    local r=sqrt(x^2 + y^2 + z^2)
    local theta = 90.0 - acosd(z/r)
    local phi = atand(y, x)
    return [r,theta,phi]
end
function sphere2xyz(r,θ,ϕ)
    local x = r * sind(θ) *  cosd(ϕ)
    local y = r * sind(θ) *  sind(ϕ)
    local z = r * cosd(θ)
    return [x,y,z]
end
function ion_energy2v(energy,AMU) # 离子子能量对应速度(相对论),输入eV, IS单位制
    local E0 = 938313.53 * AMU  # 质子静止能量 MeV
    local γ= energy*1e-3/E0 + 1.0
    local β=sqrt(1.0 - 1.0 / γ^2)
    # v = β * 3e8
    return β * 3e8
end
function ion_v2energy(v,AMU) # 离子子能量对应速度(相对论) v:速度, IS单位制,返回eV
    local E0 = 938313.53 * AMU
    local β  = v / 3e8
    local γ = 1.0 / sqrt(1.0 - β^2)
    # energy = (γ - 1.0) * E0 * 1e3
    return (γ - 1.0) * E0 * 1e3
end
# function ion_v2energy(v,mass) # 离子子能量对应速度(相对论)
#     E0 = 511.0 * mass * 1836.23
#     β = v / 3e8
#     γ = 1.0 / sqrt(1.0 - β^2)
#     energy = (γ - 1.0) * E0 * 1e3
#     return energy
# end
const EV=1.602176487e-19
const C=3.0e8
const Me=9.109e-31
const Mp=1.672621637e-27
const RADG=180.0/π
const inv_RADG=π/180.0

# vv0 =9.8e3
# ee = ion_v2energy(vv0 ,32)
# vv = ion_energy2v(ee,32)
# println(vv0," ",vv," ",ee)
# vv0^2 * 0.5*32*Mp/EV
end # module

# # # # -------------------------Test parts-------------------------

# using Test, Statistics, BenchmarkTools
# include("MAVEN_load.jl");import .MAVEN_load;
# include("MAVEN_plot.jl");import .MAVEN_plot;
# import .MAVEN_STATIC;
# using Dates
# using GLMakie
# using LinearAlgebra
# GLMakie.activate!()
# kp_vars_dict = Dict(
#     :B_SS_x => 128,
#     :B_SS_y => 130,
#     :B_SS_z => 132,
#     :MSO_x => 190,
#     :MSO_y => 191,
#     :MSO_z => 192,
#     :Orbit_Number => 210,
#     :O2_den => 58,
#     :O_den => 56,
#     :H_den => 54,
#     :O2_f => 87,
#     :O_f => 84,
#     :H_f => 78,
#     )
# # datas_dict = MAVEN_load.data_get_from_date(DateTime(2015,10,29); model_index=["STATIC_c6","KP_l3","STATIC_d1"])
# # --- 执行验证 ---

# time_range = [DateTime(2015,10,29,11,20),DateTime(2015,10,29,11,40)]
# # time_i_kp = findall(x->x>=time_range[1] && x<=time_range[2],kp_data[:time])
# # time_i_sta = findall(x->x>=time_range[1] && x<=time_range[2],sta_data[:epoch])
# # time_i_d1 = findall(x->x>=time_range[1] && x<=time_range[2],d1_data[:epoch])

# sta_data = deepcopy(datas_dict["STATIC_c6"])
# d1_data = deepcopy(datas_dict["STATIC_d1"])
# # df_d1_data = MAVEN_STATIC.STA_count2df_all(d1_data)
# @time df_data = MAVEN_STATIC.STA_count3df(sta_data)
# # @time df_data_1 = deepcopy(MAVEN_STATIC.STA_count3df_old(sta_data))
# # kp_data = MAVEN_load.convert_kp_l3(datas_dict["KP_l3"];kp_dict=kp_vars_dict)
# @time Ov,Of,On = MAVEN_STATIC.sta_v_1d(df_data;energy_range=[0,1e8],mass_range=[13,19],m_int = 16)
# @time O2v,O2f,O2n = MAVEN_STATIC.sta_v_1d(df_data;energy_range=[0,1e8],mass_range=[20,40],m_int = 32)
# # # @time Hv,Hf,Hn = MAVEN_STATIC.sta_v_1d(df_data;energy_range=[0,1e8],mass_range=[0.5,1.5],m_int = 1)

# v_d1 = []
# f_d1 = []
# n_d1 = []

# for i in time_i_d1
#     slip_data = MAVEN_STATIC.static_slip(df_d1_data,i)
#     vel,flux,density = MAVEN_STATIC.sta_v_4d(slip_data;energy_range=[0,1e8],mass_range=[10,20],m_int = 16)
#     push!(v_d1,norm(vel))
#     push!(f_d1,norm(flux))
#     push!(n_d1,density)
# end

# # v,f,n = Hv,Hf,Hn
# # f_kp,n_kp = :H_f,:H_den
# v,f,n = Ov,Of,On
# f_kp,n_kp = :O_f,:O_den
# fig = Figure(size = (1800, 1600))
# ax1 = Axis(fig[1, 1],yscale=log10,title="MAVEN STATIC c6 vs d1 vs KP L3 Ion Data Comparison, O+",ylabel="Density (cm^-3)")
# ax2 = Axis(fig[2, 1],yscale=log10,ylabel="Flux (cm^2/s)")
# ax3 = Axis(fig[3, 1],ylabel="Vel (Km/s)")

# lines!(ax1,sta_data[:epoch][time_i_sta], n[time_i_sta], color = :blue,label="sta c6")
# lines!(ax2,sta_data[:epoch][time_i_sta], f[time_i_sta], color = :blue)
# lines!(ax3,sta_data[:epoch][time_i_sta], v[time_i_sta], color = :blue)

# lines!(ax1,df_d1_data[:epoch][time_i_d1], n_d1, color = :green,label="sta d1")
# lines!(ax2,df_d1_data[:epoch][time_i_d1], f_d1, color = :green)
# lines!(ax3,df_d1_data[:epoch][time_i_d1], v_d1.*1.5, color = :green)

# lines!(ax1,kp_data[:time][time_i_kp], kp_data[n_kp][time_i_kp], color = :red,label="kp c6")
# lines!(ax2,kp_data[:time][time_i_kp], kp_data[f_kp][time_i_kp].*4π, color = :red)
# lines!(ax3,kp_data[:time][time_i_kp], kp_data[f_kp][time_i_kp].*4π ./kp_data[n_kp][time_i_kp].*1e-5, color = :red)
# save("MAVEN_data/MAVEN STATIC c6 vs d1 vs KP L3 Ion Data Comparison O+.png",fig)
# fig

# # function find_time(x, x0)
# #     local N = length(x)
# #     # 1. 边界情况处理：如果 x0 小于等于第一个元素
# #     if x0 <= x[1]
# #         return 1
# #     # 2. 边界情况处理：如果 x0 大于等于最后一个元素
# #     elseif x0 >= x[N]
# #         return N
# #     end
# #     # 3. 使用二分查找找到第一个大于或等于 x0 的元素的索引
# #     #    此操作的时间复杂度为 O(log N)
# #     local idx_upper = searchsortedfirst(x, x0)
    
# #     # idx_upper 现在是 x[idx_upper] >= x0 的最小索引
# #     # 因此，我们只需要比较 x[idx_upper] 和 x[idx_upper - 1] 即可
    
# #     local idx_lower = idx_upper - 1
    
# #     # 4. 比较哪个点更接近 x0
# #     if abs(x[idx_upper] - x0) <= abs(x[idx_lower] - x0)
# #         return idx_upper
# #     else
# #         return idx_lower
# #     end
# # end

# # time0 = DateTime(2015,10,29,11,30,15)
# # idx_c6 = find_time(df_data[:epoch], time0)
# # idx_d1 = find_time(df_d1_data[:epoch], time0)

# # d1_slip = MAVEN_STATIC.static_slip(df_d1_data,idx_d1)
# # d1_slip = MAVEN_STATIC.STA_count2df(d1_slip)

# # @show df_data[:epoch][idx_c6], df_d1_data[:epoch][idx_d1]

# # skey = :df
# # @show sum(d1_slip[skey][:,:,:],dims=1:2)[1,1,:] ./ sum(df_data[skey][idx_c6,:,:],dims=1)[1,:]
