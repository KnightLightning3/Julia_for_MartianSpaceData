# 基于mag数据制作maven 飞行器的速度
# 使用二次函数拟合计算
using Dates
using FortranFiles
include("../MAVEN_load.jl")
include("../MAVEN_STATIC.jl")
import .MAVEN_load;
import .MAVEN_plot;
import .MAVEN_STATIC;
@inline function get_vsc(mag)
    function quadratic_fitted_derivative(x, y)
        n = length(x)
        dy = NaN32 * ones(n)  # 初始化导数结果为 NaN
        # 内部点使用二次拟合计算导数
        @inbounds for i in 2:n-1
            # 对于每个点，选择前后各两个点 (i-1, i, i+1)
            X = [x[i-1], x[i], x[i+1]]
            Y = [y[i-1], y[i], y[i+1]]
            # 通过最小二乘法拟合二次多项式：y = a*x^2 + b*x + c
            A = [X.^2 X ones(3, 1)]  # 构造矩阵 A
            coeffs = A \ Y  # 解线性方程组得到系数 [a, b, c]
            a, b, c = coeffs  # 提取系数
            # 计算导数：p'(x) = 2a*x + b
            dy[i] = 2 * a * x[i] + b
        end
    
        # 处理边界点，使用边界前或边界后的三个点拟合导数
        # 左边界：使用 x[1], x[2], x[3] 来拟合
        X_left = [x[1], x[2], x[3]]
        Y_left = [y[1], y[2], y[3]]
        A_left = [X_left.^2 X_left ones(3, 1)]
        coeffs_left = A_left \ Y_left
        a_left, b_left, _ = coeffs_left
        dy[1] = 2 * a_left * x[1] + b_left  # 计算左边界的导数
    
        # 右边界：使用 x[n-2], x[n-1], x[n] 来拟合
        X_right = [x[n-2], x[n-1], x[n]]
        Y_right = [y[n-2], y[n-1], y[n]]
        A_right = [X_right.^2 X_right ones(3, 1)]
        coeffs_right = A_right \ Y_right
        a_right, b_right, _ = coeffs_right
        dy[n] = 2 * a_right * x[n] + b_right  # 计算右边界的导数
        return dy
    end
    time = datetime2unix.(mag[:epoch])
    Ntime = length(time)
    position = mag[:position]
    # 通过二次函数拟合获取速度
    vsc = zeros(Ntime,3)
    for i in 1:3
        vsc[:,i] = quadratic_fitted_derivative(time.-time[1], position[:, i])
    end
    return (time, vsc, position)
end
@inline function data2bi(time,vsc,position,filename)
    N_time = length(time)
    time_unix = convert(Vector{Float64},time)
    vsc = convert(Array{Float32,2},vsc)
    position = convert(Array{Float32,2},position)
    f = FortranFile(filename,"w")
    write(f, N_time)
    write(f, time_unix)
    write(f, vsc)
    write(f, position)
    close(f)
end
# #获取所有文件和对应的mag文件
files_mag = MAVEN_load.file_list("MAG_ss1s_l3")
dates_mag = [(m.captures[1] ,s) for s in files_mag for m in eachmatch(r"_([0-9]{8})_", s)]

for (date, file) in dates_mag
    version = match(r"_v([0-9]{2})", file).captures[1]
    r_version = match(r"_r([0-9]{2})", file).captures[1]
    new_path = dirname(replace(file, "/l3/" => "/vsc/"))*"/mvn_mag_vsc_ss1s_$(date)_v$(version)_r$(r_version).f77_unformatted"
    dir = dirname(new_path)
    if !isdir(dir)
        mkpath(dir)
    end
    if !isfile(new_path)
        print("\033[0;32mBuilding $(date)\033[0m \n")
        mag = MAVEN_load.load_mag_l3(file)
        time, vsc,position = get_vsc(mag)
        touch(new_path)
        try
            data2bi(time, vsc,position,new_path)
        catch e
            print("\033[0;31m$(date)ERROR: $(e)\033[0m \n")
            rm(new_path)
        end
    else
        print("\033[0;33mSKIP $(date)\033[0m \r")
    end
end