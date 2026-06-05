# 通过c6数据计算一维的STATIC速度,通量关系
using Dates
using FortranFiles
include("../MAVEN_load.jl");import .MAVEN_load;
include("../MAVEN_STATIC.jl");import .MAVEN_STATIC;
using JLD2
@inline function get_ion_vel(ion_data)

    ion_data_f = MAVEN_STATIC.STA_count3df(ion_data)
    mass_range = Dict(
        :H => [0,1.55],
        :He => [1.55,2.7],
        :O => [14,20],
        :O2 => [24,40],
        :CO2 => [40,60],
    )
    energy_range = [0,1e8]
    O_v,O_f,O_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:O],m_int = 16)
    O2_v,O2_f,O2_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:O2],m_int = 32)
    H_v,H_f,H_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:H],m_int = 1)
    He_v,He_f,He_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:He],m_int = 4)
    CO2_v,CO2_f,CO2_n = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:CO2],m_int = 44)

    energy_range = [0,30]
    O_v_cold,O_f_cold,O_n_cold = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:O],m_int = 16)
    O2_v_cold,O2_f_cold,O2_n_cold = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:O2],m_int = 32)
    H_v_cold,H_f_cold,H_n_cold = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:H],m_int = 1)
    He_v_cold,He_f_cold,He_n_cold = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:He],m_int = 4)
    CO2_v_cold,CO2_f_cold,CO2_n_cold = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:CO2],m_int = 44)

    energy_range = [30,1e8]
    O_v_heat,O_f_heat,O_n_heat = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:O],m_int = 16)
    O2_v_heat,O2_f_heat,O2_n_heat = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:O2],m_int = 32)
    H_v_heat,H_f_heat,H_n_heat = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:H],m_int = 1)
    He_v_heat,He_f_heat,He_n_heat = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:He],m_int = 4)
    CO2_v_heat,CO2_f_heat,CO2_n_heat = MAVEN_STATIC.sta_v_1d(ion_data_f ;energy_range=energy_range,mass_range=mass_range[:CO2],m_int = 44)

    return (
        time_unix = ion_data[:time_unix],
        H_v = hcat(H_v,H_v_cold,H_v_heat),
        He_v = hcat(He_v,He_v_cold,He_v_heat),
        O_v = hcat(O_v,O_v_cold,O_v_heat),
        O2_v = hcat(O2_v,O2_v_cold,O2_v_heat),
        CO2_v = hcat(CO2_v,CO2_v_cold,CO2_v_heat),
        H_n = hcat(H_n,H_n_cold,H_n_heat),
        He_n = hcat(He_n,He_n_cold,He_n_heat),
        O_n = hcat(O_n,O_n_cold,O_n_heat),
        O2_n = hcat(O2_n,O2_n_cold,O2_n_heat),
        CO2_n = hcat(CO2_n,CO2_n_cold,CO2_n_heat),
        H_f = hcat(H_f,H_f_cold,H_f_heat),
        He_f = hcat(He_f,He_f_cold,He_f_heat),
        O_f = hcat(O_f,O_f_cold,O_f_heat),
        O2_f = hcat(O2_f,O2_f_cold,O2_f_heat),
        CO2_f = hcat(CO2_f,CO2_f_cold,CO2_f_heat),
        pos = ion_data[:pos_sc_mso],
        b = ion_data[:magf],
        quality_flag = ion_data[:quality_flag],
        mode = ion_data[:mode],
        mass_range = mass_range,
        discribe = "heat=energy>30eV,cold=energy<30eV,total=energy<1e8eV",
    )
    # return (
    #     time_unix = ion_data[:time_unix],
    #     H_v = H_v,H_v_cold = H_v_cold,H_v_heat = H_v_heat,
    #     He_v = He_v,He_v_cold = He_v_cold,He_v_heat = He_v_heat,
    #     O_v = O_v,O_v_cold = O_v_cold,O_v_heat = O_v_heat,
    #     O2_v = O2_v,O2_v_cold = O2_v_cold,O2_v_heat = O2_v_heat,
    #     CO2_v = CO2_v,CO2_v_cold = CO2_v_cold,CO2_v_heat = CO2_v_heat,
    #     H_n = H_n,H_n_cold = H_n_cold,H_n_heat = H_n_heat,
    #     He_n = He_n,He_n_cold = He_n_cold,He_n_heat = He_n_heat,
    #     O_n = O_n,O_n_cold = O_n_cold,O_n_heat = O_n_heat,
    #     O2_n = O2_n,O2_n_cold = O2_n_cold,O2_n_heat = O2_n_heat,
    #     CO2_n = CO2_n,CO2_n_cold = CO2_n_cold,CO2_n_heat = CO2_n_heat,
    #     H_f = H_f,H_f_cold = H_f_cold,H_f_heat = H_f_heat,
    #     He_f = He_f,He_f_cold = He_f_cold,He_f_heat = He_f_heat,
    #     O_f = O_f,O_f_cold = O_f_cold,O_f_heat = O_f_heat,
    #     O2_f = O2_f,O2_f_cold = O2_f_cold,O2_f_heat = O2_f_heat,
    #     CO2_f = CO2_f,Co2_f_cold = CO2_f_cold,CO2_f_heat = CO2_f_heat,
    #     pos = ion_data[:pos_sc_mso],
    #     b = ion_data[:magf],
    #     quality_flag = ion_data[:quality_flag],
    #     mode = ion_data[:mode],
    #     mass_range = mass_range,
    #     discribe = "heat=energy>30eV,cold=energy<30eV,total=energy<1e8eV",
    # )
end
@inline function data2bi(datas_dict,filename)
    filter = [Shuffle(), Deflate()]
    jldopen(filename, "w"; compress = filter) do f
        f["data"] = datas_dict
    end
    # time = datas_dict.time_unix
    # Ntime = length(time)

    # time_unix = convert(Vector{Float64},time)

    # O_vel = convert(Vector{Float32},datas_dict.O_v)
    # O2_vel = convert(Vector{Float32},datas_dict.O2_v)
    # H_vel = convert(Vector{Float32},datas_dict.H_v)
    # He_vel = convert(Vector{Float32},datas_dict.He_v)
    # CO2_vel = convert(Vector{Float32},datas_dict.CO2_v)

    # O_f = convert(Vector{Float32},datas_dict.O_f)
    # O2_f = convert(Vector{Float32},datas_dict.O2_f)
    # H_f = convert(Vector{Float32},datas_dict.H_f)
    # He_f = convert(Vector{Float32},datas_dict.He_f)
    # CO2_f = convert(Vector{Float32},datas_dict.CO2_f)

    # O_den = convert(Vector{Float32},datas_dict.O_n)
    # O2_den = convert(Vector{Float32},datas_dict.O2_n)
    # H_den = convert(Vector{Float32},datas_dict.H_n)
    # He_den = convert(Vector{Float32},datas_dict.He_n)
    # CO2_den = convert(Vector{Float32},datas_dict.CO2_n)
    # energy_range = convert(Vector{Float32},datas_dict.energy_range)

    # pos = convert(Array{Float32,2},datas_dict.pos)
    # b_mso = convert(Array{Float32,2},datas_dict.b)
    # quality_flag = convert(Vector{Int16},datas_dict.quality_flag)
    # mode = convert(Vector{Int16},datas_dict.mode)
    # mass_range = FString(64,"H=$(datas_dict.mass_range[:H]),He=$(datas_dict.mass_range[:He]),O=$(datas_dict.mass_range[:O]),O2=$(datas_dict.mass_range[:O2]),CO2=$(datas_dict.mass_range[:CO2])")

    # f = FortranFile(filename,"w")
    # write(f, Ntime)
    # write(f, time_unix)
    # write(f, energy_range)
    
    # write(f, H_vel)
    # write(f, He_vel)
    # write(f, O_vel)
    # write(f, O2_vel)
    # write(f, CO2_vel)
    
    # write(f, H_f)
    # write(f, He_f)
    # write(f, O_f)
    # write(f, O2_f)
    # write(f, CO2_f)
    
    # write(f, H_den)
    # write(f, He_den)
    # write(f, O_den)
    # write(f, O2_den)
    # write(f, CO2_den)
    
    # write(f, b_mso)
    # write(f, pos)
    # write(f, quality_flag)
    # write(f, mode)
    # write(f, mass_range)
    # close(f)
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


for (date, file_ion) in common_dates
    ion_version = match(r"_v([0-9]{2})_", file_ion).captures[1]
    ion_revision = match(r"_r([0-9]{2})", file_ion).captures[1]
    new_path = dirname(replace(file_ion, "/l2/" => "/l3/"))*"/mvn_sta_l3_c6_v3d_$(date)_v$(ion_version)_r$(ion_revision).jld2"
    dir = dirname(new_path)
    if !isdir(dir)
        mkpath(dir)
    end
    yyyymmdd_new = date
    files_old = readdir(dir;join=true)
    for file_old in files_old # 移除旧版本数据
        yyyymmdd_old = match(r"mvn_sta_l3_c6_v3d_(\d{8})_",file_old).captures[1]
        if yyyymmdd_old == yyyymmdd_new
            v_old = match(r"_v([0-9]{2})",file_old).captures[1]
            r_old = match(r"_r([0-9]{2})",file_old).captures[1]
            vv_old = parse(Int32, v_old)
            rr_old = parse(Int32, r_old)
            vv_new = parse(Int32, ion_version)
            rr_new = parse(Int32, ion_revision)
            if vv_old < vv_new || (vv_old == vv_new && rr_old < rr_new)
                rm(file_old)
                println("\033[0;31mrm $yyyymmdd_old$v_old$r_old to_bulid $yyyymmdd_new$v_new$r_new\033[0m")
            end
        end
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