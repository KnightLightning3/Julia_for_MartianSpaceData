include("../MAVEN_data/MAVEN_load.jl")
import .MAVEN_load
using Dates
using Base.Filesystem
using ProgressMeter
using FortranFiles
using JLD2
using JSON
# 将MAVEN 的KP 数据转为JLD2二进制格式
function KP_rebuild(file_in, file_out, KP_vars)

    KP_vars_local = KP_vars[file_in[end-9:end-8]]
    varsion = parse(Int32, file_in[end-9:end-8])

    data = MAVEN_load.load_kp(file_in; str_model=true)
    time = data["time"]
    ntime = length(time)

    KP_jld2_data = Dict{String,Any}()
    KP_jld2_data["time"] = time
    KP_jld2_data["varsion"] = varsion

    for i in 2:217
        I = string(i)
        var_format = KP_vars_local[I][2]
        vars = data[I]

        vars_out = []
        if var_format[1] == 'F' || var_format[1] == 'E'
            vars_out = parse.(Float64, vars)
        elseif var_format[1] == 'A'
            vars_out = vars
        elseif var_format[1] == 'I'
            vars_out = parse.(Int64, vars)
        end
        KP_jld2_data[I] = vars_out
    end
    pc2ss_Matrix = zeros(Float64, ntime, 3, 3)
    sc2ss_Matrix = zeros(Float64, ntime, 3, 3)
    for I in (218:226)
        var = data[string(I)]
        var_float = parse.(Float64, var)
        i = div(I - 218, 3) + 1  # 计算行索引(1-based)
        j = rem(I - 218, 3) + 1
        pc2ss_Matrix[:, i, j] = var_float
    end
    for I in (227:235)
        var = data[string(I)]
        var_float = parse.(Float64, var)
        i = div(I - 227, 3) + 1  # 计算行索引(1-based)
        j = rem(I - 227, 3) + 1
        sc2ss_Matrix[:, i, j] = var_float
    end
    KP_jld2_data["pc2ss_Matrix"] = pc2ss_Matrix
    KP_jld2_data["sc2ss_Matrix"] = sc2ss_Matrix

    jldsave(file_out, KP_jld2_data=KP_jld2_data)
    return 0
end;

files = MAVEN_load.file_list("KP");
KP_dict = Dict()
for i in 2:235
    KP_dict[string(i)] = i
end
MAVEN_load.change_kp_read_data(KP_dict);
f = open("../MAVEN_data/KP_vars.json", "r")
KP_vars = JSON.parse(f)
close(f)

f = open(raw"C:\Users\chengsw\Projects\Package_for_Julia_of_csw\MAVEN_data\MAVEN_data_format.json","r")
MAVEN_format = JSON.parse(f)
close(f)


files = MAVEN_load.file_list("KP")
new_list = []
@showprogress 1 "Computing..." for file in files
    new_path = file[1:12] * "l3" * file[19:end-4] * ".jld2"
    dir = dirname(new_path)
    if !isdir(dir)
        mkpath(dir)
    end
    if !isfile(new_path)
        dummy = KP_rebuild(file, new_path, KP_vars)
    end
end;

f=MAVEN_format["save_path"]*"lists/KP_l3_list.txt"
open(f,"w") do io
    for ff in new_list
    println(io,ff[16:end])
    end
end
println("done")
# build_KP_list_files

# def search_downloaded_files(save_path,filestyle):
#     filenames =[]
#     yyyy = os.listdir(save_path)
#     for iy in yyyy:
#         mm   = os.listdir(save_path+iy+"/")
#         for im in mm:
#             files = os.listdir(save_path+iy+"/"+im+"/")
#             filepaths = [iy+"/"+im+"/"+file for file in files if re.match(filestyle,file)]
#             for filepath in filepaths:
#                 filenames.append(filepath)
#     return filenames