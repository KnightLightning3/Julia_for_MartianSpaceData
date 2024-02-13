module MAVEN_load
# 读取和计算MAVEN数据
# 使用data_get_from_date函数做全局读取
using PyCall
cdflib = pyimport("cdflib")
using TimesDates, Dates
using DataFrames
using DelimitedFiles
using JSON
# using NaNMath; nm=NaNMath
# read filelist parts
    function show_load_models()  # 打印所有可支持的数据的读取.
        keys_arr = keys(read_models)
        for key in keys_arr
            println(key)
        end
        return keys_arr
    end
    function file_list(model)
        path = read_models[model][1]
        file_path=root_path .* path
        list_path=root_path*"lists/"*model*"_list.txt"

        data = readlines(list_path)
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
    function data_get_from_date(date; model_index = [],show_filename=true) #读取函数
        File_dict = Dict()
        for model in model_index
            FileList         = file_list(model)
            File_dict[model] = find_file_of_data(FileList, date)
        end 
        datas_dict = Dict()
        for model in model_index
            filename      = File_dict[model]
            function_name = read_models[model][2]
            if show_filename 
                println(model,",",filename)
            end
            if File_dict[model] == false
                datas_dict[model] = false
            else
                datas_dict[model] = function_name(filename)
            end
        end
        return datas_dict
    end
##load parts
    function load_burst(file);
        data = cdflib.cdfread.CDF(file)
        time  = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        data  = convert(Array{Float64,1}, (get(data,"data")))
        data_dic=Dict(
            "Var name"=> "time[Ntime],data[Ntime]",
            "Vars"    => [time,data]
        )
        return data_dic
    end
    function load_swea_spec(file; No_NaN=false);
        data = cdflib.cdfread.CDF(file)
        times_num  = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        energy_arr = convert(Array{Float64,1}, (get(data,"energy")))
        flux_arr  = convert(Array{Float64,2},(get(data,"diff_en_fluxes")))
        if No_NaN
            if No_NaN
                flux_arr[flux_arr .<= 1e-10] .= 1e-10
            end
        end
        data=Dict(
            "Var name"=> "time[Ntime],energy[Nenergy],eflux[Ntime,Nenergy] ",
            "Vars"    => [times_num,energy_arr,flux_arr]
        )
        return data
    end
    function load_WaveSpactra(file;No_NaN=false);
        data      =  cdflib.cdfread.CDF(file)
        epoch     =  unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        freq      =  convert(Array{Float64,2}, (get(data,"freq")))
        wave_data =  convert(Array{Float64,2},(get(data,"data")))
        if No_NaN
                wave_data[wave_data .<= 1e-20] .= 1e-20
        end
        data=Dict(
            "Var name"=> "time[Ntime], freq[Ntime,Nfreq] Hz, wave[Ntime,Nfreq] P_E",
            "Vars" => [epoch,freq,wave_data]
        )
        return data
    end
    function load_mag(file);
        lines=readlines(file)
        line_i = maximum(findall(line -> startswith(line, "END"), lines[1:600]))
        lines = lines[line_i+1:end]
    
        nums = length(lines)
        times = Vector{DateTime}(undef,nums)
        B = Matrix{Float32}(undef,nums,3)
        position = Matrix{Float32}(undef,nums,3)
    
        function get_data_from_line(line::String)
            # colspecs = [(1,6),(8,10),(12,13),(15,16),(18,19),(21,23),(39,48),(50,58),(60,68),(74,88),(90,103),(105,118)]
            year = parse(Int32,line[1:6])
            doy = parse(Int32,line[8:10])
            hour = parse(Int32,line[12:13])
            min = parse(Int32,line[15:16])
            sec = parse(Int32,line[18:19])
            msec = parse(Int32,line[21:23])
    
            epoch = DateTime(year, 1, 1,hour,min,sec,msec) + Dates.Day(doy-1)
            
            bx = parse(Float32,line[39:48])
            by = parse(Float32,line[50:58])
            bz = parse(Float32,line[60:68])
            x = parse(Float32,line[74:88])
            y = parse(Float32,line[90:103])
            z = parse(Float32,line[105:118])
    
            return epoch,[bx,by,bz],[x,y,z]
        end
        
        for (i,line) in enumerate(lines)
            times[i],B[i,:],position[i,:] = get_data_from_line(line)
        end
    
        B_total = sqrt.(sum(B.^2, dims=2)); B_total = B_total[:,1]

        data=Dict(
            "Var name"=> "time[Ntime], B_total[Ntime],B[Ntime,3],local_time[Ntime],latitude[Ntime], alt[Ntime],position[Ntime,3]",
            "Vars"     => [times,B_total,B,position]
        )
        return data
    end
    function load_static(file; No_NaN=false)
        data   = cdflib.cdfread.CDF(file)
        epoch  = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        energy = convert(Array{Float64,3}, (get(data,"energy")))     # Nmass,Nenergy,Nswp
        denergy= convert(Array{Float64,3}, (get(data,"denergy")))    # Nmass,Nenergy,Nswp
        AMU_arr= convert(Array{Float64,3},(get(data,"mass_arr")))    # Nmass,Nenergy,Nswp
        
        eflux  = convert(Array{Float64,3}, (get(data,"eflux")))      # N_DISTS,Nmass,Nenergy
        nswp   = convert(Array{Int32,1},   (get(data,"swp_ind")))    # Nswp_ind
        
        if No_NaN
            eflux[eflux .<= 1e-10] .= 1e-10
        end
        data=Dict(
            "Var name"=> "time,energy[Nmass,Nenergy,Nswp], denergy[Nmass,Nenergy,Nswp], eflux[ Ntime,Nmass,Nenergy ], nswp[Nswp], AMU_arr[Nmass,Nenergy,Nswp]",
            "Vars" => [epoch,energy,denergy,eflux,nswp,AMU_arr]
        )
        return data
    end
    function change_kp_read_data(kp_dict_in)
        global kp_dict = kp_dict_in
    end
    function read_kp(filename)
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
        result_dict["time"] = time_dt
        return result_dict
    end
    function load_lpw_lpnt(file)
        data        = cdflib.cdfread.CDF(file)
        times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        datas       = convert(Array{Float64,2}, (get(data,"data")))
        data = Dict(
            "Var names" => "time[Ntime], Ne[Ntime]",
            "Vars" => [times_num,datas]
        )
        return data
    end
    function load_lpw_wn(file)
        data        = cdflib.cdfread.CDF(file)
        times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        datas       = convert(Array{Float64,1}, (get(data,"data")))
        data = Dict(
            "Var names" => "time[Ntime], Ne[Ntime]",
            "Vars" => [times_num,datas]
        )
        return times_num,datas
    end
    function load_sc_potential(file)
        data        = cdflib.cdfread.CDF(file)
        times_num   = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        potential  = convert(Array{Float64,1}, (get(data,"data")))
        data = Dict(
            "Var names"   => "time[Ntime], potential[Ntime]",
            "Vars" => [times_num,potential]
        )
        return data
    end
    function load_swea_pad(file;  No_NaN = false , mean_PA=true)
        data        = cdflib.cdfread.CDF(file)
        time        = unix2datetime.(cdflib.cdfepoch.unixtime(get(data,"epoch")))
        energy_arr  = convert(Array{Float64,1}, (get(data,"energy")))
        g_engy      = convert(Array{Float64,1}, (get(data,"g_engy")))
        flux        = convert(Array{Float64,3}, (get(data,"diff_en_fluxes")))
        pitch_angle = convert(Array{Float64,3}, (get(data,"pa")))
        g_pa        = convert(Array{Float64,3}, (get(data,"g_pa")))
        # pitch_angle = (pitch_angle[:, 1:8, :] .+ pitch_angle[:, 16:-1:9, :]) ./ 2
        
        # g_pa = (g_pa[:, 1:8, :] .+ g_pa[:, 16:-1:9, :]) ./ 2
        # flux        = (flux[:, 1:8, :] .+ flux[:, 16:-1:9, :]) ./ 2
        if mean_PA
            pitch_angle,flux,g_pa = mean_SWEA_pad_pa(pitch_angle,flux,g_pa)
        end
        if No_NaN
            flux[flux .<= 1e-10] .= 1e-10
        end
        data = Dict(
            "Var names"   => "time[NT], pitch_angle[NT,Npa,Nenergy], energy[Nenergy], flux[NT,Npa,Nenergy], g_pa[NT,Npa,Nenergy], g_engy[Nenergy]",
            "Vars"        => [time, pitch_angle,energy_arr, flux, g_pa, g_engy]
        )
        return data
    end
## 数据处理
function caculate_mag(position;models=["alt"])
    function c_alt(position) 
        alt = sqrt.(sum(position.^2, dims=2)) .- 3393.5
        alt = alt[:,1]
        return alt
    end
    function c_local_time(position) 
        local_time = atan.(position[:, 2], position[:, 1]) ./ π .* 12.0 .+ 12.0
        return local_time
    end
    function c_latitude(position) 
        latitude   = atan.(position[:, 3], sqrt.(sum(position[:,1:2].^2, dims=2)) ) ./ π .* 180.0
        return latitude
    end
    funcs = Dict(
        "alt" => c_alt,
        "local_time" => c_local_time,
        "latitude" => c_latitude,
    )
    for model in models
        data[model] = funcs[model](position)
    end
end
function mean_SWEA_pad_pa(pitch_angle,flux,g_pa)
    pitch_angle = (pitch_angle[:, 1:8, :] .+ pitch_angle[:, 16:-1:9, :]) ./ 2
    g_pa = (g_pa[:, 1:8, :] .+ g_pa[:, 16:-1:9, :]) ./ 2

    flux1=flux[:, 1:8,     :]
    flux2=flux[:, 16:-1:9, :]
    nan_indices_flux1 = findall(isnan.(flux1))
    nan_indices_flux2 = findall(isnan.(flux2))
    flux1[nan_indices_flux1] = flux2[nan_indices_flux1]
    flux2[nan_indices_flux2] = flux1[nan_indices_flux2]

    flux = (flux1 + flux2) ./ 2
    
    return pitch_angle,flux,g_pa
end
function caculate_static(data;model="total",mass_range=[0,0])
    epoch,energy,denergy,eflux,swp_arr,AMU_arr = data["Vars"]
    if model == "total"
        energy_all_mass = sum(energy .* denergy, dims=1)  ./ sum(denergy, dims=1); energy_all_mass = energy_all_mass[1,:,:]  
        eflux_all_mass  = sum(eflux[:,:,:], dims=2) ; eflux_all_mass = eflux_all_mass[:,1,:]
        
        # for i =1:ntime
        #     denergy_t = denergy[:,:,swp_arr[i]+1]
        #     eflux_t=eflux_arr[i,:,:]
        #     eflux_all_mass[i,:]=sum(eflux_t.* denergy_t, dims=1) ./ sum(denergy_t, dims=1)
        # end
        return_data = Dict(
            "Var name"=> "time,energy[Nenergy,Nswp], eflux[ Ntime,Nenergy], nswp[Nswp]",
            "Vars" => [epoch,energy_all_mass,eflux_all_mass,swp_arr]
        )
        return return_data
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
    return_data = Dict(
        "Var name"=> "time,energy[Nenergy,Nswp], eflux[ Ntime,Nenergy], nswp[Nswp]",
        "Vars" => [epoch,energy_mass,eflux_mass,swp_arr]
    )
    return return_data #[energy_mass,eflux_mass]
end
function carclu_SWEA_pad(data; energy_range=[])
    time, pitch_angle,energy_arr, flux_arr, g_pa, g_engy = data["Vars"]
    if size(energy_range)[1] == 1
        _, index = findmin(abs.(energy_arr .- energy_range))
        index = index[1]
        energy_single = energy_arr[index]
        pitch_angle_PAD = pitch_angle[:, :, index]
        flux_PAD        = flux_arr[:, :, index]
        flux_PAD = [isnan(t) ? 1e-10 : t for t in flux_PAD]
        return_data = Dict(
            "Var name"    => "time[Ntime], pitch_angle[Ntime,Npa], eflux[Ntime,Npa], energy_single[1]",
            "Vars"        => [time, pitch_angle_PAD, flux_PAD, energy_single]
        )
        return return_data #[time,pitch_angle_PAD,flux_PAD,energy_single]
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
        return_data = Dict(
            "Var name"    => "time[Ntime], pitch_angle[Ntime,Npa], eflux[Ntime,Npa], energy_double[2]",
            "Vars"        => [time, pitch_angle_PAD, flux_PAD, energy_double]
        )
        return return_data #[time,pitch_angle_PAD,flux_PAD,energy_double]
    end
end

function eflux2F(energy,eflux)
    M = me
    # E0=M*C^2/EV   #静止能量 eV
    #energy 与 eflux 一一对应
    # E0=M*C^2/EV
    γ=(energy * 1e-3 /E0 + 1)
    β=sqrt(1.0 - 1.0 / γ^2)
    P=γ *M * β *C        # kg m/s
    # V=β .* C
    F = (γ*M)^3 * eflux/energy *1e4 /EV / P^2
    return F
end
function Doppler_Shift(f,V_sc,k,θ) # wave frequence shift with spacecraft velocity
    # θ angle between SC and wave vector
    ω_obs = f * 2 * π
    ω_real = ω_obs - k * V_sc * cos(θ)
    return ω_real
end
const EV=1.602176487e-19
const C=3.0e8
const Me=9.109e-31

dir = dirname(@__FILE__) 
file = open(dir*"/"*"data_format.json", "r")
data = JSON.parse(read(file, String))
close(file)
root_path = data["save_path"] #所有文件的根目录
kp_dict = data["kp_dict"]
data_model = data["data_model"]
read_models = Dict{String, Tuple{String, Function}}()
for (key, value) in data_model
    func=eval(Meta.parse(value[4]))
    read_models[key] = (value[3],func)
end

end