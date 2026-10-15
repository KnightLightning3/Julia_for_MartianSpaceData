using Test
include(joinpath(@__DIR__, "..", "tools", "generate_api.jl"))

@testset "static Julia API index" begin
    mktempdir() do root
        mkpath(joinpath(root, "MAVEN_data", "Build_data"))
        mkpath(joinpath(root, "models", "extras"))
        mkpath(joinpath(root, "common", "marscommon"))
        mkpath(joinpath(root, "src"))
        write(joinpath(root, "MAVEN_data", "Main.jl"), """
            module Outer
            export exported, shared
            \"\"\"exported responsibility. More detail.\"\"\"
            exported(x) = x
            typed(x)::Int = x
            shared(x) = x
            nested_only(x) = x
            function ordinary(x)
                localfun(y) = y
                anon = z -> z
                return x
            end
            module Inner
                export nested_only
                shared(x) = x
                nested_only(x) = x
                \"\"\"nested module function responsibility.\"\"\"
                function nested(x)
                    x
                end
            end
            end
            """)
        write(joinpath(root, "MAVEN_data", "Build_data", "ignored.jl"),
              "must_not_be_parsed( = ")
        write(joinpath(root, "models", "extras", "Extra.jl"), "extra(x) = x\n")
        write(joinpath(root, "common", "MarsCommon.jl"), "module MarsCommon\nexport cross_common\nend\n")
        write(joinpath(root, "common", "marscommon", "sub.jl"), "cross_common(x) = x\n")
        write(joinpath(root, "src", "plotting.jl"), "cross_package(x) = x\n")
        write(joinpath(root, "src", "modules.jl"), "cross_manager(x) = x\n")
        write(joinpath(root, "src", "MarsData.jl"), "module MarsData\nexport cross_package, cross_manager\nend\n")

        files = GenerateAPI.source_files(root)
        @test files == ["MAVEN_data/Main.jl", "common/MarsCommon.jl", "common/marscommon/sub.jl",
                        "models/extras/Extra.jl", "src/MarsData.jl", "src/modules.jl", "src/plotting.jl"]
        exports = GenerateAPI.export_map(root, files)
        idx = GenerateAPI.index_file(root, "MAVEN_data/Main.jl", exports)
        @test idx.modules == ["Outer", "Outer.Inner"]
        names = [e.name for e in idx.entries]
        @test names == ["Outer.Inner.nested", "Outer.Inner.nested_only", "Outer.Inner.shared",
                        "Outer.exported", "Outer.nested_only", "Outer.ordinary", "Outer.shared", "Outer.typed"]
        @test only(filter(e -> e.name == "Outer.exported", idx.entries)).exported
        @test !only(filter(e -> e.name == "Outer.ordinary", idx.entries)).exported
        @test only(filter(e -> e.name == "Outer.shared", idx.entries)).exported
        @test !only(filter(e -> e.name == "Outer.nested_only", idx.entries)).exported
        @test !only(filter(e -> e.name == "Outer.Inner.shared", idx.entries)).exported
        @test only(filter(e -> e.name == "Outer.Inner.nested_only", idx.entries)).exported
        @test only(filter(e -> e.name == "Outer.exported", idx.entries)).summary == "exported responsibility."
        @test !any(occursin("localfun", n) || occursin("anon", n) for n in names)
        common_idx = GenerateAPI.index_file(root, "common/marscommon/sub.jl", exports)
        package_idx = GenerateAPI.index_file(root, "src/plotting.jl", exports)
        manager_idx = GenerateAPI.index_file(root, "src/modules.jl", exports)
        @test only(common_idx.entries).name == "MarsCommon.cross_common"
        @test only(common_idx.entries).exported
        @test only(package_idx.entries).name == "MarsData.cross_package"
        @test only(package_idx.entries).exported
        @test only(manager_idx.entries).exported
        @test occursin("%E4%B8%AD%E6%96%87", GenerateAPI.encoded_source_url("MAVEN_data/中文.jl"))
        rendered = GenerateAPI.render(root)
        @test occursin("Outer.Inner.nested", rendered)
        @test !occursin("ignored.jl", rendered)
    end
end

@testset "static index retains annotated coordinate definitions" begin
    mktempdir() do root
        write(joinpath(root, "annotated.jl"), """
            module Coordinates
            \"\"\"Convert a single point.\"\"\"
            @inline function convert_point(p)
                hidden(x) = x
                p
            end
            \"\"\"Convert the inverse point.\"\"\"
            @noinline reverse_point(p) = p
            end
            """)
        idx = GenerateAPI.index_file(root, "annotated.jl")
        @test [e.name for e in idx.entries] == ["Coordinates.convert_point", "Coordinates.reverse_point"]
        @test idx.entries[1].summary == "Convert a single point."
        @test idx.entries[2].summary == "Convert the inverse point."
        @test !any(occursin("hidden", e.name) for e in idx.entries)
    end
end
