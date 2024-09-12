# 读取和计算MAVEN数据
# data_get_from_date 返回字典dates_dict["数据类型"]["数据内容"]
# dates_dict["数据类型"]["data_load_flag"]表示读取是否成功
# 所有的CDF文件统一读取为cdf对应的字典，并去除PyObjects
# STATIC中的theta值在球坐标系下,应当为90-Theta.
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_load
using PyCall
cdflib = pyimport("cdflib")
using TimesDates, Dates
using DataFrames
using DelimitedFiles
using JSON
using JLD2
using Statistics
using Quaternions
using FortranFiles
# -------------------------Read filelist parts-------------------------
"""     
打印所有可支持的数据的读取.
"""
function show_load_models()
    keys_arr = keys(read_models)
    for key in keys_arr
        println(key)
    end
    return keys_arr
end
"""
输入model,返回对应文件的所有已下载文件路径
"""
function file_list(model::String)
    path = read_models[model][1]
    file_path = root_path .* path
    data = file_path .* filename_list[model]
    return data
end
"""
输入model,日期    
返回(bool::判断文件是否存在,String::对应文件的文件路径)  
"""
function find_file_of_data(model::String, date::DateTime)
    FileList_path = root_path * read_models[model][1]
    FileList = FileList_path .* filename_list[model]
    element = Dates.format(date, "yyyymmdd")
    for file_name in FileList
        if occursin(element, file_name)
            return true, file_name
        end
    end
    return false, "NaN"
end
"""
输入日期,返回对应日期的所有数据  
date 日期格式为DateTime(yyyy,mm,dd)  
model_index: 选择读取的数据类型  
show_filename: 是否显示读取的文件名  
"""
function data_get_from_date(date::DateTime; model_index=[], show_filename=false) #全局读取函数 date 格式为yyyymmdd
    datas_dict = Dict()
    for model in model_index
        file_flag, filename = find_file_of_data(model, date)
        function_name = read_models[model][2]
        if !file_flag
            datas_dict[model] = Dict("data_load_flag" => false)
        else
            if show_filename
                println("\033[0;32mloading\033[0m $model from $filename")
            end
            datas_dict[model] = function_name(filename)
            # println(keys(datas_dict[model]))
            datas_dict[model]["data_load_flag"] = true
        end
    end
    return datas_dict
end
function get_orbits()  # 获取每个轨道对应的time_range
    file_path = root_path * "orbit_time_range.txt"
    lines = readlines(file_path)
    data = []
    for line in lines
        items = split(line, ",")
        orbit = parse(Int, items[1])
        time_range_t = DateTime.(items[2:3], "yyyy-mm-ddTHH:MM:SS")
        push!(data, (orbit, time_range_t...))
    end
    return data
end
function change_kp_read_data(kp_dict_in) # 此函数用来修改load_KP能够读取的值有哪些. 格式为Dict{String,Int32}(变量名 => 变量序号)
    kp_dict_out = Dict()
    for (key, n) in kp_dict_in
        kp_dict_out[key] = (n, n * 16 - 16 .+ (4:19))
    end
    global kp_dict = kp_dict_out
    return kp_dict_out
end
##----------------load parts------------------------
function load_cdf(file::String)  # 将CDF文件读为字典
    local data = []

    try
        data = cdflib.cdfread.CDF(file)
    catch e
        println("Error: ", file)
        println(e)
        return Dict("data_load_flag" => false)
    end

    local data_dict = Dict{String,Any}()
    local var_list = data.cdf_info()["zVariables"]
    local vars = get.(Ref(data), var_list)
    for (var_name, var) in zip(var_list, vars)
        if typeof(var) != PyObject
            data_dict[var_name] = var
        end
    end
    data_dict["epoch"] = unix2datetime.(cdflib.cdfepoch.unixtime(get(data, "epoch")))
    data_dict["filename"] = file
    return data_dict
end
# function load_sta(file)
#     data   = cdflib.cdfread.CDF(file);
#     data_out_dict=Dict{String, Any}()
#     data_out_dict["apid"]= get(data,apid)
#     var_lists = [
#         "energy",
#         "denergy",
#         "eflux",
#         "sc_pot",
#         "swp_ind",
#         "mass_arr",
#         "theta",
#         "phi",
#         "dtheta",
#         "dphi",
#         "num_dists",
#         "nmass",
#         "nswp",
#         "nenergy",   
#     ]
#     for var_name in var_lists
#         var = get(data,var_name)
#         data_out_dict[var_name] = var
#     end
#     return data
# end
function load_mag_l2(file::String)
    function get_data_from_line_for_mag_read(line::String)
        # colspecs = [(1,6),(8,10),(12,13),(15,16),(18,19),(21,23),(39,48),(50,58),(60,68),(74,88),(90,103),(105,118)]
        year, doy, hour, min, sec, msec = parse.(Int32, [
            line[1:6], line[8:10], line[12:13], line[15:16], line[18:19], line[21:23]
        ])
        epoch = DateTime(year, 1, 1, hour, min, sec, msec) + Dates.Day(doy - 1)
        bx, by, bz, x, y, z = parse.(Float32, [
            line[39:48], line[50:58], line[60:68], line[74:88], line[90:103], line[105:118]
        ])
        return epoch, [bx, by, bz], [x, y, z]
    end
    lines = readlines(file)
    line_i = maximum(findall(line -> startswith(line, "END"), lines[1:600]))
    lines = lines[line_i+1:end]

    nums = length(lines)
    times = Vector{DateTime}(undef, nums)
    B = Matrix{Float32}(undef, nums, 3)
    position = Matrix{Float32}(undef, nums, 3)

    @inbounds for (i, line) in enumerate(lines)
        times[i], B[i, :], position[i, :] = get_data_from_line_for_mag_read(line)
    end

    B_total = sqrt.(sum(B .^ 2, dims=2))
    B_total = B_total[:, 1]

    data = Dict{String,Any}(
        "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
        "Vars" => [times, B_total, B, position],
    )
    return data
end
function load_mag_l3(file::String)
    f = FortranFile(file, "r")
    n_time = read(f, Int64)
    timeB = read(f, (Float64, n_time))
    BB = read(f, (Float32, n_time))
    B = read(f, (Float32, n_time, 3))
    position = read(f, (Float32, n_time, 3))
    close(f)

    timeB_datetime = Dates.julian2datetime.(timeB)
    data = Dict{String,Any}(
        "Var name" => "time[Ntime], BB[Ntime],B[Ntime,3],position[Ntime,3]",
        "Vars" => [timeB_datetime, BB, B, position],
    )
    return data
end
function load_kp(filename::String; pc2ss_Matrix_load=false, str_model=false)
    function kp_indicate(n)
        m = n * 16 - 16 .+ (4:19)
        return m
    end
    lines = readlines(filename)
    lines = [line for line in lines if !startswith(line, "#")]
    time = [line[1:19] for line in lines]
    time_dt = Dates.DateTime.(time, "yyyy-mm-ddTHH:MM:SS")
    Ntime = length(time)

    result_dict = Dict{String,Any}()
    result_dict["version"] = filename[end-10:end-8]

    if str_model
        for (key, value) in kp_dict
            var = [line[value[2]] for line in lines]
            result_dict[key] = var
        end
    else
        for (key, value) in kp_dict
            var = [line[value[2]] for line in lines]
            # var_float = []
            # if "SCP" in var || "SC0" in var || "I" in var || "O" in var
            #     var_float = replace.(var, "SCP" => 1)
            #     var_float = replace.(var_str, "SC0" => 0)
            #     var_float = replace.(var_str, "I" => 1)
            #     var_float = replace.(var_str, "O" => 0)
            # end
            var_float = parse.(Float64, var)
            result_dict[key] = var_float
        end
    end
    # if NaN2missing
    #     for (key, value) in result_dict
    #         ind = findall(x-> isnan(x), value)
    #         var = convert(Vector{Union{Missing, Float64}},value)
    #         var[ind] .= missing
    #         result_dict[key] = var
    #     end
    # end
    result_dict["time"] = time_dt

    if pc2ss_Matrix_load == false
        return result_dict
    else
        pc2ss_Matrix = zeros(Ntime, 3, 3)
        M_dict = Dict()
        for l in (218:226)
            value = kp_indicate(l)
            var = [line[value] for line in lines]
            var_float = parse.(Float64, var)
            M_dict[l-217] = var_float
        end
        for (key, var) in M_dict
            i = div(key - 1, 3) + 1  # 计算行索引(1-based)
            j = rem(key - 1, 3) + 1
            pc2ss_Matrix[:, i, j] = var
        end
        result_dict["pc2ss_Matrix"] = pc2ss_Matrix
        return result_dict
    end
end
function load_kp_l3(file::String)
    f = jldopen(file, "r")
    data_out_dict = f["KP_jld2_data"]
    # "pc2ss_Matrix" "sc2ss_Matrix"
    close(f)
    return data_out_dict
end
function load_swea_pad(file::String; mean_PA=true)
    # 默认将360°的数据投影到180°
    # "diff_en_fluxes_mean"
    # "g_pa_mean"
    # "pa_mean"
    data_dict = load_cdf(file)
    if mean_PA
        data_dict = mean_SWEA_pad_pa(data_dict)
    end
    return data_dict
end
function load_NGIMS_den_l3(file::String)
    lines = readlines(file)
    lines = lines[2:end]
    #t_utc,t_unix,t_sclk,t_tid,tid,orbit,focusmode,alt,mass,species,density_bins,quality
    n = length(lines)
    str_vars = Matrix{String}(undef, n, 12)
    for (i, line) in enumerate(lines)
        vars = split(line, ",")
        str_vars[i, :] = vars
    end
    t_unix = parse.(Float64, str_vars[:, 2])
    t_datetime = unix2datetime.(t_unix)
    data_out_dict = Dict{String,Any}()
    species = str_vars[:, 10]
    unique_elements = unique(species)
    for element in unique_elements
        indices = findall(x -> x == element, species)
        data_out_dict[element] = Dict{String,Any}(
            "epoch" => t_datetime[indices],
            "orbit" => parse.(Int32, str_vars[indices, 6]),
            "focusmode" => str_vars[indices, 7],
            "alt" => parse.(Float64, str_vars[indices, 8]),
            "mass" => parse.(Float64, str_vars[indices, 9]),
            "density_bins" => parse.(Float64, str_vars[indices, 11]),
            "quality" => str_vars[indices, 12],
        )
    end
    return data_out_dict
end
function load_NGIMS_den_l4(file::String)
    f = jldopen(file, "r")
    data_out_dict = f["data"]
    close(f)
    return data_out_dict
end
## ------------------------------数据处理--------------------------------
function Bpc2sphere(x, y, z, bx, by, bz)
    r = sqrt(x^2 + y^2 + z^2)
    θ = acos(z / r)
    ϕ = atan(y, x)

    sinθ = sin(θ)
    cosθ = cos(θ)
    sinϕ = sin(ϕ)
    cosϕ = cos(ϕ)

    Br = sinθ * cosϕ * bx + sinθ * sinϕ * by + cosθ * bz
    Bθ = cosθ * cosϕ * bx + cosθ * sinϕ * by - sinθ * bz
    Bϕ = -sinϕ * bx + cosϕ * by

    return Br, Bθ, Bϕ
end
function caculate_mag(position; models=["alt"])
    function c_alt(position)
        alt = sqrt.(sum(position .^ 2, dims=2)) .- 3393.5
        alt = alt[:, 1]
        return alt
    end
    function c_local_time(position)
        local_time = atan.(position[:, 2], position[:, 1]) ./ π .* 12.0 .+ 12.0
        return local_time
    end
    function c_latitude(position)
        latitude = atan.(position[:, 3], sqrt.(sum(position[:, 1:2] .^ 2, dims=2))) ./ π .* 180.0
        return latitude
    end
    funcs = Dict{String,Any}(
        "alt" => c_alt,
        "local_time" => c_local_time,
        "latitude" => c_latitude,
    )
    for model in models
        data[model] = funcs[model](position)
    end
end
function mean_SWEA_pad_pa(data_dict)  # 输入SWEA PAD的CDF字典，将其角度做平均. pad数据返回360°的16个方向的数据,可以做平均,使其变为180°的8个数据点
    flux = data_dict["diff_en_fluxes"]
    pitch_angle = data_dict["pa"]
    g_pa = data_dict["g_pa"]

    pitch_angle_mean = (pitch_angle[:, 1:8, :] .+ pitch_angle[:, 16:-1:9, :]) ./ 2
    g_pa_mean = (g_pa[:, 1:8, :] .+ g_pa[:, 16:-1:9, :]) ./ 2

    flux1 = flux[:, 1:8, :]
    flux2 = flux[:, 16:-1:9, :]
    nan_indices_flux1 = findall(isnan.(flux1))
    nan_indices_flux2 = findall(isnan.(flux2))
    flux1[nan_indices_flux1] = flux2[nan_indices_flux1]
    flux2[nan_indices_flux2] = flux1[nan_indices_flux2]

    flux_mean = (flux1 + flux2) ./ 2

    data_dict["diff_en_fluxes_mean"] = flux_mean
    data_dict["g_pa_mean"] = g_pa_mean
    data_dict["pa_mean"] = pitch_angle_mean
    return data_dict
end
function static_c6_mass_mean(data; mass_range=[0, 200])  # static 3d数据处理(不包括角度信息)
    # energy_spec为在mass维度做求和,得到eflux,energy谱
    # 默认计算所有的mass_range,设置mass_range后会计算对应范围的值
    # mass_range单位AMU
    # "time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    epoch = data["epoch"]
    energy = data["energy"]
    denergy = data["denergy"]
    eflux = data["eflux"]
    swp_ind = data["swp_ind"]
    apid = data["apid"]
    mass_arr = data["mass_arr"]
    ntime = data["num_dists"]
    nmass = data["nmass"]
    nswp = data["nswp"]
    nenergy = data["nenergy"]

    eflux_mass = zeros(ntime, nenergy)
    energy_mass = zeros(nenergy, nswp)


    # if  !isassigned(mass_range)
    #     energy_mass[:,:] = sum(energy .* denergy, dims=1)  ./ sum(denergy, dims=1)
    #     eflux_mass[:,:]  = sum(eflux,dims=2)
    # else
    # ind = findall(x->mass_range[2] >= x >= mass_range[1] , mass_arr)
    mask = (mass_arr .>= mass_range[1]) .& (mass_arr .<= mass_range[2])
    energy_mass[:, :] = sum(energy .* denergy .* mask, dims=1) ./ sum(denergy .* mask, dims=1)

    mapped_mass_arr = zeros(ntime, nmass, nenergy)
    for i in 1:ntime
        mapped_mass_arr[i, :, :] = mass_arr[:, :, swp_ind[i]+1]
    end
    # ind = findall(x->mass_range[2] >= x >= mass_range[1] , mapped_mass_arr)
    mask = (mapped_mass_arr .>= mass_range[1]) .& (mapped_mass_arr .<= mass_range[2])
    eflux_mass[:, :] = sum(eflux .* mask, dims=2)
    # end

    return_data = Dict{String,Any}(
        # "Var name"=> "time,energy[Nenergy,Nswp], eflux[Ntime,Nenergy], nswp[Nswp]",
        "apid" => apid,
        "epoch" => epoch,
        "energy" => energy_mass,
        "eflux" => eflux_mass,
        "swp_ind" => swp_ind,
        "data_load_flag" => true
    )
    return return_data
end
function static_c6_energy_mean(data; energy_range=[0, 1e6])  # static 3d数据处理(不包括角度信息)
    # 在energy维度做求和,得到eflux,mass谱
    # energy_range单位energy,不设置时默认计算所有energy的值
    # "time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    epoch = data["epoch"]
    energy = data["energy"]
    eflux = data["eflux"]
    swp_ind = data["swp_ind"]
    apid = data["apid"]
    mass_arr = data["mass_arr"]
    ntime = data["num_dists"]
    nmass = data["nmass"]
    nswp = data["nswp"]
    nenergy = data["nenergy"]

    eflux_out = zeros(ntime, nmass)
    mass_out = zeros(nmass, nswp)

    # if  !isassigned(energy_range)
    #     mass_out[:,:] = mean(mass_arr, dims=2)
    #     eflux_out[:,:]  = sum(eflux,dims=3)
    # else
    # ind = findall(x->energy_range[2] >= x >= energy_range[1] , energy)
    # mass_arr_t = mass_arr[ind]
    # mass_out[:,:] = mean(mass_arr_t, dims=2)
    mask = (energy .>= energy_range[1]) .& (energy .<= energy_range[2])
    mass_out[:, :] = mean(mass_arr .* mask, dims=2)

    mapped_energy = zeros(ntime, nmass, nenergy)
    for i in 1:ntime
        mapped_energy[i, :, :] = energy[:, :, swp_ind[i]+1]
    end
    # ind = findall(x->energy_range[2] >= x >= energy_range[1] , mapped_energy)
    mask = (mapped_energy .>= energy_range[1]) .& (mapped_energy .<= energy_range[2])
    eflux_out[:, :] = sum(eflux .* mask, dims=3)
    # end

    return_data = Dict{String,Any}(
        # "Var name"=> "time,energy[Nenergy,Nswp], eflux[ Ntime,Nenergy], nswp[Nswp]",
        "apid" => apid,
        "epoch" => epoch,
        "mass" => mass_out,
        "eflux" => eflux_out,
        "swp_ind" => swp_ind,
        "data_load_flag" => true
    )
    return return_data
end

function carclu_SWEA_pad(data; energy_range=[])
    # time, pitch_angle,energy_arr, flux_arr, g_pa, g_engy = data["Vars"]
    time = data["epoch"]
    pitch_angle = data["pa"]
    energy_arr = data["energy"]
    flux_arr = data["diff_en_fluxes"]
    g_pa = data["g_pa"]
    g_engy = data["g_engy"]
    if size(energy_range)[1] == 1
        _, index = findmin(abs.(energy_arr .- energy_range))
        index = index[1]
        energy_single = energy_arr[index]
        pitch_angle_PAD = pitch_angle[:, :, index]
        flux_PAD = flux_arr[:, :, index]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        return_data = Dict(
            "epoch" => time,
            "pa" => pitch_angle_PAD,
            "diff_en_fluxes" => flux_PAD,
            "energy" => energy_single,
            "data_load_flag" => true
        )
        return return_data #[time,pitch_angle_PAD,flux_PAD,energy_single]
    else
        # mask = (energy_arr .>= energy_range[1]) .& (energy_arr .<= energy_range[2])
        # mapped_mask = zeros(1,1,64)
        # mapped_mask[1,1,:] = mask

        energy_i = findall(e -> energy_range[1] <= e <= energy_range[2], energy_arr)
        energy_double = [energy_arr[energy_i[1]], energy_arr[energy_i[end]]]
        pitch_angle_PADt = sum(pitch_angle[:, :, energy_i] .* g_pa[:, :, energy_i], dims=3) ./ sum(g_pa[:, :, energy_i], dims=3)
        pitch_angle_PAD = pitch_angle_PADt[:, :, 1]

        g_engy_t = zeros(1, 1, 64)
        g_engy_t[1, 1, :] = g_engy

        flux_PADt = sum(flux_arr[:, :, energy_i] .* g_engy_t[:, :, energy_i], dims=3) / sum(g_engy_t[:, :, energy_i])
        flux_PAD = flux_PADt[:, :, 1]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        # return_data = Dict(
        #     "Var name" => "time[Ntime], pitch_angle[Ntime,Npa], eflux[Ntime,Npa], energy_double[2]",
        #     "Vars"     => [time, pitch_angle_PAD, flux_PAD, energy_double],
        #     "flag"     => true
        # )
        return_data = Dict(
            "epoch" => time,
            "pa" => pitch_angle_PAD,
            "diff_en_fluxes" => flux_PAD,
            "energy" => energy_double,
            "data_load_flag" => true
        )
        return return_data #[time,pitch_angle_PAD,flux_PAD,energy_double]
    end
end
function rotate_vector_with_Martrix(in_data, Rotation_Martrix) # inv
    out_data = Rotation_Martrix * in_data
    return out_data
end
function rotate_vector_with_quat(u::AbstractVector, q::QuaternionF64)
    q_u = QuaternionF64(0, u[1], u[2], u[3])
    q_v = q * q_u * conj(q)
    return [imag_part(q_v)...]
end
function eflux2F(energy, eflux)  # 电子eflux转PSD
    M = me
    E0 = 511.0   #静止能量 eV
    #energy 与 eflux 一一对应
    # E0=M*C^2/EV
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    P = γ * M * β * C        # kg m/s
    # V=β .* C
    F = (γ * M)^3 * eflux / energy * 1e4 / EV / P^2
    return F
end
function ion_eflux2F(energy, eflux, mION)  # 离子eflux转PSD
    M = mION * Mp
    E0 = 511.0 * mION * 1836.23 # 离子静止能量
    #energy 与 eflux 一一对应
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    P = γ * M * β * C        # kg m/s
    # V=β .* C
    F = (γ * M)^3 * eflux / energy * 1e4 / EV / P^2
    return F
end
function Doppler_Shift(f, V_sc, k, θ) # wave frequence shift with spacecraft velocity
    # θ angle between SC and wave vector
    ω_obs = f * 2 * π
    ω_real = ω_obs - k * V_sc * cos(θ)
    return ω_real
end
function sphere2xyz(r, θ, ϕ)
    x = r .* sind.(θ) .* cosd.(ϕ)
    y = r .* sind.(θ) .* sind.(ϕ)
    z = r .* cosd.(θ)
    return [x, y, z]
end
function energy2v(energy) # 电子能量对应速度(相对论)
    E0 = 511.0
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    v = β .* 3e8
    return v
end
function ion_energy2v(energy, mass) # 离子子能量对应速度(相对论)
    E0 = 511.0 * mass * 1836.23
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    v = β .* 3e8
    return v
end
const EV = 1.602176487e-19
const C = 3.0e8
const Me = 9.109e-31
const Mp = 1.672621637e-27
const RADG = 180.0 / π

dir = dirname(@__FILE__)
f = open(dir * "/" * "MAVEN_data_format.json", "r")
data = JSON.parse(f)
close(f)
root_path = data["save_path"] #所有文件的根目录
kp_dict = data["kp_dict"]
kp_dict = change_kp_read_data(kp_dict)

data_model = data["data_model"]
read_models = Dict{String,Tuple{String,Function}}()
for (key, value) in data_model
    func = eval(Meta.parse(value[4]))
    read_models[key] = (value[3], func)
end

# data = JSON.parsefile(root_path*"lists/"*"filename_lists.json")
f = open(dir * "/" * "filename_lists.json", "r")
data = JSON.parse(f)
close(f)
filename_list = data
end # module