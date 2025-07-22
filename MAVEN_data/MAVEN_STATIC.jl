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
function STA_count2df(dat) #计算df,需要导入static_slip取得的切片
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    energy = dat[:energy]

    gf = reshape(dat[:gf], 1, nbins,nenergy)
    eff = dat[:eff]
    G = dat[:geom_factor].*eff.*gf
    dt = dat[:time_integ]
    mass = dat[:mass]
    mass_arr = dat[:mass_arr]
    dead = dat[:dead]						# dead time array usec for STATIC
    bkg = dat[:bkg]					# background array usec for STATIC
    tmp = dat[:data]

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    df_t = scale .* tmp
    dat[:df] = df_t .*mass_arr.^2
    dat[:df_mass_mass] = df_t # 没有乘以质量的平方
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
    dat_slip[:quality_flag] = dat[:quality_flag][time_ind]
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
        dat = STA_count2df(dat)
        data = dat[:df] #取得相空间密度
    else
        data=dat[:df_mass_mass] .*m_int^2  #取得相空间密度
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
    #units are 1/cm^3
    flux = [flux3dx,flux3dy,flux3dz]
    vel = 1e-5 .* flux ./(density .+ 1e-10)
    #units are km/s
    return vel,flux,density
end
function sta_n_4d(dat;energy_range=[0,1e5],mass_range=[10,20],m_int = 16,unit ="eflux")#计算离子速度,流速，密度，需要导入static_slip取得的切片,单位cm^-3
    if dat[:valid] == 0
        println("Invalid Data")
        return NaN
    end

    data=dat[:df_mass_mass] .*m_int^2  #相空间密度

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
function sta_pickup(dat)#计算拾取率,需要conut2df处理过的dat切片
    function get_vfn(dat,dF;m_int=1)
        phi = dat[:phi] .|> deg2rad# 8,64,32
        theta = dat[:theta] .|> deg2rad# (8, 64, 32)
        energy = dat[:energy]# (8, 64, 32)
        denergy = dat[:denergy]# (8, 64, 32)
    
        dtheta = dat[:dtheta] .|> deg2rad
        dphi = dat[:dphi] .|> deg2rad
        mass = dat[:mass]
    
        mass=dat[:mass]*m_int
    
        dF_t = dF .* m_int.^2
    
        Const = 2.0/mass/mass*1e5
        flux0 = Const.*denergy.*energy.*dF_t
        theta0 = (dtheta./2.0.+cos.(2.0.*theta).*sin.(dtheta)./2.0).*2.0.*sin.(dphi./2.0)
        flux3dx = sum(flux0.*theta0.*cos.(phi))
        flux3dy = sum(flux0.*theta0.*sin.(phi))
        flux3dz = sum(flux0.*(2.0.*sin.(theta).*cos.(theta).*sin.(dtheta./2.0).*cos.(dtheta./2.0)).*dphi)
        flux = [flux3dx,flux3dy,flux3dz]
    
        Const = mass^(-1.5)*2.0^(0.5)
        density = sum(Const.*denergy.*sqrt.(energy).*dF_t.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi)
    
        vel = 1e-5 .* flux ./(density .+ 1e-10)
        return vel,flux,density
    end
    function get_bin_mask(dat,vec)
        phi = dat[:phi]# 8,64,32
        theta = dat[:theta]# (8, 64, 32)
        vec_1 = normalize(vec)
        A0 = MAVEN_STATIC.sphere2xyz_for_STATIC.([1],theta,phi)
        dl = 2*π*30/360
        bin_mask = [norm(xyz.-vec_1) > dl for xyz in A0]
        return bin_mask
    end
    df_mass = dat[:df_mass_mass]
    mass_arr = dat[:mass_arr]
    mass_mask_H = (mass_arr .> 0) .& (mass_arr .<= 1.3);
    v_H,_,n_H = get_vfn(dat,df_mass.*mass_mask_H;m_int=1);
    bin_mask = get_bin_mask(dat,v_H);
    
    mass_mask_He = (dat[:mass_arr] .> 1.3) .& (dat[:mass_arr] .<= 2.3);
    v_He,_,n_He = get_vfn(dat,df_mass.*mass_mask_He;m_int=2);
    df_He_1 = sum(dat[:df].*mass_mask_He,dims=1);
    He_mask = (df_He_1 .== 0);

    df_1 = dat[:df] .* bin_mask .* He_mask # 去除掉有He部分的H数据，H主速度方向的离子
    _,_,n_H_no_sw = get_vfn(dat,df_1.*mass_mask_H;m_int=1);

    pickup_rate = n_H_no_sw/n_H

    return pickup_rate,v_H,v_He,n_H,n_He,n_H_no_sw
end
function static_rotation(dat;frame="MSO") #将STATIC数据在某时刻的切片旋转到对应坐标系,仅限3D数据(mass,bins,energy)，需要STA_slip产生的切片
    function rotate_vector(u::AbstractVector,q::QuaternionF64)
        q_u = QuaternionF64(0, u[1], u[2], u[3])
        q_v = q*q_u*conj(q)
        q_v_i = imag_part(q_v)
        return [q_v_i[1],q_v_i[2],q_v_i[3]]
    end
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
    # dat = STA_eflux2df(dat;m_int=m_int)
    df_data = dat[:df]
    ef_data = dat[:eflux]
    
    mask = (mass_arr .>= mass_range[1]) .& (mass_arr .<= mass_range[2])
    energy_mass = energy[1,:,:]
    phi_mass = phi[1,:,:]
    theta_mass = theta[1,:,:]
    
    df_data1 = sum(df_data.*mask,dims=1)[1,:,:]
    ef_data1 = sum(ef_data.*mask,dims=1)[1,:,:]
    
    V_ = zeros(nbins,nenergy,3)
    
    energy_t = energy_mass .+ sc_pot
    energy_t[energy_t .<= 0] .= 0.001
    
    v0 = ion_energy2v.(energy_t,m_int) ./1e3
    
    APP_position = sphere2xyz_for_STATIC.(v0,theta_mass,phi_mass)
    
    V_[:,:,1] = [x[1] for x in APP_position]
    V_[:,:,2] = [x[2] for x in APP_position]
    V_[:,:,3] = [x[3] for x in APP_position]

    vsc1 = reshape(vsc,1,1,3)

    V_ =V_ .+ vsc1
    
    return_data = Dict{Symbol,Any}(
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
function STA_count3df(dat;time_ind = []) #计算c6数据的df,必须有时间轴
    ntime   = dat[:num_dists]
    nbins   = dat[:nbins]
    nenergy = dat[:nenergy]
    nmass   = dat[:nmass]
    energy = zeros(ntime,nmass,nenergy)
    denergy = zeros(ntime,nmass,nenergy)
    mass_arr = zeros(ntime,nmass,nenergy)
    phi = zeros(ntime,nmass,nenergy)
    dphi = zeros(ntime,nmass,nenergy)
    theta = zeros(ntime,nmass,nenergy)
    dtheta = zeros(ntime,nmass,nenergy)
    gf = zeros(ntime,1,nenergy)
    eff = zeros(ntime,nmass,nenergy)
    # if time_ind == []
    time_ind_local = 1:ntime
    # end
    for i in time_ind_local
        swp_ind = dat[:swp_ind][i]
        att_ind = dat[:att_ind][i]
        eff_ind = dat[:eff_ind][i]
        energy[i,:,:] = dat[:energy][:,:,swp_ind+1]
        denergy[i,:,:] = dat[:denergy][:,:,swp_ind+1]
        mass_arr[i,:,:] = dat[:mass_arr][:,:,swp_ind+1]
        
        theta[i,:,:] = dat[:theta][:,:,swp_ind+1]
        phi[i,:,:] = dat[:phi][:,:,swp_ind+1]
        dtheta[i,:,:] = dat[:dtheta][:,:,swp_ind+1]
        dphi[i,:,:] = dat[:dphi][:,:,swp_ind+1]
        
        gf[i,:,:] = dat[:gf][att_ind+1,:,swp_ind+1]
        eff[i,:,:] = dat[:eff][:,:,eff_ind+1]
    end
    dat[:energy3d] = energy
    dat[:denergy3d] = denergy
    dat[:mass_arr3d] = mass_arr
    dat[:phi3d] = phi
    dat[:dphi3d] = dphi
    dat[:theta3d] = theta
    dat[:dtheta3d] = dtheta
    dat[:gf3d] = gf
    dat[:eff3d] = eff # 重新按时间排布的数据
    G    = dat[:geom_factor].*eff.*gf
    dt   = dat[:time_integ]
    mass = dat[:mass]
    dead = dat[:dead]						# dead time array usec for STATIC
    bkg = dat[:bkg]					# background array usec for STATIC
    tmp = dat[:data]

    tmp = (tmp .- bkg ).*dead
    scale = 1 ./(dt.* G .* energy.^2 .* 2 ./mass./mass.*1e5)
    df_t = scale .* tmp
    dat[:df] = df_t .*mass_arr.^2
    dat[:df_mass_mass] = df_t # 没有乘以质量数的平方
    return dat
end
function sta_v_1d(dat;energy_range=[0,1e5],mass_range=[10,20],m_int = 16, time_ind = [])#使用c6数据计算一维离子速度,流速，密度，需要导入STA_count3df取得的相空间密度,单位km/s,cm^-3
    ntime = dat[:num_dists]
    # if time_ind == []
    #     time_ind_local = 1:ntime
    # else
    #     time_ind_local = time_ind
    # end
    
    data=dat[:df_mass_mass] .*m_int^2
    energy = dat[:energy3d]
    denergy = dat[:denergy3d]
    theta = dat[:theta3d]./RADG
    phi = dat[:phi3d] ./RADG
    dtheta = dat[:dtheta3d] ./RADG
    dphi = dat[:dphi3d] ./RADG
    mass_arr = dat[:mass_arr3d]
    pot = reshape(dat[:sc_pot],ntime,1,1)

    ind = findall(x->x <= energy_range[1] || x >= energy_range[2],energy)
    data[ind].=0.0

    ind = findall(x->x <= mass_range[1] || x >= mass_range[2],mass_arr)
    data[ind].=0.0

    mass=dat[:mass]*m_int
    
    Const = 2.0/mass/mass*1e5
    energy=energy.+pot		# energy/charge analyzer, require positive energy
    energy[energy .< 0.0] .=0.0

    
    flux0 = Const.*denergy.*energy.*data .*4π # 4PI为去除全向
    # theta0 = (dtheta./2.0.+cos.(2.0.*theta).*sin.(dtheta)./2.0).*2.0.*sin.(dphi./2.0)
    # flux3dx = sum(flux0.*theta0.*cos.(phi);dims=2:3)
    # flux3dy = sum(flux0.*theta0.*sin.(phi);dims=2:3)
    # flux3dz = sum(flux0.*(2.0.*sin.(theta).*cos.(theta).*sin.(dtheta./2.0).*cos.(dtheta./2.0)).*dphi;dims=2:3)
    flux =  sum(flux0;dims=2:3)[:,1,1]#sqrt.(flux3dx.^2 .+ flux3dy.^2 .+ flux3dz.^2)[:,1,1] #  #units are 1/cm^2-s

    Const = mass^(-1.5)*2.0^(0.5)
    density = sum(Const.*denergy.*sqrt.(energy).*data.*2.0.*cos.(theta).*sin.(dtheta./2.0).*dphi;dims=2:3)[:,1,1]
    vel = 1e-5 .* flux ./(density .+ 1e-10)

    valid  = dat[:valid] .== 0
    vel[valid] .= NaN
    flux[valid] .= NaN
    density[valid] .= NaN

    return vel,flux,density
end
function get_quality_flag(x)
    #取得二进制的质量标志，Int转二进制
    flags = [i == '1' for i in string(x, base=2)] |> reverse
    return flags
end
function compare_quality(flag,contains)
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
    flags = get_quality_flag(flag)
    if true in flags[contains]
        return true
    else   
        return false
    end
end
function rotate_vector_with_Martrix(in_data,Rotation_Martrix) # inv
    out_data = Rotation_Martrix * in_data
    return out_data
end
function rotate_vector_with_quat(u::AbstractVector, q::QuaternionF64)
    q_u = QuaternionF64(0, u[1], u[2], u[3])
    q_v = q * q_u * conj(q)
    return [imag_part(q_v)...]
end
function rotate_vector_with_quat_reverse(u::AbstractVector, q::QuaternionF64)
    q_u = QuaternionF64(0, u[1], u[2], u[3])
    q_v = conj(q) * q_u * q
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
    ct = cosd(θ)
    x = r * ct *  cosd(ϕ)
    y = r * ct *  sind(ϕ)
    z = r * sind(θ)
    return [x,y,z]
end;
function xyz2sphere_for_STATIC(x,y,z)
    r=sqrt(x^2 + y^2 + z^2)
    theta = 90.0 - acosd(z/r)
    phi = atand(y, x)
    return [r,theta,phi]
end
function sphere2xyz(r,θ,ϕ)
    x = r * sind(θ) *  cosd(ϕ)
    y = r * sind(θ) *  sind(ϕ)
    z = r * cosd(θ)
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


# # # -------------------------Test parts-------------------------
# include("MAVEN_load.jl");import .MAVEN_load;
# include("MAVEN_plot.jl");import .MAVEN_plot;
# import .MAVEN_STATIC;
# using Dates
# using CairoMakie
# # kp_vars_dict = Dict(
# #     :B_SS_x => 128,
# #     :B_SS_y => 130,
# #     :B_SS_z => 132,
# #     :MSO_x => 190,
# #     :MSO_y => 191,
# #     :MSO_z => 192,
# #     :Orbit_Number => 210,
# #     :O2_den => 58,
# #     :O_den => 56,
# #     :H_den => 54,
# #     :O2_f => 87,
# #     :O_f => 84,
# #     :H_f => 78,
# #     )
# # datas_dict = MAVEN_load.data_get_from_date(DateTime(2015,10,29); model_index=["STATIC_c6","KP_l3","STATIC_d1"])
# # kp_data = MAVEN_load.convert_kp_l3(datas_dict["KP_l3"];kp_dict=kp_vars_dict)
# # sta_data = copy(datas_dict["STATIC_c6"])
# # sta_d1_data = copy(datas_dict["STATIC_d1"])
# # @time sta_fdata = MAVEN_STATIC.STA_count3df(sta_data)
# # @time Ov,Of,On = MAVEN_STATIC.sta_v_1d(sta_fdata;energy_range=[0,1e8],mass_range=[13,19],m_int = 16)
# @time O2v,O2f,O2n = MAVEN_STATIC.sta_v_1d(sta_fdata;energy_range=[0,1e8],mass_range=[20,40],m_int = 32)
# # @time Hv,Hf,Hn = MAVEN_STATIC.sta_v_1d(sta_fdata;energy_range=[0,1e8],mass_range=[0.5,1.5],m_int = 1)

# # v,f,n = Hv,Hf,Hn
# # f_kp,n_kp = :H_f,:H_den
# v,f,n = O2v,O2f,O2n
# f_kp,n_kp = :O2_f,:O2_den
# time_range = [DateTime(2015,10,29,11,00),DateTime(2015,10,29,11,40)]
# time_i_kp = findall(x->x>=time_range[1] && x<=time_range[2],kp_data[:time])
# time_i_sta = findall(x->x>=time_range[1] && x<=time_range[2],sta_data[:epoch])
# fig = Figure(size = (800, 600))
# ax = Axis(fig[1, 1])
# lines!(ax,sta_data[:epoch][time_i_sta], n[time_i_sta], color = :blue)
# lines!(ax,kp_data[:time][time_i_kp], kp_data[n_kp][time_i_kp], color = :red)
# ax = Axis(fig[2, 1])
# lines!(ax,sta_data[:epoch][time_i_sta], f[time_i_sta], color = :blue)
# lines!(ax,kp_data[:time][time_i_kp], kp_data[f_kp][time_i_kp].*4π, color = :red)
# ax = Axis(fig[3, 1])
# lines!(ax,sta_data[:epoch][time_i_sta], v[time_i_sta], color = :blue)
# lines!(ax,kp_data[:time][time_i_kp], kp_data[f_kp][time_i_kp].*4π./kp_data[n_kp][time_i_kp].*1e-5, color = :red)
# fig