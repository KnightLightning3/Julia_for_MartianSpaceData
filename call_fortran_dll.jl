module Call_fortran_dll
RAD = π/180.0
function cold_plasma_linear_growth(ekk, psd, beq, density, pa; psir=[],frer=[])
    dll_f = raw"D:\CODE\Code_Library\Fortran\Dll1\x64\Release\linear_growth_rate.dll"

    npa=length(pa)
    nekk=length(ekk)

    psir=[0.0,30,150,180] .* RAD
    npsi=length(psir)
    nfre=length(frer)
    RI=[0.0,0.4,0.6]
    MMr=Int32[-100,100]
    tgr = Array{Float64}(undef, nfre, npsi)
    sgr = Array{Float64}(undef, nfre, npsi)

    ccall(("MAIN_mp_LINEAR_GROWTH_RATE", dll_f), Cvoid,
            (Ref{Float64}, Ref{Float64}, Ptr{Float64},
            Ref{Int32}, Ref{Int32}, Ref{Int32}, Ref{Int32},
            Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Float64},
            Ptr{Float64}, Ptr{Int32},
            Ptr{Float64}, Ptr{Float64}),
            beq, density, RI,
            npa, nekk, npsi, nfre,
            pa, ekk,
            psir, frer,
            psd, MMr,
            tgr, sgr)
    return [frer,psir,tgr,sgr]
end

end