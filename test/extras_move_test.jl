using SHA
using TOML
using Test

const REPO = normpath(joinpath(@__DIR__, ".."))
const EXTRAS = joinpath(REPO, "models", "extras")

function oracle_source_sha(path)
    bytes = read(pipeline(`git -C $REPO show d828a6e:$path`))
    bytes2hex(sha256(bytes))
end

@testset "Extras relocation and catalog" begin
    expected = Dict(
        "Graham" => "0d2707667384e6ff7396b8679dcc4bd55d1a999290431c85f4b7271935c824e3",
        "Octree" => "103b92f6dc491985572f5b41317c3b4582648dd7cc24885d491ff2a1ad32c437",
    )
    expected_deps = Dict(
        "Graham" => ["Makie"],
        "Octree" => ["GLMakie", "GeometryBasics", "StaticArrays"],
    )
    file_moves = TOML.parsefile(joinpath(REPO, "validation", "migrations", "index.toml"))["index"]["file_moves"]
    catalog = TOML.parsefile(joinpath(REPO, "models", "CATALOG.toml"))["extra"]
    by_name = Dict(entry["name"] => entry for entry in catalog)

    @test Set(keys(by_name)) == Set(keys(expected))
    for (name, digest) in expected
        relative_path = "models/extras/$(name).jl"
        destination = joinpath(REPO, split(relative_path, '/')...)
        @test isfile(destination)
        @test bytes2hex(sha256(read(destination))) == digest
        @test oracle_source_sha("models/$(name).jl") == digest

        from_path = "models/$(name).jl"
        move_records = filter(record -> record["from"] == from_path, file_moves)
        @test length(move_records) == 1
        if length(move_records) == 1
            move = only(move_records)
            @test move["to"] == relative_path
            @test move["source_revision"] == "d828a6e"
            @test move["sha256"] == bytes2hex(sha256(read(destination)))
            @test move["bytes"] == filesize(destination)
        end

        @test by_name[name]["file"] == relative_path
        @test by_name[name]["status"] == "experimental"
        @test by_name[name]["external_deps"] == expected_deps[name]
    end

    for old_name in keys(expected)
        @test !ispath(joinpath(REPO, "models", "$(old_name).jl"))
    end

    production_roots = ("src", "common", "MAVEN_data", "TW_data", "MGS_data",
                        "support_data", "models", "example", "config")
    old_path_references = String[]
    for root in production_roots
        for (directory, _, files) in walkdir(joinpath(REPO, root))
            for file in files
                (endswith(file, ".jl") || endswith(file, ".toml")) || continue
                path = joinpath(directory, file)
                text = read(path, String)
                occursin(r"models/(Graham|Octree)\.jl", text) && push!(old_path_references, path)
            end
        end
    end
    @test isempty(old_path_references)

    registry = read(joinpath(REPO, "src", "modules.jl"), String)
    @test !occursin(r"(?m)^\s*:(Graham|Octree)\s*=>", registry)
end

@testset "Graham standalone smoke" begin
    source = joinpath(EXTRAS, "Graham.jl")
    isolated = Module(:GrahamExtraSmoke)
    Base.include(isolated, source)

    points = [isolated.Point(0.0, 0.0), isolated.Point(1.0, 0.0),
              isolated.Point(1.0, 1.0), isolated.Point(0.0, 1.0),
              isolated.Point(0.5, 0.5)]
    hull = isolated.graham_scan!(points)
    @test length(hull) == 4
    @test Set((p.x, p.y) for p in hull) ==
          Set([(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)])
end

@testset "Octree static source inspection (runtime NOT tested)" begin
    source = read(joinpath(EXTRAS, "Octree.jl"), String)
    @test occursin("using GLMakie", source)
    @test occursin("using GeometryBasics", source)
    @test occursin("using StaticArrays", source)
    @test occursin("mutable struct OctreeNode", source)
    @test occursin("function build_octree!", source)
    @test occursin("function get_min_bounding_box", source)
    println("Octree static checks only; runtime NOT tested (GUI/dependency loading was not exercised).")
end
