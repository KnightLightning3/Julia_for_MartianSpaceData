# MAVEN数据处理介绍

## 数据预处理：
为便利起见，数据在下载的同时，将会产生`MAVEN_data/filename_lists.json`文件用于保存已经下载数据的目录，每次更新下载数据后，需要执行[download_data/check_exist_files.py](download_data/check_exist_files.py)来更新此文件

## 数据结构：

读取方法：

使用读取方法前需要导入读取代码module
```Julia
path = "主程序包的配置路径"
include("$path/MAVEN_load.jl")
import .MAVEN_load
```

函数`MAVEN_load.data_get_from_date(date::DateTime; model_index=[], show_filename=false)`

传入参数
- `date{DateTime}`读取的日期，一次只能读取一天的数据
- `model_index{List}`要读取的数据包名称列表
- `show_filename`控制是否显示读取进度

此程序返回一个字典，其构成为

`Dict{String,Dict}`， 返回一个字典，其中字典的Key为数据包别名 `String`，对应要读取的数据包的名称列表，由`model_index`传入，对应var为：
- `Dict{Symbol,Any}` Key值 `Symbol` 对应数据包的对应数据名称
  - `:filename` `String`
  - `:data_load_flag` `Bool` 判断是否读取成功
  - `:其他数据`
  - ......

如，
```Julia
Data_Dict = MAVEN_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```
返回得到的磁场数据为：
```Julia
mag_data = Data_Dict["MAG_pc1s"][:B]
```

# 详细读取逻辑说明

执行`include("$path/MAVEN_load.jl");import .MAVEN_load`后，程序将执行以下步骤：
1. 读取数据结构说明文件`MAVEN_data/MAVEN_data_format.json`，从中获取各个数据模块和其对应的文件名格式，读取所需的函数名称
2. 在上一步中，得到`read_models = Dict{String,Tuple{String,Function}}()`，其key值对应数据模块名称，返回读取该模块所需的具体函数名称
3. 读取`MAVEN_data/filename_lists.json`中的已下载数据的目录

具体执行数据读取时，程序将执行以下步骤：
1. `find_file_of_data`函数比较传入的日期和已经下载的文件目录，由于NASA在文件命名时，让文件名称本身包含`YYYYMMDD`格式的日期标号，所以可以通过简单的比较得到对应日期的文件
2. `file_list`输入数据模块名，返回对应的所有数据的路径名称列表，可以用在批量和统计数据的处理上
3. 如果判定数据存在，就开始读取，如果不存在，返回一个字典`Dict(:data_load_flag => false)`，表示此处数据缺失

**为了能够让使用者知道读取时发生的意外情况，我没有对读取数据做`try`语句的鲁棒性处理，只要不是对应日期数据缺失的其他任何错误，都将直接报错**

# 自建数据说明

为部分数据做了额外调整以方便使用

## KP_l3数据

以JLD2格式将KP数据保存为字典模式, epoch对应时间, 变量序号为数字对于kp说明文档中的变量序号, 同时额外将坐标变换矩阵matrix专门保存为3 $\times$ 3的矩阵的列表.

KP_l3 数据结构：
- `:time`，`Array{DateTime}`，时间戳
- `:varsion`, KP数据的版本，不同版本的数据在格式上可能有不同，需要注意
- `:pc2ss_Matrix`，`zeros(Float64, ntime, 3, 3)`，坐标系变换的3 $\times$ 3矩阵，由行星中心（planet-center）参考系转为
- `:ss2pc_Matrix`,
- `:vars`,`Dict{Symbol,Any}()`，保存其他数据
  - :var_i,i为变量序号（参见`~/MAVEN_data/KP_vars.json`），可以考虑使用新字典和新键值来保存之

保存于KP/l3/

## MAG_l3数据

将磁场数据以Fortran77无格式形式保存, 减少原数据的空间占用, 提高读取速度, 保存于MAG/l3/

<!-- 该类型数据可以通过'MAVEN_data/Build_data/磁场重构.jl'生成，但是由于空间有限，服务器上只保留MAG的原始数据，建议这一步在本地进行这一步，可以有效加速读取速度 -->

MAG_l3 数据结构：
- `:epoch`, DateTime格式的时间数组
- `:time_unix`, UNIX时间戳的时间数组
- `:coordinate`, String，说明读取数据的坐标系
- `:B_total`, 总磁场强度
- `:B`, 磁场强度3分量
- `:position`, 位置3分量
- 

## VSC 数据:

飞行器速度, vsc数据本身可以由spice程序包计算. 但是其存在学习门槛.

此数据集通过使用mag中以1秒为精度的位置数据计算二次函数拟合取得vsc数据.

保存于MAG/vsc/, 单位km/s，坐标系为MSO

VSC 数据结构：
- `:epoch`,DateTime格式的时间数组
- `:time_unix`, UNIX时间戳的时间数组
- `:vsc`,飞行器速度数组
- `:position`,飞行器位置

## STATIC_d1_v4d 数据

基于SPEDAS库中的v_4d程序编写和计算, 使用mag取得的vsc和STATIC自带的电势修正.

计算了全能量, 角度域的 $\textsf H^+$,$\textsf O^+$,$\textsf O_2^+$ 的速度vel(km/s),
密度den( $\textsf{cm}^{-3}$ ), 通量flux( $\textsf{cm}^{-2}/s$).

保存于STATIC/l3/
- `:epoch`, DateTime格式的时间数组
- `:time_unix`, UNIX时间戳的时间数组
- `:H_vel`, `:O_vel`, `:O2_vel`, $\textsf H^+$,$\textsf O^+$,$\textsf O_2^+$ 的速度vel(km/s)
- `:H_f`, `:O_f`, `:O2_f`,  通量flux( $\textsf{cm}^{-2}/s$)
- `:H_den`, `:O_den`, `:O2_den`, den( $\textsf{cm}^{-3}$ )
- `:pos_sc_mso`, 飞行器位置
- `:quality_flag`, 质量标号
- 
## STATIC_d1_v4d 数据

基于SPEDAS库中的v_4d程序编写和计算, 使用mag取得的vsc和STATIC自带的电势修正.

计算了全能量, 角度域的 $\textsf H^+$,$\textsf O^+$,$\textsf O_2^+$ 的速度vel(km/s),
密度den( $\textsf{cm}^{-3}$ ), 通量flux( $\textsf{cm}^{-2}/s$).

保存于STATIC/l3/

数据结构：
- `:epoch`, DateTime格式的时间数组
- `:time_unix`, UNIX时间戳的时间数组
- `:H_vel`, `:O_vel`, `:O2_vel`, $\textsf H^+$,$\textsf O^+$,$\textsf O_2^+$ 的速度vel(km/s)
- `:H_f`, `:O_f`, `:O2_f`,  通量flux( $\textsf{cm}^{-2}/s$)
- `:H_den`, `:O_den`, `:O2_den`, den( $\textsf{cm}^{-3}$ )
- `:pos_sc_mso`, 飞行器位置
- `:quality_flag`, 质量标号
  
## STATIC_c6_v3d 数据
基于SPEDAS库中的v_3d？程序编写和计算, 使用mag取得的vsc和STATIC自带的电势修正.
计算了全能量, 全角度求和的 $\textsf H^+$,$\textsf O^+$,$\textsf O_2^+$ 的**一维**速度vel(km/s),
密度den( $\textsf{cm}^{-3}$ ), **一维**通量flux( $\textsf{cm}^{-2}/s$).

保存于STATIC/l3/

数据结构：
- `:epoch`, DateTime格式的时间数组
- `:time_unix`, UNIX时间戳的时间数组
- `:H_vel`, `:O_vel`, `:O2_vel`, $\textsf H^+$,$\textsf O^+$,$\textsf O_2^+$ 的速度vel(km/s)
- `:H_f`, `:O_f`, `:O2_f`,  通量flux( $\textsf{cm}^{-2}/s$)
- `:H_den`, `:O_den`, `:O2_den`, den( $\textsf{cm}^{-3}$ )
- `:pos_sc_mso`, 飞行器位置
- `:quality_flag`, 质量标号
- `:vsc_mso`, 飞行器速度，MSO参考系
- `:mode`, 仪器模式，见STA的官方文档说明
- `:mass_range`, 计算选取的质量数范围
# SWIA_quat数据

不同于STATIC自带的四元数旋转矩阵，SWIA需要额外计算一个四元数用于坐标变换。在**SPADES**中，这一方法是调用SPICE程序包，该程序目前只能由**IDL**平台计算

因此，我直接批量计算了所有日期的SWIA_quat数据来用，具体用法见后续SWIA部分的说明

数据结构
- `:epoch`, DateTime格式的时间数组
- `:time_unix`, UNIX时间戳的时间数组
- `:quat`, Array{QuatRotation}，旋转四元数
- `:coordinate`, String，"SWIA to mso", 坐标系，目前只有SWIA的仪器转MSO坐标的结果

# MAVEN 数据 Tips

## STATIC 数据:

- STATIC 会返回每个时刻的(方位角,能量,离子质量数)的三维矩阵数据, 对应其中的 energy,phi,theta,mass_arr 矩阵
- 扫描模式: STATIC 有多个不同的扫描模式,对应不同的能量范围,由 swd_ind 参数[0-26]决定,对应 energy,phi,theta,mass_arr 矩阵中的最后一个维度. 在 julia 这种以 1 开始计数的语言中,要将 swd_ind 参数加一
- 衰减器 衰减器 attenuator 会根据具体情况对小于 15eV 的低能量段 STA 数据乘以(1., 1/10, 1/100, 1/1000)以防止过饱和,官方宣称其更换时间不会小于 5min,然而一些数据可以用临时的过饱和解释,而且有切换 attenuator
- STATIC 返回的 theta 和 phi,对应球坐标系的 90-theta 和 phi,处于仪器参考系下. 文件中的 quat_mso 和 quat_sc 为四元数,可以用于将仪器参考系投影到 mso 和 sc 参考系.
- STATIC, SWEA, SWIA 使用的参考系为对应球坐标系的 90-theta 和 phi. ref:spedas_6_1\general\science\sphere_to_cart.pro
- STATIC以及SWIA的能量步长关系很可能是:

  $$
  R = dE/E
  $$

  $$
  \sqrt{k} = \frac{R}{2} + \sqrt{\left(\frac{R}{2}\right)^2 + 1}
  $$

  $$
  code
  $$

  $$
  E_{i, \text{end}} = E_i \cdot \sqrt{k}
  $$


消歧义
- IAU = pc = GEO
- MSO = ss