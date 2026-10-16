# 火星空间数据 Wiki

本 Wiki 与仓库 Documenter 站点共用 `docs/src/` 正文，介绍当前架构、迁移方式与数据流程。代码与文档源位于[项目仓库](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData)。

请修改仓库文档源并重新生成；直接在 Wiki 网页编辑的正文会在下次同步时被覆盖。

## 阅读顺序

1. [项目架构](项目架构)：包初始化、模块装载、模型、分析脚本与 Extras 的分工。
2. [迁移指南](迁移指南)：旧路径、删除与改名、计算约定及初始逻辑基准。
3. [坐标转换](坐标转换)：球坐标定义、点转换接口、旋转方向和行存批处理。
4. [项目执行流程](项目执行流程)：环境、配置、下载、索引、构建和使用。
5. [MAVEN数据读取](MAVEN数据读取)：实际单日接口、错误报告和数据标志。
6. [MAVEN_data_format](MAVEN_data_format)：产品表、数据字段及 STATIC 使用顺序。
7. [程序与函数Wiki](程序与函数Wiki)：从当前源码静态生成的定义索引。
8. [swia_electron_correlated](swia_electron_correlated)：SWIA 电子修正专题。

## 当前布局

通用能力在 `common/`，模型在 `models/`，Pickup 脚本在 `analysis/`，实验算法在 `models/extras/`。旧 `head.jl` 和 `calculate_models.jl` 已移除；应按迁移指南更新已有脚本。

2026-10-16 已完成有限范围的真实数据单文件读取验证，见 `docs/reports/real_data_validation_2026-10-16.md`；DLL 未验证，文档构建不执行科学处理。

## 维护与资料

- [文档源](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/src)：专题正文；页面导航与映射统一维护在 `docs/pages.toml`。
- [文档维护说明](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/docs/README.md)：API 生成、Documenter 构建、Wiki 预览与发布。
- [参考资料](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/references)：仪器 SIS 手册和专题资料。
- [历史报告](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/reports)：保留当时名称和路径，不作为当前 API 说明。
