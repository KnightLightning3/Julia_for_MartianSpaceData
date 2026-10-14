# dependency_convergence_requirements.md — HD-01=A 依赖收敛实施契约（requirements）

> 任务：t6 [requirements]「确认依赖收敛的实施契约」（团队 `marsdata-flash-execution`）
> 执行：official-reviewer（裁决落地、架构修订与独立代码审查）— attempt 1 / `9918bf76-8ff9-4853-8092-b91461e75531`
> 日期：2026-10-14（Asia/Shanghai）
> **接续基线：`46db822425378d4ad99f8f0b7cfed07360118486`**；原始 16 项参考提交：`94da314aba65c8a129c1883931872db6198044c6`。
> 输入：`.agent/audit` 裁决（`.agent/审计结果.md` HD-01=A）、`.agent/execution_snapshot.md`（t1）、`.agent/execution_decisions.md` §3.1（t2）、团队合同 t7/t8/t9。
> 写入范围：**只写本文件**。`Project.toml`、`Manifest.toml` 属 **out of scope**，本任务不修改、不暂存、不提交它们，也不执行任何 `Pkg` 变更操作。
> 状态：**契约（requirements）**。本文件不实施收敛；实施由 t7 在契约通过后执行，独立验证由 t8 执行，独立审查由 t9 执行。

---

## 0. 目标与判据（HD-01=A）

| 项 | 内容 |
|---|---|
| 目标 | 根 `Project.toml` 与 `Manifest.toml` **恢复为 94da314 的对应内容**（原 16 项依赖），使依赖清单回到用户裁决的 A 分支 |
| 非目标 | 不回滚、不改动任何源码/测试/配置/`benchmark`/`docs`；不改全局 Julia 环境；不安装、不升级、不降级任何包 |
| 判定 | 「两份文件的内容与 94da314 的 Git blob **逐字节一致**」+「上述源码与环境的范围红线未被触碰」+「验证命令现场运行并如实记录」 |
| 数据来源 | 只允许通过 `git show 94da314:<path>` / `git cat-file blob <hash>` **读取** blob；禁止 `git checkout`/`git restore`/`git reset` 等会写工作区/索引的恢复方式 |

---

## 1. 权威参考与不变量（只读实测，锚点 `46db822`）

### 1.1 接续快照保全了原 45 项状态（可追溯）

| 文件 | `46db822` 的 blob | 当前工作区 `git hash-object` | 结论 |
|---|---|---|---|
| `Project.toml` | `f6def9eb85dafd8c45c9d2f247f5334d6649f555` | `f6def9eb85dafd8c45c9d2f247f5334d6649f555` | 与快照逐字节一致（45 项状态已被提交保全） |
| `Manifest.toml` | `a92fb4d74e70d4dc2a7b08726e8c2ee86c57e712` | `a92fb4d74e70d4dc2a7b08726e8c2ee86c57e712` | 同上 |

- `git status --porcelain=v1 -- Project.toml Manifest.toml` 为空 ⇒ 两份文件当前**无未提交修改**。
- 45 项状态的恢复路径（若将来需要）：`git show 46db822:Project.toml` / `git show 46db822:Manifest.toml`。收敛**不会**销毁该状态（历史提交不可变）。
- 【实测】当前 `Project.toml` 60 行、`Manifest.toml` 3515 行；`94da314` 的 `Project.toml` 31 行、`Manifest.toml` 1782 行。

### 1.2 目标内容（94da314 的 16 项）

| 文件 | 94da314 blob |
|---|---|
| `Project.toml` | `b9b0177feadcbd25a91f1b75b21770c94dbe6192` |
| `Manifest.toml` | `a37ba5bfefd864dd9b4aa78e9e2381614a9d4233` |

16 项（`[deps]`，与 94da314 `Project.toml` 字面一致）：
`CairoMakie, ColorTypes, DataFrames, DataInterpolations, Dates, DelaunayTriangulation, IniFile, JSON, LaTeXStrings, LinearAlgebra, Makie, ProgressMeter, StaticArrays, Statistics, TOML, TimesDates`

其余节（`[compat] julia = "1.10"`、`[extras] Test`、`[targets] test = ["Test"]`）随 blob 原样恢复。

### 1.3 行尾纪律（避免"内容一致但字节不同"）

- `.gitattributes` 有 `* text=auto`，`core.autocrlf = true`；当前工作区两份文件均为 **LF-only**（`Project.toml` CRLF=0/LF=60；`Manifest.toml` CRLF=0/LF=3515）。
- 契约要求：恢复后两份文件必须仍是 **LF-only**，且 `git hash-object`（非 `--path` 模式，按原始字节）等于 §1.2 的 blob 哈希。`git diff --exit-code` 会经 clean filter 归一化，**只能作为辅助证据**，不能单独证明字节一致。

---

## 2. 当前环境核实（只读；不安装、不改环境）

> 本节是**对环境现状的核实**，不是对收敛结果的预判。收敛后是否通过，只能以 §4 现场运行结果为准。

### 2.1 Julia 与加载路径

| 项 | 实测值 |
|---|---|
| Julia | `julia version 1.10.5`（`C:\Users\Knight Lightning\AppData\Local\Programs\Julia-1.10.5\bin\julia.exe`） |
| `JULIA_DEPOT_PATH` | 未设置 ⇒ 默认 `~/.julia`（`depot = C:\Users\Knight Lightning\.julia`） |
| 加载路径（`Base.load_path()`） | ① 根项目 `H:\code\Julia_for_MartianSpaceData\Project.toml` ② 全局环境 `~\.julia\environments\v1.10\Project.toml` ③ stdlib `…\Julia-1.10.5\share\julia\stdlib\v1.10` |
| 既有环境目录 | `~\.julia\environments\` 下有 `v1.10`、`v1.9`（本次只用 v1.10） |

**关键**：全局环境在加载路径上，因此**不在根项目 `[deps]` 中的包仍可能按名字解析**（前提是该包是全局环境的**直接依赖**）。

### 2.2 全局环境 `v1.10` 现状

| 项 | 实测值 |
|---|---|
| `Project.toml [deps]` | **42 项**（含 CSV、CommonDataFormat、DSP、DifferentialEquations、FortranFiles、GLMakie、GeometryBasics、JLD2、LsqFit、Optim、QuadGK、Rotations、StaticArrays、Makie、CairoMakie、DataFrames、DataInterpolations、IniFile、JSON、LaTeXStrings、ProgressMeter、TimesDates、ColorTypes、DelaunayTriangulation 等） |
| `Manifest.toml` | `manifest_format = "2.0"`，`julia_version = "1.10.5"`，**443** 条目 |

### 2.3 16 项在全局环境与本项目目标清单中的一致性（重点结论）

| 包 | 94da314 的 pin | 全局环境 v1.10 的 pin | 是否同版本 |
|---|---|---|---|
| CairoMakie | 0.15.15 (`1cda0b7d…`) | 0.15.15 (`1cda0b7d…`) | **一致** |
| ColorTypes | 0.12.3 (`61761f58…`) | 0.12.3 (`61761f58…`) | **一致** |
| DataFrames | 1.8.2 (`5fab31e2…`) | 1.8.2 (`5fab31e2…`) | **一致** |
| DataInterpolations | 10.1.3 (`cc280cd7…`) | 10.1.3 (`cc280cd7…`) | **一致** |
| DelaunayTriangulation | 1.6.7 (`4ac548ad…`) | 1.6.7 (`4ac548ad…`) | **一致** |
| IniFile | 0.5.1 (`f550e6e3…`) | 0.5.1 (`f550e6e3…`) | **一致** |
| JSON | 1.10.0 (`4657a834…`) | 1.10.0 (`4657a834…`) | **一致** |
| LaTeXStrings | 1.4.1 (`f88f3cce…`) | 1.4.1 (`f88f3cce…`) | **一致** |
| Makie | 0.24.15 (`5f6f5d1b…`) | 0.24.15 (`5f6f5d1b…`) | **一致** |
| ProgressMeter | 1.11.0 (`fbb92c6c…`) | 1.11.0 (`fbb92c6c…`) | **一致** |
| StaticArrays | 1.9.23 (`de349d55…`) | 1.9.23 (`de349d55…`) | **一致** |
| TimesDates | 0.3.3 (`92e20561…`) | 0.3.3 (`92e20561…`) | **一致** |
| Dates / LinearAlgebra / Statistics / TOML | 标准库 | 标准库 | 一致（stdlib） |

- 【实测】以 94da314 的 `Project.toml`+`Manifest.toml` 为 active project 做 `Base.identify_package` + `Base.locate_package`（只查 depot、不下载）：**16 项全部解析到 depot/stdlib 中的实际路径**。
- 结论（有依据、非预判）：恢复 94da314 的两份文件**不需要** `Pkg.instantiate`/联网/安装；且与全局环境的 16 项 pin **完全同版本**，不存在"根清单与全局环境对同一 UUID 双版本"的冲突面。
- 记录性差异（无需动作）：94da314 Manifest 的 `julia_version = "1.10.0"`（当前为 `1.10.5`）、`project_hash = "040c540b…"`（与 94da314 的 Project.toml 配对）。**禁止**为了"对齐版本号"运行 `Pkg.resolve`/`Pkg.update`——那会重写 Manifest 并使字节一致性验证失败。

### 2.4 源码实际 `using` 的包在当前环境中的可解析性（现状核实）

| 包（非 16 项） | 用途 | 全局环境 v1.10 | 按名解析（`identify_package`/`locate_package`） |
|---|---|---|---|
| JLD2 0.6.7 | MAVEN_load / Build_data / example | 直接依赖 | 可解析（depot 路径） |
| CommonDataFormat 0.4.4 | MAVEN_load / STATIC / SWEA / SWIA | 直接依赖 | 可解析 |
| FortranFiles 0.6.2 | IGRF / MAVEN_load / Build_data | 直接依赖 | 可解析 |
| Rotations 1.7.1 | function_coordinate / calculate_models / SWEA / SWIA / support_data | 直接依赖 | 可解析 |
| DifferentialEquations 8.1.1 | Single_Particle_Orbit | 直接依赖 | 可解析 |
| CSV 1.1.0 / DSP 0.8.6 / GeometryBasics 0.5.13 / GLMakie 0.13.15 / LsqFit 0.16.1 / Optim 2.3.2 / QuadGK 2.11.3 | support_data / head.jl / Octree / Maxwellian | 直接依赖 | 可解析 |
| SpecialFunctions 2.9.0 | 仅 `common/head.jl` | 全局 Manifest 中为**间接**条目 | **按名不可解析**（`using SpecialFunctions` 需要直接依赖） |
| BenchmarkTools | 仅 `benchmark/bench_*.jl` | **不在全局环境也不在 depot 清单** | 不可解析 |
| Documenter | 仅 `docs/make.jl` | 不在全局环境 | 不可解析 |

- 【实测】这三项（SpecialFunctions/BenchmarkTools/Documenter）在**当前 45 项根清单下同样不可解析** ⇒ 它们是**既有现状**，与本轮收敛无关，不构成收敛失败的预判依据。
- `test/runtests.jl` 的验证路径不会加载 `common/head.jl`（仓内唯一 include 者是 `models/Pickup_ion.jl:3`，且 `Pickup_ion` 不在注册表）——但**是否因此通过仍以现场运行为准**。

---

## 3. t7 实施契约（唯一允许的写操作）

### 3.1 允许的操作

| # | 操作 | 说明 |
|---|---|---|
| 1 | `git show 94da314:Project.toml` / `git show 94da314:Manifest.toml`（只读） | 取得目标内容 |
| 2 | 用文件工具把上述内容写入 **根** `Project.toml`、`Manifest.toml`（LF，无 BOM） | 两份**同时**恢复，保持 `project_hash` 配对 |
| 3 | 写 `.agent/dependency_convergence_result.md`（本任务声明的报告文件） | 结果与证据 |
| 4 | 只读校验命令（§3.2）与 `julia --project=. test/runtests.jl` | 现场实测 |
| 5 | Julia 预编译缓存写入 depot | 不可避免，允许 |

### 3.2 必须执行的校验与证据（每条记录命令、exit code、关键输出）

```text
# (a) 字节一致性（主判据）
git hash-object Project.toml   # 期望 b9b0177feadcbd25a91f1b75b21770c94dbe6192
git hash-object Manifest.toml  # 期望 a37ba5bfefd864dd9b4aa78e9e2381614a9d4233

# (b) Git 级一致性（辅助判据）
git diff --exit-code 94da314 -- Project.toml Manifest.toml    # 期望 exit 0

# (c) 行尾与编码
#    逐字节统计 CRLF 数：两份文件都必须为 0（LF-only）

# (d) 依赖集合
#    解析恢复后的 Project.toml：[deps] 恰好 16 项，且与 §1.2 清单集合相等

# (e) 范围红线（不得出现授权外改动）
git status --porcelain=v1
#    期望：仅 M Project.toml、M Manifest.toml，加上未跟踪的报告文件；无任何 .jl/配置/benchmark 改动

# (f) 现场运行（以输出为准，禁止以静态推断代替）
julia --version                     # 期望 julia version 1.10.5
julia --project=. test/runtests.jl  # 记录 exit code 与完整测试摘要行
```

### 3.3 明确禁止

1. `Pkg.add` / `Pkg.rm` / `Pkg.update` / `Pkg.resolve` / `Pkg.instantiate` / `Pkg.develop` / `Pkg.test()`（后者可能重写环境）；
2. 任何联网安装、修改 `~/.julia/environments/**`、修改 depot 中已装包、创建 `test/Project.toml`；
3. `git checkout` / `git restore` / `git reset` / `git clean` / `git stash` / `git add -A` / `git commit` / `git push`（本任务不提交；提交属 t10 集成）；
4. 修改任何源码、测试、配置、`benchmark`、`docs`、注册表或装载机制文件；
5. 以"让测试通过"为由改源码或改依赖清单（含只改回 45 项中的一部分）。

### 3.4 报告文件格式（`.agent/dependency_convergence_result.md`）

必须包含：① 接续基线哈希；② 目标 blob 哈希与实际写入后 `git hash-object`；③ 命令(a)–(f)的**逐条** exit code 与关键输出；④ 测试摘要的**原文行**（pass/broken/fail/skip 计数）；⑤ 任何未预期的观测（含警告）与是否有未修改的红线文件；⑥ 明确声明"未安装任何包、未修改全局环境、未改源码"。

---

## 4. t8 独立验证契约

- **身份独立**：验证者 ≠ 实现者；不得使用 t7 的缓存结论作为证据，必须**现场重跑**。
- **只写** `.agent/dependency_convergence_verification.md`；**不得**修改 `Project.toml`/`Manifest.toml` 或任何源码，不得安装任何包。

| # | 验证项 | 方法 |
|---|---|---|
| V1 | 字节一致 | 重跑 §3.2(a)(b)，记录 exit code |
| V2 | 依赖集合 = 16 项 | **独立解析**（自行写 TOML 解析/计数，不复用 t7 的输出），与 §1.2 集合逐项比对 |
| V3 | 源码零改动 | `git status --porcelain=v1` 与 `git diff --name-only 46db822 -- .`：改动集合只允许 `Project.toml`、`Manifest.toml`、两份报告（`.agent/**`） |
| V4 | 环境未被污染 | 记录 `julia --version`、`~/.julia/environments/v1.10/Project.toml` 与 `Manifest.toml` 的 `git` 外哈希（或行数/条目数）与本次基线对比，证明未被修改 |
| V5 | 现场测试 | `julia --project=. test/runtests.jl` 独立重跑，记录 exit code 与摘要行原文 |
| V6 | 无隐式安装 | 检查报告与 shell 证据中无 `Pkg.add|instantiate|resolve|update` 记录；若有，判 needs_revision |
| V7 | 缺口如实呈现 | 缺真实数据/DLL/未解析包的用例必须分别标注为 skip/开放/阻塞，**不得**计入通过 |

---

## 5. 判定、失败语义与合同修订路径

| 情形 | 判定 | 动作 |
|---|---|---|
| V1–V6 全部通过，V5 的测试无 fail（broken 与历史一致或更少） | **pass** | t9 独立审查后交 t10 集成 |
| 字节/范围/环境任一项不满足 | **fail（needs_revision）** | 退回 t7 并给出结构化 findings |
| `julia --project=. test/runtests.jl` 因**不可解析的包**失败 | 记录**原始错误**（包名、UUID、错误类型）→ 报 captain 请求**修订契约**（例如把该包列入允许的例外或调整验证命令），**不得** `Pkg.add`、不得改源码、不得改写结论为通过 | 阻塞上报 |
| 测试计数与历史值不同 | 记录现场数字与差异归因（新增/删除/合并用例）；**不以历史值作门槛**，也不要求解释未经证实的差异 | 如实呈现 |
| 需要联网/安装才能继续 | **停止并报告** | 属权限/环境限制，交由 captain/用户决定 |

**合同修订纪律**：一旦发现 §3.2 的验证命令在**未安装包、未改源码**的前提下不可满足，必须在 t7 动手之前报 captain 修订契约；不要求刻意制造失败，也不允许绕过。

---

## 6. 范围红线（本契约的适用边界）

- 依赖恢复**只限根** `Project.toml`、`Manifest.toml`；`benchmark` 环境、`docs` 环境、`~/.julia/environments/**`、注册表 `src/modules.jl`、装载机制代码，一律不动。
- **不回滚 P6 源码**：任何源码/测试文件的内容与 `46db822` 必须逐字节相同（V3 证明）。
- 本契约**不判定**迁移期的 API/兼容策略；`execution_decisions.md`（t2）与后续 t5 的勘误/适用边界负责该口径。此处仅记适用边界一条：本契约**不禁止**后续经授权的正常绑定（如策略 P 的规范实例 `const` 别名）或真实需要的 wrapper——本契约禁止的是**借依赖收敛之名改动源码**。
- `.agent-teams/**` 运行状态文件只读；不读改、不暂存。

---

## 7. 已记录风险与开放项（均以现场结果为准）

| ID | 项 | 现状证据 | 处理 |
|---|---|---|---|
| DR-1 | 收敛后源码仍 `using` 16 项外的包 | 【实测】§2.4：14 个非 16 项包为全局环境**直接依赖**且可解析 | 不预判失败；V5 现场运行决定；不可解析即按 §5 报阻塞 |
| DR-2 | SpecialFunctions 按名不可解析（head.jl 专用） | 【实测】全局 Manifest 中为间接条目，45 项状态下同样不可解析 | 既有现状；若 RUNTESTS 触及则报阻塞，不安装 |
| DR-3 | BenchmarkTools / Documenter 不在环境中 | 【实测】两者在 45 项状态下同样不可解析 | 与 `benchmark/`、`docs/make.jl` 相关，**不在**本验证命令范围内 |
| DR-4 | 恢复旧 Manifest 的 `julia_version` 记录为 1.10.0、`project_hash` 变化 | 【实测】§2.3 | 只记录，不运行 `Pkg.resolve`；不得为对齐而重写 |
| DR-5 | 字节一致的判据 | 【实测】工作区为 LF-only，`.gitattributes` `text=auto` + `autocrlf=true` | 以 `git hash-object`（原始字节）为主判据，`git diff --exit-code` 为辅 |
| DR-6 | git 环境 | 本类会话对 `.git` 写入受限（t1 记录），本任务**不需要**任何 `.git` 写入 | t7/t8 只读 git；若遇 `.git` 写失败即说明越界，停止并报告 |

---

## 8. 预检证据附录（本次只读命令与结果摘要）

| 命令 | 结果摘要 |
|---|---|
| `julia --version` | `julia version 1.10.5` |
| `julia --project=. -e 'println.(Base.load_path())'` | 根 Project → `~\.julia\environments\v1.10\Project.toml` → stdlib v1.10 |
| `git rev-parse 46db822:Project.toml` / `:Manifest.toml` | `f6def9eb…` / `a92fb4d7…`（与工作区 `git hash-object` 相同） |
| `git rev-parse 94da314:Project.toml` / `:Manifest.toml` | `b9b0177f…` / `a37ba5bf…` |
| `git status --porcelain=v1 -- Project.toml Manifest.toml` | 空（两份文件干净） |
| `git cat-file blob 94da314:Project.toml`（行数/UTF-8/无 CR） | 31 行；`[deps]` 16 项；`[compat] julia="1.10"`；`[extras] Test`；`[targets] test=["Test"]` |
| `git cat-file blob 94da314:Manifest.toml`（头部） | `manifest_format = "2.0"`、`julia_version = "1.10.0"`、`project_hash = "040c540bcab7dc28246654e048c8e0d52a9d64b8"`、1782 行 |
| 以 94da314 双文件为 active env 的 `identify_package`/`locate_package`（只查 depot） | 16 项全部解析到 depot/stdlib 实际路径 |
| 全局环境 `Project.toml` / `Manifest.toml`（只读解析） | 42 项直接依赖；Manifest 443 条目、format 2.0、julia 1.10.5；16 项 pin 与 94da314 **逐项同版本同 tree** |
| 全局环境对 14 个非 16 项包的 `locate_package` | 均可解析；SpecialFunctions/BenchmarkTools 不可解析（前者仅间接） |
| 行尾扫描（工作区三文件） | 全部 LF-only（CRLF=0） |
| `git check-attr -a -- Project.toml Manifest.toml`；`git config core.autocrlf` | `text: auto`；`core.autocrlf=true` |

---

## 9. 合规声明

- 本任务只写入 `.agent/dependency_convergence_requirements.md`；未修改、未暂存、未提交 `Project.toml`/`Manifest.toml` 或任何源码/测试/配置/文档。
- 未执行任何 `Pkg` 变更或安装操作；未修改 `~/.julia/environments/**`（仅**只读解析**其 `Project.toml`/`Manifest.toml`）；未联网。
- 为做只读预检，曾在 `%TEMP%\dsh-dep-probe-20261014201348\` 创建一个临时探针目录（内含 94da314 两份文件的副本）并对其运行 `identify_package`/`locate_package`（不下载、不安装）；该目录位于工作区之外的一次性临时路径，**未改动**仓库、depot 或任何已有环境，**预检结束后已删除**（核验绝对路径属于 `%TEMP%` 且匹配 `dsh-dep-probe-*` 后才删除）。
- 未创建子 Agent、未轮询、未启用自动目标；`.agent-teams/**` 未读写。
- 本文件**不实施**任何收敛动作；实施与验证分别由 t7、t8 在其合同范围内执行。
