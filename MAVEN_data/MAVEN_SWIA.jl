
# 处理MAVEN的SWIA数据
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_SWIA
using TimesDates, Dates
using Statistics
using Quaternions

# -------------------------Export parts-------------------------
# export static_c6_mass_mean,static_c6_energy_mean
# export static_rotation,static_slip,static_slip_2_V,sta_v_4d
# export ion_energy2v,ion_v2energy
function n_3d(dat,time_ind;energy_range=[0.1,1e8])# 计算SWIA的密度, SWIA假设所有离子为质子,需要SWIA coarse data 3D, 需要切片
    # general/science/n_3d.pro // projects/maven/swia/mvn_swia_get_3dc.pro 参考

    data = dat[:diff_en_fluxes]
    energy= dat[:energy_coarse]
    ind = findall(x->x <= energy_range[1] || x >= energy_range[2],energy)
    data[:,ind,:,:] .= 0.0
    denergy = energy .* dat[:de_over_e_coarse]


    # if atten <= 1
    #     theta_0 = info_str[infind].theta_coarse
    #     g_th_0 = info_str[infind].g_th_coarse
    #     gf_0 = info_str[infind].geom_coarse 
    # else
    #     theta_0 = info_str[infind].theta_coarse_atten
    #     g_th_0 = info_str[infind].g_th_coarse_atten
    #     gf_0 = info_str[infind].geom_coarse_atten 
    # end
    # dtheta_0 = (shift(theta_0,0,-1) - shift(theta_0,0,1))/2.
    # dtheta_0[*,0] = (theta_0[*,1]-theta_0[*,0])
    # dtheta_0[*,ndeflect-1] = (theta_0[*,ndeflect-1]-theta_0[*,ndeflect-2])
    
    # geom_factor = info_str[infind].geom
    
    # gf = reform(replicate(1,ndeflect)#gf_0,nbins)
    # gf = replicate(1,nenergy)#gf
    
    # theta = fltarr(nenergy,ndeflect,nanode)
    # dtheta = fltarr(nenergy,ndeflect,nanode)
    # eff = fltarr(nenergy,ndeflect,nanode)
    
    # for k = 0,nanode-1 do begin
    #     theta[*,*,k] = theta_0
    #     dtheta[*,*,k] = dtheta_0
    #     eff[*,*,k] = g_th_0
    # endfor
    
    # theta = reform(theta,nenergy,nbins)
    # dtheta = reform(dtheta,nenergy,nbins)
    # eff = reform(eff,nenergy,nbins)
    
    # domega=2.*(dphi/!radeg)*cos(theta/!radeg)*sin(.5*dtheta/!radeg)
    
    # scpot = 0.

    data = dat[:diff_en_fluxes]
    energy = dat[:energy]
    denergy = dat[:denergy]
    theta = dat[:theta]/RADG
    phi = dat[:phi]/RADG
    dtheta = dat[:dtheta]/RADG
    dphi = dat[:dphi]/RADG
    mass = 5.68566e-06*1836. * 1.6e-22
    Const = (mass/(2.0*1.6e-12))^(0.5)

    domega = 2.0*dphi*cos(theta)*sin(0.5*dtheta)

    sumdata = sum(data.*domega,dims=2)
    density = Const*sum(denergy*(energy^(-1.5))*sumdata)
    return density
end
function n_1d(dat;energy_range=[0.1,1e8],time_ind=1:10)# 计算SWIA的密度, SWIA假设所有离子为质子,需要SWIA svy spec data 3D
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
# using Dates
# using CairoMakie
# # data_swia = MAVEN_load.data_get_from_date(DateTime(2015,10,29); model_index=["SWIA_svy_spec","SWIA_coarse_svy_3d","SWIA_mom"])
# energy_range = [500,1e8]
# data_mom = data_swia["SWIA_mom"]
# data_spec = data_swia["SWIA_svy_spec"]
# time_mom_ind  = findall(x-> DateTime(2015 ,10,29,11,40,40) >= x >= DateTime(2015 ,10,29,11,20,40),data_mom[:epoch])
# time_ind = findall(x-> DateTime(2015 ,10,29,11,40,40) >= x >= DateTime(2015 ,10,29,11,20,40),data_spec[:epoch])
# flux = data_spec[:spectra_diff_en_fluxes][time_ind,:]
# energy = reshape(data_spec[:energy_spectra],1,48)
# energy_ind = findall(x->x <= energy_range[1] || x >= energy_range[2],data_spec[:energy_spectra])
# flux[:,energy_ind] .= 0.0
# denergy = energy.*data_spec[:de_over_e_spectra]
# mass = 5.68566e-6*1836. * 1.6e-22
# Const = sqrt(mass/(2.0*1.6e-12)) *8.8

# density = Const*sum(denergy.*(energy.^(-1.5)).*flux,dims=2)[:,1]

# fig = Figure(;size=(500,1200))
# ax  = Axis(fig[1,1])
# lines!(ax,data_mom[:density][time_mom_ind],data_mom[:epoch][time_mom_ind],label="n_mom")
# lines!(ax,density,data_spec[:epoch][time_ind],label="n_1d")
# fig


# dat = data_swia["SWIA_coarse_svy_3d"]
# energy_range = [0.1,1e8]
# time_ind = findall(x-> DateTime(2015 ,10,29,11,40,40) >= x >= DateTime(2015 ,10,29,11,20,40),dat[:epoch])

# nanode = 16
# ndeflect = 4
# nbins = 64
# nenergy = 48

# data = dat[:diff_en_fluxes][time_ind,:,:,:]
# energy= reshape(dat[:energy_coarse],1,48)
# denergy = energy .* 0.15 #dat[:de_over_e_coarse]
# ind = findall(x->x <= energy_range[1] || x >= energy_range[2],energy)
# data[:,:,ind] .= 0.0

# phi = dat[:phi_coarse]
# dphi = 22.5
# atten = dat[:atten_state][time_ind]
# theta =  dat[:theta_coarse]# : dat[:theta_atten_coarse]
# function compute_dtheta(theta_0)
#     nrows, ncols = 4,48
#     dtheta_0 = zeros(nrows, ncols)
#     for j in 2:ncols-1
#         dtheta_0[:, j] = (theta_0[:, j+1] - theta_0[:, j-1]) / 2
#     end
#     dtheta_0[:, 1] = theta_0[:, 2] - theta_0[:, 1]
#     dtheta_0[:, end] = theta_0[:, end] - theta_0[:, end-1]

#     return dtheta_0
# end
# dtheta = compute_dtheta(theta)

# domega = 2.0*dphi*cosd.(theta).*sind.(0.5*dtheta)
# domega = reshape(domega,1,1,4,48)
# sumdata = sum(data./8,dims=2:3)[:,1,1,:]

# mass = 5.68566e-06*1836. * 1.6e-22
# Const = (mass/(2.0*1.6e-12))^(0.5)
# density = Const*sum(denergy.*(energy.^(-1.5)).*sumdata,dims=2)[:,1]

# lines!(ax,density,dat[:epoch][time_ind],label="n_3d")
# axislegend(ax)
# fig
# # # MAVEN_SWIA.n_3d(data_swia["SWIA_coarse_svy_3d"])

# # # 要用idl测试一下