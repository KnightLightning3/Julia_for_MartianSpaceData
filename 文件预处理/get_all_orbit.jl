# 取得所有轨道对应的时间范围
using TimesDates, Dates
using ColorTypes, CairoMakie
using DataFrames
using LinearAlgebra
using LaTeXStrings
EnvironmentPath = "C:/Users/chengsw/Projects/Package_for_Julia_of_csw/"
include(EnvironmentPath*"MAVEN_load.jl")
import .MAVEN_load;
MAVEN_load.change_kp_read_data(Dict(
    "Orbit Number"    =>210,
));

function get_data(date)
    datas_dict = MAVEN_load.data_get_from_date(date, model_index = ["KP"])
    return datas_dict["KP"]
end
function time_by_orbits(time_kp,Orbit_Number)
    #掐头去尾
    unique_elements = unique(Orbit_Number)
    day0 = Dates.Day.(time_kp[1])
    date_str = Dates.format(time_kp[1], "yyyy-mm-dd")
    Orbit_Number_end = Orbit_Number[findfirst( t -> Dates.Day(t) != day0, time_kp)]
    unique_elements = [item for item  in unique_elements if (item <= Orbit_Number_end)]
    orbits = []
    time_ranges = []
    for i in unique_elements[2:end]
        time_index = findall(x -> x == i, Orbit_Number)
        x_range_orbit = (time_kp[time_index[1]],time_kp[time_index[end]])
        push!(orbits , Base.Int32(i))
        push!(time_ranges , x_range_orbit)
    end
    println(date_str,": done")
    return orbits,time_ranges
end
function val_combine(datas_dict_1,datas_dict_2)

    Orbit_Number_1 = datas_dict_1["Orbit Number"]
    time_kp_1 = datas_dict_1["time"]

    Orbit_Number_2 = datas_dict_2["Orbit Number"]
    time_kp_2 = datas_dict_2["time"]
    
    time_kp, Orbit_Number = [time_kp_1; time_kp_2],[Orbit_Number_1; Orbit_Number_2]

    return time_kp, Orbit_Number
end;


data = MAVEN_load.get_orbits()
println(data[1])
println(data[10000])
println(data[10000][2]+(data[10000][3]-data[10000][2])/2)
# time_start = DateTime(2014, 10, 11)
# time_end = DateTime(2023, 5, 15) - Dates.Day(1)
# days = range(time_start, time_end, step=Dates.Day(1))
# file_path = "E:/MAVEN/orbit_time_range.txt";
# file = open(file_path,"w")
# try
#     global datas_dict_1  =get_data(days[1])
#     for day in days[2:end-1]
#         global datas_dict_2  = get_data(day)
#         if datas_dict_2["flag"] == false
#             continue
#         end
#         time_kp, Orbit_Number = val_combine(datas_dict_1,datas_dict_2)
#         orbits,time_ranges = time_by_orbits(time_kp, Orbit_Number)
#         global datas_dict_1 = datas_dict_2
#         for i in 1:length(orbits)
#             println(file, orbits[i],",",time_ranges[i][1],",",time_ranges[i][2])
#         end
#     end
# finally
#     close(file)
# end