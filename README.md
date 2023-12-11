# My_julia_Pkg
MAVEN 数据读取,此文件需要特定的读取文件树格式,与下载部分共用文件树格式


Julia中的引用方式:
```
include("path/MAVEN_data_load.jl")
include("path/IGRF_carculate.jl")
import .MAVEN_data_load
import .IGRF_carculate
```
python部分为下载脚本,需要对应的request文件,建议使用虚环境

working on 云MAVEN数据中