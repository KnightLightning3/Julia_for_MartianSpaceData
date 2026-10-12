# MAVEN 各数据包内容格式

## STA系列：
- swp_ind 从0开始计数，使用julia时需要给数值加一
- Note that [phi, theta] = [0, 0]deg corresponds to $−Y_{MSO}$ and [+90, 0]deg corresponds to $+Z_{MSO}$

STA操作example
```julia
# 取得数据
sta_data  = MAVEN_load.data_get_from_date(DateTime(2015,2,9), model_index = ["STATIC_cf"])["STATIC_cf"];
# 取得给定时间的切片
sta_slip_data = MAVEN_load.static_slip(sta_data,time_ind);
# 旋转坐标到MSO坐标系
sta_slip_data = MAVEN_load.static_rotation(sta_slip_data;frame="MSO");
# 取得离子速度
vel,_,_ = MAVEN_load.sta_v_4d(sta_slip_data; energy_range=[0,1e4],mass_range=[0,2],m_int = 1) 
# 将坐标换成速度分布
V_data = MAVEN_load.static_slip_2_V(sta_slip_data;mass_range=[0,2],m_int = 1);
# 绘制 tri 图片
ax = MAVEN_plot.STA_2d_slip(ax,V_data;frame="perp_xy",colorrange=(1e-12,1e-4),vbluk=vel)
```

## MAG系列:
- MAG为sts文件保存,为读取更快,修改为二进制存储的文件MAG_xx_l3

## KP:
- 有不同的版本号,不同版本的数据排布有一些区别
- 考虑制作为KP_l3的julia二进制文件
- SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available
- Inbound ('I') is from geometric apoapsis to next geometric periapsis in time, outbound ('O') is the reverse 
文件格式:  
Fortan部分
```Fortran
版本号: I2,对应v15,v19等
时间维度ntime,对应数据的行数
总变量数n,对应数据的列数
时间量: Float64, unix时间
其余变量:ntime*(n-1)个量,Float64
```

```Python
data={
    变量编号:{
        "Varname":变量名
        "Vars":变量内容
    }
}
```

## 数据下载
使用`download_data\MAVEN_download.py`和`download_data\MAVEN_download_from_server.py`程序下载

数据下载为固定的格式  `SAVE_PATH/model/处理程度/年/月/ `   

一次固定下载一个月的数据

下载完成后自动产生list文件以保存下载的文件列表

需要使用`download_data\get_download_files.py`来生成一个本地的filename_lists.json的文件保存所有文件的目录以便程序查询之

以后可能会考虑弃用此方法,改为直接去对于年月文件夹寻找文件

## SPADES问题
2024-7-1的闰秒导致程序出错，暂时修改代码忽略它

## 已支持数据类型
MAVEN数据模块名列表
|模型名|描述|读取函数|名称格式|
|---|---|---|---|
|KP|KP datas|load_kp|^mvn_kp_insitu_.+\.tab$|
|KP_cdf|KP data in cdf, bulid by MAVEN_data/Build_data/KP2cdf.py|load_cdf|^mvn_kp_insitu_.+\.cdf$|
|MAG_ss|mag 32 Hz data in MSO|load_mag_l2|mvn_mag_l2_\d{7}ss_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_ss1s|mag 1 Hz data in MSO|load_mag_l2|mvn_mag_l2_\d{7}ss1s_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_pc|mag 32 Hz data in PC|load_mag_l2|mvn_mag_l2_\d{7}pc_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_pc1s|mag 1 Hz data in PC|load_mag_l2|mvn_mag_l2_\d{7}pc1s_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_ss_cdf|mag 32 Hz data in MSO (cdf)|load_cdf|mvn_mag_l2_\d{7}ss_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_ss1s_cdf|mag 1 Hz data in MSO (cdf)|load_cdf|mvn_mag_l2_\d{7}ss1s_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_pc_cdf|mag 32 Hz data in PC (cdf)|load_cdf|mvn_mag_l2_\d{7}pc_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_pc1s_cdf|mag 1 Hz data in PC (cdf)|load_cdf|mvn_mag_l2_\d{7}pc1s_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_ss1s_vsc|spacecraft velocity calculated from mag data (binary)|load_mag_vsc|mvn_mag_vsc_ss1s_\d{8}_v\d{2}_r\d{2}\.f77_unformatted|
|SWEA_spec|SWEA l2 survey spectra|load_cdf|mvn_swe_l2_svyspec_.+\.cdf|
|SWEA_pad_arc|SWEA l2 arc pad|load_swea_pad|mvn_swe_l2_arcpad_.+\.cdf|
|SWEA_pad_svy|SWEA l2 survey pad|load_swea_pad|mvn_swe_l2_svypad_.+\.cdf|
|SWEA_arc3d|SWEA l2 arc 3d|load_cdf|mvn_swe_l2_arc3d_.+\.cdf|
|SWEA_svy3d|SWEA l2 svy 3d|load_cdf|mvn_swe_l2_svy3d_.+\.cdf|
|SEP_anc| |load_cdf|mvn_sep_l2_anc_.+\.cdf|
|SEP_counts| |load_cdf|mvn_sep_l2_s1-raw-svy-full_.+\.cdf|
|SEP_spec| |load_cdf|mvn_sep_l2_s1-cal-svy-full_.+\.cdf|
|STATIC_c6|STATIC c6 32e64m|load_cdf|mvn_sta_l2_c6-32e64m_.+\.cdf|
|STATIC_c8|STATIC c8 32e16d|load_cdf|mvn_sta_l2_c8-32e16d_.+\.cdf|
|STATIC_ca|STATIC ca 16e4d16a|load_cdf|mvn_sta_l2_ca-16e4d16a_.+\.cdf|
|STATIC_cf|STATIC cf 16e4d16a16m|load_cdf|mvn_sta_l2_cf-16e4d16a16m_.+\.cdf|
|STATIC_d0|STATIC d0 32e4d16a8m|load_cdf|mvn_sta_l2_d0-32e4d16a8m_.+\.cdf|
|STATIC_d1|STATIC d1 32e4d16a8m|load_cdf|mvn_sta_l2_d1-32e4d16a8m_.+\.cdf|
|STATIC_d1_v4d|STATIC d1 velocity flux density (binary)|load_d1_v4d|mvn_sta_l3_d1_v4d_.+\.f77_unformatted|
|STATIC_d1_v4d_cold|STATIC d1 velocity flux density (binary)|load_d1_v4d|mvn_sta_l3_d1_v4d_cold.+\.f77_unformatted|
|STATIC_d1_v4d_heat|STATIC d1 velocity flux density (binary)|load_d1_v4d|mvn_sta_l3_d1_v4d_heat.+\.f77_unformatted|
|STATIC_c6_v3d|STATIC c6 velocity flux density (binary)|load_c6_v3d|mvn_sta_l3_c6_v3d_.+\.jld2|
|LPW_wave|LPW wave passitive spectra|load_cdf|mvn_lpw_l2_wspecpas_.+\.cdf|
|LPW_wave_act|LPW wave active spectra|load_cdf|mvn_lpw_l2_wspecact_.+\.cdf|
|LPW_mrgscpot|LPW merged spacecraft potential|load_cdf|mvn_lpw_l2_mrgscpot_.+\.cdf|
|LPW_lpiv|LPW lp iv|load_cdf|mvn_lpw_l2_lpiv_.+\.cdf|
|LPW_lpnt|LPW lp nt|load_cdf|mvn_lpw_l2_lpnt_.+\.cdf|
|LPW_wn|LPW w n|load_cdf|mvn_lpw_l2_wn_.+\.cdf|
|LPW_we12|LPW 1D wave|load_cdf|mvn_lpw_l2_we12_.+\.cdf|
|LPW_bursthf| |load_cdf|mvn_lpw_l2_we12bursthf_.+\.cdf|
|LPW_burstmf| |load_cdf|mvn_lpw_l2_we12burstmf_.+\.cdf|
|LPW_burstlf| |load_cdf|mvn_lpw_l2_we12burstlf_.+\.cdf|
|NGIMS_sht_l3|L3 resampled scale height table|load_NGIMS_sht_l3|mvn_ngi_l3_res-sht-.+\.csv|
|NGIMS_sht_l4|combined resampled scale height table|load_NGIMS_sht_l3|mvn_ngi_l4_res-sht-.+\.csv|
|NGIMS_den_l3|L3 resampled average denity table|load_NGIMS_den_l3|mvn_ngi_l3_res-den-.+\.csv|
|NGIMS_den_l4| |load_NGIMS_den_l3|mvn_ngi_l4_res-den-.+\.csv|
|SWIA_mom| |load_cdf|mvn_swi_l2_onboardsvymom_.+\.cdf|
|SWIA_svy_spec| |load_cdf|mvn_swi_l2_onboardsvyspec_.+\.cdf|
|SWIA_fine_svy_3d| |load_cdf|mvn_swi_l2_finesvy3d_.+\.cdf|
|SWIA_fine_arc_3d| |load_cdf|mvn_swi_l2_finearc3d_.+\.cdf|
|SWIA_coarse_svy_3d| |load_cdf|mvn_swi_l2_coarsesvy3d_.+\.cdf|
|SWIA_coarse_arc_3d| |load_cdf|mvn_swi_l2_coarsearc3d_.+\.cdf|
|EUV_l2_bands| |load_cdf|mvn_euv_l2_bands_.+\.cdf|
|EUV_l3_minute|EUV minute averaged data|load_cdf|mvn_euv_l3_minute.+\.cdf|
|EUV_l3_daily|EUV daily averaged data|load_cdf|mvn_euv_l3_daily.+\.cdf|
|SWIA_quat|quat data of SWIA to MSO|load_quat|mvn_spice_swia_qu_.+\.csv|
