# 读取和计算MAVEN数据
# data_get_from_date 返回字典dates_dict[:数据类型"][:数据内容"]
# dates_dict[:数据类型"][:data_load_flag]表示读取是否成功
# 所有的CDF文件统一读取为cdf对应的字典,并去除PyObjects
# STATIC中的theta值在球坐标系下,应当为90-Theta.
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_load
using PyCall
cdflib = pyimport("cdflib")
using TimesDates, Dates
using DataFrames
using JSON
using ConfParser
using JLD2
using Statistics
using Quaternions
using FortranFiles
# -------------------------Export parts-------------------------
export load_MAVEN_data
export mean_SWEA_pad_pa, carclu_SWEA_pad
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
            datas_dict[model] = Dict(:data_load_flag => false)
        else
            if show_filename
                println("\033[0;32mloading\033[0m $model from $filename\r")
            end
            datas_dict[model] = function_name(filename)
            datas_dict[model][:filename] = filename
            datas_dict[model][:data_load_flag] = true
        end
    end
    return datas_dict
end
load_MAVEN_data = data_get_from_date
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
        return Dict(:data_load_flag => false)
    end

    local data_dict = Dict{Symbol,Any}()
    local var_list = data.cdf_info()["zVariables"]
    local vars = get.(Ref(data), var_list)
    for (var_name, var) in zip(var_list, vars)
        if typeof(var) == PyObject || var_name == "epoch"
            # println(var_name)
            continue
        end
        data_dict[Symbol(var_name)] = var
    end

    data_dict[:epoch] = unix2datetime.(cdflib.cdfepoch.unixtime(get(data, "epoch")))
    return data_dict
end
function load_STATIC(file::String)
    local data = []
    try
        data = cdflib.cdfread.CDF(file)
    catch e
        println("Error: ", file)
        println(e)
        return Dict(:data_load_flag => false)
    end
    local data_dict = Dict{Symbol,Any}()
    local var_list = [
        "time_unix", "time_start", "time_end", "time_delta", "time_integ", "eprom_ver", "header", "valid", "mode", "rate", "swp_ind", "mlut_ind", "eff_ind", "att_ind", "sc_pot", "magf", "quat_sc", "quat_mso", "bins_sc", "pos_sc_mso", "bkg", "dead", "data", "eflux", "quality_flag", "project_name", "spacecraft", "data_name", "apid", "units_name", "units_procedure", "num_dists", "nenergy", "nbins", "nmass", "ndef", "nanode", "natt", "nswp", "neff", "nmlut", "bins", "energy", "denergy", "theta", "dtheta", "phi", "dphi", "domega", "gf", "eff", "mass_arr", "tof_arr", "twt_arr", "geom_factor", "mass", "charge", 
        # "compno_3", "compno_4", "compno_8", "compno_32", "compno_64",
        # "dead_time_1", "dead_time_2", "dead_time_3"
        ]
        var_tpyes = Dict(
            "CDF_FLOAT" => Float64,
            "CDF_DOUBLE" => Float64,
            "CDF_INT2" => Int64,
            "CDF_INT4" => Int64,
            "CDF_CHAR" => String,
        )
    for var_name in var_list
        var = data.varget(var_name)
        var_s = Symbol(var_name)
        if typeof(var) == PyObject
            data_dict[var_s] = convert(
                var_tpyes[convert(String,data.varinq(var_name)["Data_Type_Description"])],
                var
                )
            continue
        end
        data_dict[var_s] = var
    end
    data_dict[:epoch] = unix2datetime.(get(data, "time_unix"))
    return data_dict
end
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
    line_i = maximum(findall(line -> startswith(line, "END"), lines[1:300]))
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

    type = file[end-24:end-21]
    data = Dict{Symbol,Any}(
        # "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
        # "Vars" => [times, B_total, B, position],
        :epoch => times,
        :type => type,
        :B_total => B_total,
        :B => B,
        :position => position,
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

    times = Dates.julian2datetime.(timeB)
    coodinate = file[end-36:end-33]
    data = Dict{Symbol,Any}(
        :epoch => times,
        :coodinate => coodinate,
        :B_total => BB,
        :B => B,
        :position => position,
    )
    return data
end
function load_mag_vsc(file::String)
    f = FortranFile(file, "r")
    n_time = read(f, Int64)
    time_unix = read(f, (Float64, n_time))
    vsc = read(f, (Float32, n_time, 3))
    position = read(f, (Float32, n_time, 3))
    close(f)

    times = Dates.unix2datetime.(time_unix)
    # coodinate = file[end-32:end-29]
    data = Dict{Symbol,Any}(
        :epoch => times,
        # :coodinate => coodinate,
        :vsc => vsc,
        :position => position,
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

    result_dict = Dict{Symbol,Any}()
    result_dict[:version] = filename[end-10:end-8]

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
            result_dict[Symbol(key)] = var_float
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
    result_dict[:time] = time_dt

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
        result_dict[:pc2ss_Matrix] = pc2ss_Matrix
        return result_dict
    end
end
function load_kp_l3(file::String)
    f = jldopen(file, "r")
    data_out_dict = f["KP_jld2_data"]
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
        data_out_dict[element] = Dict{Symbol,Any}(
            :epoch => t_datetime[indices],
            :orbit => parse.(Int32, str_vars[indices, 6]),
            :focusmode => str_vars[indices, 7],
            :alt => parse.(Float64, str_vars[indices, 8]),
            :mass => parse.(Float64, str_vars[indices, 9]),
            :density_bins => parse.(Float64, str_vars[indices, 11]),
            :quality => str_vars[indices, 12],
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
function load_NGIMS_sht_l3(file::String) # L3 resampled scale height table of NGIMs
    lines = readlines(file)
    lines = lines[2:end]
    #t_utc,t_unix,t_sclk,t_tid,tid,orbit,exo_alt,mass,species,scale_height,scale_height_error,Temperature,Temperature_error,fit_residual,quality
    n = length(lines)
    str_vars = Matrix{String}(undef, n, 15)
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
        data_out_dict[element] = Dict{Symbol,Any}(
            :epoch => t_datetime[indices],
            :orbit => parse.(Int32, str_vars[indices, 6]),
            :exo_alt => parse.(Float64, str_vars[indices, 7]),
            :mass => parse.(Float64, str_vars[indices, 8]),
            :species => parse.(Float64, str_vars[indices, 9]),
            :scale_height => parse.(Float64, str_vars[indices, 10]),
            :scale_height_error => parse.(Float64, str_vars[indices, 11]),
            :Temperature => parse.(Float64, str_vars[indices, 12]),
            :Temperature_error => parse.(Float64, str_vars[indices, 13]),
            :fit_residual => parse.(Float64, str_vars[indices, 14]),
            :quality => str_vars[indices, 15]
        )
    end
    return data_out_dict
end
function load_d1_v4d(file::String) # build using STATIC d1 data. already been corrected by sc_pot(static) and vsc by MAG_ss1s
    f = FortranFile(file, "r")
    Ntime = read(f, Int64)
    time_unix = read(f, (Float64, Ntime))
    H_vel = read(f, (Float32, Ntime, 3))
    O_vel = read(f, (Float32, Ntime, 3))
    O2_vel = read(f, (Float32, Ntime, 3))
    H_f = read(f, (Float32, Ntime, 3))
    O_f = read(f, (Float32, Ntime, 3))
    O2_f = read(f, (Float32, Ntime, 3))
    H_den = read(f, (Float32, Ntime))
    O_den = read(f, (Float32, Ntime))
    O2_den = read(f, (Float32, Ntime))
    pos_mso = read(f, (Float32, Ntime,3))
    quality_flag = read(f, (Int16, Ntime))
    close(f)
    data = Dict{Symbol,Any}(
        :epoch => unix2datetime.(time_unix),
        :H_vel => H_vel,
        :O_vel => O_vel,
        :O2_vel => O2_vel,
        :H_f => H_f, # flux
        :O_f => O_f,
        :O2_f => O2_f,
        :H_den => H_den,
        :O_den => O_den,
        :O2_den => O2_den,
        :pos_sc_mso => pos_mso,
        :quality_flag => quality_flag,
    )
    return data
end
function load_c6_v3d(file::String) # build using STATIC d1 data. already been corrected by sc_pot(static) and vsc by MAG_ss1s
    f = FortranFile(file, "r")
    Ntime = read(f, Int64)
    time_unix = read(f, (Float64, Ntime))
    H_vel = read(f, (Float32, Ntime))
    O_vel = read(f, (Float32, Ntime))
    O2_vel = read(f, (Float32, Ntime))
    H_f = read(f, (Float32, Ntime))
    O_f = read(f, (Float32, Ntime))
    O2_f = read(f, (Float32, Ntime))
    H_den = read(f, (Float32, Ntime))
    O_den = read(f, (Float32, Ntime))
    O2_den = read(f, (Float32, Ntime))

    vsc = read(f, (Float32, Ntime,3))
    pos_mso = read(f, (Float32, Ntime,3))
    quality_flag = read(f, (Int16, Ntime))
    mode = read(f, (Int16, Ntime))
    mass_range = trimstring(read(f, FString{64}))
    close(f)

    data = Dict{Symbol,Any}(
        :epoch => unix2datetime.(time_unix),
        :H_vel => H_vel,
        :O_vel => O_vel,
        :O2_vel => O2_vel,
        :H_f => H_f, # flux
        :O_f => O_f,
        :O2_f => O2_f,
        :H_den => H_den,
        :O_den => O_den,
        :O2_den => O2_den,
        :vsc_mso => vsc,
        :pos_sc_mso => pos_mso,
        :quality_flag => quality_flag,
        :mode => mode,
        :mass_range => mass_range,
    )
    return data
end
## ------------------------------数据处理--------------------------------
kp_dict_0 = Dict(
    :electorn_density => 2,
    :GEO_x => 187,
    :GEO_y => 188,
    :GEO_z => 189,
    :MSO_x => 190,
    :MSO_y => 191,
    :MSO_z => 192,
    :Orbit_Number => 210,
    :Shape_parameter => 39,
)
function convert_kp_l3(data::Dict;kp_dict=kp_dict_0)
    data_out = Dict{Symbol,Any}()
    for key in [:sc2ss_Matrix, :filename, :varsion, :data_load_flag, :pc2ss_Matrix, :time]
        data_out[key] = data[key]
    end
    for (key, value) in kp_dict
        symobl_i = Symbol("var_$value")
        data_out[key] = data[:vars][symobl_i]
    end
    return data_out
end
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
function caculate_mag(position; models=[:alt])
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
    funcs = Dict{Symbol,Any}(
        :alt => c_alt,
        :local_time => c_local_time,
        :latitude => c_latitude,
    )
    for model in models
        data[model] = funcs[model](position)
    end
end
function mean_SWEA_pad_pa(data_dict)  # 输入SWEA PAD的CDF字典,将其角度做平均. pad数据返回360°的16个方向的数据,可以做平均,使其变为180°的8个数据点
    flux = data_dict[:diff_en_fluxes]
    pitch_angle = data_dict[:pa]
    g_pa = data_dict[:g_pa]

    pitch_angle_mean = (pitch_angle[:, 1:8, :] .+ pitch_angle[:, 16:-1:9, :]) ./ 2
    g_pa_mean = (g_pa[:, 1:8, :] .+ g_pa[:, 16:-1:9, :]) ./ 2

    flux1 = flux[:, 1:8, :]
    flux2 = flux[:, 16:-1:9, :]
    nan_indices_flux1 = findall(isnan.(flux1))
    nan_indices_flux2 = findall(isnan.(flux2))
    flux1[nan_indices_flux1] = flux2[nan_indices_flux1]
    flux2[nan_indices_flux2] = flux1[nan_indices_flux2]

    flux_mean = (flux1 + flux2) ./ 2

    data_dict[:diff_en_fluxes_mean] = flux_mean
    data_dict[:g_pa_mean] = g_pa_mean
    data_dict[:pa_mean] = pitch_angle_mean
    return data_dict
end
function static_c6_mass_mean(data; mass_range=[0, 200])  # static 3d数据处理(不包括角度信息)
    # energy_spec为在mass维度做求和,得到eflux,energy谱
    # 默认计算所有的mass_range,设置mass_range后会计算对应范围的值
    # mass_range单位AMU
    # "time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    epoch = data[:epoch]
    energy = data[:energy]
    denergy = data[:denergy]
    eflux = data[:eflux]
    swp_ind = data[:swp_ind]
    apid = data[:apid]
    mass_arr = data[:mass_arr]
    ntime = data[:num_dists]
    nmass = data[:nmass]
    nswp = data[:nswp]
    nenergy = data[:nenergy]

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

    return_data = Dict{Symbol,Any}(
        # "Var name"=> "time,energy[Nenergy,Nswp], eflux[Ntime,Nenergy], nswp[Nswp]",
        :apid => apid,
        :epoch => epoch,
        :energy => energy_mass,
        :eflux => eflux_mass,
        :swp_ind => swp_ind,
        :data_load_flag => true
    )
    return return_data
end
function static_c6_energy_mean(data; energy_range=[0, 1e6])  # static 3d数据处理(不包括角度信息)
    # 在energy维度做求和,得到eflux,mass谱
    # energy_range单位energy,不设置时默认计算所有energy的值
    # "time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]"
    epoch = data[:epoch]
    energy = data[:energy]
    eflux = data[:eflux]
    swp_ind = data[:swp_ind]
    apid = data[:apid]
    mass_arr = data[:mass_arr]
    ntime = data[:num_dists]
    nmass = data[:nmass]
    nswp = data[:nswp]
    nenergy = data[:nenergy]

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

    return_data = Dict{Symbol,Any}(
        # "Var name"=> "time,energy[Nenergy,Nswp], eflux[ Ntime,Nenergy], nswp[Nswp]",
        :apid => apid,
        :epoch => epoch,
        :mass => mass_out,
        :eflux => eflux_out,
        :swp_ind => swp_ind,
        :data_load_flag => true
    )
    return return_data
end
function carclu_SWEA_pad(data; energy_range=[])  # SWEA PAD数据处理
    time = data[:epoch]
    pitch_angle = data[:pa]
    energy_arr = data[:energy]
    flux_arr = data[:diff_en_fluxes]
    g_pa = data[:g_pa]
    g_engy = data[:g_engy]
    if size(energy_range)[1] == 1
        _, index = findmin(abs.(energy_arr .- energy_range))
        index = index[1]
        energy_single = energy_arr[index]
        pitch_angle_PAD = pitch_angle[:, :, index]
        flux_PAD = flux_arr[:, :, index]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        return_data = Dict(
            :epoch => time,
            :pa => pitch_angle_PAD,
            :diff_en_fluxes => flux_PAD,
            :energy => energy_single,
            :data_load_flag => true
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
            :epoch => time,
            :pa => pitch_angle_PAD,
            :diff_en_fluxes => flux_PAD,
            :energy => energy_double,
            :data_load_flag => true
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
function find_segments(x::Vector{T}, y::BitVector) where {T}
    segments1 = []
    segments2 = []
    start_idx = nothing
    for i in eachindex(y)
        if y[i] == 1
            if start_idx === nothing
                start_idx = i
            end
        elseif start_idx !== nothing
            push!(segments1, x[start_idx])
            push!(segments2, x[i-1])
            start_idx = nothing
        end
    end
    if start_idx !== nothing
        push!(segments1, x[start_idx])
        push!(segments2, x[end])
    end
    return segments1, segments2
end
function ion_energy2v(energy, mass) # 离子子能量对应速度(相对论)
    E0 = 511.0 * mass * 1836.23
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    v = β .* 3e8
    return v
end
function SWEA_calc_shape_arr(dat;energy_range = [20,80], pad_range = [0,30],time_i = nothing)# 计算指定pa范围的shape parameter,设置time_i后可以计算指定时间段的数据以增加运行速度
    function mvn_swe_calc_shape_arr(npts, fin, energy; hresflg=true, energy_range = [0.0, 100.0])
        function deriv(x, y)
            # ref deriv for idl
            # Ensure we have at least 3 points
            n = length(x)
    
            d = (circshift(x, -1) .- circshift(x, 1)) / 2.0
            d[1] = (-3.0 * x[1] + 4.0 * x[2] - x[3]) / 2.0
            d[end] = (3.0 * x[end] - 4.0 * x[end-1] + x[end-2]) / 2.0
        
            # Compute the shifts
            x0 = circshift(x, 1)
            x2 = circshift(x, -1)
            x01 = x0 .- x
            x02 = x0 .- x2
            x12 = x .- x2
        
            # Middle points calculation (flip sign of the last term so we can reuse x01)
            d = circshift(y, 1) .* (x12 ./ (x01 .* x02)) .+ y .* (1.0 ./ x12 .- 1.0 ./ x01) .- circshift(y, -1) .* (x01 ./ (x02 .* x12))
        
            # Formulae for the first and last points
            d[1] = y[1] * (x01[2] + x02[2]) / (x01[2] * x02[2]) - y[2] * x02[2] / (x01[2] * x12[2]) + y[3] * x01[2] / (x02[2] * x12[2])
            d[end] = -y[end-2] * x12[end-1] / (x01[end-1] * x02[end-1]) + y[end-1] * x02[end-1] / (x01[end-1] * x12[end-1]) - y[end] * (x02[end-1] + x12[end-1]) / (x02[end-1] * x12[end-1])
            return d
        end
        # ref projects\maven\swea\mvn_swe_calc_shape_arr.pro
        # Constants for ionospheric response
        df_lres = [ 0.0371289, 0.0179520, 0.0179520, 0.0356604, 0.0356604, 0.259604,
                    0.259604, 0.188697, 0.188697, -0.0261332, -0.0261332, 0.0849961,
                    0.0849961, 0.102494, 0.102494, 0.0595406, 0.0595406, 0.0591643,
                    0.0591643, 0.0459675, 0.0459675, 0.0296691, 0.0296691, 0.204077,
                    0.204077, 0.308229, 0.308229, 0.0962973, 0.0962973, 0.118876,
                    0.118876, 0.160658, 0.160658, 0.0387319, 0.0387319, 0.00507925,
                    0.00507925, 0.0866565, 0.0866565, 0.114288, 0.114288, 0.0612787,
                    0.0612787, 0.0209041, 0.0209041, -0.0567795, -0.0567795, -0.124904,
                    -0.124904, -0.123564, -0.123564, 0.123564]
        
        df_hres = [ -0.00621939, 0.144627, -0.00556159, 0.0933514, 0.101257, 0.186915,
                    0.479829, 0.401596, 0.0638178, -0.0410685, -0.0147899, 0.0405415,
                    0.120542, 0.129752, 0.0718670, 0.0592695, 0.0666794, 0.0681327,
                    0.0577553, 0.0493796, 0.0360952, 0.0234586, 0.0409702, 0.108591,
                    0.251231, 0.360782, 0.279757, 0.129745, 0.0748887, 0.0924677,
                    0.131181, 0.166274, 0.156800, 0.0917069, -0.0123766, -0.0285236,
                    0.0425429, 0.0720319, 0.0926143, 0.114485, 0.105823, 0.0707967,
                    0.0469701, 0.0305556, 0.00320172, -0.0334262, -0.0743820, -0.107133,
                    -0.127032, -0.128968, -0.118429, -0.120177]
    
        # Select df_iono based on hresflg
        df_iono = hresflg == 1 ? df_hres : df_lres
        
        # Select energy channels
        n_e = 52 # Number of model energy channels
        indx = collect(13:64)
        e = energy[indx]
        # Take the first derivative of log(eflux) w.r.t. log(E)
        f = log10.(fin[:,indx])

        emin, emax = energy_range[1], energy_range[2]
        endx = findall(x -> emin <= x <= emax, e)
        f = f[:, endx]
        df_ion = df_iono[endx]
        n_e = length(endx)
        
        # Filter out bad spectra (such as hot electron voids,if finite exit, if not, set to false) 
        gndx = findall(x -> !(false in isfinite.(x)) ,eachrow(f[:, :]))
        par = Vector{Float64}(undef,npts)
        par .= NaN
        @inbounds for i in gndx
            df = deriv(1:n_e,f[i, :]) # First derivative
            par[i] = sum(abs.(df .- df_ion))
        end
        return par
    end
    ntimes = dat[:num_dists]
    if time_i == nothing
        time_i = 1:ntimes
    end
    npts = length(time_i)
    hresflg = 1
    flux = dat[:diff_en_fluxes][time_i,:,:]
    flux[isnan.(flux)] .= 0
    energy = dat[:energy]
    hresflg = dat[:filename][end-26:end-24] == "arc"
    pad = dat[:pa][time_i,:,:]
    d_pad = dat[:d_pa][time_i,:,:]

    mask_pad = pad_range[1] .<= pad .<= pad_range[2]
    flux_pad_mean = sum(flux .* mask_pad .* d_pad,dims=2)[:,1,:] ./ sum(mask_pad.* d_pad,dims=2)[:,1,:]
    par = mvn_swe_calc_shape_arr(npts,flux_pad_mean,energy; energy_range=energy_range, hresflg=hresflg)
    return par
end
function SWEA_calc_shape_arr_mars_towrads(SWEA_dat,MAG_dat;energy_range=[0,100],time_i = nothing,pa_width =30)#将sp计算为指向和指出火星,需要同时导入磁场,建议pc,ss理论上也可,pa_width为PAD角度范围,设置time_i后可以计算指定时间段的数据以增加运行速度; 指向和指出单纯由磁场Br的正负和平行或反平行决定.
    # ref projects\maven\swea\mvn_swe_shape_par_pad_l2.pro
    ntimes = SWEA_dat[:num_dists]
    if time_i == nothing
        time_i = 1:ntimes
    end
    npts = length(time_i)
    tb = MAG_dat[:epoch]
    pb = MAG_dat[:position]
    b = MAG_dat[:B]
    b_total = MAG_dat[:B_total]
    te = SWEA_dat[:epoch][time_i]
    #计算磁场方向
    tb_i = zeros(Int64,npts)
    for i in 1:npts
        tb_i[i] = findmin(x->abs(x - te[i]),tb)[2]
    end
    norm_b = b[tb_i,:] ./ reshape(b_total[tb_i],:,1)
    norm_p = pb[tb_i,:] ./ sqrt.(sum(pb[tb_i,:].^2,dims=2))
    B_angle = acos.(sum(norm_b .* norm_p,dims=2))[:,1]
    B_out = B_angle .> 0

    par_antipara  = SWEA_calc_shape_arr(SWEA_dat;pad_range=[180-pa_width,180],energy_range=energy_range,time_i = time_i)
    par_para = SWEA_calc_shape_arr(SWEA_dat;pad_range=[0,pa_width],energy_range=energy_range,time_i = time_i)
    par_mid = SWEA_calc_shape_arr(SWEA_dat;pad_range=[pa_width,180-pa_width],energy_range=energy_range,time_i = time_i)

    par_twd = zeros(npts)
    par_away = zeros(npts)
    par_twd[B_out] .= par_antipara[B_out]
    par_twd[.!B_out] .= par_para[.!B_out]

    par_away[B_out] .= par_para[B_out]
    par_away[.!B_out] .= par_antipara[.!B_out]
    return par_twd,par_away,par_mid
end
const EV = 1.602176487e-19
const C = 3.0e8
const Me = 9.109e-31
const Mp = 1.672621637e-27
const RADG = 180.0 / π

dir = dirname(@__FILE__)
porject_path = dirname(dir)
open(dir * "/MAVEN_data_format.json", "r") do f
    data = JSON.parse(f)
    global kp_dict = data["kp_dict"]
    global data_model = data["data_model"]
end
conf = ConfParse(dirname(dir) * "/download_data/MAVEN_download_config.ini")
parse_conf!(conf)
root_path = retrieve(conf, "DEFAULT", "Save_dir")#所有文件的根目录
kp_dict = change_kp_read_data(kp_dict)

read_models = Dict{String,Tuple{String,Function}}()
for (key, value) in data_model
    func = eval(Meta.parse(value[4]))
    read_models[key] = (value[3], func)
end

# data = JSON.parsefile(root_path*"lists/"*"filename_lists.json")
open(dir * "/" * "filename_lists.json", "r") do f
    global filename_list = JSON.parse(f)
end
end # module



# ----test
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath * "MAVEN_data/MAVEN_load.jl")
# import .MAVEN_load;
# file = raw"C:\Users\Odysseus Lightning\Desktop\mvn_mag_l2_2015193pc_20150712_v01_r02.sts"
# lines = readlines(file)
# MAVEN_load.load_mag_l2(file)