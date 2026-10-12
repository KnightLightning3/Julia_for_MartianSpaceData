# 取得所有轨道对应的时间范围
using TimesDates, Dates
using ColorTypes, CairoMakie
using DataFrames
using LinearAlgebra
using LaTeXStrings
include("../MAVEN_data/MAVEN_load.jl")
import .MAVEN_load;
MAVEN_load.change_kp_read_data(Dict(
    "Orbit Number"    =>210,
));

"""
    get_data(date) -> Dict{Symbol, Any}

按日期读取 MAVEN KP 轨道数据。

# 参数说明
- `date`: 目标日期。

# 返回值
- `Dict{Symbol, Any}`: KP 数据字典（含 `:time` 与 `"Orbit Number"` 等）。

# 注意事项
- 依赖模块 `MAVEN_load` 已载入且已配置 `kp_dict`。
"""
function get_data(date)
    datas_dict = MAVEN_load.data_get_from_date(date, model_index = ["KP"])
    return datas_dict["KP"]
end
"""
    time_by_orbits(time_kp, Orbit_Number) -> (Vector, Vector)

根据轨道号序列计算各轨道对应的时间范围。

# 功能与算法概述
取唯一轨道号并剔除跨日轨道后，对每个轨道取其首末时间构成时间区间。

# 参数说明
- `time_kp`: 时间序列。
- `Orbit_Number`: 与时间对应的轨道号序列。

# 返回值
- `(orbits, time_ranges)`: 轨道号列表与对应时间区间列表。
"""
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
"""
    val_combine(datas_dict_1, datas_dict_2) -> (Vector, Vector)

合并相邻日期数据中的时间与轨道号序列。

# 参数说明
- `datas_dict_1`, `datas_dict_2`: 相邻两日的 KP 数据字典。

# 返回值
- `(time_kp, Orbit_Number)`: 拼接后的时间与轨道号序列。
"""
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