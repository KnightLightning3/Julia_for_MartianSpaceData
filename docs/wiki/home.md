# 火星空间数据 Wiki

本 Wiki 汇总项目程序索引、数据读取流程、数据格式与仪器处理专题；源码与文档源都维护在[项目仓库](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData)。

> 各专题页正文由仓库 `docs/src/*.md` 生成（`python tools/push_wiki.py --push`）。
> **请修改仓库里的源文件，不要直接在 Wiki 界面编辑**，否则下次发布会覆盖。

## 页面

- [项目执行流程](项目执行流程)：环境准备 → 配置 → 下载 → 扫描索引 → 检查维护 → 派生构建 → 读取计算 → 测试文档。
- [程序与函数Wiki](程序与函数Wiki)：按目录浏览程序职责和函数说明。
- [MAVEN数据读取](MAVEN数据读取)：统一读取入口、返回结构和数据流程。
- [MAVEN_data_format](MAVEN_data_format)：MAVEN 数据产品列表与格式说明。
- [swia_electron_correlated](swia_electron_correlated)：SWIA 电子修正假设与算法记录。

## 相关文档

- [文档源](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/src)：上面各页的仓库源文件（Documenter 站点与 Wiki 同源）。
- [参考资料](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/references)：MAVEN 各仪器 SIS 手册 PDF 与《MAVEN 卫星电势揭秘》。
- [历史报告](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/reports)：重构诊断、审计与校验报告快照（保留当时的函数名与路径，不随重命名更新）。
- [CHANGELOG](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/CHANGELOG.md)：破坏性变更说明，例如 `data_get_from_date` → `load_MAVEN_data`。
