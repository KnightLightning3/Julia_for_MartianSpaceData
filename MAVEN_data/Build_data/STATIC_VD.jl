# 制作STATIC的速度, 密度的cdf文件包, 默认为MSO坐标系,d1数据集
# using PyCall
# cdflib = pyimport("cdflib")
using Dates
using ProgressMeter
using FortranFiles
using Base.Threads
using Quaternions
@spawn :interactive f()
include("../MAVEN_load.jl")
include("../MAVEN_STATIC.jl")
import .MAVEN_load;
import .MAVEN_STATIC;

@inline function get_ion_vel(vsc_data,ion_data)
    sta_epoch = ion_data[:epoch]
    position = ion_data[:pos_sc_mso]
    quality_flag = ion_data[:quality_flag]

    ntime = length(sta_epoch)
    H_vel = zeros(ntime, 3)
    O_vel = zeros(ntime, 3)
    O2_vel = zeros(ntime, 3)
    H_den = zeros(ntime)
    O_den = zeros(ntime)
    O2_den = zeros(ntime)
    H_f = zeros(ntime, 3)
    O_f = zeros(ntime, 3)
    O2_f = zeros(ntime,3)

    time_vsc = vsc_data[:epoch]
    vsc = vsc_data[:vsc]

    @inbounds @showprogress for time_ind in 1:ntime
        dt,time_vsc_ind = findmin(x -> abs(x - sta_epoch[time_ind]), time_vsc)
        if dt >= Millisecond(2*1000)
            O2_vel[time_ind, 1:3] .= NaN32
            O2_f[time_ind,1:3] .= NaN32
            O2_den[time_ind] = NaN32

            O_vel[time_ind, 1:3] .= NaN32
            O_f[time_ind,1:3] .= NaN32
            O_den[time_ind] = NaN32
 
            H_vel[time_ind, 1:3] .= NaN32
            H_f[time_ind,1:3] .= NaN32
            H_den[time_ind] = NaN32
            continue
        end
        dat_slip = MAVEN_STATIC.static_slip(ion_data, time_ind)
        # dat_slip = MAVEN_STATIC.static_rotation(dat_slip; frame="MSO")
        rotation_Q = QuaternionF64(dat_slip[:quat_mso][1], dat_slip[:quat_mso][2], dat_slip[:quat_mso][3], dat_slip[:quat_mso][4]);

        dat_slip = MAVEN_STATIC.STA_count2df_no_m_int(dat_slip)
        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[20, 40], m_int=32,unit_cover=false)
        O2_vel[time_ind, 1:3] = MAVEN_STATIC.rotate_vector_with_quat(vel, rotation_Q) .+ vsc[time_vsc_ind,:]
        O2_f[time_ind,1:3] = MAVEN_STATIC.rotate_vector_with_quat(flux, rotation_Q)
        O2_den[time_ind] = den
        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[10, 20], m_int=16,unit_cover=false)
        O_vel[time_ind, 1:3] = MAVEN_STATIC.rotate_vector_with_quat(vel, rotation_Q) .+ vsc[time_vsc_ind,:]
        O_f[time_ind,1:3] = MAVEN_STATIC.rotate_vector_with_quat(flux, rotation_Q)
        O_den[time_ind] = den
        vel, flux, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 1e5], mass_range=[0, 2], m_int=1,unit_cover=false)
        H_vel[time_ind, 1:3] = MAVEN_STATIC.rotate_vector_with_quat(vel, rotation_Q) .+ vsc[time_vsc_ind,:]
        H_f[time_ind,1:3] = MAVEN_STATIC.rotate_vector_with_quat(flux, rotation_Q)
        H_den[time_ind] = den
    end
    datas_dict = Dict{Symbol,Any}(
        :epoch => sta_epoch,
        :H_vel => H_vel,
        :O_vel => O_vel,
        :O2_vel => O2_vel,
        :H_den => H_den,
        :O_den => O_den,
        :O2_den => O2_den,
        :H_f => H_f,
        :O_f => O_f,
        :O2_f => O2_f,
        :pos => position,
        :quality_flag => quality_flag
    )
    return datas_dict
end
@inline function data2bi(datas_dict,filename)
    time = datetime2unix.(datas_dict[:epoch])
    Ntime = length(time)

    time_unix = convert(Vector{Float64},time)

    O_vel = convert(Array{Float32,2},datas_dict[:O_vel])
    O2_vel = convert(Array{Float32,2},datas_dict[:O2_vel])
    H_vel = convert(Array{Float32,2},datas_dict[:H_vel])

    O_f = convert(Array{Float32,2},datas_dict[:O_f])
    O2_f = convert(Array{Float32,2},datas_dict[:O2_f])
    H_f = convert(Array{Float32,2},datas_dict[:H_f])

    O_den = convert(Vector{Float32},datas_dict[:O_den])
    O2_den = convert(Vector{Float32},datas_dict[:O2_den])
    H_den = convert(Vector{Float32},datas_dict[:H_den])

    pos = convert(Array{Float32,2},datas_dict[:pos])
    quality_flag = convert(Vector{Int8},datas_dict[:quality_flag])

    f = FortranFile(filename,"w")
    write(f, Ntime)
    write(f, time_unix)
    
    write(f, H_vel)
    write(f, O_vel)
    write(f, O2_vel)
    
    write(f, H_f)
    write(f, O_f)
    write(f, O2_f)
    
    write(f, H_den)
    write(f, O_den)
    write(f, O2_den)
    
    write(f, pos)
    write(f, quality_flag)
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
        print("\033[0;32mBuilding $(date)\033[0m \n")
        # println(file_vsc)
        vsc_data = MAVEN_load.load_mag_vsc(file_vsc)
        ion_data = MAVEN_load.load_STATIC(file_ion)
        datas_dict = get_ion_vel(vsc_data,ion_data)
        touch(new_path)
        try
            data2bi(datas_dict,new_path)
        catch e
            print("\033[0;31mERROR: $(e)\033[0m \n")
            rm(new_path)
        end
        
    else
        print("\033[0;33mSKIP $(date)\033[0m \r")
    end
end