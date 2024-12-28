; 取得3D quat值, 对于以下三种仪器起效. 必须包含SPEDAS_6_1版本的包
; spedas_6_1\projects\maven\eph\mvn_pfp_cotrans.pro

;time = unix_time
mk = mvn_spice_kernels(/load, /all, trange='2015-10-29/11:30:00', verbose=verbose)
spice_body_att("MAVEN_STATIC","MAVEN_MSO",'2015-10-29/11:30:00',/quaternion)
spice_body_att("MAVEN_SWIA","MAVEN_MSO",'2015-10-29/11:30:00',/quaternion)
spice_body_att("MAVEN_SWEA","MAVEN_MSO",'2015-10-29/11:30:00',/quaternion)

SC IAU MSO SWIA SWEA
end