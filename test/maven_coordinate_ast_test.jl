using Test
using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
include(joinpath(REPO, "validation", "ast", "ASTMigrate.jl"))
const A = ASTMigrate
const OLD_NAMES = Set(["instrument_cartesian_to_sphere", "instrument_sphere_to_cartesian"])
const NEW_NAMES = Set(["MAVEN_xyz2sphere", "MAVEN_sphere2xyz"])

@testset "MAVEN coordinate ownership and callers (AST)" begin
    # Scan production paths only; historical tests/docs intentionally retain oracle names.
    files = String[]
    for dir in ("src", "common", "MAVEN_data", "TW_data", "MGS_data", "models",
                "analysis", "support_data", "example", "benchmark")
        for (root, _, names) in walkdir(joinpath(REPO, dir))
            for name in names
                endswith(name, ".jl") && push!(files, relpath(joinpath(root, name), REPO))
            end
        end
    end
    idx = A.build_index(REPO; files=files, names=union(OLD_NAMES, NEW_NAMES))
    @test isempty(idx.parse_errors)
    for scan in values(idx.scans)
        @test !any(d -> d.name in OLD_NAMES, scan.defs)
        @test !any(r -> r.name in OLD_NAMES, scan.refs)
    end

    coordinate = idx.scans["common/function_coordinate.jl"]
    records = TOML.parsefile(joinpath(REPO, "validation", "migrations", "index.toml"))["index"]["coordinate_api"]["maven"]["methods"]
    for name in NEW_NAMES
        methods = filter(d -> d.name == name && d.top_level, coordinate.defs)
        # Distinct static-vector and ordinary-vector adapter methods are intentional.
        @test length(methods) == 2
        @test length(unique(d.hash for d in methods)) == 2
        @test all(d -> d.module_path == ["FunctionCoordinate"], methods)
        record = only(filter(row -> row["name"] == name, records))
        @test Set(record["target_ast_hashes"]) == Set(d.hash for d in methods)
        original = read(`git -C $REPO show $(record["source_revision"]):common/MarsCommon.jl`, String)
        original_scan = A.scan_source(original, "common/MarsCommon.jl", OLD_NAMES)
        definition = only(filter(d -> d.top_level && d.name == record["source_name"], original_scan.defs))
        @test definition.hash == record["source_ast_hash"]
    end

    static = idx.scans["MAVEN_data/MAVEN_STATIC.jl"]
    pickup = idx.scans["analysis/Pickup_ion.jl"]
    @test any(r -> r.name == "MAVEN_sphere2xyz" && r.base == "FunctionCoordinate", static.refs)
    @test any(r -> r.name == "MAVEN_xyz2sphere" && r.base == "FunctionCoordinate", static.refs)
    @test any(r -> r.name == "MAVEN_xyz2sphere" && r.base == "FunctionCoordinate", pickup.refs)
    # Do not introduce the reverse dependency MarsCommon -> FunctionCoordinate.
    @test !any(x -> occursin("function_coordinate.jl", x.included), idx.scans["common/MarsCommon.jl"].includes)
end
