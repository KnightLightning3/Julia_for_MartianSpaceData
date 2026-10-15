# =============================================================================
# Records.jl —— 迁移记录（validation/migrations/*.toml）读取与规范化
#
# 约定 schema（与 captain 的清单建议对齐）：
#
#   schema_version = 1                # 可选；缺省按 1
#
#   [[moves]]                         # 也接受 [[unit]]/[[units]]/[[migration]]/[[migrations]]
#   name        = "sta_v_4d_new"      # 必填：迁入后的目标绑定名
#   source_name = "old_name"          # 可选：迁入前的源绑定名（改名单元才有差异，缺省 = name）
#   from        = "MAVEN_data/MAVEN_STATIC.jl"   # 必填：旧定义所在文件（可带 :行号 提示）
#   to          = "MAVEN_data/MAVEN_STATIC.jl"   # 迁入目标文件；留空/缺省 = 纯删除
#   status      = "finalized"         # finalized=源已删且调用已更新；pending=迁入源尚在
#   target_hash = "sha256:…"          # 目标定义规范化 SHA-256（本工具 --print-hash 产出，64 位十六进制）
#   source_hash = "…"                 # 旧源溯源哈希：原值保留，绝不用于目标核验
#   source_hash_kind = "sha256-source-block"   # 可选：标注 source_hash 口径
#   source_revision  = "5f225db"               # 可选：标注 source_hash 对应的旧修订
#   action / kind / owner / task / notes       # 可选备注字段
#
# 哈希语义分离（修复 t8 HASH_SOURCE_TARGET_CONFLATION）：
#   * 目标核验只读 target_hash（显式优先；legacy 裸 hash 仅作兼容别名并告警）；
#   * source_hash 永不充当目标哈希，原值保留，只作旧源溯源；
#   * status=finalized 且 action=move 时，必须给出可核验（64 位十六进制）的
#     target_hash，否则记为记录错误（阻塞，退出码 3）——不得判 ok（强于 warn）；
#     纯删除（action=remove）没有目标定义，故不要求 target_hash；
#   * 记录文件只读：本工具不重写、不回填任何历史哈希，字段转换由清单层（t12）完成。
#
# 兼容策略：未知字段只告警不拒绝；status 缺失或取值无法识别时按「未完成」处理，
# 绝不判为 finalized（禁止冒称完成）。
# =============================================================================

const RECORD_ARRAY_KEYS = ["moves", "unit", "units", "migration", "migrations"]
const RECORD_KNOWN_KEYS = Set{String}(["name", "source_name", "from", "to", "status", "action",
                                       "kind", "hash", "source_hash", "source_hash_kind",
                                       "source_revision", "target_hash", "owner", "task",
                                       "notes", "note", "comment", "issue", "pr"])
"""目标哈希的可核验口径：64 位十六进制（sha256 前可有 `sha256:` 前缀，归一化时去掉）。"""
const VERIFIABLE_HASH_RE = r"^[0-9a-f]{64}$"
const SCHEMA_VERSION = 1

struct RecordIssue
    code::String
    file::String
    message::String
end

struct UnitRecord
    name::String                        # 目标（迁入后）绑定名
    source_name::String                 # 源（迁入前）绑定名；缺省 = name（改名单元才有差异）
    status::String                      # pending | finalized | ""（缺失/未知）
    status_raw::String
    action::String                      # move | remove
    from::String
    to::String
    hash::String                        # 目标哈希：只来自 target_hash（legacy 裸 hash 需告警）；绝不用 source_hash
    hash_field::String                  # 提供目标哈希的字段名："target_hash" | "hash" | ""
    kind::String
    owner::String
    task::String
    notes::String
    source_file::String
    from_line::Int
    to_line::Int
    target_hash_verifiable::Bool        # 目标哈希是否为 64 位十六进制（可核验口径）
    source_hash::String                 # 旧源溯源哈希：原值保留，不参与目标核验
    source_hash_field::String           # 提供 source_hash 的字段名："source_hash" | ""
    source_hash_kind::String            # 可选：source_hash 口径标注（如 sha256-source-block）
    source_revision::String             # 可选：source_hash 对应的旧修订标识
end

struct RecordSet
    dir::String
    dir_missing::Bool
    files::Vector{String}
    records::Vector{UnitRecord}
    errors::Vector{RecordIssue}
    warnings::Vector{RecordIssue}
end

str_or_empty(x) = x === nothing ? "" : (x isa AbstractString ? String(x) : string(x))

"""status 归一化：只有 finalized/pending 两种完成语义；其余一律视为「未完成」。"""
function normalize_status(s::AbstractString)
    t = lowercase(strip(String(s)))
    t in ("finalized", "finalised", "done", "complete", "completed") && return "finalized"
    t in ("pending", "in_progress", "inprogress", "wip", "todo", "moving", "迁移中", "未完成") && return "pending"
    return ""
end

"""`path:line` → (path, line)；无行号时 line=0。"""
function split_path_line(s::AbstractString)
    m = match(r"^([^:]+):(\d+)$", strip(String(s)))
    m === nothing && return (strip(String(s)), 0)
    return (String(m.captures[1]), parse(Int, m.captures[2]))
end

is_valid_rel_path(p::AbstractString) =
    !isempty(p) && !startswith(String(p), "/") && !occursin(r"^[A-Za-z]:", String(p)) &&
    !startswith(String(p), "..")

function load_records(dir::AbstractString; root::AbstractString="")
    files = String[]
    records = UnitRecord[]
    errors = RecordIssue[]
    warnings = RecordIssue[]
    if !isdir(dir)
        return RecordSet(String(dir), true, files, records, errors, warnings)
    end
    for fn in sort(readdir(dir))
        endswith(fn, ".toml") || continue
        rel = isempty(root) ? fn : clean_rel(relpath(joinpath(dir, fn), root))
        push!(files, rel)
        data = try
            TOML.parsefile(joinpath(dir, fn))
        catch err
            push!(errors, RecordIssue("REC_TOML_PARSE", rel, "TOML 解析失败: " * sprint(showerror, err)))
            continue
        end
        sv = get(data, "schema_version", nothing)
        if sv === nothing
            push!(warnings, RecordIssue("REC_NO_SCHEMA_VERSION", rel, "缺少 schema_version，按 $SCHEMA_VERSION 处理"))
        elseif !(sv isa Integer) || sv > SCHEMA_VERSION
            push!(errors, RecordIssue("REC_UNSUPPORTED_SCHEMA", rel,
                                      "schema_version=$(sv) 不受支持（本工具支持 $SCHEMA_VERSION）"))
            continue
        end
        keyname = nothing
        for k in RECORD_ARRAY_KEYS
            if haskey(data, k)
                keyname === nothing && (keyname = k)
                k == keyname || push!(warnings, RecordIssue("REC_MULTIPLE_ARRAY_KEYS", rel,
                                                            "同时出现 [$keyname] 与 [$k]，已忽略 [$k]"))
            end
        end
        for k in sort(collect(keys(data)))
            (k == "schema_version" || k in RECORD_ARRAY_KEYS) && continue
            push!(warnings, RecordIssue("REC_UNKNOWN_TOP_KEY", rel, "未知顶层键 $k（已忽略）"))
        end
        if keyname === nothing
            push!(errors, RecordIssue("REC_NO_RECORDS", rel,
                                      "未找到记录数组（期望 [[moves]]，兼容 [[unit]]/[[units]]/[[migration]]）"))
            continue
        end
        items = data[keyname]
        items isa AbstractVector || (items = Any[items])
        for (i, item) in enumerate(items)
            if !(item isa AbstractDict)
                push!(errors, RecordIssue("REC_BAD_ENTRY", rel, "第 $i 条记录不是表，已跳过"))
                continue
            end
            push!(records, normalize_record(item, rel, i, errors, warnings))
        end
    end
    return RecordSet(String(dir), false, files, records, errors, warnings)
end

function normalize_record(item::AbstractDict, rel::AbstractString, idx::Int,
                          errors::Vector{RecordIssue}, warnings::Vector{RecordIssue})
    where_ = "$rel #$idx"
    name = strip(str_or_empty(get(item, "name", nothing)))
    source_name = strip(str_or_empty(get(item, "source_name", nothing)))
    isempty(source_name) && (source_name = name)          # 缺省 source_name = name
    from_raw = strip(str_or_empty(get(item, "from", nothing)))
    to_raw = strip(str_or_empty(get(item, "to", nothing)))
    status_raw = strip(str_or_empty(get(item, "status", nothing)))
    status = normalize_status(status_raw)
    action = lowercase(strip(str_or_empty(get(item, "action", nothing))))
    if isempty(action)
        action = isempty(to_raw) ? "remove" : "move"
    elseif !(action in ("move", "remove"))
        push!(warnings, RecordIssue("REC_UNKNOWN_ACTION", rel, "$where_ action=$action 无法识别，按 $(isempty(to_raw) ? "remove" : "move") 处理"))
        action = isempty(to_raw) ? "remove" : "move"
    end
    if !isempty(status_raw) && isempty(status)
        push!(warnings, RecordIssue("REC_UNKNOWN_STATUS", rel,
                                    "$where_ status=$status_raw 无法识别：按「未完成」处理，不会判为 finalized"))
    elseif isempty(status_raw)
        push!(warnings, RecordIssue("REC_NO_STATUS", rel, "$where_ 缺 status：按「未完成」处理，不会判为 finalized"))
    end
    # ---- 哈希语义分离（修复 t8 HASH_SOURCE_TARGET_CONFLATION）----------------
    # 目标核验只读 target_hash（显式优先）；legacy 裸 hash 仅作兼容别名（告警）；
    # source_hash 是旧源溯源口径，永不参与目标核验，且原值保留不做归一化。
    hash_field = haskey(item, "target_hash") ? "target_hash" :
                 (haskey(item, "hash") ? "hash" : "")
    hash = hash_field == "" ? "" : normalize_hash(get(item, hash_field, nothing))
    if hash_field == "hash"
        push!(warnings, RecordIssue("REC_LEGACY_HASH_FIELD", rel,
                                    "$where_ 用裸 hash 充当目标哈希：建议改用显式 target_hash"))
    elseif hash_field == "target_hash" && haskey(item, "hash")
        push!(warnings, RecordIssue("REC_HASH_FIELD_AMBIGUOUS", rel,
                                    "$where_ 同时给出 target_hash 与裸 hash：按显式 target_hash 处理"))
    end
    source_hash = strip(str_or_empty(get(item, "source_hash", nothing)))
    source_hash_kind = strip(str_or_empty(get(item, "source_hash_kind", nothing)))
    source_revision = strip(str_or_empty(get(item, "source_revision", nothing)))
    target_verifiable = occursin(VERIFIABLE_HASH_RE, hash)

    isempty(name) && push!(errors, RecordIssue("REC_MISSING_NAME", rel, "$where_ 缺少 name，无法校验"))
    if isempty(from_raw)
        # 非严格兼容：缺 from 只告警，该单元按「未完成」处理（无法证明旧定义已删，绝不判完成）
        push!(warnings, RecordIssue("REC_NO_FROM", rel,
                                    "$where_ 缺少 from：该单元按未完成处理（无法校验旧定义移除）"))
    end

    # finalized 的迁入单元必须绑定可核验的目标哈希，否则拒绝判 ok（阻塞，强于 warn）。
    # 缺 from 的记录本就是「未完成」（REC_NO_FROM，绝不会判 ok），不再叠加门禁噪声。
    if status == "finalized" && action == "move" && !target_verifiable &&
       !isempty(name) && !isempty(from_raw)
        detail = if isempty(hash) && isempty(source_hash)
                     "未提供任何哈希"
                 elseif isempty(hash)
                     "仅有 source_hash=$(source_hash)（旧源溯源口径，不能充当目标哈希）"
                 else
                     "target_hash=$(hash) 不是 64 位十六进制，无法核验"
                 end
        push!(errors, RecordIssue("REC_FINALIZED_WITHOUT_VERIFIABLE_TARGET_HASH", rel,
                                  "$where_ status=finalized 但 target_hash 不可核验：$detail ⇒ 不得判 ok"))
    end

    for k in sort(collect(keys(item)))
        k in RECORD_KNOWN_KEYS && continue
        push!(warnings, RecordIssue("REC_UNKNOWN_KEY", rel, "$where_ 未知字段 $k（已忽略，不拒绝）"))
    end

    from_path, from_line = split_path_line(from_raw)
    to_path, to_line = split_path_line(to_raw)
    # 空字段保持空（clean_rel("") 会退化成 "."）
    from_path = isempty(from_raw) ? "" : clean_rel(from_path)
    to_path = isempty(to_raw) ? "" : clean_rel(to_path)
    if !isempty(from_raw) && !is_valid_rel_path(from_path)
        push!(errors, RecordIssue("REC_BAD_PATH", rel, "$where_ from=$from_raw 不是仓库相对路径"))
        from_path = ""
    end
    if !isempty(to_raw) && !is_valid_rel_path(to_path)
        push!(errors, RecordIssue("REC_BAD_PATH", rel, "$where_ to=$to_raw 不是仓库相对路径"))
        to_path = ""
    end

    return UnitRecord(name, source_name, status, status_raw, action, from_path, to_path, hash, hash_field,
                      str_or_empty(get(item, "kind", nothing)),
                      str_or_empty(get(item, "owner", nothing)),
                      str_or_empty(get(item, "task", nothing)),
                      str_or_empty(get(item, haskey(item, "notes") ? "notes" : "note", nothing)),
                      where_, from_line, to_line,
                      target_verifiable, source_hash,
                      isempty(source_hash) ? "" : "source_hash",
                      source_hash_kind, source_revision)
end

"""仓库中某文件里目标定义的规范化哈希（供 --print-hash 与记录生成）。"""
function definition_hash(root::AbstractString, file_rel::AbstractString, name::AbstractString)
    idx = build_index(root; files=[clean_rel(file_rel)], names=Set{String}([String(name)]))
    scan = get(idx.scans, clean_rel(file_rel), nothing)
    scan === nothing && return nothing
    ds = top_defs(scan, name)
    isempty(ds) && return nothing
    return ds[1].hash
end

# ---------------------------------------------------------------------------
# 旧源证据（源文件被合法删除时的只读核对；不做联网，只用本地 `git show`）
# ---------------------------------------------------------------------------

"""
    old_source_evidence(root, rev, path, name) -> (status, detail)

当记录的 `from` 文件已从工作区删除时，用记录声明的 `source_revision` 做只读取证：
`git -C root show <rev>:<path>` 取回旧对象并用本工具解析，确认是否确有 `name` 的顶层定义。

status：
  · `:verified`      旧对象存在且含该名字的顶层定义 → 可授权「源文件已删除」（合法迁出）
  · `:no_revision`   记录未给 source_revision → 无旧源溯源授权
  · `:object_missing` `git show` 取不到（rev 不存在 / path 不在该 rev / 无仓库 / 无 git）
  · `:name_absent`   旧对象取到了，但未见该名字的顶层定义（证据不支持）

source_hash 仅作旧源溯源展示（口径由 source_hash_kind 标注），本工具不改写、不回填、不伪造。
"""
function old_source_evidence(root::AbstractString, rev::AbstractString, path::AbstractString,
                             name::AbstractString)
    isempty(rev) && return (:no_revision, "记录未给出 source_revision（无旧源溯源授权）")
    isempty(path) && return (:object_missing, "记录未给出 from 路径")
    spec = string(rev, ":", path)
    text = try
        read(`git -C $(String(root)) show $spec`, String)
    catch err
        msg = first(replace(sprint(showerror, err), r"\s+" => " "), 90)
        return (:object_missing, "git show $(spec) 取不到（$(msg)）")
    end
    scan = scan_source(text, "old:" * String(path), Set{String}([String(name)]))
    if !isempty(scan.parse_error)
        return (:name_absent, "旧对象解析失败：$(first(scan.parse_error, 80))")
    end
    ds = top_defs(scan, name)
    isempty(ds) && return (:name_absent, "旧对象存在，但未见 $(name) 的顶层定义")
    return (:verified, "旧源 $(spec) 存在 $(name) 顶层定义（第 $(ds[1].line) 行）")
end
