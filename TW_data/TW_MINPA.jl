module TW_MINPA
using Dates
using DelimitedFiles, DataFrames

const mp = 1.6726219e-27 # 质子质量
const me = 9.10938356e-31 # 电子质量
const Q = 1.60217662e-19 # 电荷量
root_path = "E:/Tianwen-1/"
secondry_path = root_path*"MINPA/2B/"

function build_file_list()
    files = []
    println(files)
    years = 2020:2024
    for y in years
        path = secondry_path*string(y)*"/"
        if !isdir(path)
            continue
        end
        paths = readdir(path)
        i_path = findall(x -> endswith(x,".2BL"), paths)
        paths = "$y/".*paths[i_path]
        match = r"\d{14}"
        time_range = [DateTime(x[begin:end-4], DateFormat("y-m-dTH:M:S.s")) for x in paths]
        append!(files,paths)
    end
    open(root_path*"List/"*"MINPA_list.txt", "w") do io
        for file in files
            println(io, file)
        end
    end
    return nothing
end
function read_list()
    list_path = root_path*"List/"*"MINPA_list.txt"
    files = readlines(list_path)
    files = root_path.*files  
    return files
end
function load_mod1(filename::String)
    data = DataFrame(readdlm(filename), :auto)
    mass = [1,2,4,16,28,32,44,64]
    energy = [2.81, 3.548928, 4.482167, 5.660813, 7.149401, 9.029433, 11.40385, 14.40264, 18.19001, 22.97332, 29.01447, 36.64422, 46.28032, 58.45036, 73.82067, 93.23282, 117.7497, 148.7135, 187.8198, 237.2095, 299.587, 378.3675, 477.8644, 603.5253, 762.2305, 962.6694, 1215.816, 1535.532, 1939.321, 2449.292, 3093.366, 3906.809, 4934.157, 6231.661, 7870.361, 9939.98, 12553.83, 15855.03, 20024.33, 25290.0]
    θ = [11.3, 33.8, 56.2, 78.7].|>deg2rad
    ϕ = [11.25, 33.75, 56.25, 78.75, 101.25, 123.75, 146.25, 168.75, 191.25, 213.75, 236.25, 258.75, 281.25, 303.75, 326.25, 348.75].|>deg2rad

    # dθ = θ[2]-θ[1]
    dθ = (circshift(θ,(-1)) - circshift(θ,(1)))/2
    dθ[1] = θ[2] - θ[1]
    dθ[end] = θ[end] - θ[end-1]
    
    dϕ = ϕ[2]-ϕ[1]
    
    # 记录表:18-20：xyz  IAU
    # 记录表:28-30：xyz  J2000
    # data = DataFrame(readdlm(filename), :auto)
    epoch = map(x->DateTime(x[begin:end-4], DateFormat("y-m-dTH:M:S.s")), data[!, 1])
    ut = datetime2unix.(epoch)
    ntime = length(ut)
    nenergy = length(energy)
    nmass = length(mass)
    nϕ = length(ϕ)
    nθ = length(θ)
    # 原始数据为differential_flux，单位1/(s cm^2 sr eV)
    dfi= reshape(Array(data[:,60:20539]), ntime, nmass,nϕ, nθ, nenergy) #时间 质量数 方位角 俯仰角 能道 #
    dfi[dfi .< 0.0] .= 0.0
    
    # mass_n = [1, 4, 16]
    # energy_nh = [29.3, 64.4, 118.2, 200.8, 327.5, 521.8, 820, 1277.3] .+ [80.2, 176.3, 323.7, 549.8, 896.7, 1428.9, 2245.3, 3497.8] #
    # energy_nh = 0.5 .* energy_nh
    # nenergy_nh = length(energy_nh)
    # nmass_n = length(mass_n)
    # dfn = reshape(Array(data[:,20544:21311]), ntime, nmass_n, nϕ, nenergy_nh*2) #时间 质量数 方位角 俯仰角 能道 #
    
    # dfn = dfn[:, :, :, 2:2:16] .+ dfn[:, :, :, 1:2:16] #.+ dfn[:, :, :, 9:16]
    # dfn[dfn .< 0.0] .= 0.0

    pos_mso = reshape(Array(data[:,18:20]), ntime, 3)
    # pitch = data[:,15].|>deg2rad
    # yaw = data[:,16].|>deg2rad
    # roll = data[:,17].|>deg2rad
    # roll0,pitch0,yaw0 = (-89.99268749999997,-0.003999999999999999,90.00199999999997).|>deg2rad
    # rot_martrix = zeros(Float64, ntime, 3, 3)
    # for i in 1:ntime
    #     local r,p,y = roll0,pitch0,yaw0
    #     # local r,p,y = roll[i],pitch[i],yaw[i]
    #     local cp = cos(p)
    #     local sp = sin(p)
    #     local cy = cos(y)
    #     local sy = sin(y)
    #     local cr = cos(r)
    #     local sr = sin(r)
    #     rot_martrix[i,1,:] = [cp*cy, sy*cr+sr*sp*cy, sr*sy-cr*sp*cy]
    #     rot_martrix[i,2,:] =  [-cp*sy, cr*cy-sr*sp*sy, sr*cy+cr*sp*sy]
    #     rot_martrix[i,3,:] = [sp, -sr*cp, cr*cp]
    # end
    
    # 原始数据为微分方向通量j 方向通量J为J=jE

    # eknspec=dropdims(sum(dfn[:, 1, :, :], dims=(2,)), dims=(2, ))
    # for ek in eachindex(energy_nh)
    #     eknspec[:, ek] = eknspec[:, ek] .* energy_nh[ek] .* 1e4
    # end
    # ind =findall(x->x<=0, eknspec)
    # eknspec[ind] .= NaN64
    
    
    # ekHspec=dropdims(sum(dfi[:, 1, :, :, :], dims=(2, 3)), dims=(2, 3))
    # for ek in eachindex(energy)
    #     ekHspec[:, ek] = ekHspec[:, ek] .* energy[ek]
    # end
    # ind =findall(x->x<=0, ekHspec)
    # ekHspec[ind] .= NaN64
    
    
    # ekOspec=dropdims(sum(dfi[:, 4, :, :, :], dims=(2, 3)), dims=(2, 3))
    # for ek in eachindex(energy)
    #     ekOspec[:, ek] = ekOspec[:, ek] .* energy[ek]
    # end
    # ind =findall(x->x<=0, ekOspec)
    # ekOspec[ind] .= NaN64

    data_dict = Dict{Symbol,Any}(
        :data => data,
        :differential_flux => dfi, # differential flux
        :energy => energy,
        :epoch => epoch,
        :time_unix => ut,
        :ntime => ntime,
        :nenergy => nenergy,
        :nmass => nmass,
        :ntheta => nθ,
        :nphi => nϕ,
        :dtheta => dθ,
        :dphi => dϕ,
        :energy => energy,
        :mass => mass,
        :phi => ϕ, #rad
        :theta => θ,
        :pos_mso => pos_mso,
        # :spc2mso_martrix => rot_martrix, #此处弃用，选择momag的数据制作转换坐标系的矩阵
    )
    return data_dict
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
function MINPA_sphere2xyz(r,θ,ϕ) # 转换为仪器坐标系下的情况/ref: https://www.swl.ac.cn/minpa/#/home/overview
    local theta = 0.5π - θ
    local phi = 2π - ϕ
    local ct = cos(theta)
    local st = sin(theta)
    local cp = cos(phi)
    local sp = sin(phi)

    # local x = r * ct * cp
    # local y = r * ct * sp
    # local z = r * st
    local x = r * ct
    local y = -r * st * cp
    local z = -r * st * sp

    return [x,y,z]
end
function MINPA_energy2v(dat;m_int=1) #  取得质量数为m_int的速度分布,单位km/s
    nenergy = dat[:nenergy]
    ntheta = dat[:ntheta]
    nphi = dat[:nphi]

    energy = reshape(dat[:energy],1,1,nenergy)
    theta = reshape(dat[:theta],1,ntheta,1)
    phi = reshape(dat[:phi],nphi,1,1)
    
    v0 = sqrt.(2 .*Q ./(mp.*m_int).*energy)./1e3#TW_MINPA.ion_energy2v.(energy1,m_int)./1e3
    vv = MINPA_sphere2xyz.(v0,theta,phi)# 内含角度修正

    # vv = stack(vv,dims=1)
    dx = [x[1] for x in vv] |> vec
    dy = [x[2] for x in vv] |> vec
    dz = [x[3] for x in vv] |> vec
    vv = hcat(dx,dy,dz)
    vv = -vv #视场方向反向于实际方向
    return vv
end
function MINPA_get_psd(dat) # 通过角度，能量，质量数，计算PSD

    # ntime = dat[:ntime]
    nmass = dat[:nmass]
    # ntheta = dat[:ntheta]
    # nphi = dat[:nphi]
    nenergy = dat[:nenergy]

    energy = reshape(dat[:energy],1,1,1,1,nenergy)
    # theta = reshape(dat[:theta],1,1,1,ntheta,1)
    # phi = reshape(dat[:phi],1,1,nphi,1,1)
    mass = reshape(dat[:mass],1,nmass,1,1,1)

    dflux = dat[:differential_flux]* 1.0E4 # 粒子数通量原本单位为cm^-2, 转换为m^-2

    # flux = dflux.*energy #方向通量J=jE m^-2 s^-1 sr^-1

    Const = 0.5*(mp / Q)^2
    Scale = mass.^2 ./ energy .*Const # 方向通量除以速度4次方乘2
    F = dflux .* Scale

    dat[:psd] = F
    return dat
end
function v3d(dat) # 通过角度，能量，质量数，计算PSD
    dflux = dat[:differential_flux]

    ntime = dat[:ntime]
    nmass = dat[:nmass]
    ntheta = dat[:ntheta]
    nphi = dat[:nphi]
    nenergy = dat[:nenergy]

    energy = reshape(dat[:energy],1,1,1,1,nenergy)
    theta = reshape(dat[:theta],1,1,1,ntheta,1)
    phi = reshape(dat[:phi],1,1,nphi,1,1)
    mass = reshape(dat[:mass],1,nmass,1,1,1)
    dtheta = reshape(dat[:dtheta],1,1,1,ntheta,1)
    dphi = dat[:dphi];#单值

    theta = 0.5π .- theta # 角度修正
    phi = 2π .- phi
    
    vel = zeros(ntime,nmass,3)
    den = zeros(ntime,nmass)

    velocity = sqrt.(2 .*Q ./(mp.*mass).*energy)# 不同能量对应的速度

    # 由于此处θ、φ表示的是视场接收的方向，但相空间分布函数表示的应为速度方向θ',φ',两者方向相反，关系为：θ'=-θ，φ'=φ+Π

    # ct = cos.(-theta)#视场方向反向于实际方向
    # cp = cos.(phi.+π)
    # st = sin.(-theta)
    # sp = sin.(phi.+π)

    ct = cos.(theta)
    cp = cos.(phi)
    st = sin.(theta)
    sp = sin.(phi)

    J = dflux.*energy .* 1.0e4  # 粒子数通量原本单位为cm^-2, 转换为m^-2//原始数据为微分方向通量j，转换为方向通量J。J=jE

    #积分间隔为dtheta*dphi
    dsum = st .* dtheta .* dphi

    n0  =  sum(2.0 .* J ./ velocity   .*dsum ;dims=3:5)
    nvx =  sum(2.0 .* J .* (ct       .* dsum);dims=3:5)
    nvy = -sum(2.0 .* J .* (st .* cp .* dsum);dims=3:5)
    nvz = -sum(2.0 .* J .* (st .* sp .* dsum);dims=3:5)
    #  单位转换，m → cm   Δv/v(=1/2ΔE/E)  Δθ Δφ 乘上积分间隔 

    den[:,:] = n0 .* (1.0E-6 * 0.2/2)
    vel[:,:,1] = nvx  ./ n0 ./ 1.0e3 # 单位转换，m/cm → km
    vel[:,:,2] = nvy  ./ n0 ./ 1.0e3
    vel[:,:,3] = nvz  ./ n0 ./ 1.0e3

    vel = -vel

    flux = vel .* den .* 1e5 #通量，cm^-2s^-1
    
    return vel,flux,den #速度(ntime,nmass,3),km/s,密度(ntime,nmass),cm^-3
end
function v3d_single(dat,time_ind) # 通过角度，能量，质量数，计算PSD
    dflux = dat[:differential_flux][time_ind,:,:,:,:]

    # ntime = dat[:ntime]
    nmass = dat[:nmass]
    ntheta = dat[:ntheta]
    nphi = dat[:nphi]
    nenergy = dat[:nenergy]

    energy = reshape(dat[:energy],1,1,1,nenergy)
    theta = reshape(dat[:theta],1,1,ntheta,1)
    phi = reshape(dat[:phi],1,nphi,1,1)
    mass = reshape(dat[:mass],nmass,1,1,1)
    dtheta = reshape(dat[:dtheta],1,1,ntheta,1)
    dphi = dat[:dphi];#单值

    theta = 0.5π .- theta # 角度修正
    phi = 2π .- phi
    
    vel = zeros(nmass,3)
    den = zeros(nmass)

    velocity = sqrt.(2 .*Q ./(mp.*mass).*energy)# 不同能量对应的速度

    # 由于此处θ、φ表示的是视场接收的方向，但相空间分布函数表示的应为速度方向θ',φ',两者方向相反，关系为：θ'=-θ，φ'=φ+Π

    # ct = cos.(-theta)#视场方向反向于实际方向
    # cp = cos.(phi.+π)
    # st = sin.(-theta)
    # sp = sin.(phi.+π)

    ct = cos.(theta)
    cp = cos.(phi)
    st = sin.(theta)
    sp = sin.(phi)

    J = dflux.*energy .* 1.0e4  # 粒子数通量原本单位为cm^-2, 转换为m^-2//原始数据为微分方向通量j，转换为方向通量J。J=jE

    #积分间隔为dtheta*dphi
    dsum = st .* dtheta .* dphi

    n0  =  sum(2.0 .* J ./ velocity   .*dsum ;dims=2:4)
    nvx =  sum(2.0 .* J .* (ct       .* dsum);dims=2:4)
    nvy = -sum(2.0 .* J .* (st .* cp .* dsum);dims=2:4)
    nvz = -sum(2.0 .* J .* (st .* sp .* dsum);dims=2:4)
    #  单位转换，m → cm   Δv/v(=1/2ΔE/E)  Δθ Δφ 乘上积分间隔 

    den[:] = n0 .* (1.0E-6 * 0.2/2)
    vel[:,1] = nvx  ./ n0 ./ 1.0e3 # 单位转换，m/cm → km
    vel[:,2] = nvy  ./ n0 ./ 1.0e3
    vel[:,3] = nvz  ./ n0 ./ 1.0e3

    vel = -vel

    flux = vel .* den .* 1e5 #通量，cm^-2s^-1
    
    return vel,flux,den #速度(ntime,nmass,3),km/s,密度(ntime,nmass),cm^-3
end
using LinearAlgebra
function slice2d_cal_rot(v1, v2)
    a = normalize(v1)
    d = normalize(v2)
    c = cross(a, d)
    c = normalize(c)
    b = -cross(a, c)
    b = normalize(b)
    # rotinv[:, 1] = a
    # rotinv[:, 2] = b
    # rotinv[:, 3] = c
    rotinv = hcat(a, b, c)
    rot = inv(rotinv)
    return rot
end

end

# import .TW_MINPA
# include("../MAVEN_data/MAVEN_plot.jl");import .MAVEN_plot
# include("TW_load.jl");import .TW_load


# using DelimitedFiles, DataFrames
# using Dates
# using Statistics
# using LinearAlgebra
# using CairoMakie
# using DSP
# using GLMakie
# GLMakie.activate!()
# function color_mapping(vars, color_range; scaler=nothing)
#     vars_no_zero = copy(vars)
#     vars_no_zero[vars_no_zero.==0] .= 1e-20
#     if scaler == "log"
#         color_range_in = log10.(color_range)
#         vars_in = log10.(vars_no_zero)
#     else
#         color_range_in = color_range
#         vars_in = vars_no_zero
#     end
#     vars_mapped = round.(Int, ((vars_in .- color_range_in[1]) ./ (color_range_in[2] - color_range_in[1])) .* 255 .+ 1)
#     vars_mapped[vars_mapped.>256] .= 256
#     vars_mapped[vars_mapped.<1] .= 1
#     return vars_mapped
# end
# # TW_MINPA.build_file_list()

# #original 2pi view
# using MAT
# file = matopen("TW_data/minpa_iondata_20220612.mat")
# time = identity.(read(file, "time"))
# time_mat = map(x->DateTime(x[begin:end-7], DateFormat("y-m-dTH:M:S.s")), time)
# time_mat_unix = datetime2unix.(time_mat)
# ions_eflux = read(file, "ions_eflux")
# Ei = dropdims(read(file, "Ei"), dims=(1,))
# phi_i = read(file, "phi_i")
# theta_i = read(file, "theta_i")
# mass_num = read(file, "mass_num")
# nH = read(file, "nH")
# TH = read(file, "TH")
# VH = read(file, "VH")
# nO = read(file, "nO")
# TO = read(file, "TO")
# VO = read(file, "VO")

# f = raw"E:/Tianwen-1/MINPA/HX1-Or_GRAS_MINPA-MOD1-DEF_SCI_N_20220612034833_20220612105300_01288_A.2B"
# @time data_mag = TW_load.load_mag_2c_bydlm(raw"E:\Tianwen-1\MOMAG\TW1_MOMAG_MSO_01Hz_20220612_2C_v03.dat")
# @time data = TW_MINPA.load_mod1(f)
# @time data = TW_MINPA.MINPA_df2psd(data)
# @time vels,flux,den = TW_MINPA.v3d(data)

# # 设置时间为minpa为基准
# time_0 = DateTime(2022,6,12,9,58,20)
# time_i = findtime(data[:epoch],time_0)
# time_0 = data[:epoch][time_i]
# println("time0 = $time_0")
# time_i_mat = findtime(time_mat,time_0)

# data_points = data[:psd][time_i,1,:,:,:] |> vec# time,mass,phi,theta,energy

# # flux_max_i = findmax(data_points)[2]
# vvec_0 = rot_matrix *vels[time_i,1,:]#[-300,0,100]
# vvec_mat = VH[time_i_mat,:]

# timeb,b = data_mag[:time],data_mag[:B] # 需要加入滤波 wavelet.jl
# #滤波
# # digitalfilter()

# findtime = (x,x0)-> findmin(abs.(x .-x0))[2]
# timeb_i = findtime(timeb,time_0)
# bvec = normalize(Array(b[timeb_i,:]))

# vvec = normalize(vvec_0)# [-1,0,0] #假设太阳风方向为-xmso
# Evec = normalize(cross(-vvec,bvec)) # 平均上游电场方向
# E_cross_B = normalize(cross(Evec,bvec)) # 电场与磁场的叉乘
# rot_bv = TW_MINPA.slice2d_cal_rot(E_cross_B,bvec)

# #计算旋转矩阵：
# _,rotspc2mso = TW_load.get_spc2mso_rot_martrix_via_2c(data_mag)
# rot_matrix = rotspc2mso[timeb_i,:,:]

# # pos = data[:pos_mso][time_i,:]
# vv = TW_MINPA.MINPA_energy2v(data;m_int=1)
# vv_mso = vv * rot_matrix' # 转到MSO坐标系
# vv_bv = vv_mso * rot_bv' # 转到新坐标系

# # ponits = [Point3f(i) for i in eachrow(vv_mso)]

# # fig_3d = Figure()
# # ax1 = LScene(fig_3d[1, 1], scenekw=(ssao=Makie.SSAO(radius=5.0, blur=3),))
# # colors = color_mapping(data_points, [1e-20,1e-8]; scaler="log")
# # inds = colors .> 1
# # scatter!(ax1,ponits[inds],color=colors[inds],colormap=:jet)
# # points_ray = [Point3f(0,0,0),Point3f(vvec_0)]
# # lines!(ax1,points_ray,linewidth=10)
# # points_ray = [Point3f(0,0,0),Point3f(vvec_mat)]
# # lines!(ax1,points_ray,linewidth=10)

# # arrows!(ax1, [Point3f(0,0,0),Point3f(0,0,0)],[Vec3f(E_cross_B.*300),Point3f(bvec.*300)],color=[:red,:green],arrowsize=Vec3f([30, 30, 40]),linewidth=7)
# # display(fig_3d)

# fig = Figure()
# ax1 = Axis(fig[1,1])#,aspect=1)
# ax2 = Axis(fig[2,1])#,aspect=1)
# ax3 = Axis(fig[3,1])#,aspect=1)
# ax4 = Axis(fig[4,1])#,aspect=1)
# ax5 = Axis(fig[5,1],yscale=log10)#,aspect=1)

# # ax1,return_rot_matrix = MAVEN_plot.VDF_2d_slip(ax1,vv_mso, data_points;
# #     normal_vectors=[E_cross_B,bvec],
# #     vbluk=vvec_0,
# #     magf=bvec, 
# #     colorrange=(1e-13, 1e-9), 
# #     angle_range=[-30, 30], 
# #     ylabel="", 
# #     xlabel="", 
# #     plot_range=(-1000, 1000), 
# #     return_rot_matrix=true,  show_data=true)
# # fig


# phi = 2π .- data[:phi]
# theta = 0.5π .- data[:theta]
# energy = data[:energy]
# # time_range = [DateTime(2022,6,12,3,40),DateTime(2022,6,12,10,50)]
# time_range = [DateTime(2022,6,12,9,40),DateTime(2022,6,12,10,20)]
# time_range_i = findall(x->time_range[1]<=x<=time_range[2],data[:epoch])
# time_range_mat = findall(x->time_range[1]<=x<=time_range[2],time_mat)
# data1 = sum(data[:differential_flux][time_range_i,1,:,:,:],dims=4)[:,:,:,1]
# heatmap!(ax1,data[:time_unix][time_range_i],phi./3.14159.*180,sum(data1,dims=3)[:,:,1],colormap=:viridis,colorrange=(10^3.5,10^6.5),colorscale=log10)
# heatmap!(ax2,data[:time_unix][time_range_i],theta./3.14159.*180,sum(data1,dims=2)[:,1,:],colormap=:viridis,colorrange=(10^3.5,10^6.5),colorscale=log10)

# #MSO
# vel_mso = copy(vels[:,1,:])
# vel_df = copy(vel_mso)
# for i in time_range_i
#     local t_minpa = data[:epoch][i]
#     local t_timeb_i = findtime(timeb,t_minpa)
#     local rot = rotspc2mso[t_timeb_i,:,:]
#     vel_mso[i,:] = rot*vels[i,1,:]

#     data_energy_filter = data[:psd][i,1,:,:,:]
#     data_energy_filter[:,:,findall(energy.<200)].=0 # 解除能量小于一定程度的数据
#     local ind = findmax( data_energy_filter|> vec)[2]
#     vel_df[i,:] = rot*vv[ind,:]
# end

# lines!(ax3,data[:time_unix][time_range_i],vel_mso[time_range_i,1];color=:red)
# lines!(ax3,data[:time_unix][time_range_i],vel_mso[time_range_i,2];color=:blue)
# lines!(ax3,data[:time_unix][time_range_i],vel_mso[time_range_i,3];color=:green)

# scatter!(ax3,data[:time_unix][time_range_i],vel_df[time_range_i,1];color=:red)
# scatter!(ax3,data[:time_unix][time_range_i],vel_df[time_range_i,2];color=:blue)
# scatter!(ax3,data[:time_unix][time_range_i],vel_df[time_range_i,3];color=:green)

# lines!(ax3,time_mat_unix[time_range_mat],VH[time_range_mat,1];color=:red,linestyle=:dash)
# lines!(ax3,time_mat_unix[time_range_mat],VH[time_range_mat,2];color=:blue,linestyle=:dash)
# lines!(ax3,time_mat_unix[time_range_mat],VH[time_range_mat,3];color=:green,linestyle=:dash)

# #SPC
# # VH_spc = copy(VH)
# # for i in time_range_mat
# #     local t_timeb_i = findtime(timeb,time_mat[i])
# #     local rot = inv(rotspc2mso[t_timeb_i,:,:])
# #     VH_spc[i,:] = rot * VH[i,:]
# # end

# # lines!(ax3,data[:time_unix][time_range_i],vels[time_range_i,1,1];color=:red)
# # lines!(ax3,data[:time_unix][time_range_i],vels[time_range_i,1,2];color=:blue)
# # lines!(ax3,data[:time_unix][time_range_i],vels[time_range_i,1,3];color=:green)

# # lines!(ax3,time_mat_unix[time_range_mat],VH_spc[time_range_mat,1];color=:red,linestyle=:dash)
# # lines!(ax3,time_mat_unix[time_range_mat],VH_spc[time_range_mat,2];color=:blue,linestyle=:dash)
# # lines!(ax3,time_mat_unix[time_range_mat],VH_spc[time_range_mat,3];color=:green,linestyle=:dash)


# lines!(ax4,data[:time_unix][time_range_i],den[time_range_i,1])
# lines!(ax4,time_mat_unix[time_range_mat],nH[time_range_mat];linestyle=:dash)

# data1 = sum(data[:differential_flux][time_range_i,1,:,:,:],dims=2:3)[:,1,1,:]
# heatmap!(ax5,data[:time_unix][time_range_i],energy,data1,colormap=:viridis,colorrange=(10^3.5,10^6.5),colorscale=log10)
# fig