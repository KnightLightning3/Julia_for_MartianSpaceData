using Test

const PATH_REPO = normpath(joinpath(@__DIR__, ".."))

# Evaluate only the production path helpers, without loading data readers or DLLs.
function path_helper(file, name)
    matches = Expr[]
    function visit(ex)
        ex isa Expr || return
        if ex.head == :function
            signature = ex.args[1]
            signature isa Expr && signature.head == :call && signature.args[1] == name && push!(matches, ex)
            return
        end
        foreach(visit, ex.args)
    end
    visit(Meta.parseall(read(joinpath(PATH_REPO, file), String)))
    return only(matches)
end

@testset "configured roots need no trailing separator" begin
    mktempdir() do root
        for (file, subpath) in (
            ("MGS_data/MGS_load.jl", "MAG_SUNSTATE_list"),
            ("TW_data/TW_load.jl", joinpath("List", "mag_list.txt")),
            ("TW_data/TW_MINPA.jl", joinpath("List", "MINPA_list.txt")),
        )
            path = joinpath(root, subpath)
            mkpath(dirname(path))
            write(path, "2020/01/synthetic.dat\n")
            scope = Module(gensym(:ListPaths))
            Core.eval(scope, :(root_path = $root))
            Core.eval(scope, path_helper(file, :read_list))
            @test Base.invokelatest(() -> getfield(scope, :read_list)()) == [joinpath(root, "2020/01/synthetic.dat")]
        end
        scope = Module(gensym(:MavenPaths))
        Core.eval(scope, :(root_path = $root))
        Core.eval(scope, :(read_models = Dict("KP" => ["KP/insitu/"])))
        Core.eval(scope, :(filename_list() = Dict("KP" => ["2020/01/mvn_kp_20200102.tab"])))
        Core.eval(scope, :(const _FILE_INDEX_CACHE = Dict{String,Dict{String,Vector{String}}}()))
        for name in (:file_list, :_file_index)
            Core.eval(scope, path_helper("MAVEN_data/MAVEN_load.jl", name))
        end
        expected = joinpath(root, "KP/insitu/2020/01/mvn_kp_20200102.tab")
        @test Base.invokelatest(() -> getfield(scope, :file_list)("KP")) == [expected]
        @test Base.invokelatest(() -> getfield(scope, :_file_index)("KP"))["20200102"] == [expected]
    end
end
