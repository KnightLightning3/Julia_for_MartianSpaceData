# 读取和处理 MGS 磁场数据，并提供按日期组织的统一读取入口。

module MGS_load
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
include(joinpath(@__DIR__, "..", "common", "paths.jl"))
using .Paths
root_path = Paths.mgs_data_root()  # 数据根目录由 config/settings.toml 配置
using Dates
# struct MGS_mag
#     staute::Bool
#     time::Vector{DateTime} 
#     B0::Vector{Float32}
#     B::Matrix{Float32} 
#     position::Matrix{Float32} 
# end
"""
    get_data_from_line_for_mag_read(line::String) -> (DateTime, Vector, Vector)

解析单条 MGS 磁场文本记录中的时间、磁场与位置。

# 功能与算法概述
按固定字符列宽解析年积日与时刻得到 `epoch`，再解析磁场与位置分量。

# 参数说明
- `line::String`: 单行文本。

# 返回值
- `(epoch, [bx,by,bz], [x,y,z])`: 时间与磁场、位置分量。
"""
function get_data_from_line_for_mag_read(line::String)
    year, doy, hour, min, sec, msec = parse.(Int32, [
        line[1:6], line[8:10], line[12:13], line[15:16], line[18:19], line[21:23]
    ])
    epoch = DateTime(year, 1, 1,hour,min,sec,msec) + Dates.Day(doy-1)
    bx,by,bz,x,y,z = parse.(Float32,[
            line[39:48],line[50:58],line[60:68],line[75:86],line[87:98],line[99:110]
        ])
    return epoch,[bx,by,bz],[x,y,z]
end
"""
    load_mag(file::String) -> Dict{String, Any}

读取并解析指定的 MGS 磁场数据文件。

# 功能与算法概述
跳过表头后逐行调用 `get_data_from_line_for_mag_read` 解析，用 `try-catch` 跳过坏行，
计算旋磁总强度并以统一字典返回。

# 参数说明
- `file::String`: MGS 磁场文本文件路径。

# 返回值
- `Dict{String, Any}`: 含 `"Vars" => [time, B_total, B, position]` 等键的字典。

# 注意事项
- 解析失败的行被丢弃，不报错。
"""
function load_mag(file::String);

    lines=readlines(file)
    nums = length(lines)
    line_i = findlast(line -> startswith(line, "END"), lines[1:min(600,nums)])
    lines = lines[line_i+1:end]

    nums = length(lines)
    times = Vector{DateTime}(undef,nums)
    B = Matrix{Float32}(undef,nums,3)
    position = Matrix{Float32}(undef,nums,3)
    flag = Vector{Bool}(undef,nums)
    @inbounds for (i,line) in enumerate(lines)
        try
            times[i],B[i,:],position[i,:] = get_data_from_line_for_mag_read(line)
        catch e
            # println(file," : ",i,e)
            flag[i] = false
            continue
        end
        flag[i] = true
    end
    # index = findall( x -> x , flag)
    # println(file," : ",length(index))
    times = times[flag]
    B = B[flag,:]
    position =position[flag,:]
    B_total = sqrt.(sum(B.^2, dims=2)); B_total = B_total[:,1]

    data=Dict(
        "data staute" => true,
        "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
        "Vars"     => [times,B_total,B,position],
    )
    # data = MGS_mag(true,times,B_total,B,position)
    return data
end
"""
    read_list() -> Vector{String}

读取 MGS 本地磁场数据文件清单并拼上根目录。

# 功能与算法概述
逐行读取 `MAG_SUNSTATE_list` 中的相对路径，再用 `joinpath` 与 `root_path` 组合。

# 返回值
- `Vector{String}`: 所有 MGS 磁场文件的完整路径。

# 注意事项
- `root_path` 经 `common/paths.jl` 解析（`Paths.mgs_data_root()`，由
  `config/settings.toml` 的 `paths.mgs_data_root` 配置）。
"""
function read_list()
    list_path = joinpath(root_path, "MAG_SUNSTATE_list")
    files = readlines(list_path)
    files = joinpath.(root_path, files)
    return files
end
end


# import .MGS_load
# using TimesDates, Dates
# println("-----NEW PORESS----")
# file = "E:/MGS/1999/091_120APR/MAG_SUNSTATE/99096.STS"
# date = MGS_load.load_mag(file)
# time,b0,b,position=date["Vars"]
# for i =1:20
#     println(time[i])
#     println(position[i,1],b0[i])
# end
