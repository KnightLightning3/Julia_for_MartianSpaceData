using Test
using TOML

const PATHS_SOURCE = normpath(joinpath(@__DIR__, "..", "common", "paths.jl"))

function fixture_repo(paths=nothing; settings=true)
    root = mktempdir()
    common_dir = joinpath(root, "common")
    config_dir = joinpath(root, "config")
    mkpath(common_dir)
    mkpath(config_dir)
    cp(PATHS_SOURCE, joinpath(common_dir, "paths.jl"))
    if settings
        open(joinpath(config_dir, "settings.toml"), "w") do io
            TOML.print(io, Dict("paths" => paths))
        end
    end
    return root
end

function load_fixture_paths(root)
    container = Module(gensym(:PathsFixture))
    Base.include(container, joinpath(root, "common", "paths.jl"))
    return Base.invokelatest(getfield, container, :Paths)
end

function valid_paths(overrides...)
    base = Dict{String,Any}(
        "maven_data_root" => "maven",
        "tw_data_root" => "tianwen",
        "mgs_data_root" => "mgs",
    )
    merge!(base, Dict{String,Any}(string(k) => v for (k, v) in overrides))
    return base
end

@testset "Paths TOML configuration" begin
    @testset "relative roots are repository-relative and preserve edge spaces" begin
        paths = valid_paths("maven_data_root" => "  data/maven  ")
        root = fixture_repo(paths)
        cwd = joinpath(root, "elsewhere")
        mkpath(cwd)
        P = cd(cwd) do
            load_fixture_paths(root)
        end
        @test Base.invokelatest(P.maven_data_root) == normpath(joinpath(root, "  data/maven  "))
        @test Base.invokelatest(P.tw_data_root) == normpath(joinpath(root, "tianwen"))
        @test Base.invokelatest(P.mgs_data_root) == normpath(joinpath(root, "mgs"))
        @test rstrip(Base.invokelatest(P.project_root), ('/', '\\')) ==
              rstrip(normpath(root), ('/', '\\'))
        @test Base.invokelatest(P.index_path) == joinpath(root, "MAVEN_data", "filename_lists.json")
    end

    @testset "Windows absolute roots remain absolute on this host" begin
        winroot = raw"C:\MAVEN\science"
        P = load_fixture_paths(fixture_repo(valid_paths("maven_data_root" => winroot)))
        @test Base.invokelatest(P.maven_data_root) == winroot
    end

    @testset "optional Fortran directory defaults to repository root" begin
        P = load_fixture_paths(fixture_repo(valid_paths()))
        @test Base.invokelatest(P.fortran_dll_dir) == Base.invokelatest(P.project_root)
        Pblank = load_fixture_paths(fixture_repo(valid_paths("fortran_dll_dir" => " \t ")))
        @test Base.invokelatest(Pblank.fortran_dll_dir) == Base.invokelatest(Pblank.project_root)
    end

    @testset "relative Fortran directory preserves edge spaces" begin
        dll = "  local dll dir  "
        P = load_fixture_paths(fixture_repo(valid_paths("fortran_dll_dir" => dll)))
        @test Base.invokelatest(P.fortran_dll_dir) ==
              normpath(joinpath(Base.invokelatest(P.project_root), dll))
    end

    @testset "missing file, invalid type, and blank required value fail clearly" begin
        missing_root = fixture_repo(; settings=false)
        missing_error = try
            load_fixture_paths(missing_root)
            nothing
        catch err
            err
        end
        @test missing_error isa LoadError
        @test occursin("initialize_download_parameters.py", sprint(showerror, missing_error))

        @test_throws LoadError load_fixture_paths(fixture_repo(valid_paths("tw_data_root" => 42)))

        @test_throws LoadError load_fixture_paths(fixture_repo(valid_paths("mgs_data_root" => " \t ")))
    end
end
