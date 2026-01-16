# 制作STATIC的速度, 密度的cdf文件包, 默认为MSO坐标系,d1数据集
using Dates
using ProgressMeter
using FortranFiles
# using Polyester: @batch
using Base.Threads
using Rotations
@spawn :interactive f()
include("../MAVEN_load.jl");import .MAVEN_load;
include("../MAVEN_STATIC.jl");import .MAVEN_STATIC;

@inline function get_ion_vel(vsc_data,ion_data)
    # local sta_epoch = ion_data[:epoch]
    local time_unix = ion_data[:time_unix]
    local position = ion_data[:pos_sc_mso]
    local mag = ion_data[:magf]
    local quality_flag = ion_data[:quality_flag]

    local ntime = length(time_unix)
    local H_vel = fill(NaN32,ntime, 3)
    local He_vel = fill(NaN32,ntime, 3)
    local O_vel = fill(NaN32,ntime, 3)
    local O2_vel = fill(NaN32,ntime, 3)
    local H_den = fill(NaN32,ntime)
    local He_den = fill(NaN32,ntime)
    local O_den = fill(NaN32,ntime)
    local O2_den = fill(NaN32,ntime)
    local H_f = fill(NaN32,ntime, 3)
    local He_f = fill(NaN32,ntime, 3)
    local O_f = fill(NaN32,ntime, 3)
    local O2_f = fill(NaN32,ntime,3)
    local vsc_quality = fill(true,ntime)

    local time_vsc = vsc_data[:time_unix]
    local vsc = vsc_data[:vsc]

    @info "开始计算: 共有$(ntime)个时间点,使用$(Threads.nthreads())个线程"

    @showprogress Threads.@threads for time_ind in 1:ntime
        # local dt,time_vsc_ind = findmin(x -> abs(x - time_unix[time_ind]), time_vsc)
        time_vsc_ind = searchsortedfirst(time_vsc, time_unix[time_ind])
        time_vsc_ind = clamp(time_vsc_ind, 1, length(time_vsc))
        dt = abs(time_vsc[time_vsc_ind] - time_unix[time_ind])
        if dt >= 2
            vsc_quality[time_ind] = false
            continue # 缺少vsc数据
        end
        local dat_slip = MAVEN_STATIC.static_slip(ion_data, time_ind)
        local rotation_Q = QuatRotation(dat_slip[:quat_mso]);

        local dat_slip = MAVEN_STATIC.STA_count2df(dat_slip)

        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[20, 40], m_int=32,unit_cover=false)
        O2_vel[time_ind, 1:3] =rotation_Q * vel .+ @view vsc[time_vsc_ind,:]
        O2_f[time_ind,1:3] = rotation_Q * flux
        O2_den[time_ind] = den
        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[10, 20], m_int=16,unit_cover=false)
        O_vel[time_ind, 1:3] = rotation_Q * vel .+ @view vsc[time_vsc_ind,:]
        O_f[time_ind,1:3] = rotation_Q * flux
        O_den[time_ind] = den
        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[0, 1.3], m_int=1,unit_cover=false)
        H_vel[time_ind, 1:3] = rotation_Q * vel .+ @view vsc[time_vsc_ind,:]
        H_f[time_ind,1:3] = rotation_Q * flux
        H_den[time_ind] = den
        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[1.4, 3.3], m_int=2,unit_cover=false)
        He_vel[time_ind, 1:3] = rotation_Q * vel .+ @view vsc[time_vsc_ind,:]
        He_f[time_ind,1:3] = rotation_Q * flux
        He_den[time_ind] = den
    end

    datas_dict = (
        time_unix = time_unix,
        H_vel = H_vel,
        He_vel = He_vel,
        O_vel = O_vel,
        O2_vel = O2_vel,
        H_den = H_den,
        He_den = He_den,
        O_den = O_den,
        O2_den = O2_den,
        H_f = H_f,
        He_f = He_f,
        O_f = O_f,
        O2_f = O2_f,
        pos = position,
        mag = mag,
        quality_flag = quality_flag,
        vsc_quality = vsc_quality,
    )
    return datas_dict
end
@inline function data2bi(datas_dict,filename)
    time = datas_dict.time_unix
    Ntime = length(time)

    time_unix = convert(Vector{Float64},time)

    O_vel = convert(Array{Float32,2},datas_dict.O_vel)
    O2_vel = convert(Array{Float32,2},datas_dict.O2_vel)
    H_vel = convert(Array{Float32,2},datas_dict.H_vel)
    He_vel = convert(Array{Float32,2},datas_dict.He_vel)

    O_f = convert(Array{Float32,2},datas_dict.O_f)
    O2_f = convert(Array{Float32,2},datas_dict.O2_f)
    H_f = convert(Array{Float32,2},datas_dict.H_f)
    He_f = convert(Array{Float32,2},datas_dict.He_f)

    O_den = convert(Vector{Float32},datas_dict.O_den)
    O2_den = convert(Vector{Float32},datas_dict.O2_den)
    H_den = convert(Vector{Float32},datas_dict.H_den)
    He_den = convert(Vector{Float32},datas_dict.He_den)

    pos = convert(Array{Float32,2},datas_dict.pos)
    mag = convert(Array{Float32,2},datas_dict.mag)
    quality_flag = convert(Vector{Int16},datas_dict.quality_flag)
    vsc_quality = convert(Vector{Bool},datas_dict.vsc_quality)

    f = FortranFile(filename,"w")
    write(f, Ntime)
    write(f, time_unix)
    
    write(f, H_vel)
    write(f, He_vel)
    write(f, O_vel)
    write(f, O2_vel)
    
    write(f, H_f)
    write(f, He_f)
    write(f, O_f)
    write(f, O2_f)
    
    write(f, H_den)
    write(f, He_den)
    write(f, O_den)
    write(f, O2_den)

    write(f, pos)
    write(f, mag)
    write(f, quality_flag)
    write(f, vsc_quality)
    close(f)
end
#获取所有文件和对应的mag文件
files_ion = MAVEN_load.file_list("STATIC_d1")
files_mag = MAVEN_load.file_list("MAG_ss1s_vsc")
dates_ion = [(m.captures[1] ,s) for s in files_ion for m in eachmatch(r"_([0-9]{8})_", s)]
dates_mag = [(m.captures[1] ,s) for s in files_mag for m in eachmatch(r"_([0-9]{8})_", s)]
common_dates = [
    (date, files_ion[i], files_mag[j]) 
    for (i, (date, _)) in enumerate(dates_ion) 
    for (j, (date2, _)) in enumerate(dates_mag)
    if date == date2
]
for (date, file_ion, file_vsc) in common_dates
    ion_version = match(r"_v([0-9]{2})_", file_ion).captures[1]
    new_path = dirname(replace(file_ion, "/l2/" => "/l3/"))*"/mvn_sta_l3_d1_vel_flux_den_$(date)_v$(ion_version).f77_unformatted"
    dir = dirname(new_path)
    if !isdir(dir)
        mkpath(dir)
    end
    if !isfile(new_path)
        @time begin 
            print("\033[0;32mReading $(date)\033[0m \r")
            # println(file_vsc)
            local vsc_data = MAVEN_load.load_mag_vsc(file_vsc)
            local ion_data = MAVEN_load.load_cdf(file_ion)
            print("\033[0;32mBuilding $(date)\033[0m \n")
            local datas_dict = get_ion_vel(vsc_data,ion_data)
            touch(new_path)
            try
                print("\033[0;32mWriting $(date)\033[0m \r")
                data2bi(datas_dict,new_path)
                print("\033[0;32mDone Writing $(date)\033[0m \r")
            catch e
                print("\033[0;31mERROR: $(e)\033[0m \n")
                rm(new_path)
            end
        end
        
    else
        print("\033[0;33mSKIP $(date)\033[0m \r")
    end
end