# 将MAVEN 的MAG 数据转为f77二进制格式
include("../MAVEN_data/MAVEN_load.jl")
import .MAVEN_load
using Dates
using Base.Filesystem
using ProgressMeter
using FortranFiles
function data2bi(data,file)
    timeB,BB,B,position = data
    timeB_julian = datetime2julian.(timeB)
    n_time = Int64(length(timeB))
    timeB_in = convert(Vector{Float64},timeB_julian)
    BB_in = convert(Vector{Float32},BB)
    B_in = convert(Array{Float32,2},B)
    position_in = convert(Array{Float32,2},position)

    f = FortranFile(file,"w")
    write(f, n_time)
    write(f, timeB_in)
    write(f, BB_in)
    write(f, B_in)
    write(f, position_in)
    close(f)
end

mag_keys = ["MAG_ss1s","MAG_pc1s","MAG_pc","MAG_ss"]#]#]#,
# if !isdefined(lists)
#     lists = []
# end
for mag_key in mag_keys
    # println("\033[0;32mBUILDING $mag_key\033[0m")
    local files = MAVEN_load.file_list(mag_key)
    for file in files  # @showprogress 1 "Computing..."*mag_key 
        new_path = file[1:13]*"l3"*file[16:32]*"l3"*file[35:end-4]*".f77_unformatted"
        dir = dirname(new_path)
        if !isdir(dir)
            mkpath(dir)
        end
        # if file in lists
        #     println("skip $(new_path[25:end])")
        #     continue
        # end
        # print("\033[0;32mREADing $(new_path[25:end])\033[0m")
        # BData = MAVEN_load.load_mag_l2(file)["Vars"]
        # push!(lists,file)
        if !isfile(new_path)
            print("\033[0;32mBuilding $(new_path[25:end])\033[0m \n")
            BData = MAVEN_load.load_mag_l2(file)["Vars"]
            touch(new_path)
            data2bi(BData,new_path)
        else
            print("\033[0;33mSKIP $(new_path[25:end])\033[0m \r")
        end
    end
end