import os
import configparser
# 此程序只需要运行一次, 用于生成下载MAVEN数据的配置文件, 修改下载设置时只需要修改对应的配置文件即可
# This program only needs to be run once to generate the configuration file for downloading MAVEN data. When modifying the download settings, you only need to modify the corresponding configuration file.
data_format_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
config_file_path = os.path.join(data_format_path, "download_data", "MAVEN_download_config.ini")

config = configparser.ConfigParser()
config.optionxform = str
config['DEFAULT'] = {
    'Save_dir': 'E:/MAVEN/',
    # 'MAVEN_server_ucla': 'https://pds-ppi.igpp.ucla.edu/data/',
    # 'MAVEN_server_colorado': 'https://lasp.colorado.edu/maven/sdc/public/data/sci/',
    # 'USTC_Server_url': 'http://222.195.76.155:8000/MAVEN/',
    "sleep_time": "60 \n;下载错误时的休眠时间\n;Sleep time in case of download error",
    "step_time": "0 \n;每个请求之间间隔的时间, 以防被ban\n;The time between each request to prevent being banned", 
}
config['Servers'] = {
    'Server_ind' : "0\n;下载服务器的编号\n;0: 自建服务器USTC\n;1: 加州大学UCLA\n;2: 科罗拉多大学LASP",
    'Username': '待定用户007',
    'Password': '待定用户007的密码是待定用户007',
    "0" : "http://222.195.76.155:8000/MAVEN/",
    "1" : "https://pds-ppi.igpp.ucla.edu/data/",
    "2" : "https://lasp.colorado.edu/maven/sdc/public/data/sci/",
}
config['VPN_proxy'] = {
    "Outer_server":"http://127.0.0.1:7890\n;vpn设置,None为不使用VPN\n;VPN settings, None means no VPN is used.",
    "USTC_server": "None\n;vpn设置,None为不使用VPN,校外访问时可以忽略\n;VPN settings, None means no VPN is used, which can be ignored when accessing outside the school.",
}
config['Properties'] = {
    "download_mode": "python.request \n;python.request:通过request方式下载文件 \n;win.idm:通过IDM下载文件,需要安装IDM软件,IDM可以启动多线程,但是下载程序将无法追踪下载进度,需要自行在软件中查看并启动文件录入功能(download_data/check_exist_files.py)",
    "continue_download": "False\n;为True时继续下载未完成的文件,为False时重新下载所有文件, 首次启动必然false\n;True to continue downloading unfinished files, False to redownload all files",
    "IDM_program_path" : "C:\Program Files (x86)\Internet Download Manager\IDMan.exe",
}
config['Settings'] = {
    "start_date": "2014-10-01 \n;下载数据的起始日期 \n;Start date yyyy-mm-dd",
    "end_date": "2024-06-01 \n;下载数据的终止日期 \n;End date yyyy-mm-dd",
    "single_model": "LPW_lpiv \n;单次模式下载的模块,如果single_download为True, 则下载此模块 \n;Module downloaded in single mode. If single_download = True, this module will be downloaded.",
    "muti_models": "Null\n;填入想要批量下载的仪器模块, 如果为Null, 则下载所有模块\n;Fill in the instrument modules you want to download in batches. If it is Null, all modules will be downloaded.",
    "models_pass" : "MAG_ss,MAG_ss1s,MAG_pc1s,MAG_pc,KP \n;从USTC服务器上批量下载的时候默认跳过的模块,MAG数据的l3为占用更小的二进制格式,所以不需要下载l2的数据,不同模块间用英文逗号分隔\n; Modules that are skipped by default when downloading in batches from the USTC server. l3 data of the MAG is a smaller Fortran binary format, so there is no need to download the l2 data. Different modules are separated by commas.",
    "single_download": "False\n;为true时下载single_model, 为false时下载muti_models\n;true for single_model, false for muti_models",
    "check_download_file":"False\n;检查并索引所有已下载文件,检索模式不会下载文件 \n;check and build all data already downloaded,check download file mode do not download file",
    "update_file_version" : "False\n;为True 时检查所下载文件的版本,此时下载会逐月检索所有文件 \n;update data already downloaded, on this mode, all files on server will be checked",
}
with open(config_file_path, "w", encoding='utf-8') as file:
    config.write(file)

with open(config_file_path, 'r', encoding='utf-8') as file:
    lines = file.readlines()
stripped_lines = [line.lstrip() for line in lines]
with open(config_file_path, 'w', encoding='utf-8') as file:
    file.writelines(stripped_lines)
