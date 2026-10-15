using Test

include(joinpath(@__DIR__, "..", "common", "data_keys.jl"))

@testset "DataKeys public contract" begin
    public_names = names(DataKeys; all=false, imported=false)
    public_symbol_values = [getfield(DataKeys, name) for name in public_names
                            if isdefined(DataKeys, name) && getfield(DataKeys, name) isa Symbol]
    @test length(public_symbol_values) == length(unique(public_symbol_values))

    @test :MASS in names(DataKeys)
    @test DataKeys.MASS === :mass
    @test DataKeys.MASS_ARR === :mass_arr
    @test DataKeys.MASS !== DataKeys.MASS_ARR

    @test !(:B_FIELD_LEGACY in names(DataKeys))
    @test !(:VARS_LEGACY in names(DataKeys))
    @test !(:DATA_STATUS_LEGACY in names(DataKeys))
end
