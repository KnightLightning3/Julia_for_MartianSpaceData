# 介绍

火星数据处理程序打包

主要以Julia代码为主

下载程序以Python为主

# 读取数据  
MAVEN 数据读取 MAVEN_data_load.jl,  

```
Datas = MAVEN_data_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

此程序需要特定的读取文件树格式,  
与下载部分共用文件树格式  

Julia中的引用方式:  
```
include("path/MAVEN_data_load.jl")  
include("path/IGRF_carculate.jl")  
import .MAVEN_data_load  
import .IGRF_carculate  
```


# 下载数据  
使用python程序, 下载文件的方式与Julia相同  
如果不想手动下载对应的包, 建议使用虚环境, requirements.txt  
```
pip install -r requirements.txt
```

# 火星磁场模型
IGRF_carculate.jl
利用IGRF模型计算火星模拟磁场

模型来源: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)  


# ToDo list
- [X]  云MAVEN数据  
- [ ]  全仪器读取  
- [X]  简易Julia绘图包  
- [X]  外接读取文件树  
- [ ]  更多磁场模型  
- [X]  天问数据  
- [ ]  磁力线追踪  

随缘更新
