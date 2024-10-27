using TimesDates, Dates
using ColorTypes, CairoMakie
using DataFrames
using ProgressMeter
using LinearAlgebra
using LaTeXStrings
using JLD2
EnvironmentPath = "D:/CODE/Package_for_Julia/"
include("../../MAVEN_data/MAVEN_load.jl")
include("../../MAVEN_data/MAVEN_STATIC.jl")
import .MAVEN_load;
import .MAVEN_STATIC;

@inline function get_data(date;time_range = time_range)
    @inline function get_ion_vel(time_range, datas_dict)
        data_sta = datas_dict["STATIC_d1"]
        sta_epoch = data_sta["epoch"]
        time_i = findall(x -> time_range[2] >= x >= time_range[1], sta_epoch)
        time = data_sta["epoch"][time_i]
        ntime = length(time)
        H_vel_1 = zeros(ntime, 4)
        H_vel_2 = zeros(ntime, 4)
        O_vel_1 = zeros(ntime, 4)
        O_vel_2 = zeros(ntime, 4)
        O2_vel_1 = zeros(ntime, 4)
        O2_vel_2 = zeros(ntime, 4)
        H_den = zeros(ntime)
        O_den = zeros(ntime)
        O2_den = zeros(ntime)
    
        timeb, B_total, B, position = datas_dict["MAG_ss1s_l3"]["Vars"]
    
        @showprogress dt = 1 desc = "carcu_sta_vel" for (i, time_ind) in enumerate(time_i)
    
            timeB_ind = findfirst(x -> x >= sta_epoch[time_ind], timeb)
            vsc = (position[timeB_ind+1, :] .- position[timeB_ind-1, :]) ./ (datetime2unix(timeb[timeB_ind+1]) - datetime2unix(timeb[timeB_ind-1]))
    
            dat_slip = MAVEN_STATIC.static_slip(data_sta, time_ind)
            dat_slip = MAVEN_STATIC.static_rotation(dat_slip; frame="MSO")
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 10], mass_range=[20, 40], m_int=32)
            O2_vel_1[i, 1:3] = vel .+ vsc
            O2_vel_1[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 10], mass_range=[10, 20], m_int=16)
            O_vel_1[i, 1:3] = vel .+ vsc
            O_vel_1[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[0, 10], mass_range=[0, 2], m_int=1)
            H_vel_1[i, 1:3] = vel .+ vsc
            H_vel_1[i, 4] = den
    
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[10, 1e4], mass_range=[20, 40], m_int=32)
            O2_vel_2[i, 1:3] = vel .+ vsc
            O2_vel_2[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[10, 1e4], mass_range=[10, 20], m_int=16)
            O_vel_2[i, 1:3] = vel .+ vsc
            O_vel_2[i, 4] = den
            vel, _, den = MAVEN_STATIC.sta_v_4d(dat_slip; energy_range=[10, 1e4], mass_range=[0, 2], m_int=1)
            H_vel_2[i, 1:3] = vel .+ vsc
            H_vel_2[i, 4] = den
    
            den = MAVEN_STATIC.sta_n_4d(dat_slip; energy_range=[0, 1e4], mass_range=[20, 40], m_int=32)
            O2_den[i] = den
            den = MAVEN_STATIC.sta_n_4d(dat_slip; energy_range=[0, 1e4], mass_range=[10, 20], m_int=16)
            O_den[i] = den
            den = MAVEN_STATIC.sta_n_4d(dat_slip; energy_range=[0, 1e4], mass_range=[0, 2], m_int=1)
            H_den[i] = den
    
        end
        datas_dict["ion_vel"] = Dict{String,Any}(
            "epoch" => time,
            "H_vel_1" => H_vel_1,
            "H_vel_2" => H_vel_2,
            "O_vel_1" => O_vel_1,
            "O_vel_2" => O_vel_2,
            "O2_vel_1" => O2_vel_1,
            "O2_vel_2" => O2_vel_2,
            "H_den" => H_den,
            "O_den" => O_den,
            "O2_den" => O2_den
        )
        return datas_dict
    end;
    @inline function mag2shpere(datas_dict)
        _,_, b, position = datas_dict["MAG_ss1s_l3"]["Vars"]
        data = MAVEN_load.Bpc2sphere.(position[:, 1], position[:, 2], position[:, 3], b[:, 1], b[:, 2], b[:, 3])
        br = [x[1] for x in data]
        bθ = [x[2] for x in data]
        bϕ = [x[3] for x in data]
        datas_dict["MAG_ss1s_l3"]["SphereB"] = (br, bθ, bϕ)
        return datas_dict
    end
    model_index = [
        "MAG_ss1s_l3",
        "LPW_wave",
        "KP_l3",
        "SWEA_spec",
        "STATIC_c6",
        "SWEA_pad_svy",
        "LPW_mrgscpot"
    ]
    datas_dict = MAVEN_load.data_get_from_date(date, model_index=model_index, show_filename=true)
    # 替换KP_l3数据中的数字标为元标签
    KP_data_name_replace = Dict(
       :Ne => 2,
       :Ne_quality_min => 3,
       :Ne_quality_max => 4,
       :GEO_x => 187,
       :GEO_y => 188,
       :GEO_z => 189,
       :MSO_x => 190,
       :MSO_y => 191,
       :MSO_z => 192,
       :Orbit_Number => 210,
       :Shape_parameter => 39,
       :H_flow_MSO_x => 43,
       :H_flow_MSO_y => 45,
       :H_flow_MSO_z => 47,
       :O_iondensity => 56,
       :O2_iondensity => 58,
       :O_ionTemperature => 62,
       :O2_ionTemperature => 64,
    )
    datas_dict["KP"] = Dict()
    datas_dict["KP"]["data_load_flag"] = datas_dict["KP_l3"]["data_load_flag"]
    for key in keys(KP_data_name_replace)
        datas_dict["KP"][key] = datas_dict["KP_l3"][KP_data_name_replace[key]]
    end
    sta_data = datas_dict["STATIC_c6"]
    if sta_data["data_load_flag"] == false
        sta_total = Dict("data_load_flag" => false)
        sta_mass = Dict("data_load_flag" => false)
        sta_O2 = Dict("data_load_flag" => false)
    else
        sta_data = MAVEN_STATIC.STA_count2df_all(sta_data)
        sta_total = MAVEN_STATIC.static_c6_mass_mean(sta_data)
        sta_mass = MAVEN_STATIC.static_c6_energy_mean(sta_data)
        sta_O2 = MAVEN_STATIC.static_c6_mass_mean(sta_data, mass_range=[20, 40])
    end
    datas_dict["STATIC_c6_orign"] = sta_data
    datas_dict["STATIC_c6"] = sta_total
    datas_dict["STATIC_mass"] = sta_mass
    datas_dict["STATIC_O2"] = sta_O2

    x1, y1, z1 = datas_dict["KP"]["GEO_x"], datas_dict["KP"]["GEO_y"], datas_dict["KP"]["GEO_z"]
    alt = sqrt.(x1 .^ 2 .+ y1 .^ 2 .+ z1 .^ 2) .- 3393.5
    datas_dict["KP"]["alt"] = alt
    swea_pad = datas_dict["SWEA_pad_svy"]
    if swea_pad["data_load_flag"] == false
        swea_pad_low = Dict("data_load_flag" => false)
        swea_pad_high = Dict("data_load_flag" => false)
    else
        swea_pad_low = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[20, 30])
        swea_pad_high = MAVEN_load.carclu_SWEA_pad(swea_pad; energy_range=[90, 120])
    end
    datas_dict["swea_pad_low"] = swea_pad_low
    datas_dict["swea_pad_high"] = swea_pad_high

    datas_dict = mag2shpere(datas_dict)

    time_range = time_range
    # datas_dict = get_ion_vel(time_range, datas_dict) # 计算离子速度, 速度计算较慢,需要载入"STATIC_d1"

    return datas_dict
end

yyyy = 2015
mm = 10
dd = 29
save_file_name = "../data/" * Dates.format(DateTime(yyyy, mm, dd), "yyyymmdd") * "_MAVEN_data.jld2"
if isfile(save_file_name)
    datas_dict = load(save_file_name)["data"]
else
    datas_dict = get_data(DateTime(yyyy, mm, dd);time_range= [DateTime(yyyy, mm, dd,11,20),DateTime(yyyy, mm, dd,11,45)])
    save(save_file_name, "data", datas_dict)
end