# ============================================================================
# 模块装载管理器（阶段 A）
#
# 目标：把"以 include 装载模块"这件事包化。一次函数调用等价于
#       `include(对应文件)` + 可选的逐名引入（白名单）。
#
#   MarsData.load_module(:MAVEN_load)                  # 等价于 include，落点 MarsData
#   MarsData.@load MAVEN_load MAVEN_STATIC             # 落点调用者作用域并绑定模块名
#
# 白名单语义（已实测）：
#   - 装载器一律使用逐名形式 `using .Mod: a, b`，**从不**使用整体 `using .Mod`
#   - 因此"能否裸名调用"完全由 `ModuleSpec.allow` 决定，与模块里怎么 `export` 无关
#     （Julia 的 `using Mod: foo` 对未 export 的 foo 同样有效）
#   - `allow` 为空 ⇒ 只绑定模块名，不引入任何裸名
#
# 阶段 A 范围：只新增本文件与 API，**不改动**任何模块的 `export` 行、示例与 Build_data。
# ============================================================================

"""
    ModuleSpec

单个可装载模块的注册表条目。

# 字段说明
- `name::Symbol`：模块名，必须与文件内的 `module <name>` 一致。
- `path::String`：相对仓库根的路径。
- `deps::Vector{Symbol}`：语义前置模块，仅用于 `:all` 的拓扑排序与校验（不自动装载）。
- `kind::Symbol`：`:module`（普通模块）或 `:preloaded`（已随包 include）。
- `allow::Vector{Symbol}`：**白名单** —— `@load` 允许引入到调用者作用域的裸名。
  留空表示不引入任何裸名（只绑定模块名）。
- `note::String`：用途简述。
"""
struct ModuleSpec
    name::Symbol
    path::String
    deps::Vector{Symbol}
    kind::Symbol
    allow::Vector{Symbol}
    note::String
end

_spec(name, path, note; deps = Symbol[], kind = :module, allow = Symbol[]) =
    ModuleSpec(name, path, deps, kind, allow, note)

"""
    MODULE_REGISTRY

全部可装载模块的注册表（唯一事实来源）。

`allow` 白名单决定 `@load` 会把哪些名字变成调用者作用域的**裸名**；为空表示只绑定
模块名（须写 `MAVEN_load.xxx` 这样的限定名）。当前已开放：

- `MarsCommon`：`searchsortednearest`、`e_energy2v`、`ion_energy2v`
- `MAVEN_load`：`load_cdf`、`load_MAVEN_data`
- `IGRF_calculate`：`IGRF_pc`、`pc2sphere`、`sphere2pc`

其余模块的白名单仍留空，待逐个填写。
"""
const MODULE_REGISTRY = Dict{Symbol,ModuleSpec}(
    :constants => _spec(:constants, "common/constants.jl", "共享物理常量"),
    :MarsCommon => _spec(
        :MarsCommon, "common/MarsCommon.jl", "通用坐标与科学计算函数";
        deps = [:constants], allow = [:searchsortednearest, :e_energy2v, :ion_energy2v],
    ),
    :Paths => _spec(:Paths, "common/paths.jl", "配置与路径解析（已随包预装）"; kind = :preloaded),
    :DataKeys => _spec(:DataKeys, "common/data_keys.jl", "数据键契约常量（已随包预装）"; kind = :preloaded),
    :MAVEN_load => _spec(
        :MAVEN_load, "MAVEN_data/MAVEN_load.jl", "MAVEN 统一读取入口";
        deps = [:constants, :MarsCommon, :Paths], allow = [:load_cdf, :load_MAVEN_data],
    ),
    :MAVEN_STATIC => _spec(
        :MAVEN_STATIC, "MAVEN_data/MAVEN_STATIC.jl", "STATIC 仪器数据处理";
        deps = [:constants, :MarsCommon],
    ),
    :MAVEN_SWIA => _spec(
        :MAVEN_SWIA, "MAVEN_data/MAVEN_SWIA.jl", "SWIA 仪器数据处理";
        deps = [:constants, :MarsCommon],
    ),
    :MAVEN_SWEA => _spec(
        :MAVEN_SWEA, "MAVEN_data/MAVEN_SWEA.jl", "SWEA 仪器数据处理";
        deps = [:constants],
    ),
    :MAVEN_plot => _spec(
        :MAVEN_plot, "MAVEN_data/MAVEN_plot.jl", "绘图基元（已随包预装）";
        deps = [:constants, :MarsCommon], kind = :preloaded,
    ),
    :IGRF_calculate => _spec(
        :IGRF_calculate, "Magnetic_Model/IGRF_calculate.jl", "IGRF 磁场模型（依赖 Fortran DLL）";
        deps = [:constants], allow = [:IGRF_pc, :pc2sphere, :sphere2pc],
    ),
    :Cold_Plasma_Dispersion_Relation => _spec(
        :Cold_Plasma_Dispersion_Relation, "models/Cold_Plasma_Dispersion_Relation.jl",
        "冷等离子体色散关系"; deps = [:constants],
    ),
    :Maxwellian_Distribution => _spec(
        :Maxwellian_Distribution, "models/Maxwellian_distribution.jl", "麦克斯韦分布拟合";
        deps = [:constants],
    ),
    :Single_Particle_Orbit => _spec(
        :Single_Particle_Orbit, "models/Single_Particle_Orbit.jl", "单粒子轨道追踪";
        deps = [:constants],
    ),
    :calculate_models => _spec(
        :calculate_models, "calculate/calculate_models.jl", "模型组合计算入口";
        deps = [:constants, :MarsCommon],
    ),
    :MGS_load => _spec(
        :MGS_load, "MGS_data/MGS_load.jl", "MGS 数据读取";
        deps = [:constants, :MarsCommon],
    ),
    :TW_load => _spec(
        :TW_load, "TW_data/TW_load.jl", "天问一号数据读取";
        deps = [:constants, :MarsCommon],
    ),
    :TW_MINPA => _spec(
        :TW_MINPA, "TW_data/TW_MINPA.jl", "MINPA 仪器数据处理";
        deps = [:constants],
    ),
    :SP_load => _spec(:SP_load, "support_data/support_data_load.jl", "外部支持数据（OMNI 等）"),
    :Call_fortran_dll => _spec(:Call_fortran_dll, "call_fortran_dll.jl", "Fortran 动态库调用封装"),
)

"""
    ModuleLoadError(name, file, cause)

装载模块失败（文件缺失、语法错误、内部依赖异常等）时抛出，保留原始异常为 `cause`。
"""
struct ModuleLoadError <: Exception
    name::Symbol
    file::String
    cause::Any
end

function Base.showerror(io::IO, e::ModuleLoadError)
    print(io, "ModuleLoadError: 装载模块 ", e.name, " 失败\n  文件：", e.file, "\n  原因：")
    showerror(io, e.cause)
    return nothing
end

# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

_editdistance(a::String, b::String) = begin
    la, lb = length(a), length(b)
    prev = collect(0:lb)
    cur = similar(prev)
    for i in 1:la
        cur[1] = i
        for j in 1:lb
            cost = a[i] == b[j] ? 0 : 1
            cur[j + 1] = min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
        end
        prev, cur = cur, prev
    end
    prev[lb + 1]
end

function _unknown_message(sym::Symbol)
    cands = sort!(collect(keys(MODULE_REGISTRY)); by = c -> _editdistance(string(sym), string(c)))
    near = join(string.(cands[1:min(3, length(cands))]), "、")
    return "未知模块 `$(sym)`。最相近的可用模块：$(near)。" *
           "完整清单见 `MarsData.available_modules()`。"
end

function _spec_of(name::Union{Symbol,AbstractString})
    sym = Symbol(name)
    spec = get(MODULE_REGISTRY, sym, nothing)
    spec === nothing && throw(ArgumentError(_unknown_message(sym)))
    return spec
end

function _topo_order()
    order = Symbol[]
    visiting = Set{Symbol}()
    done = Set{Symbol}()
    function visit(s::Symbol)
        s in done && return nothing
        s in visiting && throw(ArgumentError("模块依赖成环，涉及 `$(s)`"))
        push!(visiting, s)
        for d in MODULE_REGISTRY[s].deps
            haskey(MODULE_REGISTRY, d) && visit(d)
        end
        delete!(visiting, s)
        push!(done, s)
        push!(order, s)
        return nothing
    end
    for s in sort!(collect(keys(MODULE_REGISTRY)))
        visit(s)
    end
    return order
end

"""
    _apply_allow!(into, name, allow)

按白名单把 `into` 命名空间内的模块 `name` 的指定名字逐名引入。

始终使用 `using .name: a, b` 形式（**不**使用整体 `using .name`），
因此引入面完全由 `allow` 决定，与模块自身的 `export` 无关。
`allow` 为空时不做任何事。
"""
function _apply_allow!(into::Module, name::Symbol, allow::Vector{Symbol})
    isempty(allow) && return nothing
    expr = Meta.parse("using ." * string(name) * ": " * join(string.(allow), ", "))
    try
        Core.eval(into, expr)
    catch err
        throw(
            ArgumentError(
                "模块 `$(name)` 的白名单引入失败（请检查名字是否存在于该模块）：" *
                sprint(showerror, err),
            ),
        )
    end
    return nothing
end

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

"""
    module_path(name) -> String

返回注册表中该模块的**绝对路径**（已归一化，不检查文件是否存在）。
"""
module_path(name::Union{Symbol,AbstractString}) =
    normpath(joinpath(project_root(), _spec_of(name).path))

"""
    available_modules() -> Vector{Symbol}

返回全部可装载模块名（按字母序）。
"""
available_modules() = sort!(collect(keys(MODULE_REGISTRY)))

"""
    module_info(name) -> NamedTuple

返回该模块的注册信息与当前状态（是否已装载到 MarsData 命名空间）。
"""
function module_info(name::Union{Symbol,AbstractString})
    spec = _spec_of(name)
    loaded = isdefined(@__MODULE__, spec.name) && getfield(@__MODULE__, spec.name) isa Module
    return (
        name = spec.name,
        path = spec.path,
        abs_path = module_path(spec.name),
        deps = spec.deps,
        kind = spec.kind,
        allow = spec.allow,
        loaded = loaded,
        note = spec.note,
    )
end

"""
    loaded_modules() -> Dict{Symbol,Module}

返回已装载到 MarsData 命名空间的注册模块。
"""
function loaded_modules()
    d = Dict{Symbol,Module}()
    for s in keys(MODULE_REGISTRY)
        if isdefined(@__MODULE__, s) && getfield(@__MODULE__, s) isa Module
            d[s] = getfield(@__MODULE__, s)
        end
    end
    return d
end

# 运行时载体模块（懒创建），设计动机见 `_carrier` 的说明
const _CARRIER = Ref{Module}()

"""
    _carrier() -> Module

返回（并按需创建）**运行时载体模块**，所有被装载模块都在其中求值。
# 为什么需要载体
Julia 对**包模块**内的 `using` 做严格依赖校验：把 `MAVEN_load.jl` 直接 include 进
`MarsData`（一个包模块）会因 `using CommonDataFormat` 等不在本包 `[deps]` 中而失败
（错误：`Package MarsData does not have CommonDataFormat in its dependencies`）。

而运行时由 `Module(:Name)` 创建的模块没有 pkgid，其 `using` 走 `LOAD_PATH` 回退
（与 `Main` 一致），因此可以正常解析这些外部依赖 —— 这样就不必把 8 个重依赖
（CommonDataFormat/JLD2/FortranFiles/Rotations/CSV/DifferentialEquations/LsqFit/…）
全部声明进本包。

装载后的模块再以 `const` 别名绑定进 `into`（默认 `MarsData`），
因此对外仍是 `MarsData.MAVEN_load.数据函数(...)`。
"""
function _carrier()
    if !isassigned(_CARRIER)
        m = Module(:_MarsDataLoader)
        # 运行时创建的模块不自带 include，补一个
        Core.eval(m, :(include(p::AbstractString) = Base.include($m, p)))
        _CARRIER[] = m
    end
    return _CARRIER[]
end

"""
    load_module(name; into=MarsData, force=false, verbose=false) -> Module

把注册表中的模块装载进 `into` 命名空间，等价于 `include(对应文件)`。

# 参数说明
- `name::Union{Symbol,AbstractString}`：模块名；传 `:all` 时按依赖拓扑序装载全部模块
  （此时返回 `Vector{Module}`）。
- `into::Module`：落点命名空间，默认 `MarsData`（得到 `MarsData.MAVEN_load` 等）。
- `force::Bool`：是否强制重新 `include`（默认 `false`，幂等）。
- `verbose::Bool`：是否打印装载日志。

# 返回值
- 装载后的模块对象；`name === :all` 时为 `Vector{Module}`。

# 注意事项
- **幂等**：同一进程内同一模块只 `include` 一次，重复调用返回**同一对象**。
- **载体机制**：模块实际在运行时载体模块中求值（以绕开包模块的严格依赖校验），
  再以 `const` 别名绑定进 `into`；因此 `parentmodule(MarsData.MAVEN_load)` 是载体，
  而非 `MarsData` 本身。
- `:preloaded` 模块（`Paths` / `MAVEN_plot`）直接返回包内已装载的实例，不重复装载。
- `ModuleSpec.deps` 会在装载目标模块**之前**递归装入同一载体，以满足相对父模块引用
  （如 `MarsCommon` 的 `using ..constants`）。
- 装载后按 `ModuleSpec.allow` 白名单做逐名引入；白名单为空则不引入任何裸名。
"""
function load_module(
    name::Union{Symbol,AbstractString};
    into::Module = @__MODULE__,
    force::Bool = false,
    verbose::Bool = false,
)
    sym = Symbol(name)

    if sym === :all
        mods = Module[]
        for s in _topo_order()
            push!(mods, load_module(s; into = into, force = force, verbose = verbose))
        end
        return mods
    end

    spec = _spec_of(sym)

    if spec.kind === :preloaded
        mod = getfield(@__MODULE__, sym)
        if into !== (@__MODULE__) && !isdefined(into, sym)
            Core.eval(into, :(const $(sym) = $mod))
        end
        _apply_allow!(into, sym, spec.allow)
        return mod
    end

    carrier = _carrier()

    # 先把语义前置模块递归装入同一载体：部分模块以相对父模块语法引用兄弟模块
    # （如 `common/MarsCommon.jl` 的 `using ..constants`），因此 `constants` 必须
    # 先存在于载体中，否则单独装载 MarsCommon 会报 `UndefVarError: constants`。
    for d in spec.deps
        load_module(d; into = carrier, force = force, verbose = verbose)
    end

    if force || !(isdefined(carrier, sym) && getfield(carrier, sym) isa Module)
        file = module_path(sym)
        isfile(file) || throw(ArgumentError("模块 `$(sym)` 的文件不存在：$(file)"))
        verbose && @info "装载模块" name = sym file
        try
            Base.include(carrier, file)
        catch err
            throw(ModuleLoadError(sym, file, err))
        end
        if !(isdefined(carrier, sym) && getfield(carrier, sym) isa Module)
            throw(ModuleLoadError(sym, file, ErrorException("文件已求值但未定义模块 `$(sym)`")))
        end
    end

    mod = getfield(carrier, sym)

    # 以 const 别名绑定进目标命名空间（已是同一对象则跳过）
    if into !== carrier && !(isdefined(into, sym) && getfield(into, sym) === mod)
        try
            Core.eval(into, :(const $(sym) = $mod))
        catch err
            @warn "无法在 `$(into)` 中绑定 `$(sym)`（可能已存在指向旧对象的同名绑定）；请重启会话" exception = err
        end
    end

    _apply_allow!(into, sym, spec.allow)
    return mod
end

"""
    validate_registry(; verbose=false) -> (; errors, warnings)

自检注册表：键与 `name` 一致、文件存在、文件内确有 `module <name>`、`deps` 均在注册表中、
依赖无环，并检查模块文件中的相对引用与自包含 include 是否和 `deps` 一致。

# 新增校验（TASK-015）
- **错误**：文件含 `using ..X` 但 `X` 未声明在 `deps` 中。
- **警告**：文件自包含 `include(...X.jl...)` 且 `X` 又声明在 `deps` 中（冗余）。

# 返回值
- `NamedTuple{(:errors, :warnings)}`：`errors` 为问题清单；两者皆空表示全部通过。
"""
function validate_registry(; verbose::Bool = false)
    errors = String[]
    warnings = String[]
    for (s, spec) in MODULE_REGISTRY
        s === spec.name || push!(errors, "键 `$(s)` 与 `name` 字段 `$(spec.name)` 不一致")
        file = module_path(s)
        if !isfile(file)
            push!(errors, "模块 `$(s)` 的文件不存在：$(spec.path)")
            continue
        end
        txt = read(file, String)
        if !occursin(Regex("(?m)^\\s*module\\s+" * string(spec.name) * "\\b"), txt)
            push!(errors, "文件 `$(spec.path)` 中未找到 `module $(spec.name)`")
        end
        for d in spec.deps
            haskey(MODULE_REGISTRY, d) ||
                push!(errors, "模块 `$(s)` 的依赖 `$(d)` 不在注册表中")
        end

        # TASK-015 (a): 检测 `using ..X` 但 X 未声明在 deps 中 → 错误
        for m in eachmatch(r"using\s+\.\.([A-Za-z_]\w*)", txt)
            dep_name = Symbol(m[1])
            if !(dep_name in spec.deps)
                push!(errors,
                    "模块 `$(s)` 使用 `using ..$(m[1])`，但 `$(m[1])` 未在 deps 中声明")
            end
        end

        # TASK-015 (b): 检测自包含 `include(...\.jl)` 且同名模块又在 deps 中 → 警告
        for inc in eachmatch(r"include\s*\(([^)]*\.jl[^)]*)\)", txt)
            inc_arg = inc[1]
            for m in eachmatch(r"([A-Za-z_]\w*)\.jl", inc_arg)
                stem = Symbol(m[1])
                if stem in spec.deps
                    push!(warnings,
                        "模块 `$(s)` 自包含 include `$(m[1]).jl`，同时 deps 包含 `$(m[1])`（冗余）")
                end
            end
        end
    end
    try
        _topo_order()
    catch err
        push!(errors, sprint(showerror, err))
    end
    if verbose
        println("注册表自检：$(length(MODULE_REGISTRY)) 个模块，$(length(errors)) 个错误，$(length(warnings)) 个警告")
        foreach(e -> println("  [错误] ", e), errors)
        foreach(w -> println("  [警告] ", w), warnings)
    end
    return (errors = errors, warnings = warnings)
end

"""
    @load Name1 Name2 ...

在调用者作用域装载并绑定一个或多个注册模块，等价于逐个
`include(文件) + import .模块`。

# 用法
```julia
using MarsData
MarsData.@load MAVEN_load MAVEN_STATIC IGRF_calculate
# 之后可直接写 MAVEN_load.load_MAVEN_data(...)
```

# 注意事项
- 只能用于**顶层**（展开为 `const` 赋值）。
- 是否会把模块的导出名变成裸名，取决于 `ModuleSpec.allow` 白名单；为空则只绑定模块名。
"""
macro load(names...)
    isempty(names) && return :(nothing)
    load_ref = GlobalRef(@__MODULE__, :load_module)
    exprs = Any[]
    for n in names
        n isa Symbol || throw(ArgumentError("@load 只接受模块名（Symbol），收到：$(n)"))
        push!(
            exprs,
            :(const $(esc(n)) = $load_ref($(QuoteNode(n)); into = $(__module__))),
        )
    end
    return Expr(:block, exprs...)
end

export load_module, @load, available_modules, loaded_modules, module_path, module_info
export validate_registry, ModuleLoadError, ModuleSpec, MODULE_REGISTRY
