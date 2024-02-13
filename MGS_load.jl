# 读取和计算MGS数据
# 使用data_get_from_date函数做全局读取

module MGS_load
root_path = "E:/MGS/"
using Dates
# struct MGS_mag
#     staute::Bool
#     time::Vector{DateTime} 
#     B0::Vector{Float32}
#     B::Matrix{Float32} 
#     position::Matrix{Float32} 
# end
function load_mag(file::String);

    lines=readlines(file)
    line_i = maximum(findall(line -> startswith(line, "END"), lines[1:600]))
    lines = lines[line_i+1:end]

    nums = length(lines)
    times = Vector{DateTime}(undef,nums)
    B = Matrix{Float32}(undef,nums,3)
    position = Matrix{Float32}(undef,nums,3)

    function get_data_from_line(line::String)
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
        x = parse(Float32,line[75:86])
        y = parse(Float32,line[87:98])
        z = parse(Float32,line[99:110])

        return epoch,[bx,by,bz],[x,y,z]
    end
    
    for (i,line) in enumerate(lines)
        times[i],B[i,:],position[i,:] = get_data_from_line(line)
    end

    B_total = sqrt.(sum(B.^2, dims=2)); B_total = B_total[:,1]

    data=Dict(
        "data staute" => true,
        "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
        "Vars"     => [times,B_total,B,position],
    )
    # data = MGS_mag(true,times,B_total,B,position)
    return data
end
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
function read_list()
    list_path = root_path*"MAG_SUNSTATE_list"
    files = readlines(list_path)
    files = root_path.*files  
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