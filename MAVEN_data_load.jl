module MAVEN_data_load
using PyCall
cdflib = pyimport("cdflib")
using TimesDates, Dates
using DataFrames
using DelimitedFiles

function load_swea_spec(file);
    data = cdflib.cdfread.CDF(file)
    times_num  = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    energy_arr = convert(Array{Float64,1}, (get(data,"energy")))
    flux_arr  = convert(Array{Float64,2},(get(data,"diff_en_fluxes")))
    flux_arr[flux_arr .<= 1e-10] .= 1e-10
    return [times_num, energy_arr, flux_arr]
end
function load_WaveSpactra(file);
    data      =  cdflib.cdfread.CDF(file)
    epoch     =  unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    freq      =  convert(Array{Float64,2}, (get(data,"freq")))
    wave_data =  convert(Array{Float64,2},(get(data,"data")))

    wave_data[wave_data .<= 1e-20] .= 1e-20
    
    return [epoch, freq, wave_data]
end
function load_mag(file);
    colspecs = [(1,6),(8,10),(12,13),(15,16),(18,19),(21,23),(39,48),(50,58),(60,68),(74,88),(90,103),(105,118)]
    skiprows = 155
    data = readdlm(file, skipstart=skiprows, header=false)#

    year = data[:, 1]
    doy = data[:, 2]
    hours = data[:, 3]
    minutes = data[:, 4]
    seconds = data[:, 5]
    milliseconds = data[:, 6]
    println(year[1], doy[1], hours[1], minutes[1], seconds[1], milliseconds[1])
    epoch = DateTime.(year, 1, 1) .+ Dates.Millisecond.((doy .- 1)*24*3600*1000 + hours*3600*1000 + minutes*60*1000 + seconds*1000 + milliseconds)
    
    # time_i = findall(t -> time_range[1] <= t <= time_range[2], epoch)
    times_num=epoch[:]
    B= data[:, 8:10]
    position_mso = data[:, 12:14]
    x_mso = position_mso[:, 1]
    y_mso = position_mso[:, 2]
    z_mso = position_mso[:, 3]
    alt = sqrt.(sum(position_mso.^2, dims=2)) .- 3393.5
    
    local_time = atan.(position_mso[:, 2], position_mso[:, 1]) ./ π .* 12.0 .+ 12.0
    latitude   = atan.(position_mso[:, 3], sqrt.(sum(position_mso[:,1:2].^2, dims=2)) ) ./ π .* 180.0
    
    B_total = sqrt.(sum(B.^2, dims=2))
    alt = alt[:,1] ; B_total = B_total[:,1]
    B_total = convert(Array{Float64,1}, B_total)
    B_mso = convert(Array{Float64,2}, B)
    position_mso = convert(Array{Float64,2}, position_mso)
    alt=convert(Array{Float64,1}, alt)
    return [times_num, B_total,B_mso,local_time,latitude, alt,position_mso ]
end
function load_static(file)
    data   = cdflib.cdfread.CDF(file)
    epoch  = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    energy = convert(Array{Float64,3}, (get(data,"energy")))     # Nmass,Nenergy,Nswp
    denergy= convert(Array{Float64,3}, (get(data,"denergy")))    # Nmass,Nenergy,Nswp
    AMU_arr= convert(Array{Float64,3},(get(data,"mass_arr")))    # Nmass,Nenergy,Nswp
    
    eflux  = convert(Array{Float64,3}, (get(data,"eflux")))      # N_DISTS,Nmass,Nenergy
    nswp   = convert(Array{Int32,1},   (get(data,"swp_ind")))    # Nswp_ind
    
    
    eflux[eflux .<= 0] .= 1e-10
    
    return [epoch,energy,eflux,nswp,AMU_arr,denergy]
end
function caculate_static(data;model="total",mass_range=[0,0])
    epoch,energy,eflux,swp_arr,AMU_arr,denergy = data;

    if model == "total"   
        energy_all_mass = sum(energy .* denergy, dims=1)  ./ sum(denergy, dims=1); energy_all_mass = energy_all_mass[1,:,:]  
        eflux_all_mass  = sum(eflux[:,:,:], dims=2) ; eflux_all_mass = eflux_all_mass[:,1,:]
        
        # for i =1:ntime
        #     denergy_t = denergy[:,:,swp_arr[i]+1]
        #     eflux_t=eflux_arr[i,:,:]
        #     eflux_all_mass[i,:]=sum(eflux_t.* denergy_t, dims=1) ./ sum(denergy_t, dims=1)
        # end
        
        return [epoch,energy_all_mass,eflux_all_mass,swp_arr]
    end
    n = size(eflux)
    ntime   = n[1]
    n = size(energy)
    nswp    = n[3] 
    nenergy = n[2]
    nmass   = n[1]
    
    eflux_mass=zeros((ntime,nmass,nenergy))
    energy_mass = zeros(nmass,nenergy,nswp)
    denergy_mass = zeros(nmass,nenergy,nswp)
    ind_mass=findall(m -> mass_range[1] <= m <= mass_range[2], AMU_arr)
    energy_mass[ind_mass] = energy[ind_mass]
    denergy_mass[ind_mass] = denergy[ind_mass]
    energy_mass = sum(energy.* denergy, dims=1)  ./ sum(denergy, dims=1); energy_mass = energy_mass[1,:,:]  
    
    for i =1:ntime
        ind_mass_t=findall(m -> mass_range[1] <= m <= mass_range[2], AMU_arr[:,:,swp_arr[i]+1])
        eflux_t=eflux[i,:,:]
        eflux_mass[i,ind_mass_t]=eflux_t[ind_mass_t]
    end
    eflux_mass = sum(eflux_mass,dims=2); eflux_mass=eflux_mass[:,1,:]
    
    return [energy_mass,eflux_mass]
end
function load_sc_potential(file)
    data        = cdflib.cdfread.CDF(file)
    times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    potential  = convert(Array{Float64,1}, (get(data,"data")))
    return [times_num,potential]
end
function load_swea_pad(file)
    data        = cdflib.cdfread.CDF(file)
    times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    energy_arr  = convert(Array{Float64,1}, (get(data,"energy")))
    g_engy      = convert(Array{Float64,1}, (get(data,"g_engy")))
    flux        = convert(Array{Float64,3}, (get(data,"diff_en_fluxes")))
    pitch_angle = convert(Array{Float64,3}, (get(data,"pa")))
    g_pa        = convert(Array{Float64,3}, (get(data,"g_pa")))
    # pitch_angle = (pitch_angle[:, 1:8, :] .+ pitch_angle[:, 16:-1:9, :]) ./ 2
    
    # g_pa = (g_pa[:, 1:8, :] .+ g_pa[:, 16:-1:9, :]) ./ 2
    # flux        = (flux[:, 1:8, :] .+ flux[:, 16:-1:9, :]) ./ 2
    flux[flux .<= 1e-10] .= 1e-10
    return [times_num, pitch_angle,energy_arr, flux, g_pa, g_engy]
end
function carclu_SWEA_pad(data; energy_range=[])
    times_num, pitch_angle,energy_arr, flux_arr, g_pa, g_engy = data
    
    if size(energy_range)[1] == 1
        _, index = findmin(abs.(energy_arr .- energy_range))
        index = index[1]
        energy_single = energy_arr[index]
        pitch_angle_PAD = pitch_angle[:, :, index]
        flux_PAD        = flux_arr[:, :, index]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        return [times_num,pitch_angle_PAD,flux_PAD,energy_single]
    else
        energy_i = findall(e -> energy_range[1] <= e <= energy_range[2], energy_arr)
        energy_double = [energy_arr[energy_i[1]],energy_arr[energy_i[end]] ]
        pitch_angle_PADt = sum(pitch_angle[:, :, energy_i] .* g_pa[:,:,energy_i], dims=3) ./ sum(g_pa[:,:,energy_i], dims=3)
        pitch_angle_PAD=pitch_angle_PADt[:,:,1]
    
        g_engy_t=zeros(1,1,64)
        g_engy_t[1,1,:]=g_engy
        
        flux_PADt = sum(flux_arr[:, :, energy_i] .* g_engy_t[:,:,energy_i], dims=3) / sum(g_engy_t[:,:,energy_i])
        flux_PAD=flux_PADt[:,:,1]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        return [times_num,pitch_angle_PAD,flux_PAD,energy_double]
    end
end
function read_kp(filename)
    #skiprow. keyparamater ion density ion temperature
    #kp i, 32+ 163, 16+ 172,H+ 60,O+ 62,O2+ 64   mvn_kp_insitu_20200608_v17_r02.tab
    function kp_indicate(n)
        m = n * 16-16 .+ (4:19)
        return m
    end
    lines=readlines(filename)
    lines = [line for line in lines if !startswith(line, "#")]
    time    = [line[1:19] for line in lines]
    time_dt = Dates.DateTime.(time, "yyyy-mm-ddTHH:MM:SS")
    Ntime=length(time)
    kp_dict=Dict(
        "electorn density" => 2,
        "Ne quality min" => 3,
        "Ne quality max" => 4,
        "temperature" => 5,
        "local hour" => 196,
        "32+ ion" => 163,
        "16+ ion" => 172,
        "H+ T"    =>  60,
        "O+ T"    =>  62,
        "O2+ T"   =>  64,
    )
    kp_t= Dict()
    for key in keys(kp_dict)
        kp_t[key] = kp_indicate(kp_dict[key])
    end
    result_dict = Dict()
    for (key, value) in kp_t
        var = [line[value] for line in lines]
        var_float = parse.(Float64, replace.(var, "NaN" => "1e-10"))#var #
        result_dict[key] = var_float
    end 

    pc2ss_Matrix = zeros(Ntime,3,3)
    M_dict = Dict()
    for l in (218:226)
        value = kp_indicate(l)
        var =  [line[value] for line in lines]
        var_float = parse.(Float64, var)
        M_dict[l-217] = var_float
    end
    for (key,var) in M_dict
        i = div(key - 1, 3) + 1  # 计算行索引(1-based)
        j = rem(key - 1, 3) + 1
        pc2ss_Matrix[:,i,j] = var
    end
    result_dict["pc2ss_Matrix"] = pc2ss_Matrix
    
    return time_dt,result_dict
end
function load_lpw_lpnt(file)
    data        = cdflib.cdfread.CDF(file)
    times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    datas       = convert(Array{Float64,2}, (get(data,"data")))
    return times_num,datas
end
function load_lpw_wn(file)
    data        = cdflib.cdfread.CDF(file)
    times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
    datas       = convert(Array{Float64,1}, (get(data,"data")))
    return times_num,datas
end
function file_list(model)
    path = file_path_dict[model]
    file_path="E:/MAVEN/" .* path
    list_path="E:/MAVEN/lists/"*model*"_list.txt"

    data = readdlm(list_path,header=false)
    data = file_path.*data
    return data
end
function find_file_of_data(file_names, element)
    for file_name in file_names
        if occursin(element, file_name)
            return file_name
        end
    end
    return false
end
function data_get_from_date(date; model_index = [])
    File_dict = Dict()
    for model in model_index
        FileList         = file_list(model)
        File_dict[model] = find_file_of_data(FileList, date)
    end 
    
    datas_dict = Dict()
    for model in model_index
        filename      = File_dict[model]
        function_name = read_models[model]
        println(model,",",filename)
        datas_dict[model] = function_name(filename)
    end
    return datas_dict
end
read_models = Dict(
    "MAG_pc1s"     => load_mag,
    "MAG_ss"       => load_mag,
    "MAG_ss1s"     => load_mag,
    "MAG_pc"       => load_mag,
    "LPW_wave"     => load_WaveSpactra,
    "KP"           => read_kp,
    "SWEA_pad_svy" => load_swea_pad,
    "SWEA_spec"    => load_swea_spec,
    "LPW_lpnt"     => load_lpw_lpnt,
    "LPW_wn"       => load_lpw_wn,
)
file_path_dict = Dict(
    "SWEA_spec"    => "SWEA/svyspec/",
    "SWEA_pad_svy" => "SWEA/svypad/",
    "LPW_wave"     => "LPW/wspecpas/",
    "LPW_mrgscpot" => "LPW/mrgscpot/",
    "LPW_lpnt"     => "LPW/lpnt/",
    "LPW_wn"       => "LPW/wn/",
    "MAG_ss1s"     => "MAG/ss_1s/",
    "MAG_ss"       => "MAG/ss/",
    "MAG_pc1s"     => "MAG/pc_1s/",
    "MAG_pc"       => "MAG/pc/",
    "STATIC"       => "STATIC/c6-32e64m/",
    "KP"           => "KP/",
)
end