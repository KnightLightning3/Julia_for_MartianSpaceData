# 将ngi的l3数据的一天多份整合成一天一份

include("../MAVEN_load.jl")
import .MAVEN_load
using Dates
using Base.Filesystem
using ProgressMeter
using JLD2

data_key = "NGIMS_sht_l3"
data_key = "NGIMS_den_l3"
name_formats = Dict(
   "NGIMS_sht_l3" => ["mvn_ngi_l4_res-sht-","NGIMS_sht_l4"],
   "NGIMS_den_l3" =>["mvn_ngi_l4_res-den-","NGIMS_den_l4"]
)

name_format = name_formats[data_key][1]
files = MAVEN_load.file_list(data_key)
save_path = MAVEN_load.root_path
grouped_files = Dict{String, Vector{String}}()
pattern = r"\d{8}"
for file in files
    date_match = match(pattern, file)
    if date_match !== nothing
        date_str = date_match.match
        if !haskey(grouped_files, date_str)
            grouped_files[date_str] = []
        end
        push!(grouped_files[date_str], file)
    end
end
files_list = []
for (date, file_group) in grouped_files
    # 创建一个新的输出文件名
    dir = "$save_path/NGIMS/l4/$(date[1:4])/$(date[5:6])/"
    output_filename = "$(dir)$name_format$date.csv"
    if !isdir(dir)
        mkpath(dir)
    end
    # 打开文件写入模式
    open(output_filename, "w") do outfile
        for file in file_group
            # 读取文件内容并写入输出文件
            lines = readlines(file)
            write(outfile, join(lines[2:end], "\n"))
        end
    end
    println("文件已生成: $output_filename")
    push!(files_list,"$(date[1:4])/$(date[5:6])/$name_format$date.csv")
end

f=save_path*"lists/$(name_formats[data_key][2])_list.txt"
open(f,"w") do io
    for ff in files_list
        println(io,ff)
    end
end
println("done")