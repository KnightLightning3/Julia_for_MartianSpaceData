# AI_HANDOFF.md —— 当前唯一接续入口（DeepSeek Flash 整理，2026-10-15 14:15 +08:00）

> **MAVEN 专用坐标归位与 hypot 审查（2026-10-15，当前最新）**
> - 用户确认原 instrument 两函数未对外使用，要求直接移入 FunctionCoordinate 并命名 `MAVEN_sphere2xyz` / `MAVEN_xyz2sphere`，不在面向用户的迁移指南记录改名。本轮已删除 MarsCommon 旧定义/导出，无 alias；README、坐标定义专题和生成API同步现行名称。
> - AST 对旧源 d828a6e 的索引确认两定义及四处生产引用：STATIC.static_rotation 两处、static_slip_2_V 一处、Pickup 一处。现行 STATIC 显式 include FunctionCoordinate，并补 `using Rotations: QuatRotation`；分析脚本原已 include FC，本轮严格只改一个调用。FC 清除未使用的 MarsCommon/constants include，避免反向依赖与嵌套副本。
> - 实测 MAVEN 与 MINPA 不等价：同球坐标 `(1,0°,0°)` 分别得到 +X 与 +Y，反算同一点与退化轴行为也不同。因此分别保留 MAVEN_* / MINPA_*，不创建 ins_* 合并接口。
> - 按用户新授权逐函数改 hypot：MAVEN_xyz2sphere 的 sqrt 平方和、pa_xyz2sphere 的 norm3、MINPA_xyz2sphere 的 norm3/投影norm2，分别换成 hypot3/hypot2；pc2sphere 原已用 hypot。正算三角公式不改；slice2d_cal_rot 的 norm/normalize 参与 1e-8 共线判断，保持原式。允许末位误差与极大/极小输入稳定性、混合NaN/Inf优先级的明确变化，不能再引用旧的逐位一致表述。
> - MAVEN 初始公式 oracle 直接从 `a09511aa7b88c874cefe8ca966c98aa267db9365` 提取；普通有限点对照、正逆反例、类型/广播/维度与大/小半径测试通过。STATIC 调用回归包含 Float32 角网格，最大角差 1.56e-6°；Float64仍严格1e-12。
> - 验证：MAVEN新接口45、生产接线38、专门AST检查103、Pickup22、统一三维接口177、旧坐标迁移117、STATIC质量64，共566项定向检查通过。文档工具8/8、API生成与过期检查通过；Documenter构建无警告、Wiki10页预览自检通过。真实数据挂起、不验证DLL、未提交/未发布。
> - 专门AST检查使用现有 ASTMigrate 扫描生产定义/引用，并核对两新函数各静态方法+普通向量适配的ASThash及旧源hash。通用move校验器会把合法重载判作重复，故本次额外归属证据放 `index.coordinate_api.maven`，不伪增39个旧AST单元；通用校验仍28 ok/0 fail/11 unknown。Pickup原始物理移动sha保留，新增 current_sha/current_bytes 单列本轮调用替换后字节状态。

> **坐标接口调整（2026-10-15，当前最新）**
> - 用户要求通用三维静态点接口、移除四元数包装及 IGRF 坐标裸名。FunctionCoordinate 的点转换均为 3→3；`rotation_matrix`（两个角）和 `slice2d_cal_rot`（两个三维向量）是 3×3 矩阵构造器，分别保留 Matrix/RotMatrix 返回，不混作点转换。
> - 新增 `FunctionCoordinate.pc2sphere(p)`、`sphere2pc(p)`：SVector{3} 主接口、长度3 AbstractVector{<:Real} 适配、SVector{3} 返回，弧度制余纬，计算顺序沿用初始 IGRF 标量公式。原 PA/MINPA 四函数增加同样普通向量适配，不合并角定义或改变零/NaN 边界。MINPA 反算改 `norm(@view p[2:3])` 去临时数组，范数算法保留；Float32/Float64 各 100009 个仓外合成探针未发现逐值差异，静态索引替换会改变部分 Float32 结果，未采用。
> - `Quaternion_Rot` / `Quaternion_Rot_reverse` 已删除，无 alias，生产调用点未发现依赖；改直接 `q * v` / `inv(q) * v`。IGRF 两个标量函数取消 export 和 allow，仅白名单 `IGRF_pc`，内部函数 AST 与 `a09511aa7b88c874cefe8ca966c98aa267db9365` 一致，未调用 DLL。
> - 坐标清单记录 1 move + 2 remove；全体仍为39个AST单元（37 move + 2 remove），纯删除不要求 target_hash；校验仍28 ok / 0 fail / 0 pending / 11 unknown。IGRF 模块 AST/源码字节锁及清单 SHA 已同步。
> - 实际回归：新三维接口131/131、IGRF namespace 8/8、旧坐标迁移116/116；API生成器23/23（新增@inline/@noinline索引保护）；文档工具8/8，9段坐标文档合成示例成功。带输出Ref防消除、预热后，六个静态点函数 Float32/Float64 探针均为0字节堆分配；这不是所有输入类型/调用场景的性能保证。
> - 中英文README新增坐标专题，详细Wiki源 `docs/src/coordinates.md`，解释主动/被动、q/R列向量、行存N×3转换及批量循环；文档重新生成，Documenter最终构建无警告，Wiki10页预览自检通过。未发布/未提交。真实数据挂起，DLL验证不需要，未执行相关运行验证。

> **最新范围与文档同步（2026-10-15，优先于下文旧待办）**
> - 用户已指定逻辑溯源初始提交 `a09511aa7b88c874cefe8ca966c98aa267db9365`；真实数据校验暂时挂起，**DLL 验证不需要**。已有中间 oracle `5f225db` 夹具不因此自动变成相对初始提交的完整证明；本轮未改科学实现或重写科学测试断言。
> - 当前任务为 README/Wiki 配套架构调整。已重写中英文 README，新增 `docs/src/architecture.md`、`migration.md`，同步首页/执行流程/读取说明/数据格式及 Wiki 导航；旧聚合入口与迁移路径不再作为现行示例。读取指南按实际单日 DateTime、error_report、未知产品 KeyError 与惰性索引行为说明；STATIC 示例显式转换 df，按函数区分输入质量基准和输出同名键。
> - 新增 `tools/generate_api.jl`：标准库静态解析 30 个生产 Julia 文件、索引顶层函数/短定义及模块作用域导出，排除局部函数，绝对源码链接。默认生成 `docs/src/api.md`，`--check` 检查过期，不加载科学依赖/数据/DLL。
> - 新增 `docs/pages.toml` 为 Documenter/Wiki 共同页面清单；`docs/make.jl` 与 `tools/push_wiki.py` 消费同一清单。Wiki dry-run 保留输出目录里的其他文件。修复 SWIA 数学定界：24 条行内公式及两条显示公式的内容不变，HTML/Wiki 分别采用兼容定界。
> - 实际验证：API 生成器 fixture 19/19、Python 文档工具 8/8；API `--check` 通过；69 个相对 Markdown 链接解析通过；产品生成幂等、53 个产品 ID 对应 JSON；Wiki 本地生成 9 页并自检通过。Documenter 1.19.0 实际构建成功（最终日志无 Warning/Error），HTML 为 `docs/build/index.html`，8 个正文页。
> - 构建依赖安装于 `/tmp/marsdata-docs-env` 与 `/tmp/marsdata-docs-depot`，未改根项目或 docs 的 Project/Manifest。文档源与生成器均在工作树，未提交/未 push，**未发布远端 Wiki**。维护命令与页面映射见 `docs/README.md`。历史报告和参考资料不改。

> **本轮实施进度（2026-10-15，GPT 主代理协调，3 个 GPT-6 Luna 子代理实施）**
> - 完成 HD-14 剩余物理迁移：`models/{Graham,Octree}.jl` → `models/extras/`；`models/Pickup_ion.jl` → `analysis/Pickup_ion.jl`。三文件对 `d828a6e` 的字节 SHA-256 一致；Pickup 同为根目录下一级，两个 `../common` 引导 include 不变且已从仓库外 CWD 验证。旧源文件已移除，无兼容入口。**Pickup 尚未函数化**，既有 Windows 硬编码回退和顶层数据副作用未改。
> - 新增 `models/CATALOG.toml` 登记两项 Extra，保留显式 include、不进 registry；Octree GUI 运行未测。`validation/migrations/index.toml` 用 `index.file_moves` 单列三项文件 SHA，**不混入 39 个 AST 单元统计**；更新 IGRF 消费者/坐标保留项的当前 Pickup 路径及清单 SHA。`callsite_plan.toml` 为历史施工计划，里面的旧路径不作为现行入口。
> - STATIC/SWIA/SWEA 各删除一条未使用的 `using CommonDataFormat`，未改公式。CDF 读取器仍保留真实依赖。补 `DataKeys.MASS = :mass`（单一公开常量），明确其与 MASS_ARR、m_int 的区别。
> - README 中英文版及 api.md 增加迁移标注；旧文档示例按 HD-13 留给使用者适配，历史报告未改。
> - 新回归：`test/pickup_move_test.jl`、`test/extras_move_test.jl`、`test/data_keys_contract_test.jl`。最终本机分别通过 19/19、35/35（含 Octree 静态检查 6 项，非运行验证）、8/8，覆盖移动/纯函数与索引、Extras 字节与清单、公开键唯一性。本机现有回归已通过：STATIC 64、common 280、environment 191、coordinate 113、fortran_parse 28；AST 校验 exit 0（28 ok / 0 fail / 0 pending / 11 unknown），unknown 不计通过。
> - 另核实 IGRF 旧测试锁定的 `Magnetic_Model/gh_gao.txt` 大小/哈希已与当前基线不符：工作树和 `d828a6e` 均为 418914 字节、SHA-256 `8e2ec412d4265271793f68babe6131fcc9e4477f312686f5a26d38279c1d2095`；该文件本轮未改，不放宽旧断言。
> - 主套件实际为 **123 pass / 4 error / 1 broken**（exit 1，缺 FortranFiles/CommonDataFormat）；SWEA 迁移套件为 **116 pass / 1 error**（CDF loader 缺 CommonDataFormat）。没有跳过失败、安装依赖或改写项目环境。通过 `--compiled-modules=existing --startup-file=no` 使用既有缓存，避免用户 depot 新缓存写入。完整科学/真实数据/DLL 回归仍未完成。
> - 本轮未提交、未 push；接手前已有 Project.toml/Manifest.toml/doc/ 改动保持。后续仍有 allow 白名单、DataKeys 其他键评估、Pickup 函数化、DLL 平台/缺符号及真实数据验证等工作，不得称全项目重构完成。

> **2026-10-15 接手现场更正（优先于下文历史状态）**
> - 当前 HEAD 为 `d828a6e1ded1566f094b1e8d4fb923a5fcca5748`，分支 `main`，与本地 `origin/main` 引用差异为 0 / 0（未联网 fetch）。
> - `f6e63bb`（代码）、`5b3e87d`（文档备份）、`d828a6e`（文档清理）均已存在于历史；§1、§7 和末尾的“当前成果未提交”等文字为旧记录，不适用于当前工作树。旧行为 oracle 仍取 `5f225db`，不可改用当前 HEAD。
> - 接手前已有未提交改动：`Project.toml`、`Manifest.toml` 和未跟踪 `doc/`。保留其内容，不归为本轮成果。
> - 当前用户已明确允许使用 `gpt-6-luna` 子代理，覆盖 §2 的旧“禁止子 agent / Official Flash”模型约束；其余科研契约和不 push 约束继续遵守。
> - 本轮先核对接手基线与迁移边界；§5 的未完成项仍未宣称完成。后文测试数字是历史记录，除明确记录的新运行外不代表本机验证。
> - 本机 Julia 1.12.5 重新运行：`test/ast_migration_test.jl` 为 204/204；`validation/check_migrations.jl` exit 0，28 ok / 0 fail / 0 pending / 11 unknown。`test/runtests.jl` exit 1，装载 SWEA 时缺 `CommonDataFormat`，另出现用户 depot 预编译缓存写入 EPERM；未进入完整科学回归，不算通过。未安装依赖或改动项目环境。

> 本文档是**当前唯一权威接续入口**。冗余的规划/决策/分析历史稿已于 2026-10-15 清理移除（可经 git 历史找回，见 §9）。
> **本整理只做记录整合，不代表对已审成果的额外审查**；未重跑整套科学测试（见 §4 的“最后运行时间”标注）。
> 整理与提交由 captain 依用户三步要求完成：①代码提交 → ②文档备份提交 → ③删冗余文档后整理提交（见 §1）。

---

## 1. 当前工作树基线（现场只读核对，2026-10-15 14:15 +08:00）

| 项 | 现场值 |
|---|---|
| HEAD | `5f225dba4c30d102682bb349460a3e05eee5d87f`（短号 `5f225db`，提交信息「暂存」，2026-10-14 22:48:11 +0800） |
| branch | `main` |
| remote | `origin` = `git@git.ustc.edu.cn:KnightLightning/Julia_for_MartianSpaceData.git` |
| 与远端关系 | `main...origin/main [ahead 2]`（`git rev-list --left-right --count HEAD...@{u}` = **2 / 0**） |
| 领先的 2 个提交（**均早于本批、均未 push**） | `5f225db 暂存`、`46db822 快照：纳入 HD-01…15 裁决文档与执行快照` |
| 提交状态（2026-10-15 清理后） | 已分三步提交（均**未 push**）：`f6e63bb` 代码更改（53 文件）→ `5b3e87d` 文档备份 → 本清理提交（删 32 份冗余文档 + 本说明更新） |
| 剩余未提交 | 仅团队运行态 `.agent-teams/**`（永不入库）；无源码/文档待提交 |

要点：`5f225db` 是**已提交的旧参考基线**（历史 oracle 来源，见 §7），而本批成果**完全在工作区未提交**（见 §4/§8）。

---

## 2. 用户最新裁决与协作/模型约束

- **阶段性停止施工**：用户明确要求暂停施工，先做记录整合，由后续 AI 接续。
- **模型/成员约束**：使用**本实例 Official Flash** 作为主力实施者；**禁止子 agent**；**无 Claude / Pro / Gemini**；团队规模**最多 8 人（含 captain）**；**报告驱动**（以任务书/报告为准）。
- **职责边界**：**captain 不写代码**（协调/裁决/派单）；**USTC 侧仅承担具体短任务**（如 IP 整理），不做长链实施。
- **本批已生效的工程裁决（现场可见的权威人工记录）**：用户 HD-01…HD-15 见 <.agent/审计结果.md>（含 HD-10 STATIC `:mass` 语义与常量等效、HD-08 移除 `sta_v_4d_new`、HD-06/HD-09/HD-15 取消兼容周期、HD-13 不改文档而是标注、HD-14 移动前先全局查依赖）。
- **Git 约束**：不 push；受限 `.git` 不重试不绕过；提交交用户**外部一次执行**（清单见 §8）。
- **文档约束**：除本文档外不新增 Markdown；历史 md 原地保留、不删除不移动；不读改 `.agent-teams/` 状态文件。

---

## 3. 科研契约（必须保持，不得“顺手改科学”）

1. **STATIC 质量基准精度提升（已实施/已审）**：9 处质量基准由数据包 `dat[:mass]`（`Float32`）改为常量 `constants.mp_eV_per_km_s2 = 0.010439684891821985`（`Float64`）。
   - 实测依据：同一确定性夹具 101 探针，`Float32` vs 同值 `Float64` 基准最大相对差 ≈ **7.07e-8**；同值路径与旧 `Float64` 基线**逐位一致**；键值 ×1.0001 的敏感度为 2.0e-4；缺 `:mass` 旧路径 `KeyError(:mass)`。
   - `mass_arr` / `m_int` **角色不变**：`mass_arr` 仍来自数据包质量轴、供质量掩膜与配平；`m_int` 仍是质荷比参数；本次只替换“质子静止质量常量”的取法，不改运算次序与公式。
2. **非等价函数各自保留**（不得合并、不得互相替代）：
   - `slice2d_cal_rot`（`FunctionCoordinate`，返回 `RotMatrix3`，共线抛 `ErrorException`）**vs** `slice2d_cal_rot_matrix`（`TW_MINPA`，返回 `SMatrix`，共线行为按输入类型不同）。
   - `Bpc2sphere`（`hypot` 稳健版）**vs** `Bpc2sphere_naive`（`sqrt` 版，`|坐标| ≳ 1.34e154` 上溢）。
   - `bowshock_plot_nan64` / `magnetopause_plot_nan64`（`MAVEN_plot` 内 NaN64/Float64 变体）**vs** 权威 `bowshock` / `magnetopause`（`MarsEnvironment`，NaN32/Float32）。
3. **NaN / 异常 / 副作用原则**：不改变任何几何或统计公式；无效输入保持原有 NaN 位置或异常类型（例：B 系列零坐标 `(NaN,NaN,2.0)`；FC 版共线抛 `ErrorException`；TW 版 `Vector` 共线抛 `ArgumentError`、`SVector` 共线返回 `SMatrix`）；就地修改（如 `mean_SWEA_pad_pa` 原地写回同一字典且保留原始键）保持不变。
4. **既有开放项不许伪造通过**：IGRF `:adaptive` 因 `IGRF_DLL.dll` 缺 `MAIN_mp_ADAPTIVE_STEP_TRACE` 当前抛错——测试以“抛错”这一可证伪断言固定，符号补齐后该断言会失败并提示更新。

---

## 4. 阶段性真实完成（按模块短表）

| 模块/文件（现行路径） | 完成内容 | 证据/回归 |
|---|---|---|
| `MAVEN_data/MAVEN_STATIC.jl` | 9 处质量基准 → `constants.mp_eV_per_km_s2`；删除 `sta_v_4d_new` | <.agent/06_IMPLEMENTATION_LOG.md> STATIC 节；<test/static_mass_regression.jl>（64/64） |
| <common/MarsCommon.jl> + <common/marscommon/>（statistics/geometry/numerics/cyclotron） | 通用能力子文件化（16 函数）；新增公开 `Bsphere2pc`/`Bpc2sphere`/`Bpc2sphere_naive` | <validation/migrations/common.toml>；<test/common_migration_test.jl>（280/280） |
| <models/Mars_Environment.jl> | 环境权威（模块名 `MarsEnvironment`，文件路径保留 `Mars_Environment.jl`）；`solve_func` 复用 MarsCommon | <validation/migrations/environment.toml>；<test/environment_migration_test.jl>（191/191） |
| <common/function_coordinate.jl> | 包化 `module FunctionCoordinate`；迁入 3 个旋转函数 | <validation/migrations/coordinate.toml>；<test/coordinate_migration_test.jl>（113/113） |
| <MAVEN_data/MAVEN_SWEA.jl> | shape 闭包 + `carclu_SWEA_pad` 迁入 | <validation/migrations/swea.toml>；<test/swea_migration_test.jl>（145/145） |
| <MAVEN_data/MAVEN_load.jl> | 旧副本/旧定义清理（`cyclone_*`、`static_c6_*`、`Bpc2sphere`），loader 链保留 | <test/callsite_migration_test.jl>（85/85） |
| IGRF（现 <models/IGRF_calculate.jl> + <models/gh_gao> + <models/IGRF_DLL.dll>） | 三文件同批移入 `models/`；注册 deps 补 `:MarsCommon`；两档复用规范实例 | <validation/migrations/igrf.toml>；<test/igrf_move_test.jl>（64/64） |
| 坐标变体去重 | `Bpc2sphere_naive`、`slice2d_cal_rot_matrix` 显式命名保留 | <validation/migrations/coordinate_variants.toml>；<test/coordinate_variants_test.jl>（81/81） |
| `call_fortran_dll.jl` | 字符串插值 `$p3；` → `$(p3)；`（1 行，整文件由不可解析转为可装载） | <test/fortran_parse_test.jl>（28/28） |
| 旧入口真删 | `common/head.jl`、`calculate/calculate_models.jl` 物理删除（清单补 `source_revision` 后由工具取证） | <validation/migrations/index.toml>；<validation/check_migrations.jl> |

**机器记录（现行权威）**：<validation/migrations/index.toml>
- 清单 **7** 份（`callsite_plan`、`common`、`coordinate`、`coordinate_variants`、`environment`、`igrf`、`swea`）；`units_total = 39`，`finalized_rows = 39`，`pending_rows = 0`，`retained_rows = **3**`，非法 `target_hash` = 0。
- 校验器 verdict：**ok 28 / fail 0 / pending 0 / unknown 11**；`unknown` 为**动态/无法静态解析点**，**不计通过**（**28 ≠ 39 科学通过**）；`overall_refactor_complete = false`。
- 3 条保留例外（`status=retained`，**无** `target_hash`）：`swea/mean_SWEA_pad_pa`、`coordinate_variants/slice2d_cal_rot`（FC 版 @<common/function_coordinate.jl>）、`coordinate_variants/slice2d_cal_rot`（MAVEN_plot 嵌套版 @<MAVEN_data/MAVEN_plot.jl>）。

**测试数值与运行状态（本次整理**未重跑**，沿用批内最后一次运行结果）**：

| 命令 | 结果 | 最后运行 |
|---|---|---|
| `test/runtests.jl` | 144 Pass / 1 Broken / 145 + STATIC 64 Pass | 2026-10-15 ≈13:2x（本批内） |
| `test/coordinate_variants_test.jl` | 81/81 | 同上 |
| `test/igrf_move_test.jl` | 64/64 | 同上 |
| `test/common_migration_test.jl` / `coordinate` / `environment` / `swea` / `callsite` | 280 / 113 / 191 / 145 / 85 | 同上 |
| `test/ast_migration_test.jl` / `fortran_parse_test.jl` | 204 / 28 | 同上 |
| `validation/check_migrations.jl` | exit 0（ok 28 / fail 0 / pending 0 / unknown 11） | 同上 |
| `git diff --check` | exit 0 | 同上 |

> 接续者若需在当前工作树上重新验证，请自行运行上表命令；**不要**把历史任务中的失败当作当前失败（见 §10）。

---

## 5. 尚未完成（**不得**称“全重构完工”）

- **Extras 与 Pickup 的物理移动**：尚未执行（本轮冻结）。
- **registry 的 `allow` 白名单与 DataKeys 相关项**：未完成。
- **最终文档同步**：<README.md>、<CHANGELOG.md>、<docs/> 仍提旧路径（例：`Magnetic_Model/IGRF_calculate.jl`），**未同步**（用户裁决 HD-13：仅在文档标注、由使用者自行适配）。
- **DLL 符号 / 真实数据验证**：IGRF `:adaptive` 缺 `MAIN_mp_ADAPTIVE_STEP_TRACE`；真实 CDF/科研数据端到端验证未做（本轮仅合成夹具与既有回归）。
- 其它见 <validation/migrations/index.toml> 的 `[index.overall].remaining_note`。

---

## 6. API 破坏 / 旧入口删除 / 新名称 / IGRF 资产新位置

- **旧入口删除（无兼容层）**：<common/head.jl>、<calculate/calculate_models.jl> 已**物理删除**；`:calculate_models` 注册条目已移除。
- **IGRF export 清理**：原 `export pc2sphere, sphere2pc, Bsphere2pc, Bpc2sphere` → `export pc2sphere, sphere2pc`（B 系列权威移至 `MarsCommon`，IGRF 仅 `using .MarsCommon: …` 绑定）。
- **新公开 API**：`MarsCommon` 新增 `Bsphere2pc`、`Bpc2sphere`、`Bpc2sphere_naive` 导出。
- **改名（旧名不再存在，无 alias）**：TW 本地 `slice2d_cal_rot` → **`slice2d_cal_rot_matrix`**；loader 的 sqrt `Bpc2sphere` → **`Bpc2sphere_naive`**；`models/Single_Particle_Orbit.jl` 本地 `TimeFormat` → **`TimeFormatMMSS`**（公共 `MarsData.TimeFormat` = `HH:MM:SS.mmm` 不变）；`head.jl` 迁入的 `color_mapping` → **`color_mapping_lut`**；`carclu_SWEA_pad` 由 `MAVEN_load` 迁至 **`MAVEN_SWEA`**（两示例已改 `MAVEN_SWEA.carclu_SWEA_pad`）。
- **模块名与路径**：`models/Mars_Environment.jl` 内模块名改为 **`MarsEnvironment`**（**文件路径不变**）；注册表新增 `:MarsEnvironment`（`kind=:preloaded`），`:IGRF_calculate` deps 补 `:MarsCommon`。
- **IGRF 资产新位置**：<models/IGRF_calculate.jl>、<models/gh_gao>、<models/IGRF_DLL.dll>（字节 `sha256` 与移动前一致）；资源仍以 `dirname(@__FILE__)` 同目录定位；**文本备份 <.agent…> 之外的 <Magnetic_Model/gh_gao.txt> 原位保留**（未移动、未改写）。

---

## 7. 已提交旧参考 vs 当前未提交成果（**必须区分**）

- **已提交参考**：HEAD `5f225db`（以及 `46db822`）——团队全部「旧 oracle / 旧行为」对照均来自 `git show 5f225db:<路径>`（例如旧的 `Magnetic_Model/IGRF_calculate.jl`、旧 `MAVEN_data/MAVEN_load.jl`、旧 `TW_data/TW_MINPA.jl`）。
- **当前未提交成果**：§4 的模块表、§8 的 59 条路径全部只是**工作区改动**；任何“已迁移/已删除”结论都**尚未进入历史**。
- 因此：`git show HEAD:<path>` 看到的是**旧实现**；比对时请用工作区文件，或用 `git show 5f225db:<path>` 取旧行为。

---

## 8. 提交清单（已执行，仅留档；供排查用）

> 本清单的代码与文档备份**已由 captain 于 2026-10-15 分步提交**（§1）；下方逐文件数组为当时提交的路径留档，不再需要外部执行。若后续 AI 需要核对提交内容，用 `git show f6e63bb` 与 `git show 5b3e87d`。

```powershell
cd H:\code\Julia_for_MartianSpaceData
$paths = @(
  '.agent/06_IMPLEMENTATION_LOG.md'
  '.agent/AI_HANDOFF.md'
  '.agent/new_plan.md'
  'benchmark/bench_03_sta_v4d.jl'
  'calculate/calculate_models.jl'
  'call_fortran_dll.jl'
  'common/function_coordinate.jl'
  'common/head.jl'
  'common/MarsCommon.jl'
  'common/marscommon/cyclotron.jl'
  'common/marscommon/geometry.jl'
  'common/marscommon/numerics.jl'
  'common/marscommon/statistics.jl'
  'docs/src/api.md'
  'example/MAVEN_plot_sample/MAVEN_overview_cases.jl'
  'example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl'
  'Magnetic_Model/gh_gao'
  'Magnetic_Model/IGRF_calculate.jl'
  'Magnetic_Model/IGRF_DLL.dll'
  'MAVEN_data/MAVEN_load.jl'
  'MAVEN_data/MAVEN_plot.jl'
  'MAVEN_data/MAVEN_STATIC.jl'
  'MAVEN_data/MAVEN_SWEA.jl'
  'models/gh_gao'
  'models/IGRF_calculate.jl'
  'models/IGRF_DLL.dll'
  'models/Mars_Environment.jl'
  'models/Pickup_ion.jl'
  'models/Single_Particle_Orbit.jl'
  'src/MarsData.jl'
  'src/modules.jl'
  'test/ast_migration_test.jl'
  'test/callsite_migration_test.jl'
  'test/common_migration_test.jl'
  'test/coordinate_migration_test.jl'
  'test/coordinate_variants_test.jl'
  'test/environment_migration_test.jl'
  'test/fortran_parse_test.jl'
  'test/igrf_move_test.jl'
  'test/runtests.jl'
  'test/static_mass_regression.jl'
  'test/swea_migration_test.jl'
  'TW_data/TW_MINPA.jl'
  'validation/ast/ASTMigrate.jl'
  'validation/ast/Checks.jl'
  'validation/ast/ExprWalk.jl'
  'validation/ast/Index.jl'
  'validation/ast/Records.jl'
  'validation/ast/Report.jl'
  'validation/ast/Scanner.jl'
  'validation/check_migrations.jl'
  'validation/migrations/callsite_plan.toml'
  'validation/migrations/common.toml'
  'validation/migrations/coordinate_variants.toml'
  'validation/migrations/coordinate.toml'
  'validation/migrations/environment.toml'
  'validation/migrations/igrf.toml'
  'validation/migrations/index.toml'
  'validation/migrations/swea.toml'
)
git add -A -- $paths

# 安全核对：暂存区不得含团队运行态 / 仅 CR 差异文件（两条命令期望均无输出）
git diff --cached --name-only
git diff --cached --name-only | Select-String '^\.agent-teams/|审计结果'

git commit -m "迁移批次：STATIC 质量基准常量 + common/MarsEnvironment/FunctionCoordinate/SWEA/IGRF 权威收束 + AST 校验器 + AI 交接"
```

**排除项（必须不进入提交）**：
- `.agent-teams/**`（团队运行态：`static-small-change/`、`archive/marsdata-flash-execution/`、已跟踪但仅状态变化的 `retired-members.json`）。
- `<.agent/审计结果.md>`：相对 HEAD **仅有 CR 行尾差异**（`git diff --ignore-cr-at-eol` 无输出），虽为权威人工裁决记录，但其**内容未变**，按既定口径不纳入本批提交。
- 临时文件/探针目录（当前 `_tmpprobe*` 残留数 = 0）；仓外 `%TEMP%` 的生成脚本与校验脚本（如索引生成脚本）**不在仓库内**，不参与提交。
- 注意：**不要**使用 `test/{a,b}.jl` 这类 brace 展开，也**不要**使用无范围 `git add -A`。

---

## 9. 文档效力索引（谁现行、谁 superseded）

**现行（权威）**
1. **本文档** <.agent/AI_HANDOFF.md> —— 当前唯一接续入口（整合记录，非额外审查）。
2. **权威人工裁决** <.agent/审计结果.md> —— 用户 HD-01…HD-15（含 HD-08/HD-10/HD-13/HD-14 等直接约束）。
3. **机器记录** <validation/migrations/index.toml> + 7 份清单 <validation/migrations/>（`common`/`environment`/`coordinate`/`coordinate_variants`/`swea`/`igrf` + `callsite_plan`）。
4. **实施证据** <validation/check_migrations.jl>、<validation/ast/>（AST 校验器与自检）、<test/> 下各回归、<.agent/06_IMPLEMENTATION_LOG.md>（实施日志；STATIC 节 + 迁移批次冻结节）。

**历史 / 已清理（冗余决策备案与规划/分析稿，可经 git 历史找回）**
- 已从工作区移除 **32 份冗余文档**：`00…09` 规划链、`target_architecture_*` / `architecture_*` / `science_*` 系列、`execution_*` / `dependency_convergence_*`、`physical_path_audit`、`static_mass_removal_audit`、`planning_archive_handoff`、`ustc_supplement`、`current_state_recovery`、`new_plan`。
- 它们的内容已由本文档与机器记录收敛；**需要原始文本时**：`git show 5b3e87d:.agent/<name>.md`，或更早归档提交 `3f68187` / `46db822` / `5f225db`。
- **不要**据此假设旧数字/旧哈希仍有效；以本文件与 <validation/migrations/index.toml> 为准。

---

## 10. 后续 AI 的第一步（建议顺序）

1. **先只读核对**：`git rev-parse HEAD`、`git status -sb`、`git log origin/main..HEAD --oneline`，确认 §1 的基线是否仍成立（尤其“本批仍未提交”）。
2. **读本文档 + 机器记录**：本文件 §3/§4/§5、<.agent/审计结果.md>、<validation/migrations/index.toml>、<.agent/06_IMPLEMENTATION_LOG.md>。
3. **核对未提交差异**：`git status --porcelain` 与 `git diff --stat`（需要时按文件 `git diff -- <path>`）；**不要** `git reset` / `git clean` / 自动回滚或 `git checkout --` 覆盖工作区。
4. **区分历史与当前**：不要因历史任务报告中的“失败/阻塞/被驳回”就假定当前失败；以现场文件与当前回归为准（必要时自行运行 §4 命令）。
5. **无用户授权不部署、不 push**；需要提交时，用 §8 的显式清单**一次性**提交（受限 `.git` 不重试不绕过）。
6. 若继续施工：以 §5 的未完成清单为准（Extras/Pickup 物理移动 → allow/DataKeys → 文档同步 → DLL 符号与真实数据验证），并沿用 §3 的科学契约（不改公式/不合并非等价函数/不伪造通过）。

---

*整理者说明：本文档由本实例 Official Flash 依据现场只读核对与既有任务记录整理；只新增本文件并精确编辑 <.agent/new_plan.md> 头部指引，未改源码/测试/工具，未提交未 push；历史 Markdown 均原地保留。*
