# =============================================================================
# Checks.jl —— 逐单元校验：目标定义 / 旧定义移除 / 悬空引用 / 动态 unknown
#
# 判定规则（与验收契约一致）：
#   * finalized + move  : to 文件必须存在模块级目标定义（名字 = name）；from≠to 时
#                         from 不得残留源定义（名字 = source_name，缺省同 name）；
#                         必须给出可核验（64 位十六进制）的 target_hash 且与目标定义一致，
#                         缺失/不可核验/不符一律 fail（不得判 ok）；source_hash 仅旧源溯源，不参与。
#   * finalized + remove: from 不得再定义源名字（纯删除单元）。
#   * pending           : 允许暂双份（from 与 to 并存）或尚未迁入，但一律记为
#                         「未完成」，绝不判为完成。
#   * 悬空引用          : 仅当引用点静态可解析、且确实解析不到时才报 fail；
#                         限定名基座不是模块、或是外部模块成员时只报 unknown/note。
#   * 动态引用          : eval / getfield(x, sym) / Symbol(…) / 动态 include 一律
#                         显式报告 unknown，绝不冒称安全；isdefined 这类缺失探测
#                         （例如 @test !isdefined(M, :sta_v_4d_new)）视为删除证据，
#                         不影响判决。
#   * 记录哈希不是 64 位十六进制时只报 warn（无法核验，不当作已验证）。
# =============================================================================

struct Finding
    severity::String                    # fail | pending | unknown | warn | note
    code::String
    unit::String
    file::String
    line::Int
    message::String
end

mutable struct UnitResult
    name::String
    source_name::String
    status::String
    action::String
    from::String
    to::String
    hash_expected::String
    hash_actual::String
    verdict::String                     # fail | pending | unknown | ok
    findings::Vector{Finding}
end

mutable struct Report
    root::String
    migrations_dir::String
    record_files::Vector{String}
    record_set::RecordSet
    index::RepoIndex
    units::Vector{UnitResult}
    record_errors::Vector{RecordIssue}
    record_warnings::Vector{RecordIssue}
    parse_errors::Vector{ParseError}
    inventory::Dict{String,Int}
    interesting_names::Vector{String}
    skipped_dirs::Vector{String}
end

const HEX64_RE = r"^[0-9a-f]{64}$"

"""单元涉及的名字：目标名 + 源名（改名单元两者不同）。"""
unit_names(rec::UnitRecord) = unique(String[rec.name, isempty(rec.source_name) ? rec.name : rec.source_name])

function run_checks(root::AbstractString;
                    files::Union{Nothing,Vector{String}}=nothing,
                    migrations_dir::Union{Nothing,AbstractString}=nothing,
                    extra_names::Vector{String}=String[])
    rootabs = abspath(String(root))
    mdir = migrations_dir === nothing ? joinpath(rootabs, "validation", "migrations") : String(migrations_dir)
    rs = load_records(mdir; root=rootabs)
    names = Set{String}()
    for r in rs.records
        for n in unit_names(r)
            isempty(n) || push!(names, n)
        end
    end
    for n in extra_names
        isempty(n) || push!(names, String(n))
    end
    skipped = String[]
    flist = if files === nothing
        discover_files(rootabs; skipped=skipped)
    else
        [isabspath(f) ? clean_rel(relpath(String(f), rootabs)) : clean_rel(String(f)) for f in files]
    end
    idx = build_index(rootabs; files=flist, names=names, skipped=skipped)
    units = UnitResult[]
    for rec in rs.records
        isempty(rec.name) && continue
        push!(units, check_unit(idx, rec))
    end
    return Report(rootabs, mdir, rs.files, rs, idx, units, rs.errors, rs.warnings,
                  idx.parse_errors, idx.inventory, sort(collect(names)), idx.skipped_dirs)
end

# ---------------------------------------------------------------------------
# 单单元校验
# ---------------------------------------------------------------------------

"""来源（旧）定义与目标（新）定义分组。"""
function unit_defs(idx::RepoIndex, rec::UnitRecord)
    src = isempty(rec.source_name) ? rec.name : rec.source_name
    from_scan = get(idx.scans, rec.from, nothing)
    to_scan = rec.to == "" ? nothing : get(idx.scans, rec.to, nothing)
    from_top = from_scan === nothing ? Definition[] : top_defs(from_scan, src)
    from_nested = from_scan === nothing ? Definition[] :
                  [d for d in from_scan.defs if !d.top_level && d.name == src]
    to_top = to_scan === nothing ? Definition[] : top_defs(to_scan, rec.name)
    to_nested = to_scan === nothing ? Definition[] :
                [d for d in to_scan.defs if !d.top_level && d.name == rec.name]
    return (src=src, from_scan=from_scan, to_scan=to_scan, from_top=from_top,
            from_nested=from_nested, to_top=to_top, to_nested=to_nested)
end

function check_unit(idx::RepoIndex, rec::UnitRecord)
    f = Finding[]
    d = unit_defs(idx, rec)
    u = UnitResult(rec.name, d.src, rec.status, rec.action, rec.from, rec.to, rec.hash, "", "ok", f)
    renamed = d.src != rec.name

    if isempty(rec.from)
        push!(f, Finding("pending", "UNFINISHED_NO_FROM", rec.name, rec.source_file, 0,
                         "记录缺少 from：无法校验旧定义移除，该单元按未完成处理"))
    elseif d.from_scan === nothing
        # from 文件不在扫描集合：区分「文件仍在磁盘」（扫描集合不完整 → 无法核对）与
        # 「文件已被删除」（合法迁出，需 source_revision 旧对象取证，t27）。
        on_disk = !isempty(idx.root) && isfile(joinpath(idx.root, rec.from))
        if on_disk
            push!(f, Finding("fail", "FROM_FILE_MISSING", rec.name, rec.from, rec.from_line,
                             "from 文件存在但不在扫描集合内，无法证明源定义是否残留"))
        else
            ev, detail = old_source_evidence(idx.root, rec.source_revision, rec.from, d.src)
            # finalized 才升级为 fail：pending 单元本就未完成（note 足够），但都不会判 ok
            no_rev_sev = rec.status == "finalized" ? "fail" : "note"
            if ev === :verified
                push!(f, Finding("note", "SOURCE_FILE_DELETED_VERIFIED", rec.name, rec.from, 0,
                                 "from 文件已删除且旧源可核对（$(detail)）→ 允许源定义移除，不要求保留空壳"))
            elseif ev === :no_revision
                push!(f, Finding(no_rev_sev, "SOURCE_FILE_DELETED_UNAUTHORIZED", rec.name, rec.from, rec.from_line,
                                 "from 文件已删除但缺少旧源取证授权（$(detail)）→ 无法证明源定义已删"))
            else
                push!(f, Finding("unknown", "SOURCE_FILE_DELETED_UNVERIFIABLE", rec.name, rec.from, rec.from_line,
                                 "from 文件已删除但旧源不可核对（$(detail)）→ 不得判 ok"))
            end
        end
    end
    if rec.action == "move" && d.to_scan === nothing
        push!(f, Finding("fail", "TARGET_FILE_MISSING", rec.name, rec.to, rec.to_line,
                         "to 目标文件不在扫描集合内，无法确认目标定义"))
    end
    rename_note = renamed ? "（source_name=$(d.src) → name=$(rec.name)）" : ""

    if rec.status == "finalized"
        if rec.action == "move"
            if isempty(d.to_top)
                msg = "目标定义缺失（漏迁）" * rename_note
                isempty(d.to_nested) ||
                    (msg *= "；另有 $(length(d.to_nested)) 处嵌套同名定义，嵌套定义不算模块级目标定义")
                push!(f, Finding("fail", "TARGET_DEFINITION_MISSING", rec.name, rec.to, rec.to_line, msg))
            else
                u.hash_actual = d.to_top[1].hash
                if length(d.to_top) > 1
                    push!(f, Finding("fail", "DUPLICATE_DEFINITION", rec.name, rec.to, d.to_top[2].line,
                                     "目标文件有 $(length(d.to_top)) 处模块级同名定义（旧/新并存）"))
                end
                hf = hash_finding(rec, u.hash_actual, rec.to, d.to_top[1].line, true)
                hf === nothing || push!(f, hf)
            end
            if rec.from != rec.to
                if !isempty(d.from_top)
                    push!(f, Finding("fail", "OLD_DEFINITION_RESIDUE", rec.name, rec.from, d.from_top[1].line,
                                     "finalized 但旧文件仍存在模块级源定义（旧定义残留）" * rename_note))
                elseif !isempty(d.from_nested)
                    push!(f, Finding("note", "NESTED_SHADOW_ONLY", rec.name, rec.from, d.from_nested[1].line,
                                     "旧文件仅剩 $(length(d.from_nested)) 处嵌套同名定义（非模块级旧定义，不计残留）"))
                end
            end
        else  # remove
            if !isempty(rec.to)
                push!(f, Finding("warn", "REMOVE_WITH_TARGET", rec.name, rec.to, rec.to_line,
                                 "action=remove 但给出了 to=$(rec.to)：目标位置仅作备注，不参与完成判定"))
            end
            if !isempty(d.from_top)
                push!(f, Finding("fail", "OLD_DEFINITION_RESIDUE", rec.name, rec.from, d.from_top[1].line,
                                 "删除单元 finalized 但源定义仍在" * rename_note))
            elseif !isempty(d.from_nested)
                push!(f, Finding("note", "NESTED_SHADOW_ONLY", rec.name, rec.from, d.from_nested[1].line,
                                 "旧文件仅剩嵌套同名定义（非模块级旧定义，不计残留）"))
            end
        end
    elseif rec.status == "pending"
        has_from = !isempty(d.from_top)
        has_to = !isempty(d.to_top)
        if has_from && has_to
            push!(f, Finding("pending", "PENDING_DOUBLE_DEFINITION", rec.name, rec.to, d.to_top[1].line,
                             "pending 迁入：旧/新定义暂双份（允许），不得视为已完成" * rename_note))
        elseif has_from
            push!(f, Finding("pending", "PENDING_NOT_MIGRATED", rec.name, rec.from, d.from_top[1].line,
                             "pending：仅源定义存在，尚未迁入" * rename_note))
        elseif has_to
            push!(f, Finding("pending", "PENDING_NOT_FINALIZED", rec.name, rec.to, d.to_top[1].line,
                             "pending：目标已存在且源定义已无，但状态仍为 pending（未完成）" * rename_note))
        else
            push!(f, Finding("fail", "MIGRATION_MISSING_TARGET", rec.name, rec.from, rec.from_line,
                             "pending 但源、目标位置都找不到定义（迁移悬空）" * rename_note))
        end
        if has_to
            u.hash_actual = d.to_top[1].hash
            hf = hash_finding(rec, u.hash_actual, rec.to, d.to_top[1].line, false)
            hf === nothing || push!(f, hf)
        end
    else
        # status 缺失或取值无法识别：按「未完成」处理，绝不判为 finalized
        push!(f, Finding("pending", "UNFINISHED_UNKNOWN_STATUS", rec.name, rec.source_file, 0,
                         "status 缺失或无法识别（原始值 \"$(rec.status_raw)\"）：按未完成处理"))
        if isempty(d.from_top) && isempty(d.to_top) && isempty(d.from_nested) && isempty(d.to_nested)
            push!(f, Finding("fail", "MIGRATION_MISSING_TARGET", rec.name, rec.from, rec.from_line,
                             "源、目标位置都没有该定义（迁移悬空）"))
        end
    end

    check_references!(idx, rec, f, rec.status == "finalized" ? "fail" : "note")

    for ds in dynamic_concerns(idx, rec)
        push!(f, Finding("unknown", "DYNAMIC_REFERENCE_UNKNOWN", rec.name, ds.file, ds.line,
                         "存在无法静态解析的动态引用（$(ds.kind)），该单元不能宣称已验证安全: $(ds.snippet)"))
    end

    u.verdict = any(x -> x.severity == "fail", f) ? "fail" :
                any(x -> x.severity == "pending", f) ? "pending" :
                any(x -> x.severity == "unknown", f) ? "unknown" : "ok"
    return u
end

"""target_hash（目标定义哈希）比对：finalized 必须有可核验（64 位十六进制）且一致的目标哈希，
缺失/不可核验/不符一律判 fail；pending 只给 note/warn（pending 自身已判未完成）。
source_hash 属旧源溯源口径，不进入本函数。"""
function hash_finding(rec::UnitRecord, actual::AbstractString, file::AbstractString, line::Int,
                      finalized::Bool)
    loc = rec.hash_field == "" ? "target_hash" : rec.hash_field
    if isempty(rec.hash)
        finalized || return nothing
        return Finding("fail", "TARGET_HASH_MISSING", rec.name, file, line,
                       "finalized 但缺少 target_hash（$(loc) 为空；source_hash 只是旧源溯源，不能充当目标哈希）")
    end
    h = lowercase(String(rec.hash))
    if !occursin(HEX64_RE, h)
        if finalized
            return Finding("fail", "TARGET_HASH_UNVERIFIABLE", rec.name, file, line,
                           "$loc=$(h) 不是 64 位十六进制 SHA-256，无法核验目标定义（请用 --print-hash 生成 target_hash）")
        end
        return Finding("warn", "HASH_UNVERIFIABLE", rec.name, file, line,
                       "$loc=$(h) 不是 64 位十六进制 SHA-256，本工具无法核验（请用 --print-hash 生成 target_hash）")
    end
    lowercase(String(actual)) == h && return nothing
    if finalized
        return Finding("fail", "HASH_MISMATCH", rec.name, file, line,
                       "$loc 不一致：期望 $(h)，实际 $(lowercase(String(actual)))")
    end
    return Finding("note", "HASH_PENDING_DIFF", rec.name, file, line,
                   "$loc 与目标定义不一致（pending 未完成，仅供参考）")
end

# ---------------------------------------------------------------------------
# 引用与动态点
# ---------------------------------------------------------------------------

function refs_for(idx::RepoIndex, name::AbstractString)
    out = RefSite[]
    for rel in idx.order
        for r in idx.scans[rel].refs
            r.name == String(name) && push!(out, r)
        end
    end
    return out
end

function check_references!(idx::RepoIndex, rec::UnitRecord, f::Vector{Finding}, severity::String)
    for nm in unit_names(rec)
        for r in refs_for(idx, nm)
            if r.shadowed
                # 局部绑定（形参/局部变量/解构/循环变量/内层函数名…）：Julia 中与全局同名不冲突，
                # 该引用不指向全局定义，故不做悬空判定（t26 形参误报修复）。
                continue
            end
            if is_nested_name_file(idx, nm, r.file)
                push!(f, Finding("note", "NESTED_SCOPE_POSSIBLE", nm, r.file, r.line,
                                 "该文件含嵌套同名定义，局部绑定可能解析此引用，不做 fail 判定"))
                continue
            end
            if r.role == "quoted"
                push!(f, Finding("unknown", "DYNAMIC_QUOTED_REFERENCE", nm, r.file, r.line,
                                 "引号 / @eval 内的引用 ($(nm)) 可能被动态执行，无法静态判定，不判悬空"))
                continue
            end
            if r.role == "qualified" || r.role == "qualified-call"
                if isempty(r.base)
                    push!(f, Finding("note", "UNRESOLVED_QUALIFIER_BASE", nm, r.file, r.line,
                                     "限定引用基座无法确定"))
                    continue
                end
                tk = resolve_base_module(idx, r.file, r.module_path, r.base)
                if tk === nothing
                    push!(f, Finding("note", "NON_MODULE_BASE", nm, r.file, r.line,
                                     "$(r.base).$(nm) 的基座 $(r.base) 不是可判定模块（可能是字段访问），无法静态判定"))
                elseif length(tk) == 1 && tk[1] == "*external*"
                    push!(f, Finding("note", "EXTERNAL_MODULE_MEMBER", nm, r.file, r.line,
                                     "$(r.base).$(nm) 基座为外部模块，成员无法静态判定"))
                elseif member_resolves(idx, tk, nm) == :unresolved
                    push!(f, Finding(severity, "DANGLING_REFERENCE", nm, r.file, r.line,
                                     "限定引用 $(r.base).$(nm) 在项目模块 [$(join(tk, ", "))] 中找不到定义"))
                end
            else
                res = resolves_in(idx, r.file, r.module_path, nm)
                if res == :unresolved
                    scope = isempty(r.module_path) ? "<脚本根>" : mkey(r.module_path)
                    push!(f, Finding(severity, "DANGLING_REFERENCE", nm, r.file, r.line,
                                     "引用 $(nm)（$(r.role)）在作用域 [$scope] 无法静态解析到任何定义/导入（悬空引用）"))
                elseif res == :external
                    push!(f, Finding("note", "EXTERNAL_NAME", nm, r.file, r.line,
                                     "$(nm) 未在本项目解析到定义，但 Base/Core 存在同名绑定，未判悬空"))
                end
            end
        end
    end
    return
end

"""与单元相关的动态点：字面量提示命中单元名，或同文件内名称完全不可判定。"""
function dynamic_concerns(idx::RepoIndex, rec::UnitRecord)
    out = DynamicSite[]
    seen = Set{Tuple{String,Int,String}}()
    names = Set{String}(unit_names(rec))
    for d in idx.dynamic_sites
        d.kind == "absence-probe" && continue          # isdefined 等缺失探测=删除证据
        hit = (!isempty(d.hint) && d.hint in names) ||
              (d.unknown_name && (d.file == rec.from || d.file == rec.to))
        hit || continue
        key = (d.file, d.line, d.kind)
        key in seen && continue
        push!(seen, key)
        push!(out, d)
    end
    return out
end

# ---------------------------------------------------------------------------
# 汇总与退出码
# ---------------------------------------------------------------------------

all_findings(rep::Report) = vcat([u.findings for u in rep.units]...)

findings_of(rep::Report, code::AbstractString) =
    [x for x in all_findings(rep) if x.code == String(code)]

units_with_verdict(rep::Report, v::AbstractString) =
    [u for u in rep.units if u.verdict == String(v)]

unit_result(rep::Report, name::AbstractString) =
    (found = [u for u in rep.units if u.name == String(name)]; isempty(found) ? nothing : found[1])

"未完成清单：pending 或 unknown 单元（不含已 ok 的）。"
function unfinished_units(rep::Report)
    return [u for u in rep.units if u.verdict in ("pending", "unknown")]
end

has_parse_errors(rep::Report) = !isempty(rep.parse_errors)
has_failures(rep::Report) = any(u -> u.verdict == "fail", rep.units)

"""
退出码约定：
  3 = 记录配置错误（schema/必填字段/路径非法）
  2 = 解析失败（AST 解析不出）
  1 = 存在 fail 判定（漏迁/旧定义残留/悬空引用/哈希不符等）
  0 = 通过（pending/unknown 会打印但不算失败）
"""
function exit_code(rep::Report)
    isempty(rep.record_errors) || return 3
    isempty(rep.parse_errors) || return 2
    has_failures(rep) && return 1
    return 0
end
