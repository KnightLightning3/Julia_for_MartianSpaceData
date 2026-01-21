# 通过c6数据计算一维的STATIC速度,通量关系
using Dates
using FortranFiles
include("../MAVEN_load.jl");import .MAVEN_load;
include("../MAVEN_STATIC.jl");import .MAVEN_STATIC;

@inline function get_ion_vel(ion_data)

    ion_data_f = MAVEN_STATIC.STA_count3df(ion_data)
    mass_range = Dict(
        :H => [0, 1.3],
        :He => [1.4, 3.3],
        :O => [13,19],
        :O2 => [20,40]
    )
    O_v,O_f,O_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:O],m_int = 16)
    O2_v,O2_f,O2_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:O2],m_int = 32)
    H_v,H_f,H_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:H],m_int = 1)
    He_v,He_f,He_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=[0,1e8],mass_range=mass_range[:He],m_int = 4)

    return (
        time_unix = ion_data[:time_unix],
        H_v = H_v,
        He_v = He_v,
        O_v = O_v,
        O2_v = O2_v,
        H_n = H_n,
        He_n = He_n,
        O_n = O_n,
        O2_n = O2_n,
        H_f = H_f,
        He_f = He_f,
        O_f = O_f,
        O2_f = O2_f,
        pos = ion_data[:pos_sc_mso],
        b = ion_data[:magf],
        quality_flag = ion_data[:quality_flag],
        mode = ion_data[:mode],
        mass_range = mass_range,
    )
end
@inline function data2bi(datas_dict,filename)
    time = datas_dict.time_unix
    Ntime = length(time)

    time_unix = convert(Vector{Float64},time)

    O_vel = convert(Vector{Float32},datas_dict.O_v)
    O2_vel = convert(Vector{Float32},datas_dict.O2_v)
    H_vel = convert(Vector{Float32},datas_dict.H_v)
    He_vel = convert(Vector{Float32},datas_dict.He_v)

    O_f = convert(Vector{Float32},datas_dict.O_f)
    O2_f = convert(Vector{Float32},datas_dict.O2_f)
    H_f = convert(Vector{Float32},datas_dict.H_f)
    He_f = convert(Vector{Float32},datas_dict.He_f)

    O_den = convert(Vector{Float32},datas_dict.O_n)
    O2_den = convert(Vector{Float32},datas_dict.O2_n)
    H_den = convert(Vector{Float32},datas_dict.H_n)
    He_den = convert(Vector{Float32},datas_dict.He_n)

    pos = convert(Array{Float32,2},datas_dict.pos)
    b_mso = convert(Array{Float32,2},datas_dict.b)
    quality_flag = convert(Vector{Int16},datas_dict.quality_flag)
    mode = convert(Vector{Int16},datas_dict.mode)
    mass_range = FString(64,"H=$(datas_dict.mass_range[:H]),He=$(datas_dict.mass_range[:He]),O=$(datas_dict.mass_range[:O]),O2=$(datas_dict.mass_range[:O2])")

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
    
    write(f, b_mso)
    write(f, pos)
    write(f, quality_flag)
    write(f, mode)
    write(f, mass_range)
    close(f)
end
#获取所有文件和对应的mag文件
files_ion = MAVEN_load.file_list("STATIC_c6")
dates_ion = [(m.captures[1] ,s) for s in files_ion for m in eachmatch(r"_([0-9]{8})_", s)]
# yyyy = parse(Int, ARGS[1])
# time_range = (Date(yyyy,1,1), Date(yyyy,12,31))
common_dates = [
    (date, files_ion[i]) 
    for (i, (date, _)) in enumerate(dates_ion) 
    # if DateTime(date, "yyyymmdd") >= time_range[1] && DateTime(date, "yyyymmdd") <= time_range[2]
] #|> reverse

#清理已存在文件
remove_old = false
if remove_old
    file_path = "E:/MAVEN/STATIC/l3/"
    element = "mvn_sta_l3_c6_vel_flux_den_"
    for (root, dirs, files) in walkdir(file_path)
        for file in files
            if occursin(Regex(element), file)
                println("rm $(joinpath(root, file))")
                rm(joinpath(root, file))
            end
        end
    end
end
for (date, file_ion) in common_dates
    ion_version = match(r"_v([0-9]{2})_", file_ion).captures[1]
    new_path = dirname(replace(file_ion, "/l2/" => "/l3/"))*"/mvn_sta_l3_c6_vel_flux_den_$(date)_v$(ion_version).f77_unformatted"
    dir = dirname(new_path)
    if !isdir(dir)
        mkpath(dir)
    end
    @time if !isfile(new_path)
        print("\033[0;32mBuilding $(date)\033[0m \n")
        local ion_data = MAVEN_load.load_cdf(file_ion)
        local datas_dict = get_ion_vel(ion_data)
        touch(new_path)
        try
            data2bi(datas_dict,new_path)
        catch e
            global e
            print("\033[0;31mERROR: $(e)\033[0m \n")
            rm(new_path)
        end
    else
        print("\033[0;33mSKIP $(date)\033[0m \n")
    end
end