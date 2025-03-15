module TW_MINPA
using Dates

root_path = "E:/Tianwen-1/"
secondry_path = root_path*"MINPA/2B/"

function build_file_list()
    files = []
    println(files)
    years = 2020:2024
    for y in years
        path = secondry_path*string(y)*"/"
        if !isdir(path)
            continue
        end
        paths = readdir(path)
        i_path = findall(x -> endswith(x,".2BL"), paths)
        paths = "$y/".*paths[i_path]
        match = r"\d{14}"
        time_range = [DateTime(x[begin:end-4], DateFormat("y-m-dTH:M:S.s")) for x in paths]
        append!(files,paths)
    end
    open(root_path*"List/"*"MINPA_list.txt", "w") do io
        for file in files
            println(io, file)
        end
    end
    return nothing
end

function read_list()
    list_path = root_path*"List/"*"MINPA_list.txt"
    files = readlines(list_path)
    files = root_path.*files  
    return files
end

end

import .TW_MINPA
using DelimitedFiles, DataFrames
using Dates

# TW_MINPA.build_file_list()
minpafmod1 = "E:/Tianwen-1/MINPA/2B/2022/".*["HX1-Or_GRAS_MINPA-MOD1-DEF_SCI_N_20220612034833_20220612105300_01288_A.2B"]

massmod1 = [1,2,4,16,28,32,44,64]
energymod1 = [2.81, 3.548928, 4.482167, 5.660813, 7.149401, 9.029433, 11.40385, 14.40264, 18.19001, 22.97332, 29.01447, 36.64422, 46.28032, 58.45036, 73.82067, 93.23282, 117.7497, 148.7135, 187.8198, 237.2095, 299.587, 378.3675, 477.8644, 603.5253, 762.2305, 962.6694, 1215.816, 1535.532, 1939.321, 2449.292, 3093.366, 3906.809, 4934.157, 6231.661, 7870.361, 9939.98, 12553.83, 15855.03, 20024.33, 25290.0]
θmod1 = [11.3, 33.8, 56.2, 78.7].|>deg2rad
ϕmod1 = [11.25, 33.75, 56.25, 78.75, 101.25, 123.75, 146.25, 168.75, 191.25, 213.75, 236.25, 258.75, 281.25, 303.75, 326.25, 348.75].|>deg2rad

@time minpamod1 = reduce(vcat, [identity.(DataFrame(readdlm(file), :auto)) for file in minpafmod1])
minpautmod1 = map(x->DateTime(x[begin:end-4], DateFormat("y-m-dTH:M:S.s")), minpamod1[!, 1])
minpajulianmod1 = datetime2julian.(minpautmod1)
minpadfimod1= reshape(Array(minpamod1[:,60:20539]), length(minpautmod1), length(massmod1), length(ϕmod1), length(θmod1), length(energymod1)) #时间 质量数 方位角 俯仰角 能道 #
ind =findall(x->x<0, minpadfimod1)
minpadfimod1[ind] .= 0.0

massnmod1 = [1, 4, 16]
energynhmod1 = [29.3, 64.4, 118.2, 200.8, 327.5, 521.8, 820, 1277.3] .+ [80.2, 176.3, 323.7, 549.8, 896.7, 1428.9, 2245.3, 3497.8] #
energynhmod1 = 0.5 .* energynhmod1
minpadfnmod1 = reshape(Array(minpamod1[:,20544:21311]), length(minpautmod1), length(massnmod1), length(ϕmod1), length(energynhmod1) *2) #时间 质量数 方位角 俯仰角 能道 #

minpadfnmod1 = minpadfnmod1[:, :, :, 2:2:16] .+ minpadfnmod1[:, :, :, 1:2:16] #.+ minpadfnmod1[:, :, :, 9:16]
ind =findall(x->x<0, minpadfnmod1)
minpadfnmod1[ind] .= 0.0

eknspec=dropdims(sum(minpadfnmod1[:, 1, :, :], dims=(2,)), dims=(2, ))
for ek in eachindex(energynhmod1)
	eknspec[:, ek] = eknspec[:, ek] .* energynhmod1[ek] .* 1e4
end
ind =findall(x->x<=0, eknspec)
eknspec[ind] .= NaN64


ekHspec=dropdims(sum(minpadfimod1[:, 1, :, :, :], dims=(2, 3)), dims=(2, 3))
for ek in eachindex(energymod1)
	ekHspec[:, ek] = ekHspec[:, ek] .* energymod1[ek]
end
ind =findall(x->x<=0, ekHspec)
ekHspec[ind] .= NaN64


ekOspec=dropdims(sum(minpadfimod1[:, 4, :, :, :], dims=(2, 3)), dims=(2, 3))
for ek in eachindex(energymod1)
	ekOspec[:, ek] = ekOspec[:, ek] .* energymod1[ek]
end
ind =findall(x->x<=0, ekOspec)
ekOspec[ind] .= NaN64