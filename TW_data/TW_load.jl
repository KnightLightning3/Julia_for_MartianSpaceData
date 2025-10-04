# 读取和计算天问一号数据
# 使用data_get_from_date函数做全局读取

module TW_load
root_path = "E:/Tianwen-1/"
using Dates

# function load_mag(file::String);#弃用，以dlm方法为准

#     lines=readlines(file)
#     lines = lines[20:end]

#     nums = length(lines)
#     times = Vector{DateTime}(undef,nums)
#     B = Matrix{Float32}(undef,nums,3)
#     position = Matrix{Float32}(undef,nums,3)
#     flag = Vector{Int32}(undef,nums)
    
#     @inbounds for (i,line) in enumerate(lines)
#         times[i],B[i,:],position[i,:],flag[i] = get_data_from_line(line)
#     end

#     B_total = sqrt.(sum(B.^2, dims=2)); B_total = B_total[:,1]

#     data=Dict(
#         "data staute" => true,
#         "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
#         "Vars"     => [times,B_total,B,position],
#         "flag"     => flag
#     )
#     # data = MGS_mag(true,times,B_total,B,position)
#     return data
# end
# function get_data_from_line(line::String)
#     epoch = DateTime(line[1:23], DateFormat("y-m-dTH:M:S.s"))
#     # data_t = [line[33:44],line[45:56],line[57:68],line[69:79],line[80:90],line[91:101]]
#     bx = parse(Float32,line[33:44])
#     by = parse(Float32,line[45:56])
#     bz = parse(Float32,line[57:68])
#     x = parse(Float32,line[69:79])
#     y = parse(Float32,line[80:90])
#     z = parse(Float32,line[91:101])
#     iflag = parse(Int32,line[139:140])
#     return epoch,[bx,by,bz],[x,y,z],iflag
# end
using DelimitedFiles,DataFrames
function load_mag_2c_bydlm(file::String);
    mag2c1hz = identity.(DataFrame(readdlm(file, skipstart=19), :auto))
    name = ["Time", "Sampling_Rate", "X_MSO", "Y_MSO", "Z_MSO", "Probe_Position_X_MSO", "Probe_Position_Y_MSO", "Probe_Position_Z_MSO", "Roll", "Pitch", "Yaw",  "Quality_Flags"]
    rename!(mag2c1hz, name)
    mag2c1hz[!, :Time] = map(x->DateTime(x[begin:end-4], DateFormat("y-m-dTH:M:S.s")), mag2c1hz[!, :Time])
    unique!(mag2c1hz) #remove depulicate rows
    sort!(mag2c1hz) #sorting

    times = mag2c1hz[!, :Time]
    BMSO1hz = mag2c1hz[:, [:X_MSO, :Y_MSO, :Z_MSO]]
    position = mag2c1hz[:, [:Probe_Position_X_MSO, :Probe_Position_Y_MSO, :Probe_Position_Z_MSO]]
    roll = mag2c1hz[!, :Roll]
    pitch = mag2c1hz[!, :Pitch]
    yaw = mag2c1hz[!, :Yaw]
    flag = mag2c1hz[:, :Quality_Flags]
    # ind0 = findall(x-> !isnan(x), BMSO1hz[!, 1] )
    # ind1 = findall(x-> isnan(x), BMSO1hz[!, 1] )
    # if length(ind1) >= 1 && length(ind0) > 1
    #     for ib in 1:3 
    #         interp_linear = linear_interpolation(magut1hz[ind0], BMSO1hz[ind0, ib]; extrapolation_bc=Line())
    #         BMSO1hz[ind1, ib] = interp_linear(magut1hz[ind1])
    #     end
    # end

    B_total = sqrt.(BMSO1hz[:,:X_MSO].^2 + BMSO1hz[:,:Y_MSO].^2 + BMSO1hz[:,:Z_MSO].^2); B_total = B_total[:,1]

    data=Dict{Symbol,Any}(
        :data_load_flag => true,
        :time => times |> Array,
        :epoch => times |> Array,
        :B => BMSO1hz |> Array,
        :B_total => B_total |> Array,
        :position => position |> Array,
        :flag     => flag |> Array,
        :yaw => yaw |> Array,
        :pitch => pitch |> Array,
        :roll => roll |> Array,
    )
    return data
end

function calculate_mag(position;models=["alt"])
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
    results = Dict{Symbol,Any}(
        :alt => c_alt,
        :local_time => c_local_time,
        :latitude => c_latitude,
    )
    for model in models
        data[model] = results[model](position)
    end
end

function get_spc2mso_rot_matrix_via_2c(dat) # 需要load_mag_2c_bydlm的返回值\
    ntime = length(dat[:time])
    rot_matrix = zeros(ntime,3,3)

    local pitch = dat[:pitch].|>deg2rad
    local yaw   = dat[:yaw]  .|>deg2rad
    local roll  = dat[:roll] .|>deg2rad
    rot_matrix = zeros(Float64, ntime, 3, 3)
    for i in 1:ntime
        local r,p,y = roll[i],pitch[i],yaw[i]
        local cp = cos(p)
        local sp = sin(p)
        local cy = cos(y)
        local sy = sin(y)
        local cr = cos(r)
        local sr = sin(r)
        rot_matrix[i,1,:] = [cp*cy, sy*cr+sr*sp*cy, sr*sy-cr*sp*cy]
        rot_matrix[i,2,:] =  [-cp*sy, cr*cy-sr*sp*sy, sr*cy+cr*sp*sy]
        rot_matrix[i,3,:] = [sp, -sr*cp, cr*cp]
    end
    return dat[:time],rot_matrix
end
function read_list()
    list_path = root_path*"List/"*"mag_list.txt"
    files = readlines(list_path)
    files = root_path.*files  
    return files
end

end