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