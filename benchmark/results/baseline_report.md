# baseline_report.md — PHASE 6 S0a/S0b Benchmark 基线报告

> 生成时间：待 golden_snapshot.jl 运行后更新
> 阶段：PHASE 6 - Implementation
> 任务：TASK-001（benchmark 基建）+ TASK-008（真实数据基线）

---

## 1. 环境信息

| 项目 | 值 |
| --- | --- |
| Julia 版本 | 待记录 |
| 平台 | 待记录 |
| 种子 | 12345（固定） |
| 数据根目录 | E:/MAVEN/（如果可用） |

---

## 2. Golden 快照清单

### 2.1 合成类（S0a，TASK-001）

| 文件 | 状态 | 内容 |
| --- | --- | --- |
| baseline_marscommon.json | ✓ 待生成 | 球↔笛卡尔往返测试、能量↔速度 |
| baseline_static.json | ✓ 待生成 | STATIC 矩输入形状、已知问题记录 |
| baseline_swia_swea.json | ✓ 待生成 | SWIA coarse/fine 输入形状、C4/C5 bug 记录 |
| baseline_coldplasma.json | ✓ 待生成 | Cold Plasma 输入范围、状态隐式问题记录 |

### 2.2 真实数据/DLL 类（S0b，TASK-008）

| 文件 | 状态 | 内容 |
| --- | --- | --- |
| baseline_igrf.json | ⏳ 待 TASK-008 | IGRF 磁场网格、磁力线追踪结果 |
| baseline_loader.json | ⏳ 待 TASK-008 | load_mag_l2/load_kp/load_cdf 单文件输出摘要 |

---

## 3. 已知问题快照记录（改动前状态）

### 3.1 AR-12: STA_count2eflux 默认参数

```
STA_count2eflux(dat) → UndefVarError: m_int not defined
```

**记录位置**：baseline_static.json
**修复任务**：TASK-003

### 3.2 C4: SWEA n1d 死变量

```
tiny = 1.0-31  # = -30.0 (笔误，疑为 1e-31)
```

**记录位置**：baseline_swia_swea.json
**修复任务**：TASK-018

### 3.3 C5: SWIA v_3d 索引维度

```
v_3d(coarse_data) → BoundsError
# theta/domega 为 3D (ntime,4,48)，但代码使用 4D 索引
```

**记录位置**：baseline_swia_swea.json
**修复任务**：TASK-019

---

## 4. Benchmark 基准结果

### 4.1 可运行项（TASK-001 后）

以下基准脚本在合成数据上运行（无需真实数据）：

| # | 脚本 | 状态 | 备注 |
| --- | --- | --- | --- |
| 2 | bench_02_static.jl | ⏳ 待创建 | STATIC 矩计算 |
| 3 | bench_03_sta_v4d.jl | ⏳ 待创建 | sta_v_4d vs sta_v_4d_new |
| 4 | bench_04_c6.jl | ⏳ 待创建 | static_c6_mass_mean/energy_mean |
| 5 | bench_05_findfile.jl | ⏳ 待创建 | 文件定位索引 |
| 6 | bench_06_plot.jl | ⏳ 待创建 | plot_module 合成 |
| 7 | bench_07_trace.jl | ⏳ 待创建 | 磁力线追踪对比 |

### 4.2 Opt-in 项（需真实数据/DLL）

| # | 脚本 | 状态 | 数据要求 |
| --- | --- | --- | --- |
| 1 | bench_01_loader.jl | ⏳ 待 TASK-008 | E:/MAVEN/ 真实文件 |
| 8 | bench_08_fullday.jl | ⏳ 待 TASK-008 | E:/MAVEN/ 一日全产品 |

---

## 5. 验收检查

### 5.1 TASK-001 验收标准

- [x] benchmark/ 目录结构创建
- [x] Project.toml 定义独立环境
- [x] common.jl 合成数据生成器
- [x] golden_snapshot.jl 可运行
- [ ] 6 个 baseline_*.json 生成
- [ ] 快照可重复（两次运行一致）
- [ ] baseline_report.md 记录基线

### 5.2 TASK-008 验收标准（待执行）

- [ ] 真实数据可用时更新 baseline_igrf.json
- [ ] 真实数据可用时更新 baseline_loader.json
- [ ] bench_01/08 基准入档

---

## 6. 签名

- 执行人：GLM-5（PHASE 6 Implementation Agent）
- 日期：待更新
- 审核人：待 PHASE 9 独立评审