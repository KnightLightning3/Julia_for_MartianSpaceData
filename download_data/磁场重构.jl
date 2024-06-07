# 将MAVEN 的MAG 数据转为f77二进制格式
include(raw"C:\Users\chengsw\Projects\Package_for_Julia_of_csw\load_data\MAVEN_load.jl")
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

mag_keys = ["MAG_pc","MAG_ss"]#,"MAG_ss1s","MAG_pc1s",
for mag_key in mag_keys
    local files = MAVEN_load.file_list(mag_key)
    @showprogress 1 "Computing..."*mag_key for file in files  #  
        old_path = file[1:13]*"l3"*file[16:end-4]*".f77_unformatted"
        new_path = file[1:13]*"l3"*file[16:32]*"l3"*file[35:end-4]*".f77_unformatted"
        dir = dirname(new_path)
        if !isdir(dir)
            mkpath(dir)
        end
        if isfile(old_path)
            rm(old_path)
        end
        if !isfile(new_path)
            touch(new_path)
            BData = MAVEN_load.load_mag_l2(file)["Vars"]
            data2bi(BData,new_path)
        end
    end
end