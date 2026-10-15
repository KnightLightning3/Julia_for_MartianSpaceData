# MAVEN 数据读取

本页说明当前仓库的 MAVEN 文件读取入口与失败语义。文件定位依赖产品注册表 `MAVEN_data/MAVEN_data_format.json` 和索引文件 `MAVEN_data/filename_lists.json`；真实数据目录由路径配置解析。索引缺失时读取器会按空索引处理，因此不会因此在模块加载时崩溃，但请求数据仍会报告文件缺失。

## 装载读取模块

```julia
using MarsData, Dates
MarsData.@load MAVEN_load
```

`@load` 是顶层宏，会把 `MAVEN_load` 模块绑定到当前作用域。它装载的是完整读取器；`using MarsData` 本身不等于装载 MAVEN CDF/STS 读取器。装载器会读取 `MAVEN_data/MAVEN_data_format.json` 并检查每个产品的 loader 名称是否存在于 `MAVEN_load.LOADER_FUNCS`。未知名称会在装载时抛错。`filename_lists.json` 则由 `filename_list()` 在首次定位文件时惰性读取。

## 按一天读取

`load_MAVEN_data` 的实际签名是 `load_MAVEN_data(date::DateTime; model_index=[], show_filename=false, error_report::Vector{String}=String[])`。日期参数是一个 `DateTime`，代表按文件名中的日历日期查找一天；此方法没有接受 `DateTime` 向量的重载。产品名使用注册表中的 ID，例如 `MAG_ss`：

```julia
using MarsData, Dates
MarsData.@load MAVEN_load

errors = String[]
data = MAVEN_load.load_MAVEN_data(
    DateTime(2015, 2, 9);
    model_index=["MAG_ss"],
    show_filename=true,
    error_report=errors,
)
mag = data["MAG_ss"]
if mag[:data_load_flag]
    B = mag[:B]
else
    @warn "MAG_ss 未读取" errors
end
```

成功的产品字典会附加 `:filename` 和 `:data_load_flag => true`。已注册产品未找到文件，或其 loader 抛出异常时，该产品对应 `Dict` 含 `:data_load_flag => false`，同时原因会追加到传入的 `error_report`；批量读取会继续处理其余产品。调用者应检查标志，不能把返回键存在当作数据读取成功。方法默认 `model_index=[]`，因此需要显式指定产品。应使用当前注册表中的产品 ID；未知 ID 可能在文件查找阶段触发 `KeyError`，不保证转换为失败字典。

产品 ID、保存子目录、文件名模式及 loader 由 `data_model` 注册表统一维护。`MAVEN_load.read_models` 在模块装载时根据注册表建立读取函数映射；`filename_lists.json` 列表项在请求日期时用于查找文件。按日期的文件索引在某个模型首次查询时构造并缓存，未命中时还会进行兼容性子串扫描。`file_list(model::String)` 可列出索引中该模型的路径；它假定模型键和索引键有效，未知键可能抛出 `KeyError`。

更广的项目执行顺序见 [pipeline.md](pipeline.md)，包边界见 [architecture.md](architecture.md)，旧接口迁移说明见 [migration.md](migration.md)。

## 数据内容与阅读范围

底层 CDF loader 将变量读为字典；具体键、维度、单位和坐标系取决于产品及后处理函数。`MAG_ss` 的读取由 `load_mag_l2` 处理，STATIC/SWEA/SWIA CDF 产品通常经 `load_cdf`；它们不是统一的数据结构。请按对应产品说明核对变量名和单位，不要从产品别名推断未记录字段。

STATIC 的原始质量轴字段是 `:mass_arr`（共享键名常量 `MarsData.DataKeys.MASS_ARR`），不是通用的 `:mass`。`:mass` 必须按产生它的函数解释：`static_slip_2_V` 返回的 `:mass` 是 `m_int` 标量；`static_c6_energy_mean` 返回的 `:mass` 是 `nmass×nswp` 质量轴数组。前者不能称作质量谱，后者才是该函数返回的质量轴。源码注释将可能存在的输入 `dat[:mass]` 视为质子质量基准，但当前 STATIC 转换函数不依赖这个输入键；例如 `STA_count2df` 直接使用 `constants.mp_eV_per_km_s2`（单位 `eV/(km/s)^2`），并另用 `:mass_arr` 做质量维数据计算。坐标旋转是独立处理步骤；字段所在参考系应以产品说明及姿态字段为准，不能将质量字段或读入动作描述为坐标变换。STATIC 角度到笛卡尔坐标及旋转的接口位于 `MAVEN_data/MAVEN_STATIC.jl`。

MAG L2 `.sts` 读取器返回 `:epoch`、`:type`、`:B`、`:B_total`、`:position`；MAG CDF 产品则由通用 CDF loader 按文件变量名读入，键集合可能不同。`MAG_ss1s_vsc` 专用读取器返回 `:epoch`、`:time_unix`、`:vsc`、`:position`。STATIC 派生 `STATIC_d1_v4d` 的字段由专用 JLD2 loader 映射，参见 [data_format.md](data_format.md) 的产品字段说明。字段细节应按对应 loader 而非产品家族推断。

SWIA 电子分布修正的理论推导见 [swia_electron.md](swia_electron.md)，其当前相关实现位于 `MAVEN_data/MAVEN_SWIA.jl` 和 `MAVEN_data/MAVEN_SWEA.jl`。此处不将理论公式等同于自动调用的读取步骤。
