setenv,"ROOT_DATA_DIR=H:/data"
setenv,"local_data_dir=H:/data"
setenv,'http_proxy=http://127.0.0.1:7890'
cdf_leap_second_init,/no_update,/no_download
date='2015-10-29'
timespan,date+'/'+['11:05','11:45']
;  ttarget_PAD=date+'/'+'11:32:40'
;mvn_spice_load;,/no_download
;
;sta_files = ["E:\MAVEN\STATIC\l2\2015\10\mvn_sta_l2_c6-32e64m_20151029_v02_r01.cdf",$
;  "H:\data\maven\data\sci\sta\l2\2015\10\mvn_sta_l2_c0-64e2m_20151029_v02_r01.cdf", $
;  "H:\data\maven\data\sci\sta\l2\2015\10\mvn_sta_l2_ca-16e4d16a_20151029_v02_r01.cdf"]
;mvn_sta_l2_load,files = sta_files,/no_update,/no_download
;mvn_sta_scpot_load;need c0 c8 c6
mvn_scpot


end