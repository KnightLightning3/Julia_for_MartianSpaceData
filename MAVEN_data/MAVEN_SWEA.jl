# 处理MAVEN的SWIA数据
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module MAVEN_SWEA
using TimesDates, Dates
using Statistics
# using Quaternions
using Rotations
using CommonDataFormat
# -------------------------Export parts-------------------------
# export static_c6_mass_mean,static_c6_energy_mean
# export static_rotation,static_slip,static_slip_2_V,sta_v_4d
# export ion_energy2v,ion_v2energy
#---------------------------初始化-------------------------------- 由于SWIA的糟糕数据,需要对其读取后进行初始化处理
# function mvn_swe_getspec()

# end
# function convert_units(dat)
#     energy  = dat[:energy     ]       #[eV]
#     denergy = dat[:denergy    ]       #[eV]
#     gf      = dat[:gf]  .*dat[:eff]     #energy/angle dependent GF with MCP efficiency [cm2-ster-eV/eV]
#     dt      = dat[:integ_t ]          #integration time [sec] per energy/angle bin (unsummed)
#     dt_arr  = dat[:dt_arr     ]       ##energies * #anodes per bin for rate and dead time corrections
#     dtc     = dat[:dtc        ]       #dead time correction: 1. - (raw count rate)*dead time [1]


# end
function n1d(dat;energy_range=[0,1e8],sc_pot=0) #projects/maven/swea/mvn_swe_n1d.pro

    mass = 5.6856296585483802e-6                    # electron rest mass [eV/(km/s)^2]
    c1 = (mass/(2*π))^1.5
    c2 = (2e5/(mass*mass))
    c3 = 4.0*π*1e-5*sqrt(mass/2.0)  # assume isotropic electron distribution
    tiny = 1.0-31
    
    E = dat[:energy]
    dE = zeros(64)
    dE[1] = abs(E[2]-E[1])/2.0 
    dE[2:63] = abs.(E[3:64] .- E[1:62])./2.0
    dE[64] = abs(E[64]-E[63])
    eflux = dat[:diff_en_fluxes]

    E = reshape(E,1,64)
    dE = reshape(dE,1,64)

    #     ounits = mvn_swe_engy[0].units_name
    # mvn_swe_convert_units, mvn_swe_engy, 'eflux'
    # energy = mvn_swe_engy[tndx].energy
    # eflux = mvn_swe_engy[tndx].data
    # var = mvn_swe_engy[tndx].var
    # bkg = mvn_swe_engy[tndx].bkg
    # sc_pot = mvn_swe_engy[tndx].sc_pot

    # F = (eflux[*,i] - bkg[*,i]) > 0.
    F = eflux
    # S = sdev[*,i]
    pot = sc_pot
    prat = (pot./E)
    ff = x -> x > 1 ? 1.0 : x # prevent prat from going below tiny
    prat = ff.(prat)
    # prat = 0
    Enorm = c3.*dE.*sqrt.(1.0 .- prat) .*(E.^(-1.5))
    N_j = Enorm.*F
    #     S_j = Enorm*S[j]

    dens = sum(N_j,dims=2)[:,1] # sum over energy bins
    return dens
end
function load_quat(filename::String)#读取idl导出的quat数据
    # 数据格式, filename = file.csv ut, scrotmat, msorotmat, format="(I10,1x,4(f14.10,1x),4(f14.10,1x))"
    # 统计行数以预分配矩阵
    n = 0
    open(filename) do io
        for _ in eachline(io)
            n += 1
        end
    end
    # 预分配矩阵，每行包含ut和8个浮点数
    data = Matrix{Float64}(undef, n, 5)
    # 逐行解析数据
    open(filename) do io
        for (i, line) in enumerate(eachline(io))
            # 提取各字段并转换为Float64
            ut = parse(Float64, SubString(line, 1, 10))
            mso1 = parse(Float64, SubString(line, 12, 25))
            mso2 = parse(Float64, SubString(line, 27, 40))
            mso3 = parse(Float64, SubString(line, 42, 55))
            mso4 = parse(Float64, SubString(line, 57, 70))
            
            # 填充数据到矩阵
            @inbounds data[i, :] .= (ut, mso1, mso2, mso3, mso4)
        end
    end
    
    return data
end
function rotate_vector_with_Martrix(in_data,Rotation_Martrix) # inv
    out_data = Rotation_Martrix * in_data
    return out_data
end
function eflux2df!(dat) #projects/maven/swia/mvn_swia_convert_units.pro, 返回单位:1/(cm^3-(km/s)^3)
    energy = reshape(dat[:energy],1,1,1,48)
    mass = dat[:mass]
    df = dat[:diff_en_fluxes] ./ (energy.^2 * 2.0 ./mass./mass.*1e5)
    dat[:df] = df
    return dat
end
function sphere2xyz_for_SWIA(r,θ,ϕ) #general/science/sphere_to_cart.pro
    local ct = cosd(θ)
    x = r * ct *  cosd(ϕ)
    y = r * ct *  sind(ϕ)
    z = r * sind(θ)
    # local st = sind(θ)
    # x = r * st *  cosd(ϕ)
    # y = r * st *  sind(ϕ)
    # z = r * cosd(θ)
    return [x,y,z]
end;
function xyz2sphere_for_SWIA(x,y,z)
    r=sqrt(x^2 + y^2 + z^2)
    theta = 90.0 - acosd(z/r)
    phi = atand(y, x)
    return [r,theta,phi]
end
function ion_eflux2F(energy,eflux;m_int=1)  # 离子eflux转PSD, 使用IS单位制, 与STA方法差了1e3倍
    E0 = 511.0 * m_int * 1836.23
    γ =(energy * 1e-3 /E0 + 1)
    β =sqrt(1.0 - 1.0 / γ^2)
    V = β * C
    F = 2 * eflux *1e4 / V^4
    return F
end
function ion_energy2v(energy,AMU) # 离子子能量对应速度(相对论),输入eV, IS单位制
    E0 = 938313.53 * AMU  # 质子静止能量 MeV
    γ= energy*1e-3/E0 + 1.0
    β=sqrt(1.0 - 1.0 / γ^2)
    v = β * 3e8
    return v
end
function ion_v2energy(v,AMU) # 离子子能量对应速度(相对论) v:速度, IS单位制
    E0 = 938313.53 * AMU
    β  = v / 3e8
    γ = 1.0 / sqrt(1.0 - β^2)
    energy = (γ - 1.0) * E0 * 1e3
    return energy
end
const EV=1.602176487e-19
const C=3.0e8
const Me=9.109e-31
const Mp=1.672621637e-27
const RADG=180.0/π

end

# # -------------------------Test parts-------------------------
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath * "MAVEN_data/MAVEN_load.jl")
# import .MAVEN_load;
# import .MAVEN_SWEA;
# using Dates
# using CairoMakie
# using DataInterpolations
# time_range = [DateTime(2015,10,29,11),DateTime(2015,10,29,12)]
# time_range = [DateTime(2015,10,29,11,27),DateTime(2015,10,29,11,39)]
# MAVEN_load.change_kp_read_data(Dict(
#     :electorn_density => 2,
#     :sw_electorn_density => 23,
#     :Ne_quality_min => 3,
#     :Ne_quality_max => 4,
#     :GEO_x => 187,
#     :GEO_y => 188,
#     :GEO_z => 189,
#     :MSO_x => 190,
#     :MSO_y => 191,
#     :MSO_z => 192,
#     :Orbit_Number => 210,
#     :Shape_parameter => 39,
#     :H_flow_MSO_x => 43,
#     :H_flow_MSO_y => 45,
#     :H_flow_MSO_z => 47,
#     :Oiondensity => 56,
#     :O2iondensity => 58,
#     :iondensity16 => 172,
#     :iondensity32 => 163,
#     :iondensity44 => 167,
#     :OionTemperature => 62,
#     :O2ionTemperature => 64,
# ));
# dat0 = MAVEN_load.data_get_from_date(DateTime(2015,10,29); model_index=["SWEA_spec","KP","LPW_mrgscpot","LPW_lpnt","LPW_wn"])
# dat_swe=dat0["SWEA_spec"]
# dat_kp = dat0["KP"]
# dat_pot = dat0["LPW_mrgscpot"]
# func_on_zero = x -> isnan(x) ? 0.0 : x
# func_pot = CubicSpline(func_on_zero.(dat_pot[:data]),datetime2unix.(dat_pot[:epoch]),extrapolate=true)
# pots = func_pot.(datetime2unix.(dat_swe[:epoch]))

# dens = MAVEN_SWEA.n1d(dat_swe;sc_pot=pots)
# time_i_swe = findall(x ->time_range[2]>= x >= time_range[1], dat_swe[:epoch])

# time_i_kp = findall(x ->time_range[2]>= x >= time_range[1], dat_kp[:time])
# fig = Figure(resolution=(800, 600))
# ax = Axis(fig[1, 1], xlabel="time", ylabel="Density (1/cm^3)", title="MAVEN SWEA Density")
# lines!(ax, dat_swe[:epoch][time_i_swe], dens[time_i_swe], color=:blue, label="Density")
# lines!(ax, dat_kp[:time][time_i_kp], dat_kp[:sw_electorn_density][time_i_kp], color=:red, label="Kp Index")

# ax = Axis(fig[2, 1], xlabel="time", ylabel="Density (1/cm^3)", title="MAVEN SWEA Density",yscale=log10)

# time_i1 = findall(x ->time_range[2]>= x >= time_range[1], dat0["LPW_lpnt"][:epoch])
# scatter!(ax, dat0["LPW_lpnt"][:epoch][time_i1], dat0["LPW_lpnt"][:data][time_i1], color=:blue, label="Density")

# time_i2 = findall(x ->time_range[2]>= x >= time_range[1], dat0["LPW_wn"][:epoch])
# scatter!(ax, dat0["LPW_wn"][:epoch][time_i2], dat0["LPW_wn"][:data][time_i2], color=:red, label="Density")

# fig