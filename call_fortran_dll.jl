"""Julia 对 Fortran 动态库计算例程的调用封装。"""

module Call_fortran_dll
# Ref{Float64},  Ptr{Float64}
# Ref{Int32},    Ptr{Int32}
"""
    cold_plasma_linear_growth(ekk, pa, psd, psir, frer; B=10.0, Ne=100.0, test=false, MMr=Int32[-100,100]) -> Vector

调用 Fortran 例程计算冷等离子体线性增长率。

# 功能与算法概述
把能量、俯仰角、相空间密度与频率/波法角网格经 `ccall` 传入动态库的
`LINEAR_GROWTH_RATE`（`test=true` 时用 `TEST_VALS`），回读时间增长率 `tgr` 与空间增长率 `sgr`。

# 参数说明
- `ekk`, `pa`: 能量与俯仰角网格。
- `psd`: 相空间密度矩阵。
- `psir`, `frer`: 波法角与频率网格。
- `B`, `Ne`: 磁场（nT）与电子密度。
- `test`: 是否调用测试例程。
- `MMr`: 质量/磁矩范围参数。

# 返回值
- 非测试时 `[frer, psir, tgr, sgr]`；测试时 `[tgr, sgr]`。

# 注意事项
- 依赖 `linear_growth_rate.dll`，路径当前硬编码为 Windows 绝对路径。
"""
function cold_plasma_linear_growth(ekk,pa, psd, psir,frer; B=10.0, Ne=100.0,test=false, MMr=Int32[-100,100])
    npa=length(pa)
    nekk=length(ekk)

    npsi=length(psir)
    nfre=length(frer)
    RI=[0.0,0.4,0.6]
    
    tgr = Array{Float64}(undef, nfre, npsi)
    sgr = Array{Float64}(undef, nfre, npsi)
    # println(psd[1:44,1])
    # println(size(ekk),size(pa),size(psd))
    if test
        ccall(("MAIN_mp_TEST_VALS", "D:/CODE/Package_for_Julia/linear_growth_rate.dll"), Cvoid,
        (Ref{Float64}, Ref{Float64}, Ptr{Float64},
        Ref{Int32}, Ref{Int32}, Ref{Int32}, Ref{Int32},
        Ptr{Float64}, Ptr{Float64},
        Ptr{Float64}, Ptr{Float64},
        Ptr{Float64}, Ref{Int32},
        Ptr{Float64}, Ptr{Float64}),
        B, Ne, RI,
        npa, nekk, npsi, nfre,
        pa, ekk,
        psir, frer,
        psd, MMr,
        tgr, sgr)
        return [tgr,sgr]
    end
    ccall(("MAIN_mp_LINEAR_GROWTH_RATE", "D:/CODE/Package_for_Julia/linear_growth_rate.dll"), Cvoid,
            (Ref{Float64}, Ref{Float64}, Ptr{Float64},
            Ref{Int32}, Ref{Int32}, Ref{Int32}, Ref{Int32},
            Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ref{Int32},
            Ptr{Float64}, Ptr{Float64}),
            B, Ne, RI,
            npa, nekk, npsi, nfre,
            pa, ekk,
            psir, frer,
            psd, MMr,
            tgr, sgr)
    return [frer,psir,tgr,sgr]
end

"""
    Bspline_db1ink(x, fcn; kx::Int32=Int32(4)) -> Vector

调用 Fortran B 样条例程生成一维插值系数。

# 功能与算法概述
把样本点与函数值经 `ccall` 传入 `DB1INK`，得到节点序列 `tx` 与 B 样条系数 `bcoef`。

# 参数说明
- `x`, `fcn`: 自变量与函数值数组。
- `kx`: B 样条阶数（默认 4）。

# 返回值
- `[nx, kx, tx, bcoef]`: 供 `Bspline_db1var` 使用的插值数据。

# 注意事项
- 依赖 `Bspline.dll`；`iflag != 0` 时打印错误。
"""
function Bspline_db1ink(x,fcn; kx::Int32 = Int32(4))
    nx::Int32 = length(x)
    iknot::Int32 = 0
    
    bcoef = Array{Float64}(undef, nx)
    tx = Array{Float64}(undef, nx+kx)
    iflag = Ref{Int32}(0)
    ccall(("BSPLINE_SUB_MODULE_mp_DB1INK", "Bspline.dll"), Cvoid,
            (Ptr{Float64},Ref{Int32},Ptr{Float64},
            Ref{Int32},Ref{Int32},
            Ptr{Float64},Ptr{Float64},Ref{Int32}),
            x,nx,fcn,kx,iknot,tx,bcoef,iflag)
    if iflag != 0
        println("Error in Bspline_ink => ",iflag)
    end
    return [nx,kx,tx,bcoef]
end
"""
    Bspline_db1var(xval, INK_data; idx::Int32=Int32(0), extrap=false, inbvx::Int32=Ref{Int32}(1)) -> Vector

调用 Fortran B 样条例程做单点插值。

# 功能与算法概述
由 `Bspline_db1ink` 生成的插值数据，经 `ccall` 调用 `DB1VAL` 求 `xval` 处的函数值。

# 参数说明
- `xval`: 待求点。
- `INK_data`: `Bspline_db1ink` 的返回值 `[nx, kx, tx, bcoef]`。
- `idx`, `inbvx`: 区间提示与初始化参数。
- `extrap`: 是否允许外推。

# 返回值
- `[f, inbvx]`: 插值值与更新后的初始化参数。

# 注意事项
- 依赖 `Bspline.dll`；`inbvx` 首次调用须为 1。
"""
function Bspline_db1var(xval,INK_data;idx::Int32 = Int32(0), extrap = false,inbvx::Int32 = Ref{Int32}(1))#单点插值
    nx,kx,tx,bcoef = INK_data
    f     = Ref{Float64}(0.0)
    iflag = Ref{Int32}(0)
    ccall(("BSPLINE_SUB_MODULE_mp_DB1VAL", "Bspline.dll"), Cvoid,
            (Ref{Float64},Ref{Int32},Ptr{Float64},
            Ref{Int32},Ref{Int32},
            Ptr{Float64},Ref{Float64},Ref{Int32},
            Ref{Int32},Ref{Bool}),
            xval,idx,tx,
            nx,kx,
            bcoef,f,iflag,
            Ref{Int32}(inbvx),extrap)
    if iflag != 0
        println("Error in Bspline_ink => ",iflag)
    end
    # integer,intent(inout) :: inbvx    !initialization parameter which must be set to 1 the first time this routine is called, and must not be changed by the user.
    return [f,inbvx]
end

end