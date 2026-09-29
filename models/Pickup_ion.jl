# 计算并载入单日拾取数据的程序，建议使用include执行，需要预先准备：time_event=DateTime；instrument_mode = "swi" or "sta"，spice_name = "p+"，天问minpa可以以类似方式整合进去

include("../common/head.jl")
include("../common/function_coordinate.jl")


# E in keV, σ in cm^2，lindsayChargeTransferCross2005 电荷交换电离率
σex(E) = (4.15-0.531*log(E))^2*(1-exp(-67.3/E))^4.5 * 1e-16

function func_E_range(E,dE) # 对数能量分割法
        local R = dE/E
        local k_sqrt = R/2 + sqrt((R/2)^2+1)
        return (E/k_sqrt,E*k_sqrt)
end
function get_3d_slip_data_from_ins_FOR_PICKUP(dat,time_i;mode = "swi",mass_range = [0,1.3],m_int=1) # 读取仪器切片数据
    # local time0_local = dat[:epoch][time_i]
    if mode == "swi"
        local quat_mso = dat[:quat_mso][time_i]
        # 定义基本量
        local df_data = dat[:df][time_i,:,:,:]
        local energy= reshape(dat[:energy],1,1,48)
        local denergy = energy .* 0.15
        local phi_0 = reshape(dat[:phi],16,1,1) # 注意,此模式下phi的范围在0-360deg
        local dphi = 22.5
        local theta =  reshape(dat[:theta][time_i,:,:],1,4,48)
        local dtheta =  reshape(dat[:dtheta][time_i,:,:],1,4,48)

        local mass = dat[:mass]
        local bins_sc = ones(Int32,size(df_data))

        local Const = mass^(-1.5)*2.0^(0.5)
        local d_V = Const.*denergy.*sqrt.(energy)  .* 2.0 .* cosd.(theta).*sind.(dtheta./2.0).*deg2rad(dphi) #|>vec # 取得仪器坐标系下的体积分
        local phi = atand.(sind.(phi_0),cosd.(phi_0)) # 处理掉swi的phi问题
        local sta_mode = 1
        local quality_flag = 1

    elseif mode == "sta"
        local d1_data_slip = MAVEN_STATIC.static_slip(dat,time_i)
        local d1_data_slip = MAVEN_STATIC.STA_count2df(d1_data_slip)
        local quat_mso = QuatRotation(d1_data_slip[:quat_mso])
        # 定义基本量
        local mass_mask = mass_range[1] .<= d1_data_slip[:mass_arr] .<= mass_range[2]
        local func_reshape = x -> permutedims(reshape(x,4,16,32), (2,1, 3))

        local df_data     = sum(d1_data_slip[:df_mass_mass].*mass_mask.*m_int^2,dims=1)[1,:,:] |> func_reshape
        
        local energy      = d1_data_slip[:energy][1,:,:] |> func_reshape
        local denergy     = d1_data_slip[:denergy][1,:,:] |> func_reshape
        local phi         = d1_data_slip[:phi][1,:,:] |> func_reshape
        local dphi        = d1_data_slip[:dphi][1,:,:] |> func_reshape
        local theta       = d1_data_slip[:theta][1,:,:] |> func_reshape
        local dtheta      = d1_data_slip[:dtheta][1,:,:] |> func_reshape
        local bins_sc     = reshape(d1_data_slip[:bins_sc],64,1) .* ones(Int32,(64,32))  |> func_reshape
        # 计算速度分布
        local mass = d1_data_slip[:mass]
        local d_V = (mass*m_int)^(-1.5)*2.0^(0.5).*denergy.*sqrt.(energy)  .* 2.0 .* cosd.(theta).*sind.(dtheta./2.0).*deg2rad.(dphi) #|>vec # 取得仪器坐标系下的体积分、
        local sta_mode = d1_data_slip[:mode]
        local quality_flag = d1_data_slip[:quality_flag]
        # println(size(sta_mode)," ,",size(quality_flag))
        
    elseif mode == "minpa"

        local mass = dat[:mass]

        local i_mass = findfirst(mass .== m_int)

        local nenergy = dat[:nenergy]
        local ntheta  = dat[:ntheta]
        local nphi    = dat[:nphi]

        local energy      = reshape(dat[:energy],1,1,nenergy)
        local denergy     = reshape(dat[:denergy],1,1,nenergy)
        
        local phi         = reshape(dat[:phi],nphi,1,1) .|> rad2deg
        local dphi        = dat[:dphi] |> rad2deg
        
        local theta       = reshape(dat[:theta],1,ntheta,1) .|> rad2deg
        local dtheta      = reshape(dat[:dtheta],1,ntheta,1) .|> rad2deg
        
        local energy_mask = energy .>= 100

        local df_data = dat[:psd][time_i,i_mass,:,:,:].*1e3 .* energy_mask

        if m_int == 1 
            local v0 = TW_minpa_data[:v0_H]
        end

        local d_V = v0.^3 .* sind.(theta) .* deg2rad.(dtheta) .*deg2rad(dphi) .* 0.1 # 取得仪器坐标系下的体积分

        local bins_sc = ones(Int32,size(df_data))

        local quat_mso = TW_minpa_data[:rot][time_i]
        local sta_mode = 0
        local quality_flag = 0
    end
    local shaped_matrix = ones(size(df_data)) # 将所有坐标扩展到和eflux相同的维度
    
    Energy_ranges = [func_E_range(E,dE) for (E,dE) in zip(energy.*shaped_matrix,denergy.*shaped_matrix)]
    local theta_ranges = [(x - dx/2, x + dx/2) for (x,dx) in zip(theta.*shaped_matrix,dtheta.*shaped_matrix)]
    local phi_ranges =  [(round(x - dx/2,digits=1), round(x + dx/2,digits=1)) for (x,dx) in zip(phi.*shaped_matrix,dphi.*shaped_matrix)]

    return (
        quat_mso      = quat_mso,
        df_data       = df_data,
        energy        = energy.*shaped_matrix,
        d_V           = d_V.*shaped_matrix, # 体积元大小
        bins_sc       = bins_sc, # 飞行器遮掩， swi默认全部有效
        energy_ranges = Energy_ranges,
        theta_ranges  = theta_ranges,
        phi_ranges    = phi_ranges,
        mode = sta_mode,
        quality_flag = quality_flag
    )
end
function get_pickup_point(pick_points_sphere,energy_range_data,theta_range_data,phi_range_data) # 较高效率取得拾取分布
    
    local energy_pick_points = [p[1] for p in pick_points_sphere]
    local theta_pick_points  = [p[2] for p in pick_points_sphere]
    local phi_pick_points    = [p[3] for p in pick_points_sphere] #球坐标的第一维度为模长
    
    local phi_index = zeros(Int32,length(pick_points_sphere))
    @inbounds for (i,Pp) in enumerate(phi_pick_points)
        for (iP,ee) in enumerate(phi_range_data)
            if ee[1] <= Pp <= ee[2]
                phi_index[i] = iP
                break
            end
        end
    end
    local phi_range_bool = phi_index .!= 0
    local energy_index = zeros(Int32,length(pick_points_sphere))

    @inbounds for (i,Ep) in enumerate(energy_pick_points)
        for (iE,ee) in enumerate(energy_range_data)
            if ee[1] <= Ep <= ee[2]
                energy_index[i] = iE
                break
            end
        end
    end
    local energy_range_bool = energy_index .!= 0 .&& phi_range_bool# 是否在指定能量和phi范围内

    local theta_index = zeros(Int32,length(pick_points_sphere))

    @inbounds for (i,iE) in enumerate(energy_index)
        if energy_range_bool[i]
            for (iT,tt) in enumerate(theta_range_data[:,iE])
                if tt[1] <= theta_pick_points[i] <= tt[2]
                    theta_index[i] = iT
                    break
                end
            end
        end
    end
    local range_bool = theta_index .!= 0 .&& energy_range_bool#是否在指定theta和energy范围内
    local data_index = [(i,j,k,e) for (i,j,k,e) in zip(energy_index[range_bool],theta_index[range_bool],phi_index[range_bool],energy_pick_points[range_bool])]
    return data_index
end

if instrument_mode == "swi"
    global spice_name = "p+"
    @info "SWI数据为全质子"
elseif instrument_mode == "sta" && spice_name == "p+"
    @error "不能用全质子方式规定STA数据,已经设定为H+"
    global spice_name = "H+"
elseif instrument_mode == "sta"
    @info "STA选择$spice_name"
end

pickup_circle = 0:0.01:2π
m_int = spice_dict[spice_name][:m_int]
mass_range = spice_dict[spice_name][:mass_range]
energy_range = spice_dict[spice_name][:energy_range]


time_range = [time_event - dtime, time_event + dtime]
time_event = time_event

current_date_str = Dates.format(time_event,"yyyymmdd")
try
    global date_str = Dates.format(MAVEN_data["SWIA_coarse_svy_3d"][:epoch][1],"yyyymmdd")
catch
    global date_str = "000"
end
if !(current_date_str == date_str)
    try
        @load "data/MAVEN_$(Dates.format(time_event,"yyyymmdd")).jld2" MAVEN_data
        global MAVEN_data
        @info "从二进制文件读取MAVEN数据完成"
        global d1_data = MAVEN_data["STATIC_d1"]
        global c6_mass_data =  MAVEN_data["c6_mass"]
        global d1_v4d_data = MAVEN_data["STATIC_d1_v4d"]
        global swi3d_data = MAVEN_data["SWIA_coarse_svy_3d"]
        global swi2d_data = MAVEN_data["SWIA_svy_spec"]
        global swi_mom_data = MAVEN_data["SWIA_mom"]
        global d1_v4d_data = MAVEN_data["STATIC_d1_v4d"]
    catch
        if !isdefined(Main, :MAVEN_load)
            pkg_path = "D:/CODE/Package_for_Julia/"
            include(pkg_path*"MAVEN_data/MAVEN_load.jl");import .MAVEN_load;
            include(pkg_path*"MAVEN_data/MAVEN_plot.jl");import .MAVEN_plot;
            include(pkg_path*"MAVEN_data/MAVEN_STATIC.jl");import .MAVEN_STATIC;
            include(pkg_path*"MAVEN_data/MAVEN_SWIA.jl");import .MAVEN_SWIA;
            include(pkg_path*"Magnetic_Model/IGRF_calculate.jl");import .IGRF_calculate;
        end
        global swi_mom_data = MAVEN_load.data_get_from_date(time_event, model_index=["SWIA_mom"], show_filename=false)["SWIA_mom"]

        if !swi_mom_data[:data_load_flag]
            error("MOM data load failed")
        end

        KP_data = MAVEN_load.data_get_from_date(time_event, model_index=["KP_l3"], show_filename=false)["KP_l3"]

        global is_in_sw_bool_all_day = false# 一整天的数据存在出太阳风的部分
        @inbounds for i in eachindex(KP_data[:time])
            local P_mso = (KP_data[:vars][:var_190][i],KP_data[:vars][:var_191][i],KP_data[:vars][:var_192][i])
            local is_in_sw_bool = bowshock_zero(P_mso[1]/3393.5) < sqrt(P_mso[3]^2 + P_mso[2]^2)/3393.5
            if is_in_sw_bool
                global is_in_sw_bool_all_day = true
                break
            end
        end
        if !is_in_sw_bool_all_day
            error("跳过 $time_event 的拾取密度计算，原因：全天MAVEN均不在太阳风中")
        end

        global MAVEN_data
        model_index = [
            "MAG_ss1s_cdf",
            "STATIC_d1",
            "SWIA_coarse_svy_3d",
            "SWIA_quat",
        ]
        @time MAVEN_data = MAVEN_load.data_get_from_date(time_event, model_index=model_index, show_filename=false)

        MAVEN_data["KP_l3"] = KP_data
        println("读取 $time_event 数据完成")

        if !MAVEN_data["STATIC_d1"][:data_load_flag]
            error("STATIC_d1 data load failed")
        end
        if !MAVEN_data["SWIA_coarse_svy_3d"][:data_load_flag]
            error("SWIA_coarse_svy_3d data load failed")
        end
        global d1_data = MAVEN_data["STATIC_d1"] |> MAVEN_STATIC.STA_count2df_all
        MAVEN_data["STATIC_d1"] = d1_data
        global swi3d_data = MAVEN_SWIA.get_3dc!(MAVEN_data["SWIA_coarse_svy_3d"]; quat_data = MAVEN_data["SWIA_quat"])
        global swi3d_data = MAVEN_SWIA.eflux2df!(swi3d_data)
        MAVEN_data["SWIA_coarse_svy_3d"] = swi3d_data
        # 磁场平滑化
        time_b_ss,B_ss,P_ss = MAVEN_data["MAG_ss1s_cdf"][:epoch],MAVEN_data["MAG_ss1s_cdf"][:B],MAVEN_data["MAG_ss1s_cdf"][:position]
        fs = 1
        f0 = 0.01
        Wn = f0 / (fs / 2)
        B_ss[isnan.(B_ss)] .= 0
        B_ss_filtered = stack([filtfilt(digitalfilter(Lowpass(Wn), Butterworth(4)), B_ss[:, i]) for i in 1:3]); 
        MAVEN_data["MAG_ss1s_cdf"][:B_filtered] = B_ss_filtered
        @info "读取MAVEN数据完成"
    end
end
time_B_ss,B_ss = MAVEN_data["MAG_ss1s_l3"][:epoch],MAVEN_data["MAG_ss1s_l3"][:B]
B_ss_filtered = MAVEN_data["MAG_ss1s_l3"][:B_filtered]
P_ss = MAVEN_data["MAG_ss1s_l3"][:position]
Mars_distance = MAVEN_data["KP_l3"][:vars][:var_213][1]

time_range_d1 = find_time_range(d1_data[:epoch],time_range)
time_range_b = find_time_range(time_B_ss,time_range.+[-Minute(1),Minute(1)])
time_range_swi = find_time_range(swi3d_data[:epoch],time_range.+[-Minute(1),Minute(1)])
time_range_mom =find_time_range(swi_mom_data[:epoch],time_range)
x_range_unix = datetime2unix.(time_range)
xtimes, x_i = MAVEN_plot.time_ticks(time_range;step=Minute(10), format="HH:MM")

# 根据仪器重整数据结构到相同的维度
if instrument_mode == "sta"
    data1 = d1_data
    time_range_i = time_range_d1
    time_data1_unix = d1_data[:time_unix]
    time_plot  = d1_data[:time_unix][time_range_i]
    bins_sc = reshape(d1_data[:bins_sc][time_range_i,:],length(time_range_i),4,16,1)
    swp_ind    = d1_data[:swp_ind][time_range_i[1]] + 1
    mass_mask  = reshape(mass_range[1] .<= d1_data[:mass_arr][:,:,:,swp_ind] .<= mass_range[2],1,8,64,32)
    eflux_plot = reshape(sum(d1_data[:eflux][time_range_i,:,:,:].*mass_mask,dims=2)[:,1,:,:],length(time_range_i),4,16,32) .*bins_sc
    psd_plot   = reshape(sum(d1_data[:df_mass_mass][time_range_i,:,:,:].*mass_mask.*m_int^2,dims=2)[:,1,:,:],length(time_range_i),4,16,32) .*bins_sc
    eflux_plot = permutedims(eflux_plot, (1,3, 2, 4))
    psd_plot = permutedims(psd_plot, (1,3, 2, 4))
    phi0 = reshape(d1_data[:phi][1,:,:,swp_ind],4,16,32)[1,:,1]
    energy_plot = d1_data[:energy][1,1,:,swp_ind]
elseif instrument_mode == "swi"
    data1 = swi3d_data
    quat_quality = swi3d_data[:quat_quality][time_range_swi]
    time_range_i = time_range_swi[:quat_quality]
    time_data1_unix =  swi3d_data[:time_unix]
    time_plot  = swi3d_data[:time_unix][time_range_i]
    eflux_plot = swi3d_data[:diff_en_fluxes][time_range_i,:,:,:]
    psd_plot   = swi3d_data[:df][time_range_i,:,:,:]
    energy_plot = swi3d_data[:energy][1,:]
    phi0 = atand.(sind.(swi3d_data[:phi]),cosd.(swi3d_data[:phi]))
    theta0 = swi3d_data[:theta]
end

pick_points_data = [[] for i in 1:16, j in 1:4]
pick_points_data_O = [[] for i in 1:16, j in 1:4]
pick_points_count = zeros(length(time_range_i),16,4,data1[:nenergy])
time_mom_unix = swi_mom_data[:epoch] .|> datetime2unix
time_ss_unix = time_B_ss .|> datetime2unix
points_data_df = DataFrame(  # 数据集
    time_unix = Float64[],
    pickup_count= Int32[],       # 存在拾取离子的bin的计数
    scale_rate = Float32[],      # 积分放大倍数
    pickup_density = Float32[],  # 拾取密度
    total_density = Float32[],   # 总密度~太阳风密度
    pickup_rate = Float32[],     # 拾取率
    pickup_flux = Float32[],     # F = n_pickup * U_sw * sin(θ_sw)
    pos_x = Float32[], pos_y = Float32[], pos_z = Float32[], #位置信息，km
    mag_x = Float32[], mag_y = Float32[], mag_z = Float32[], #磁场信息，nT
    v_x = Float32[], v_y = Float32[], v_z = Float32[], #速度信息，km/s
    quality_flag = Int16[], #sta的质量标识
    mode = Int16[],#sta的模式标识
    I_cx = Float64[],#电荷交换电离率
)#所有点的数据集
@info "使用平均后的磁场"

@inbounds @showprogress for (itime,time_index) in enumerate(time_range_i)
    local local_result = get_3d_slip_data_from_ins(data1, time_index; mode = instrument_mode, m_int = m_int, mass_range = mass_range) # 返回局地的数据结果
    local time0_unix = time_data1_unix[time_index]
    local it_mom = time_range_mom[find_time(time_mom_unix[time_range_mom],time0_unix)]
    local it_ss = time_range_b[find_time(time_ss_unix[time_range_b],time0_unix)]
    local V_mso = swi_mom_data[:velocity_mso][it_mom,:]
    local N0 = swi_mom_data[:density][it_mom,:]
    # local B_mso = B_ss[it_ss,:]
    local B_mso = B_ss_filtered[it_ss,:]
    local P_mso = P_ss[it_ss,:]
    
    # 制作拾取速度分布圆环
    local V_vec_sw = SVector{3}(local_result.quat_mso' * V_mso)# 仪器坐标系方向的太阳风
    local X_vec = SVector{3}(local_result.quat_mso' * [1.0,0.0,0.0])# 仪器坐标系方向的MSO X方向
    local B_vec = SVector{3}(local_result.quat_mso' * B_mso)# 仪器坐标系方向的磁场
    local E_vec = normalize(cross(-normalize(V_vec_sw),normalize(B_vec))) # 仪器坐标下太阳风电场方向
    local rot_bv = slice2d_cal_rot(B_vec,E_vec)# 从仪器坐标系旋转到平行坐标系下

    local v_n = norm(V_vec_sw) # 速度模
    local bv_angle = get_angle(B_vec,V_vec_sw)
    local pickup_point_bv = SVector{2}(π-deg2rad(bv_angle), v_n) # bv参考系下的拾取位置

    local x1 ,y1 = -v_n*cosd(bv_angle),v_n*sind(bv_angle);
    local pick_points_instrument = [SVector{3}(rot_bv'*[x1,y1*cos(i),y1*sin(i)].+V_vec_sw) for i in pickup_circle]; # 仪器坐标系下的拾取速度分布圆环

    local v0_sphere_pick_points = STATIC_xyz2sphere.(pick_points_instrument);
    local v0_pick_points = [p[1] for p in v0_sphere_pick_points] #球坐标的第一维度为模长
    local energy_pick_points = ion_v2energy.(v0_pick_points.*1e3;m_int = m_int)
    local pick_points_sphere = [SVector{3}(r,pp[2],pp[3]) for (r,pp) in zip(energy_pick_points,v0_sphere_pick_points)] # 仪器球坐标系Energy-theta-phi下的拾取分布
    local energy_pick_points_O = ion_v2energy.(v0_pick_points.*1e3;m_int = 16) # 8倍太阳风能量
    local pick_points_sphere_O = [SVector{3}(r,pp[2],pp[3]) for (r,pp) in zip(energy_pick_points_O,v0_sphere_pick_points)] # 仪器球坐标系Energy-theta-phi下的拾取分布

    # 由于做出来的STA数据就是16*4*32的, 所以可以和swi共享同一个算法
    local energy = local_result.energy[1,1,:]
    local theta_range_data = local_result.theta_ranges[1,:,:]
    local energy_range_data = local_result.energy_ranges[1,1,:]
    local phi_range_data = local_result.phi_ranges[:,1,1]

    local data_index = get_pickup_point(pick_points_sphere,energy_range_data,theta_range_data,phi_range_data)
    local data_index_O = get_pickup_point(pick_points_sphere_O,energy_range_data,theta_range_data,phi_range_data)

    local pick_points_data_local = [[] for j in 1:16, i in 1:4]
    for (i,j,k,e) in data_index # r,t,p,e
        global pick_points_count[itime,k,j,i] += 1
        push!(pick_points_data_local[k,j],e)
        push!(pick_points_data[k,j],SVector{2,Float64}(time0_unix,e))
    end
    for (i,j,k,e) in data_index_O
        push!(pick_points_data_O[k,j],SVector{2,Float64}(time0_unix,e))
    end

    push!(points_data_df,
        (
            time_unix = time0_unix,
            result = local_result,
            V_mso = V_mso,
            B_mso = B_mso,
            P_mso = P_mso,
            E_vec = E_vec,
            B_vec = B_vec,
            V_vec = V_vec_sw,
            X_vec = X_vec,
            trans_rot = rot_bv,
            trans_p0 = V_vec_sw,
            bv_angle = bv_angle,
            density = N0[1],
            energy_local = energy,
            range_data = (
                energy=energy_range_data,
                theta=theta_range_data,
                phi=phi_range_data,
            ),
            pick_points = pick_points_data_local,
            pick_points_count = pick_points_count[itime,:,:,:],
            pick_points_sphere = pick_points_sphere,
            pick_points_instrument = pick_points_instrument
        )
    )
end