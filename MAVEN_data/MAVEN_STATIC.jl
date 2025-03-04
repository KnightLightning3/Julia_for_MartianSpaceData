# 处理MAVEN的STATIC数据
# STATIC中的theta值在球坐标系下,应当为90-Theta.
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_STATIC
using TimesDates, Dates
using Statistics
using Quaternions

# -------------------------Export parts-------------------------
export static_c6_mass_mean,static_c6_energy_mean
export static_rotation,static_slip,static_slip_2_V,sta_v_4d
export ion_energy2v,ion_v2energy
function static_c6_mass_mean(data;mass_range=[0,200])  # static 3d数据处理(不包括角度信息)
    # energy_spec为在mass维度做求和,得到eflux,energy谱
    # 默认计算所有的mass_range,设置mass_range后会计算对应范围的值
    # mass_range单位AMU
    #:time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    epoch   = data[:epoch]
    energy  = data[:energy]
    denergy = data[:denergy]
    eflux   = data[:eflux]
    swp_ind = data[:swp_ind]
    apid    = data[:apid]
    mass_arr = data[:mass_arr]
    ntime    = data[:num_dists]
    nmass    = data[:nmass]
    nswp    = data[:nswp]
    nenergy = data[:nenergy]

    eflux_mass   = zeros(ntime,nenergy)
    energy_mass  = zeros(nenergy,nswp)
    
    mask = (mass_arr .>= mass_range[1]) .& (mass_arr .<= mass_range[2])
    energy_mass[:,:] = sum(energy.* denergy .* mask , dims=1)  ./ sum(denergy.* mask, dims=1)

    mapped_mass_arr = zeros(ntime,nmass,nenergy)
    for i in 1:ntime
        mapped_mass_arr[i,:,:] = mass_arr[:,:,swp_ind[i]+1]
    end

    mask = (mapped_mass_arr .>= mass_range[1]) .& (mapped_mass_arr .<= mass_range[2])
    eflux_mass[:,:]=sum(eflux.*mask,dims=2)
    # end

    if :df in keys(data)
        df = data[:df]
        df_mass    = zeros(ntime,nenergy)
        df_mass[:,:] = sum(df.*mask,dims=2)
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
    epoch   = data[:epoch]
    energy  = data[:energy]
    eflux   = data[:eflux]
    swp_ind = data[:swp_ind]
    apid    = data[:apid]
    mass_arr = data[:mass_arr]
    ntime    = data[:num_dists]
    nmass    = data[:nmass]
    nswp    = data[:nswp]
    nenergy = data[:nenergy]

    eflux_out   = zeros(ntime,nmass)
    mass_out    = zeros(nmass,nswp)

    mask = (energy .>= energy_range[1]) .& (energy .<= energy_range[2])
    mass_out[:,:] = mean(mass_arr.*mask, dims=2)

    mapped_energy = zeros(ntime,nmass,nenergy)
    for i in 1:ntime
        mapped_energy[i,:,:] = energy[:,:,swp_ind[i]+1]
    end

    mask = (mapped_energy .>= energy_range[1]) .& (mapped_energy .<= energy_range[2])
    eflux_out[:,:]=sum(eflux.*mask,dims=3)

    if :df in keys(data)
        df = data[:df]
        df_out    = zeros(ntime,nmass)
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
# 'counts':y_units = 'counts'
# 'eflux':y_units = 'eV/(cm^2-s-sr-eV)'
# 'rate':y_units = '#/sec'
# 'crate':y_units = 'Deadtime Corrected #/sec'
# 'flux':y_units = '#/(cm^2-s-sr-eV)'
# 'df':y_units = '#/(cm^3-(km/sec)^3)'
# 使用一个变量记录(ntime,nbin,nenergy,nmass)的数据,计算时根据情况将数据转为对应4D数据
# function STA_count2eflux_full_time_4d(dat)
#     ntime   = dat[:ntime]
#     nbins   = dat[:nbins]
#     nenergy = dat[:nenergy]
#     nmass   = dat[:nmass]
#     eflux2  = zeros(ntime,nmass,nbins,nenergy)
#     # eflux    = dat[:eflux]
#     dead = dat[:dead]
#     bkg  = dat[:bkg]
#     tmp  = dat[:data]
#     tmp = (tmp .- bkg ).*dead

#     gf1 = zeros(ntime,1,nbins,nenergy)
#     eff1= zeros(ntime,nmass,nbins,nenergy)
#     dt1 = reshape(dat[:time_integ], ntime,1,1,1)
#     for time_ind in 1:ntime
#         swp_ind = dat[:swp_ind][time_ind]
#         att_ind = dat[:att_ind][time_ind]
#         eff_ind = dat[:eff_ind][time_ind]
#         gf   = reshape(dat[:gf][att_ind+1,:,:,swp_ind+1], 1, nbins,nenergy)
#         eff  = dat[:eff][:,:,:,eff_ind+1]
#         gf   = dat[:geom_factor].*eff.*gf
#         dt   = dat[:time_integ][time_ind]

#         scale = 1 ./(dt.* gf)
#         eflux2[time_ind,:,:,:] = scale .* tmp[time_ind,:,:,:]
#     end
#     dat[:eflux] = eflux2
#     return dat
# end
function STA_count2df(dat;m_int=m_int) #计算df,需要导入static_slip取得的切片
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    energy = dat[:energy]

    gf = reshape(dat[:gf], 1, nbins,nenergy)
    eff = dat[:eff]
    G = dat[:geom_factor].*eff.*gf
    dt = dat[:time_integ]
    mass = dat[:mass].*m_int
    dead = dat[:dead]						# dead time array usec for STATIC
    bkg = dat[:bkg]					# background array usec for STATIC
    tmp = dat[:data]

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    dat[:df] = scale .* tmp
    return dat
end
function STA_count2df_no_m_int(dat) #计算df,需要导入static_slip取得的切片, 结果需要times 质量数的平方
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    energy = dat[:energy]

    gf = reshape(dat[:gf], 1, nbins,nenergy)
    eff = dat[:eff]
    G = dat[:geom_factor].*eff.*gf
    dt = dat[:time_integ]
    mass = dat[:mass]
    dead = dat[:dead]						# dead time array usec for STATIC
    bkg = dat[:bkg]					# background array usec for STATIC
    tmp = dat[:data]

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    dat[:df_mass_mass] = scale .* tmp
    return dat
end
function STA_count2df_all(dat) #计算df,对非时间切片数据
    ntime   = dat[:num_dists]

    nmass   = dat[:nmass]
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    energy  = dat[:energy]
    dims4 = (ntime,nmass,nbins,nenergy) 
    if nbins == 1
        gf     = zeros(ntime,1,nenergy)
        eff    = zeros(ntime,nmass,nenergy)
        mass   = zeros(ntime,nmass,nenergy)
        energy = zeros(ntime,nmass,nenergy)
        dt   = reshape(dat[:time_integ],ntime, 1,  1)
    
        dead = dat[:dead]
        bkg = dat[:bkg]
        tmp = dat[:data]
    
        @inbounds for i in 1:ntime
            swp_ind = dat[:swp_ind][i]
            att_ind = dat[:att_ind][i]
            eff_ind = dat[:eff_ind][i]
            gf[i,:,:]   = dat[:gf][att_ind+1,:,swp_ind+1]
            eff[i,:,:]  = dat[:eff][:,:,eff_ind+1]
            mass[i,:,:] = dat[:mass].*dat[:mass_arr][:,:,swp_ind+1]
            energy[i,:,:] = dat[:energy][:,:,swp_ind+1]
        end
    else
        gf     = zeros(ntime,1,nbins,nenergy)
        eff    = zeros(ntime,nmass,nbins,nenergy)
        mass   = zeros(ntime,nmass,nbins,nenergy)
        energy = zeros(ntime,nmass,nbins,nenergy)
        dt   = reshape(dat[:time_integ],ntime, 1, 1, 1)

        dead = dat[:dead]
        bkg = dat[:bkg]
        tmp = dat[:data]

        @inbounds for i in 1:ntime
            swp_ind = dat[:swp_ind][i]
            att_ind = dat[:att_ind][i]
            eff_ind = dat[:eff_ind][i]
            gf[i,:,:,:]   = dat[:gf][att_ind+1,:,:,swp_ind+1]
            eff[i,:,:,:]  = dat[:eff][:,:,:,eff_ind+1]
            mass[i,:,:,:] = dat[:mass].*dat[:mass_arr][:,:,:,swp_ind+1]
            energy[i,:,:,:] = dat[:energy][:,:,:,swp_ind+1]
        end
    end

    G = dat[:geom_factor].*eff.*gf

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    dat[:df] = scale .* tmp
    return dat
end
# function STA_count2df_all_no_m_int(dat) #计算df,结果需要times 质量数的平方
#     ntime   = dat[:num_dists]

#     nmass   = dat[:nmass]
#     nbins   = dat[:nbins]
#     nenergy = dat[:nenergy]
#     energy  = dat[:energy]
#     dims4 = (ntime,nmass,nbins,nenergy) 
#     if nbins == 1
#         gf     = zeros(ntime,1,nenergy)
#         eff    = zeros(ntime,nmass,nenergy)
#         mass   = zeros(ntime,nmass,nenergy)
#         energy = zeros(ntime,nmass,nenergy)
#         dt   = reshape(dat[:time_integ],ntime, 1,  1)
    
#         dead = dat[:dead]
#         bkg = dat[:bkg]
#         tmp = dat[:data]
    
#         @inbounds for i in 1:ntime
#             swp_ind = dat[:swp_ind][i]
#             att_ind = dat[:att_ind][i]
#             eff_ind = dat[:eff_ind][i]
#             gf[i,:,:]   = dat[:gf][att_ind+1,:,swp_ind+1]
#             eff[i,:,:]  = dat[:eff][:,:,eff_ind+1]
#             mass[i,:,:] = dat[:mass]
#             energy[i,:,:] = dat[:energy][:,:,swp_ind+1]
#         end
#     else
#         gf     = zeros(ntime,1,nbins,nenergy)
#         eff    = zeros(ntime,nmass,nbins,nenergy)
#         mass   = zeros(ntime,nmass,nbins,nenergy)
#         energy = zeros(ntime,nmass,nbins,nenergy)
#         dt   = reshape(dat[:time_integ],ntime, 1, 1, 1)

#         dead = dat[:dead]
#         bkg = dat[:bkg]
#         tmp = dat[:data]

#         @inbounds for i in 1:ntime
#             swp_ind = dat[:swp_ind][i]
#             att_ind = dat[:att_ind][i]
#             eff_ind = dat[:eff_ind][i]
#             gf[i,:,:,:]   = dat[:gf][att_ind+1,:,:,swp_ind+1]
#             eff[i,:,:,:]  = dat[:eff][:,:,:,eff_ind+1]
#             mass[i,:,:,:] = dat[:mass]
#             energy[i,:,:,:] = dat[:energy][:,:,:,swp_ind+1]
#         end
#     end

#     G = dat[:geom_factor].*eff.*gf

#     tmp = (tmp .- bkg ).*dead
#     scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
#     dat[:df] = scale .* tmp
#     return dat
# end
function STA_count2eflux_all(dat) #计算df,对非时间切片数据
    ntime   = dat[:num_dists]

    nmass   = dat[:nmass]
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    natt = dat[:natt]
    nswp = dat[:nswp]
    neff = dat[:neff]
    # dims4 = (ntime,nmass,nbins,nenergy) 

    gf     = zeros(ntime,1,nbins,nenergy)
    eff    = zeros(ntime,nmass,nbins,nenergy)
    dt   = reshape(dat[:time_integ],ntime, 1, 1, 1)

    dead = reshape(dat[:dead],ntime,nmass,nbins,nenergy)
    bkg  = reshape(dat[:bkg],ntime,nmass,nbins,nenergy)
    tmp  = reshape(dat[:data],ntime,nmass,nbins,nenergy)

    gf0  = reshape(dat[:gf], natt,1,nbins,nenergy,nswp)
    eff0 = reshape(dat[:eff], nmass,nbins,nenergy,neff)
    @inbounds for i in 1:ntime
        swp_ind = dat[:swp_ind][i]
        att_ind = dat[:att_ind][i]
        eff_ind = dat[:eff_ind][i]
        gf[i,:,:,:]   = gf0[att_ind+1,:,:,:,swp_ind+1]
        eff[i,:,:,:]  = eff0[:,:,:,eff_ind+1]
    end

    G = dat[:geom_factor].*eff.*gf

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G)
    dat[:eflux_from_count] = scale .* tmp
    return dat
end
function STA_count2eflux(dat;m_int=m_int)
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    # energy = dat[:energy]   				# in eV     (n_e,nbins,n_m)
    gf = reshape(dat[:gf], 1, nbins,nenergy)
    eff = dat[:eff]
    G = dat[:geom_factor].*eff.*gf
    dt = dat[:time_integ]
    # mass = dat[:mass].*m_int
    dead = dat[:dead]						# dead time array usec for STATIC
    bkg = dat[:bkg]						# background array usec for STATIC
    tmp = dat[:data]

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G)
    dat[:eflux] = scale .* tmp
    return dat
end
function STA_eflux2df(dat;m_int=m_int)
    energy = dat[:energy]
    mass = dat[:mass].*m_int
    scale = 1 ./(energy.^2 .* 2 ./mass./mass.*1e5)
    dat[:df] = scale .* dat[:eflux]
    return dat
end
#数据切片
function static_slip(dat,time_ind) #取得static在指定时刻的切片,time_ind 为对应时刻的坐标; 平滑的时间会有插值的问题,所以不考虑
    dat_slip =Dict{Symbol,Any}()
    for key in keys(dat)
        dat_slip[key] = dat[key]
    end
    swp_ind = dat[:swp_ind][time_ind]
    att_ind = dat[:att_ind][time_ind]
    eff_ind = dat[:eff_ind][time_ind]

    dat_slip[:eflux]        = dat[:eflux][time_ind,:,:,:]
    dat_slip[:data]         = dat[:data][time_ind,:,:,:]
    dat_slip[:bkg]          = dat[:bkg][time_ind,:,:,:]
    dat_slip[:epoch]        = dat[:epoch][time_ind]
    dat_slip[:time_integ]   = dat[:time_integ][time_ind]
    dat_slip[:swp_ind]      = dat[:swp_ind][time_ind]
    dat_slip[:att_ind]      = dat[:att_ind][time_ind]
    dat_slip[:eff_ind]      = dat[:eff_ind][time_ind]
    dat_slip[:sc_pot]       = dat[:sc_pot][time_ind]
    dat_slip[:dead]         = dat[:dead][time_ind,:,:,:]
    dat_slip[:quat_mso]     = dat[:quat_mso][time_ind,:]
    dat_slip[:quat_sc]      = dat[:quat_sc][time_ind,:]
    dat_slip[:magf]         = dat[:magf][time_ind,:]
    dat_slip[:pos_sc_mso]   = dat[:pos_sc_mso][time_ind,:]
    
    dat_slip[:energy]   = dat[:energy][:,:,:,swp_ind+1]
    dat_slip[:denergy]  = dat[:denergy][:,:,:,swp_ind+1]
    dat_slip[:theta]    = dat[:theta][:,:,:,swp_ind+1]
    dat_slip[:phi]      = dat[:phi][:,:,:,swp_ind+1]
    dat_slip[:dtheta]   = dat[:dtheta][:,:,:,swp_ind+1]
    dat_slip[:dphi]     = dat[:dphi][:,:,:,swp_ind+1]
    dat_slip[:mass_arr] = dat[:mass_arr][:,:,:,swp_ind+1]
    dat_slip[:gf]       = dat[:gf][att_ind+1,:,:,swp_ind+1]
    dat_slip[:eff]      = dat[:eff][:,:,:,eff_ind+1]

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
        dat = STA_count2df(dat;m_int=m_int)
        data=dat[:df]
    else
        data=dat[:df_mass_mass] .*m_int^2  #需要提前用STA_count2df_no_m_int处理之
    end
    energy = dat[:energy] 
    denergy = dat[:denergy] 
    theta = dat[:theta]./RADG
    phi = dat[:phi] ./RADG
    dtheta = dat[:dtheta] ./RADG
    dphi = dat[:dphi] ./RADG
    mass_arr = dat[:mass_arr]
    pot = dat[:sc_pot]

    ind = findall(x->x <= energy_range[1] || x >= energy_range[2],energy)
    data[ind].=0.0

    ind = findall(x->x <= mass_range[1] || x >= mass_range[2],mass_arr)
    data[ind].=0.0
    
    # if m_int != 0
    # mass_arr[:] .= m_int
    # else
    #     mass_arr=round.(mass_arr .-0.1) # the minus 0.1 helps account for straggling at low mass
    #     mass_arr[mass_arr .< 1] .= 1.0
    # end
    mass=dat[:mass]*m_int
    
    Const = 2.0/mass/mass*1e5
    energy=energy.+pot		# energy/charge analyzer, require positive energy
    energy[energy .< 0.0] .=0.0

    flux0 = Const.*denergy.*energy.*data
    theta0 = (dtheta./2.0.+cos.(2.0.*theta).*sin.(dtheta)./2.0).*2.0.*sin.(dphi./2.0)
    flux3dx = sum(flux0.*theta0.*cos.(phi))
    flux3dy = sum(flux0.*theta0.*sin.(phi))
    flux3dz = sum(flux0.*(2.0.*sin.(theta).*cos.(theta).*sin.(dtheta./2.0).*cos.(dtheta./2.0)).*dphi)
    #units are 1/cm^2-s
    Const = mass^(-1.5)*2.0^(0.5)
    density = sum(Const.*denergy.*sqrt.(energy).*data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi)
    
    flux = [flux3dx,flux3dy,flux3dz]
    vel = 1e-5 .* flux ./(density .+ 1e-10)
    return vel,flux,density
end
# function sta_v_4d(dat,time_ind;energy_range=[0,1e5],mass_range=[10,20],m_int = 16,unit_cover=true)#计算离子速度,流速,密度,单位km/s,/cm^2/s cm^-3
#     if unit_cover
#         dat = STA_count2df_all(dat;m_int=m_int)
#         data=dat[:df]
#     else
#         data=dat[:df_mass_mass] .*m_int^2  #需要提前用STA_count2df_all_no_m_int处理之
#     end
#     energy = dat[:energy] 
#     denergy = dat[:denergy] 
#     theta = dat[:theta]./RADG
#     phi = dat[:phi] ./RADG
#     dtheta = dat[:dtheta] ./RADG
#     dphi = dat[:dphi] ./RADG
#     mass_arr = dat[:mass_arr]
#     pot = dat[:sc_pot]

#     ind = findall(x->x <= energy_range[1] || x >= energy_range[2],energy)
#     data[ind].=0.0

#     ind = findall(x->x <= mass_range[1] || x >= mass_range[2],mass_arr)
#     data[ind].=0.0
    
#     mass=dat[:mass]*m_int
    
#     Const = 2.0/mass/mass*1e5
#     energy=energy.+pot		# energy/charge analyzer, require positive energy
#     energy[energy .< 0.0] .=0.0

#     flux0 = Const.*denergy.*energy.*data
#     theta0 = (dtheta./2.0.+cos.(2.0.*theta).*sin.(dtheta)./2.0).*2.0.*sin.(dphi./2.0)
#     flux3dx = sum(flux0.*theta0.*cos.(phi))
#     flux3dy = sum(flux0.*theta0.*sin.(phi))
#     flux3dz = sum(flux0.*(2.0.*sin.(theta).*cos.(theta).*sin.(dtheta./2.0).*cos.(dtheta./2.0)).*dphi)
#     #units are 1/cm^2-s
#     Const = mass^(-1.5)*2.0^(0.5)
#     density = sum(Const.*denergy.*sqrt.(energy).*data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi)
    
#     flux = [flux3dx,flux3dy,flux3dz]
#     vel = 1e-5 .* flux ./(density .+ 1e-10)
#     return vel,flux,density
# end
function sta_n_4d(dat;energy_range=[0,1e5],mass_range=[10,20],m_int = 16,unit ="eflux")#计算离子速度,流速，密度，需要导入static_slip取得的切片,单位cm^-3
    if dat[:valid] == 0
        println("Invalid Data")
        return NaN
    end

    dat = STA_count2df(dat;m_int=m_int)
    data=dat[:df]

    energy = dat[:energy] 
    denergy = dat[:denergy] 
    theta = dat[:theta]./RADG
    phi = dat[:phi] ./RADG
    dtheta = dat[:dtheta] ./RADG
    dphi = dat[:dphi] ./RADG
    mass_arr = dat[:mass_arr]
    pot = dat[:sc_pot]

    ind = findall(x->x <= energy_range[1] || x >= energy_range[2],energy)
    data[ind].=0.0

    ind = findall(x->x <= mass_range[1] || x >= mass_range[2],mass_arr)
    data[ind].=0.0
    
    mass=dat[:mass]*m_int
    
    # Const = 2.0/mass/mass*1e5
    energy=energy.+pot		# energy/charge analyzer, require positive energy
    energy[energy .< 0.0] .=0.0

    #units are 1/cm^2-s
    Const = mass^(-1.5)*2.0^(0.5)
    density = sum(Const.*denergy.*sqrt.(energy).*data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi)
    return density
end
function static_rotation(dat;frame="MSO") #将STATIC数据在某时刻的切片旋转到对应坐标系,仅限3D数据(mass,bins,energy)，需要STA_slip产生的切片
    function rotate_vector(u::AbstractVector,q::QuaternionF64)
        q_u = QuaternionF64(0, u[1], u[2], u[3])
        q_v = q*q_u*conj(q)
        q_v_i = imag_part(q_v)
        return [q_v_i[1],q_v_i[2],q_v_i[3]]
    end
    function sphere2xyz_for_static_rotation(θ,ϕ)
        x = cosd.(θ) .*  cosd.(ϕ)
        y = cosd.(θ) .*  sind.(ϕ)
        z = sind.(θ)
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

    quat = QuaternionF64(dat2[frame_t][1],dat2[frame_t][2],dat2[frame_t][3],dat2[frame_t][4])

    xyz = sphere2xyz_for_static_rotation.(theta,phi);
    xyz_mso = rotate_vector.(xyz,quat);
    sphere_mso = xyz2sphere_for_static_rotation.(xyz_mso)

    thetaT=zeros(n_m,n_b,n_e)
    phiT=zeros(n_m,n_b,n_e)

    for (i,var) in enumerate(sphere_mso)
        phiT[i] = var[2]
        thetaT[i] = var[1]
    end
    magfT = rotate_vector(magf,quat);
    dat2[:theta] = thetaT
    dat2[:phi] = phiT
    dat2[:magf] = magfT
    return dat2
end
function static_slip_2_V(dat;mass_range=[10,20],m_int = 16,vsc=[0,0,0]) #use slip_data
    nenergy  = dat[:nenergy]
    nbins    = dat[:nbins]
    energy   = dat[:energy]      
    phi      = dat[:phi]        
    theta    = dat[:theta]         
    mass_arr = dat[:mass_arr]   
    sc_pot   = dat[:sc_pot]     

    # dat = STA_count2df(dat;m_int=m_int)
    dat = STA_eflux2df(dat;m_int=m_int)
    data=dat[:df]
    
    mask = (mass_arr .>= mass_range[1]) .& (mass_arr .<= mass_range[2])
    energy_mass = energy[1,:,:]
    phi_mass = phi[1,:,:]
    theta_mass = theta[1,:,:]
    
    df_data = sum(data.*mask,dims=1)
    df_data = df_data[1,:,:]
    
    V_MSO = zeros(nbins,nenergy,3)
    
    energy_t = energy_mass .+ sc_pot
    energy_t[energy_t .<= 0] .= 0.001
    
    v0 = ion_energy2v.(energy_t,m_int) ./1e3
    
    APP_position = sphere2xyz_for_STATIC.(v0,theta_mass,phi_mass)
    
    V_MSO[:,:,1] = [x[1] for x in APP_position]
    V_MSO[:,:,2] = [x[2] for x in APP_position]
    V_MSO[:,:,3] = [x[3] for x in APP_position]

    vsc1 = reshape(vsc,1,1,3)

    V_MSO =V_MSO .+ vsc1
    
    return_data = Dict{Symbol,Any}(
       :dF=> df_data,
       :v => V_MSO,
       :mass=> m_int,
       :nbins=>nbins,
       :energy=>energy_t,
       :nenergy=>nenergy,
       :magf => dat[:magf],
    )
    return return_data
end
function rotate_vector_with_Martrix(in_data,Rotation_Martrix) # inv
    out_data = Rotation_Martrix * in_data
    return out_data
end
function rotate_vector_with_quat(u::AbstractVector,q::QuaternionF64)
    q_u = QuaternionF64(0, u[1], u[2], u[3])
    q_v = q*q_u*conj(q)
    return [imag_part(q_v)...]
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

    E0 = 511.0 * m_int * 1836.23
    γ =(energy * 1e-3 /E0 + 1)
    β =sqrt(1.0 - 1.0 / γ^2)
    V = β * C
    F = 2 * eflux *1e4 / V^4
    return F
end
function sphere2xyz_for_STATIC(r,θ,ϕ) #spedas_6_1\general\science\sphere_to_cart.pro
    x = r .* cosd.(θ) .*  cosd.(ϕ)
    y = r .* cosd.(θ) .*  sind.(ϕ)
    z = r .* sind.(θ)
    return [x,y,z]
end;
function xyz2sphere_for_STATIC(x,y,z)
    r=sqrt(x^2 + y^2 + z^2)
    theta = 90. - acosd(z/r)
    phi = atand(y, x)
    return [r,theta,phi]
end
function sphere2xyz(r,θ,ϕ)
    x = r .* sind.(θ) .*  cosd.(ϕ)
    y = r .* sind.(θ) .*  sind.(ϕ)
    z = r .* cosd.(θ)
    return [x,y,z]
end
function ion_energy2v(energy,AMU) # 离子子能量对应速度(相对论),输入eV, IS单位制
    E0 = 938313.53 * AMU  # 质子静止能量 MeV
    γ= energy*1e-3/E0 + 1.0
    β=sqrt(1.0 - 1.0 / γ^2)
    v = β * 3e8
    return v
end
function ion_v2energy(v,AMU) # 离子子能量对应速度(相对论) v:速度, IS单位制,返回eV
    E0 = 938313.53 * AMU
    β  = v / 3e8
    γ = 1.0 / sqrt(1.0 - β^2)
    energy = (γ - 1.0) * E0 * 1e3
    return energy
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

# vv0 =9.8e3
# ee = ion_v2energy(vv0 ,32)
# vv = ion_energy2v(ee,32)
# println(vv0," ",vv," ",ee)
# vv0^2 * 0.5*32*Mp/EV
end # module