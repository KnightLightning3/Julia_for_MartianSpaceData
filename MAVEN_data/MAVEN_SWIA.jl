# 处理MAVEN的SWIA数据
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_SWIA
using TimesDates, Dates
using Statistics
using Quaternions
using Rotations
using DataInterpolations
# -------------------------Export parts-------------------------
# export static_c6_mass_mean,static_c6_energy_mean
# export static_rotation,static_slip,static_slip_2_V,sta_v_4d
# export ion_energy2v,ion_v2energy
#---------------------------初始化-------------------------------- 由于SWIA的糟糕数据,需要对其读取后进行初始化处理
function get_3dc!(dat;quat_data = nothing)#projects/maven/swia/mvn_swia_get_3dc.pro,直接处理dat,需要SWIA coarse data 3D
    ntime = length(dat[:epoch])
    nanode = 16
    ndeflect = 4
    nbins = 64
    nenergy = 48

    energy= reshape(dat[:energy_coarse],1,48)
    denergy = energy .* 0.15 #dat[:de_over_e_coarse]

    phi = dat[:phi_coarse]
    dphi = 22.5
    atten = dat[:atten_state]
    theta_coarse =  dat[:theta_coarse] # : dat[:theta_atten_coarse]
    theta_atten_coarse = dat[:theta_atten_coarse]

    theta = zeros(ntime,ndeflect,nenergy)

    for i in 1:ntime
        if atten[i] <= 1
            theta[i,:,:] = theta_coarse[:,:]
        else
            theta[i,:,:] = theta_atten_coarse[:,:]
        end
    end

    dtheta = (circshift(theta,(0,-1,0)) - circshift(theta,(0,1,0)))/2
    dtheta[:,1,:] = theta[:,2,:] - theta[:,1,:]
    dtheta[:,end,:] = theta[:,end,:] - theta[:,end-1,:]
    theta = reshape(theta,ntime,4,48)
    dtheta = reshape(dtheta,ntime,4,48)

    domega = 2.0*deg2rad(dphi)*cosd.(theta).*sind.(0.5*dtheta)

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
    dat[:mass] = 5.68566e-6*1836.0

    # 处理quat数据
    if quat_data === nothing
        @warn "No quat data used"
        return dat
    end
    local time_dat  = dat[:time_unix]
    local time_quat = quat_data[:time_unix]
    local dat[:quat_mso] = fill(one(QuatRotation),ntime)
    @inbounds for i in 1:ntime
        local ii = findmin(abs.(time_quat .- time_dat[i]))
        if ii[1] > 4
            @warn "存在时间偏差过大的quat值, t = $(dat[:epoch][i]), dt = $(ii[1])秒"
            # continue
        end
        dat[:quat_mso][i] = quat_data[:quat][ii[2]]
    end
    return dat
    # [:filename, :theta_coarse, :theta_atten_coarse, :g_phi_atten_coarse, :g_theta_atten_coarse, :g_phi_coarse, :energy_coarse, :time_unix, :time_met, :diff_en_fluxes, :atten_state, :g_theta_coarse, :counts, :phi_coarse, :data_load_flag, :dindex, :num_accum, :grouping, :epoch]
end
function get_3df!(dat;quat_data = nothing) #projects/maven/swia/mvn_swia_get_3df.pro,直接处理dat,需要SWIA fine data 3D
    # keys(dat) = [:geom_factor, :filename, :theta_fine, :theta_atten_fine, :time_unix, :time_met, :diff_en_fluxes, :g_theta_fine, :atten_state, :estep_first, :phi_fine, :g_phi_fine, :eindex, :num_dists, :energy_fine, :dstep_first, :counts, :data_load_flag, :g_phi_atten_fine, :accum_time_fine, :g_theta_atten_fine, :dindex, :grouping, :de_over_e_fine, :epoch]
    ntime = length(dat[:epoch])
    nanode = 10
    ndeflect = 12
    nbins = 120
    nenergy = 48

    # startt = dat[:time_unix]
	atten = dat[:atten_state]
	# infind = dat[:info_index]
	estepf = dat[:estep_first]
	dstepf = dat[:dstep_first]
    # dt_int  = dat[:dt_int]
    # dt_arr = ones(1,nenergy,nbins)

    phi = dat[:phi_fine]
    dphi = 4.5
    atten = dat[:atten_state]
    theta_fine =  dat[:theta_fine] # : dat[:theta_atten_fine]
    theta_atten_fine = dat[:theta_atten_fine]

    energy = zeros(ntime,nenergy)
    theta = zeros(ntime,ndeflect,nenergy)

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
    denergy = energy .* dat[:de_over_e_fine]

    dtheta = (circshift(theta,(0,-1,0)) - circshift(theta,(0,1,0)))/2
    dtheta[:,1,:] = theta[:,2,:] - theta[:,1,:]
    dtheta[:,end,:] = theta[:,end,:] - theta[:,end-1,:]
    theta = reshape(theta,ntime,1,ndeflect,nenergy)
    dtheta = reshape(dtheta,ntime,1,ndeflect,nenergy)

    domega = 2.0*deg2rad(dphi)*cosd.(theta).*sind.(0.5*dtheta)

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
    dat[:mass] = 5.68566e-6*1836.0

    # 处理quat数据
    if quat_data === nothing
        @warn "No quat data used"
        return dat
    end
    local time_dat  = dat[:epoch] .|> datetime2unix
    local time_quat = quat_data[:epoch] .|> datetime2unix
    local time00 = time_dat[1]
    local time_quat .-= time00
    local time_dat .-= time00
    local dat[:quat_mso] = fill(one(QuatRotation),ntime)
    @inbounds for i in 1:ntime
        local ii = findmin(abs.(time_quat .- time_dat[i]))
        if ii[1] > 4
            @warn "存在时间偏差过大的quat值, t = $(dat[:epoch][i]), dt = $(ii[1])秒"
            # continue
        end
        dat[:quat_mso][i] = quat_data[:quat][ii[2]]
    end
    return dat
    # [:filename, :theta_coarse, :theta_atten_coarse, :g_phi_atten_coarse, :g_theta_atten_coarse, :g_phi_coarse, :energy_coarse, :time_unix, :time_met, :diff_en_fluxes, :atten_state, :g_theta_coarse, :counts, :phi_coarse, :data_load_flag, :dindex, :num_accum, :grouping, :epoch]
end
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

    # mass = 5.68566e-06*1836. * 1.6e-22
    # Const = (mass/(2.0*1.6e-12))^(0.5)
    Const = 7.224566339926571e-7
    density = Const*sum(denergy.*(energy.^(-1.5)).*sumdata,dims=2)[:,1]
    return density
end
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
function v_3d(dat,time_ind;energy_range=[0.1,1e8])# 计算SWIA的速度, SWIA假设所有离子为质子,需要SWIA coarse data 3D, 经过检验，可以正常工作
    # general/science/v_3d.pro // projects/maven/swia/mvn_swia_get_3dc.pro 参考，已经经过检验，速度单位km/s
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

    local sumdata = sum(data.*domega,dims=2:3)[:,1,1,:]

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
function n_1d(dat0;energy_range=[0.1,1e8],time_ind=1:10)# 计算SWIA的密度, SWIA假设所有离子为质子,需要SWIA svy spec data 3D
    local dat= deepcopy(dat0)
    flux = dat[:spectra_diff_en_fluxes][time_ind,:]
    energy = reshape(dat[:energy_spectra],1,48)
    energy_ind = findall(x->x <= energy_range[1] || x >= energy_range[2],dat[:energy_spectra])
    flux[:,energy_ind] .= 0.0
    denergy = energy.*dat[:de_over_e_spectra]
    mass = 5.68566e-6*1836. * 1.6e-22
    Const = sqrt(mass/(2.0*1.6e-12)) *8.8
    density = Const*sum(denergy.*(energy.^(-1.5)).*flux,dims=2)[:,1]
    return density
end
# function load_quat(filename::String)#读取idl导出的quat数据
#     # 数据格式, filename = file.csv ut, scrotmat, msorotmat, format="(I10,1x,4(f14.10,1x),4(f14.10,1x))"
#     # 统计行数以预分配矩阵
#     n = 0
#     open(filename) do io
#         for _ in eachline(io)
#             n += 1
#         end
#     end
#     # 预分配矩阵，每行包含ut和8个浮点数
#     data = Matrix{Float64}(undef, n, 5)
#     # 逐行解析数据
#     open(filename) do io
#         for (i, line) in enumerate(eachline(io))
#             # 提取各字段并转换为Float64
#             ut = parse(Float64, SubString(line, 1, 10))
#             mso1 = parse(Float64, SubString(line, 12, 25))
#             mso2 = parse(Float64, SubString(line, 27, 40))
#             mso3 = parse(Float64, SubString(line, 42, 55))
#             mso4 = parse(Float64, SubString(line, 57, 70))
            
#             # 填充数据到矩阵
#             @inbounds data[i, :] .= (ut, mso1, mso2, mso3, mso4)
#         end
#     end
    
#     return data
# end
function rotate_vector_with_Martrix(in_data,Rotation_Martrix) # inv
    out_data = Rotation_Martrix * in_data
    return out_data
end
function sphere2xyz_for_SWIA(r,θ,ϕ) #general/science/sphere_to_cart.pro
    local ct = cosd(θ)
    x = r * ct *  cosd(ϕ)
    y = r * ct *  sind(ϕ)
    z = r * sind(θ)
    # local st = sind(θ)
    # x = r * st *  cosd(ϕ)
    # y = r * st *  sind(ϕ)
    # z = r * cosd(θ)
    return [x,y,z]
end;
function eflux2df!(dat) #projects/maven/swia/mvn_swia_convert_units.pro, 返回单位:1/(cm^3-(km/s)^3)
    energy = reshape(dat[:energy],1,1,1,48)
    mass = dat[:mass]
    df = dat[:diff_en_fluxes] ./ (energy.^2 * 2.0 ./mass./mass.*1e5)
    dat[:df] = df
    return dat
end
function xyz2sphere_for_SWIA(x,y,z)
    r=sqrt(x^2 + y^2 + z^2)
    theta = 90.0 - acosd(z/r)
    phi = atand(y, x)
    return [r,theta,phi]
end
function ion_eflux2F(energy,eflux;m_int=1)  # 离子eflux转PSD, 使用IS单位制, 与STA方法差了1e3倍
    E0 = 511.0 * m_int * 1836.23
    γ =(energy * 1e-3 /E0 + 1)
    β =sqrt(1.0 - 1.0 / γ^2)
    V = β * C
    F = 2 * eflux *1e4 / V^4
    return F
end
function ion_energy2v(energy,AMU) # 离子子能量对应速度(相对论),输入eV, IS单位制
    E0 = 938313.53 * AMU  # 质子静止能量 MeV
    γ= energy*1e-3/E0 + 1.0
    β=sqrt(1.0 - 1.0 / γ^2)
    v = β * 3e8
    return v
end
function ion_v2energy(v,AMU) # 离子子能量对应速度(相对论) v:速度, IS单位制
    E0 = 938313.53 * AMU
    β  = v / 3e8
    γ = 1.0 / sqrt(1.0 - β^2)
    energy = (γ - 1.0) * E0 * 1e3
    return energy
end
const EV=1.602176487e-19
const C=3.0e8
const Me=9.109e-31
const Mp=1.672621637e-27
const RADG=180.0/π

end

# # -------------------------Test parts-------------------------
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath * "MAVEN_data/MAVEN_load.jl")
# import .MAVEN_load;
# import .MAVEN_SWIA;
# using Dates
# using CairoMakie
# # data_swia = MAVEN_load.data_get_from_date(DateTime(2015,10,29); model_index=["SWIA_svy_spec","SWIA_fine_svy_3d","SWIA_coarse_svy_3d","SWIA_mom"])
# energy_range = [0,1e8]
# data_mom = data_swia["SWIA_mom"]
# data_spec = data_swia["SWIA_svy_spec"]
# time_mom_ind  = findall(x-> DateTime(2015 ,10,29,11,40,40) >= x >= DateTime(2015 ,10,29,11,20,40),data_mom[:epoch])
# dat = data_swia["SWIA_coarse_svy_3d"]
# dat = MAVEN_SWIA.get_3dc!(dat)
# # dat = data_swia["SWIA_fine_svy_3d"]
# # dat = MAVEN_SWIA.get_3df!(dat)
# energy_range = [0,1e8]
# time_ind = findall(x-> DateTime(2015 ,10,29,11,40,40) >= x >= DateTime(2015 ,10,29,11,20,40),dat[:epoch])
# density = MAVEN_SWIA.n_3d(dat,time_ind;energy_range=energy_range)
# flux = MAVEN_SWIA.j_3d(dat,time_ind;energy_range=energy_range)
# vel0,_,_ = MAVEN_SWIA.v_3d(dat,time_ind;energy_range=energy_range)
# density = reshape(density,length(density),1)

# time_swia = datetime2unix.(dat[:epoch][time_ind])
# # using CSV,DataFrames
# using Quaternions
# swi_quat_dat = MAVEN_SWIA.load_quat("E:/MAVEN/SPICE/$(Dates.format(DateTime(2015,10,29),"yyyy-mm-dd"))_swia_qu.csv")
# # quat = CSV.File(raw"D:\work\20151029低海拔jet\data\swia_qu.csv",delim=' ',ignorerepeated=true)|> DataFrame
# for i in eachindex(time_swia)
#     jj = findmin(x -> abs(x - time_swia[i]), swi_quat_dat[:,1])[2]
#     flux[i,:] = MAVEN_SWIA.rotate_vector_with_quat(flux[i,:],QuaternionF64(swi_quat_dat[jj,2:5]...))
# end

# vel = 1e-5 .* flux ./ density
# # vel = MAVEN_SWIA.v_3d(dat,time_ind;energy_range=energy_range)
# fig = Figure(;size=(500,1200))
# ax  = Axis(fig[1,1])
# colors = [:red,:green,:blue]
# for i in 1:3
#     lines!(ax,data_mom[:velocity_mso][time_mom_ind,i],data_mom[:epoch][time_mom_ind],label="n_mom",color = colors[i])
#     lines!(ax,vel[:,i],dat[:epoch][time_ind],color=colors[i],linestyle = :dash)
# end
# fig
# # time_ind = findfirst(x-> x>= DateTime(2015 ,10,29,11,32,42),dat[:epoch])
# # time_ind = [time_ind,time_ind+1]
# nanode = 16
# ndeflect = 4
# nbins = 64
# nenergy = 48

# data = dat[:diff_en_fluxes][time_ind,:,:,:]
# energy = dat[:energy_coarse]
# ind = findall(x-> !(energy_range[2] >= x >= energy_range[1]),energy)
# data[:,:,:,ind] .= 0.0
# energy= reshape(dat[:energy_coarse],1,48)
# denergy = energy .* 0.15 #dat[:de_over_e_coarse]

# # phi = dat[:phi_coarse]
# dphi = 22.5/180*π
# atten = dat[:atten_state][time_ind]
# theta =  dat[:theta_coarse] # : dat[:theta_atten_coarse]

# dtheta = (circshift(theta,(-1,0)) - circshift(theta,(1,0)))/2
# dtheta[1,:] = theta[2,:] - theta[1,:]
# dtheta[end,:] = theta[end,:] - theta[end-1,:]

# domega = 2.0*dphi*cosd.(theta).*sind.(0.5*dtheta)
# domega = reshape(domega,1,1,4,48)
# sumdata = sum(data.*domega,dims=2:3)[:,1,1,:]

# # mass = 5.68566e-06*1836. * 1.6e-22
# # Const = (mass/(2.0*1.6e-12))^(0.5)
# Const = 7.224566339926571e-7
# density = Const*sum(denergy.*(energy.^(-1.5)).*sumdata,dims=2)[:,1]

# density = MAVEN_SWIA.n_3d(dat,time_ind;energy_range=energy_range)
# x= dat[:epoch][time_ind]
# @show findmax(density)

# @show Int(round(datetime2unix(x[findmax(density)[2]])))
# lines!(ax,density,x,label="n_3d")
# axislegend(ax)
# fig
# # MAVEN_SWIA.n_3d(data_swia["SWIA_coarse_svy_3d"])

# # # idl验证完毕,可以证明n_3d,v_3d