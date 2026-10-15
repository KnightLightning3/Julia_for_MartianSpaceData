using Test
using SHA
using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const NEW_SOURCE = joinpath(REPO, "analysis", "Pickup_ion.jl")
const OLD_SOURCE = joinpath(REPO, "models", "Pickup_ion.jl")
const BASELINE_REV = "d828a6e"

function extract_function(src::String, name::String)
    lines = split(src, '\n'; keepempty=true)
    offsets = Int[1]
    i = firstindex(src)
    while true
        newline = findnext(==('\n'), src, i)
        newline === nothing && break
        push!(offsets, nextind(src, newline))
        i = nextind(src, newline)
    end
    line = findfirst(s -> occursin(Regex("^\\s*function\\s+" * name * "\\s*\\("), s), lines)
    line === nothing && error("function $name not found")
    expr, stop = Meta.parse(src, offsets[line])
    return src[offsets[line]:prevind(src, stop)]
end

function adapter_module(name, source)
    m = Module(name)
    for fn in ("func_E_range", "get_pickup_point")
        Base.include_string(m, extract_function(source, fn), "$(name):$(fn).jl")
    end
    return m
end

@testset "Pickup_ion 物理移动" begin
    @testset "与 d828a6e 旧基线仅有坐标调用点替换，旧路径消失" begin
        baseline = read(`git -C $REPO show $BASELINE_REV:models/Pickup_ion.jl`)
        @test bytes2hex(sha256(copy(baseline))) == "56ac006dd36c14622e97e8fd7ec20c11df1ef72ebed3a2d12b62a4072fc5dc44"
        baseline_source = String(baseline)
        old_call = "MarsCommon.instrument_cartesian_to_sphere(p...)"
        new_call = "FunctionCoordinate.MAVEN_xyz2sphere(p)"
        @test length(findall(old_call, baseline_source)) == 1
        moved_source = read(NEW_SOURCE, String)
        @test length(findall(new_call, moved_source)) == 1
        @test replace(moved_source, new_call => old_call) == baseline_source
        @test !isfile(OLD_SOURCE)
    end

    @testset "index.toml 文件迁移记录唯一且与目标字节匹配" begin
        index = TOML.parsefile(joinpath(REPO, "validation", "migrations", "index.toml"))
        matches = filter(m -> get(m, "from", "") == "models/Pickup_ion.jl",
                         index["index"]["file_moves"])
        @test length(matches) == 1
        if length(matches) == 1
            move = only(matches)
            baseline = read(`git -C $REPO show $BASELINE_REV:models/Pickup_ion.jl`)
            @test move["to"] == "analysis/Pickup_ion.jl"
            @test move["source_revision"] == "d828a6e"
            target = read(joinpath(REPO, move["to"]))
            @test move["sha256"] == bytes2hex(sha256(copy(baseline)))
            @test move["bytes"] == length(baseline)
            @test get(move, "current_sha256", move["sha256"]) == bytes2hex(sha256(target))
            @test get(move, "current_bytes", move["bytes"]) == length(target)
        end
    end

    @testset "两个 common include 在非仓库 CWD 下仍解析" begin
        cwd0 = pwd()
        tmp = mktempdir()
        try
            cd(tmp)
            common_dir = normpath(joinpath(dirname(NEW_SOURCE), "..", "common"))
            coordinate = joinpath(common_dir, "function_coordinate.jl")
            constants = joinpath(common_dir, "constants.jl")
            @test realpath(pwd()) == realpath(tmp)
            @test isfile(coordinate)
            @test isfile(constants)

            # 用移动后脚本所在目录作为 @__DIR__ 基准，在仓库外 cwd 实际 include。
            sandbox = Module(:PickupIncludeSandbox)
            Base.include(sandbox, constants)
            Base.include(sandbox, coordinate)
            @test isdefined(sandbox, :constants)
            @test isdefined(sandbox, :FunctionCoordinate)
        finally
            cd(cwd0)
            rm(tmp; force=true, recursive=true)
        end
        @test pwd() == cwd0
    end

    @testset "引导前纯适配器函数与旧 HEAD 行为一致" begin
        current = read(NEW_SOURCE, String)
        baseline = read(`git -C $REPO show $BASELINE_REV:models/Pickup_ion.jl`, String)
        moved = adapter_module(:PickupMovedAdapters, current)
        old = adapter_module(:PickupOldAdapters, baseline)

        for (energy, width) in ((1.0, 0.1), (10.0, 3.0), (1000.0, 50.0))
            @test moved.func_E_range(energy, width) === old.func_E_range(energy, width)
        end
        points = [(2.0, 10.0, 15.0), (5.0, 45.0, 100.0), (20.0, 80.0, 300.0),
                  (50.0, 20.0, -5.0)]
        eranges = [(1.0, 3.0), (4.0, 6.0), (19.0, 21.0)]
        tranges = [(0.0, 20.0) (40.0, 50.0) (70.0, 90.0);
                   (20.0, 30.0) (50.0, 60.0) (90.0, 100.0)]
        pranges = [(0.0, 30.0), (90.0, 110.0), (290.0, 310.0)]
        @test moved.get_pickup_point(points, eranges, tranges, pranges) ==
              old.get_pickup_point(points, eranges, tranges, pranges)
    end
end
