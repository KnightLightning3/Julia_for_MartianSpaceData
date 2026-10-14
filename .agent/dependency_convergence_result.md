# dependency_convergence_result.md — HD-01=A 依赖收敛实施结果（t7）

> 任务：t7 [implementation]「恢复根环境的原16项依赖」（团队 `marsdata-flash-execution`）
> 执行：official-engineer — attempt 1 / `009d0bab-5b5e-4c05-acd3-d000bda78eb9`
> 日期：2026-10-14（Asia/Shanghai）
> **接续基线：`46db822425378d4ad99f8f0b7cfed07360118486`**；目标参考提交：`94da314aba65c8a129c1883931872db6198044c6`
> 契约依据：`.agent/dependency_convergence_requirements.md`（t6，verdict=pass）
> 写入范围：**只写** `Project.toml`、`Manifest.toml`、本报告文件。

---

## 1. 结果摘要

| 项 | 结果 |
|---|---|
| 目标 | 根 `Project.toml` / `Manifest.toml` 恢复为 `94da314` 对应内容（16 项依赖），源码零回滚 |
| 结论 | **成功**：两份文件与目标 blob **逐字节一致**，`git diff --exit-code 94da314` = exit 0 |
| 依赖集合 | `[deps]` = **16 项**（与 §1.2 参考清单逐项相等） |
| 测试 | `julia --project=. test/runtests.jl` → **exit 0**；`Pass 141 / Broken 1 / Fail 0 / Total 142` |
| 红线 | 未改任何源码/测试/配置/`benchmark`/`docs`/注册表；未安装任何包；未联网；未改全局环境；未提交、未推送 |

## 2. 接续基线与目标 blob（②）

- 接续基线（t1 固定）：`46db822425378d4ad99f8f0b7cfed07360118486`
- 收敛前（= 基线）双文件 blob：`Project.toml` = `f6def9eb85dafd8c45c9d2f247f5334d6649f555`、`Manifest.toml` = `a92fb4d74e70d4dc2a7b08726e8c2ee86c57e712`（45 项状态已被该提交保全，可由 `git show 46db822:<path>` 取回）

| 文件 | 目标 blob（94da314） | 写入后 `git hash-object --no-filters`（原始字节） | 一致 |
|---|---|---|---|
| `Project.toml` | `b9b0177feadcbd25a91f1b75b21770c94dbe6192` | `b9b0177feadcbd25a91f1b75b21770c94dbe6192` | ✅ |
| `Manifest.toml` | `a37ba5bfefd864dd9b4aa78e9e2381614a9d4233` | `a37ba5bfefd864dd9b4aa78e9e2381614a9d4233` | ✅ |

- 文件字节数：`Project.toml` = 1061 B，`Manifest.toml` = 60944 B（与 `git cat-file -s 94da314:<path>` 完全相同）。
- 缓存过滤后的 `git hash-object`（不带 `--no-filters`）与上表相同，说明两份文件处于 LF-only，`text=auto`+`autocrlf=true` 的 clean filter 不改变内容。

## 3. 校验命令逐条结果（③）

| # | 命令 | exit | 关键输出 |
|---|---|---|---|
| a | `git hash-object Project.toml` | 0 | `b9b0177feadcbd25a91f1b75b21770c94dbe6192`（期望值一致） |
| a | `git hash-object Manifest.toml` | 0 | `a37ba5bfefd864dd9b4aa78e9e2381614a9d4233`（期望值一致） |
| a′ | `git hash-object --no-filters <file>`（主判据，原始字节） | 0 | 同上两个哈希，逐字节一致 |
| b | `git diff --exit-code 94da314 -- Project.toml Manifest.toml` | **0** | 无输出（两文件与 94da314 一致） |
| c | 行尾/编码扫描（逐字节） | 0 | `Project.toml`: CR=0 / LF=31 / endsWithLF=True；`Manifest.toml`: CR=0 / LF=1782 / endsWithLF=True；均无 BOM、无 TAB、无行尾空格 |
| d | `julia -e "using TOML; ..."`（只读解析，默认环境仅 stdlib） | 0 | `deps_count=16`；清单 = `CairoMakie, ColorTypes, DataFrames, DataInterpolations, Dates, DelaunayTriangulation, IniFile, JSON, LaTeXStrings, LinearAlgebra, Makie, ProgressMeter, StaticArrays, Statistics, TOML, TimesDates`；`Manifest`: `julia_version=1.10.0`、`project_hash=040c540bcab7dc28246654e048c8e0d52a9d64b8`、包条目 264 |
| e | `git status --porcelain=v1` | 0 | 见 §5（仅两份依赖文件 + `.agent/**` 文档；无任何 `.jl`/配置/`benchmark`/`docs` 改动） |
| f | `julia --version` | 0 | `julia version 1.10.5` |
| f | `julia --project=. test/runtests.jl` | **0** | 见 §4 摘要原文 |

## 4. 测试摘要原文（④）

```
┌ Info: 注册表警告
└   w = "模块 `MAVEN_STATIC` 自包含 include `MarsCommon.jl`，同时 deps 包含 `MarsCommon`（冗余）"
Test Summary:    | Pass  Broken  Total   Time
MarsData 模块装载管理器 |  141       1    142  19.3s
```

- 完整输出中匹配 `Fail|Error|ERROR|FAILED` 的行数 = **0**（对已捕获的完整测试输出逐行扫描）。
- `julia_exit=0`（`julia --project=. test/runtests.jl`，命令耗时含预编译）。
- **broken 单列**：`Broken = 1`（源码中既有的 1 处 `@test_broken`），**未计入通过**。
- **无 fail、无 skip、无因缺真实数据或 DLL 而"通过"的用例**：本次运行不存在这两类情形；因此不存在需要单列为"缺数据/缺 DLL"的用例（如实记录，而非推断）。
- 计数说明：现场为 **141 Pass**（与历史记录 141 一致）；本次不引入任何以历史值为门槛的判定。

## 5. 范围红线核查（⑤）

`git status --porcelain=v1` 现场输出：

```
 M .agent/execution_snapshot.md
 M Manifest.toml
 M Project.toml
?? .agent-teams/marsdata-flash-execution/
?? .agent/dependency_convergence_requirements.md
?? .agent/execution_decisions.md
?? .agent/target_architecture_execution.md
```

- 两份依赖文件按契约修改：`M Project.toml`、`M Manifest.toml`。
- `.agent/execution_snapshot.md` 的修改来自 **t1 收尾**（按队长指示回填 §7 基线哈希，由 t10 补记），不是本任务所为。
- 其余 `??` 项均为 t2/t6 的文档与本团队运行状态目录（运行状态目录只读、未读改、未暂存）。
- **无任何 `.jl` 源码/测试、配置、`benchmark`、`docs`、注册表改动**；未执行 `git add/commit/push`。

### 未预期观测与处理（如实记录）

1. **行尾警告（非内容差异）**：`git diff` 输出 "LF will be replaced by CRLF" 警告，属 `.gitattributes` `text=auto` + `core.autocrlf=true` 的提示；工作区实测 CR=0（LF-only），主判据哈希已证明逐字节一致，故不构成差异。
2. **首次写入后的 1 处偏差（已修复并复核）**：分 5 段写入 `Manifest.toml` 时，第 4/5 段边界误插 1 个空行（`deps.Unitful.extensions` 内部），使文件为 60945 B、哈希 `901181db…`、`git diff --exit-code` = 1。定位后仅删除该空行（文件工具 `edit`），复核为 60944 B、`a37ba5bf…`、`git diff` = **exit 0**。该过程说明主判据能捕获任何字节级偏差。
3. **写入方式说明（工具纪律）**：两份依赖文件的最终内容均由**受观察保护的文件工具**（`write`/`edit`，先读后写）写入，符合契约 §3.1-2。为取得目标 blob 的精确文本，先用 `git cat-file blob <hash>`（只读）把 blob 原样落到一次性探针文件 `.agent/_probe_manifest.toml`（**新文件**，不属于两份依赖文件，也不属于任何源码），分段转写完成后已核验绝对路径并删除；另有一份 `Tee-Object` 捕获的测试输出临时文件 `.agent/_t7_runtests_out.txt` 亦已删除。二者均不在工作区留下残留（`git status` 可证）。
4. **未使用**：`git checkout/restore/reset/clean/stash/add/commit/push` 一律未执行；未运行任何 `Pkg.add/rm/update/resolve/instantiate/develop/test()`；未联网。
5. **depot 影响**：运行测试导致的 Julia 预编译缓存写入 depot（契约 §3.1-5 明确允许）；`~/.julia/environments/v1.10/{Project,Manifest}.toml` 的 mtime 仍为 `2026-10-14 01:49:43`（早于本任务），**未被修改**。

## 6. 合规声明（⑥）

- **未安装任何包**：全程无 `Pkg.add`/`instantiate`/`resolve`/`update`/`develop`，无联网下载。
- **未修改全局环境**：`~/.julia/environments/**` 仅被只读解析；其 `Project.toml`(2158 B)、`Manifest.toml`(134770 B) 时间戳早于本任务。
- **未改源码**：除 `Project.toml`、`Manifest.toml` 与本报告外，工作区无任何文件被本任务修改；源码相对 `46db822` 逐字节不变（`git status` 无 `.jl` 条目）。
- **未提交、未推送**：本任务不做 git 写操作（`.git` 写入在本类会话亦受限，本任务无需该能力）。
- 记录差异（无需动作，按契约 §2.3 DR-4 仅记录）：恢复后的 `Manifest.toml` 记 `julia_version = "1.10.0"`、`project_hash = "040c540b…"`；现场 Julia 为 1.10.5。**未**为对齐版本号运行 `Pkg.resolve`。

## 7. 交接说明（t8 独立验证用）

- 复用证据仅为定位手段；t8 必须现场重跑 §3(a)(b) 与测试命令，并**独立解析**依赖集合，不复用本报告结论。
- 本任务已证明：45 项状态可由 `46db822` 恢复（`git show 46db822:Project.toml|Manifest.toml`），无需任何安装。
- 已知现场差异：测试摘要的 `Broken = 1` 为源码内既有 `@test_broken`；加载期的多条「注册表警告（冗余 include + deps）」为既有告警，非本次收敛引入（在 45 项状态下同样出现）。
