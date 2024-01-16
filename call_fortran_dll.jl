module Call_fortran_dll
# Ref{Float64},  Ptr{Float64}
# Ref{Int32},    Ptr{Int32}
RAD = π/180.0
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