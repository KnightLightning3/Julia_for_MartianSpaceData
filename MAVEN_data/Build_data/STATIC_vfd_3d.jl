# 通过c6数据计算一维的STATIC速度,通量关系
using Dates
using ProgressMeter
using FortranFiles
using Base.Threads
include("../MAVEN_load.jl");import .MAVEN_load;
include("../MAVEN_STATIC.jl");import .MAVEN_STATIC;

@inline function get_ion_vel(vsc_data,ion_data)
    sta_epoch = ion_data[:epoch]
    vsc_epoch = vsc_data[:epoch]

    vsc = vsc_data[:vsc]

    vsc_sta = zeros(length(sta_epoch),3)

    for i in eachindex(sta_epoch)
        dt,vsc_epoch_ind = findmin(x -> abs(x - sta_epoch[i]), vsc_epoch)
        if dt >= Millisecond(2*1000)
            vsc_sta[i,:] .= 0
            continue
        end
        vsc_sta[i,:] = vsc[vsc_epoch_ind,:]
    end

    ion_data_f = MAVEN_STATIC.STA_count3df(ion_data)
    mass_range = Dict(
        :H => [0.5,1.5],
        :O => [13,19],
        :O2 => [20,40]
    )
    O_v,O_f,O_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:O],m_int = 16)
    O2_v,O2_f,O2_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:O2],m_int = 32)
    H_v,H_f,H_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:H],m_int = 1)

    datas_dict = Dict{Symbol,Any}(
        :epoch => sta_epoch,
        :H_v => H_v,
        :O_v => O_v,
        :O2_v => O2_v,
        :H_n => H_n,
        :O_n => O_n,
        :O2_n => O2_n,
        :H_f => H_f,
        :O_f => O_f,
        :O2_f => O2_f,
        :vsc => vsc_sta,
        :pos => ion_data[:pos_sc_mso],
        :quality_flag => ion_data[:quality_flag],
        :mode => ion_data[:mode],
        :mass_range => mass_range,
    )
    return datas_dict
end
@inline function data2bi(datas_dict,filename)
    time = datetime2unix.(datas_dict[:epoch])
    Ntime = length(time)

    time_unix = convert(Vector{Float64},time)

    O_vel = convert(Vector{Float32},datas_dict[:O_v])
    O2_vel = convert(Vector{Float32},datas_dict[:O2_v])
    H_vel = convert(Vector{Float32},datas_dict[:H_v])

    O_f = convert(Vector{Float32},datas_dict[:O_f])
    O2_f = convert(Vector{Float32},datas_dict[:O2_f])
    H_f = convert(Vector{Float32},datas_dict[:H_f])

    O_den = convert(Vector{Float32},datas_dict[:O_n])
    O2_den = convert(Vector{Float32},datas_dict[:O2_n])
    H_den = convert(Vector{Float32},datas_dict[:H_n])
    
    vsc = convert(Array{Float32,2},datas_dict[:vsc])
    pos = convert(Array{Float32,2},datas_dict[:pos])
    quality_flag = convert(Vector{Int16},datas_dict[:quality_flag])
    mode = convert(Vector{Int16},datas_dict[:mode])
    mass_range = FString(64,"H=$(datas_dict[:mass_range][:H]),O=$(datas_dict[:mass_range][:O]),O2=$(datas_dict[:mass_range][:O2])")

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
    
    write(f, vsc)
    write(f, pos)
    write(f, quality_flag)
    write(f, mode)
    write(f, mass_range)
    close(f)
end
#获取所有文件和对应的mag文件
files_ion = MAVEN_load.file_list("STATIC_c6")
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
    new_path = dirname(replace(file_ion, "/l2/" => "/l3/"))*"/mvn_sta_l3_c6_vel_flux_den_$(date)_v$(ion_version).f77_unformatted"
    dir = dirname(new_path)
    if !isdir(dir)
        mkpath(dir)
    end
    @time if !isfile(new_path)
        print("\033[0;32mBuilding $(date)\033[0m \n")
        local vsc_data = MAVEN_load.load_mag_vsc(file_vsc)
        local ion_data = MAVEN_load.load_STATIC(file_ion)
        local datas_dict = get_ion_vel(vsc_data,ion_data)
        touch(new_path)
        try
            data2bi(datas_dict,new_path)
        catch e
            global e
            print("\033[0;31mERROR: $(e)\033[0m \n")
            rm(new_path)
        end
        
    else
        print("\033[0;33mSKIP $(date)\033[0m \r")
    end
end
# date, file_ion, file_vsc = common_dates[1];
# vsc_data = MAVEN_load.load_mag_vsc(file_vsc);
# ion_data = MAVEN_load.load_STATIC(file_ion);
# @time datas_dict = get_ion_vel(vsc_data,ion_data);
# data2bi(datas_dict,raw"D:\CODE\Package_for_Julia\MAVEN_data\Build_data\test")