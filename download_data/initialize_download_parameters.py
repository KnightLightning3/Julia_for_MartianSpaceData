import os
import configparser
# 此程序只需要运行一次, 用于生成下载MAVEN数据的配置文件, 修改下载设置时只需要修改对应的配置文件即可
# This program only needs to be run once to generate the configuration file for downloading MAVEN data. When modifying the download settings, you only need to modify the corresponding configuration file.

DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "download_data", "MAVEN_download_config.ini",
)


def build_config():
    """构造包含全部默认值的 ConfigParser 对象（含下载器读取的全部键）。"""
    config = configparser.ConfigParser()
    config.optionxform = str
    config['DEFAULT'] = {
        'Save_dir': 'E:/MAVEN/',
        'CDF_LIB': 'D:/software/CDF.3.9_64bit/lib\n;CDF库文件路径,请根据实际安装路径修改\n;Path to CDF library, please modify according to the actual installation path',
        "sleep_time": "60 \n;下载错误时的休眠时间\n;Sleep time in case of download error",
        "step_time": "0 \n;每个请求之间间隔的时间, 以防被ban\n;The time between each request to prevent being banned",
    }
    config['Servers'] = {
        'Server_ind': "0\n;下载服务器的编号\n;0: 自建服务器USTC\n;1: 加州大学UCLA\n;2: 科罗拉多大学LASP",
        'Username': '待定用户007',
        'Password': '待定用户007的密码是待定用户007',
        "0": "http://222.195.76.155:8000/MAVEN/",
        "1": "https://pds-ppi.igpp.ucla.edu/data/",
        "2": "https://lasp.colorado.edu/maven/sdc/public/data/sci/",
    }
    config['VPN_proxy'] = {
        "Outer_server": "http://127.0.0.1:7890\n;vpn设置,None为不使用VPN\n;VPN settings, None means no VPN is used.",
        "USTC_server": "None\n;vpn设置,None为不使用VPN,校外访问时可以忽略\n;VPN settings, None means no VPN is used, which can be ignored when accessing outside the school.",
    }
    config['Properties'] = {
        "download_mode": "python.request \n;python.request:通过request方式下载文件 \n;win.idm:通过IDM下载文件,需要安装IDM软件,IDM可以启动多线程,但是下载程序将无法追踪下载进度,需要自行在软件中查看并启动文件录入功能(download_data/check_exist_files.py) \n;Aria2c,通过Aria2c下载文件",
        "continue_download": "True\n;为True时继续下载未完成的文件,为False时重新下载所有文件, 首次启动必然false\n;True to continue downloading unfinished files, False to redownload all files",
        "IDM_program_path": r"C:\Program Files (x86)\Internet Download Manager\IDMan.exe",
        "Aria2c_program_path": r"D:\software\aria2-1.37.0-win-64bit-build1\aria2c.exe",
        'max_threads': "5 \n; 多线程的线程数量",
        'show_tqdm_bar': "False \n; 是否显示下载进度条(多线程下会出错)",
    }
    config['Settings'] = {
        "start_date": "2014-10-01 \n;下载数据的起始日期 \n;Start date yyyy-mm-dd",
        "end_date": "2025-06-01 \n;下载数据的终止日期 \n;End date yyyy-mm-dd",
        "single_model": "LPW_lpiv \n;单次模式下载的模块,如果single_download为True, 则下载此模块 \n;Module downloaded in single mode. If single_download = True, this module will be downloaded.",
        "muti_models": "Null\n;填入想要批量下载的仪器模块, 如果为Null, 则下载所有模块\n;Fill in the instrument modules you want to download in batches. If it is Null, all modules will be downloaded.",
        "models_pass": "MAG_ss,MAG_ss1s,MAG_pc1s,MAG_pc,KP \n;从USTC服务器上批量下载的时候默认跳过的模块,MAG数据的l3为占用更小的二进制格式,所以不需要下载l2的数据,不同模块间用英文逗号分隔\n; Modules that are skipped by default when downloading in batches from the USTC server. l3 data of the MAG is a smaller Fortran binary format, so there is no need to download the l2 data. Different modules are separated by commas.",
        "single_download": "False\n;为true时下载single_model, 为false时下载muti_models\n;true for single_model, false for muti_models",
        "update_file_version": "False\n;为True 时检查所下载文件的版本,此时下载会逐月检索所有文件,注意，此模式会先批量删除本地旧版本文件，请做好备份 \n;update data already downloaded, on this mode, all files on server will be checked",
        # P0 契约补齐：下载器 MAVEN_download.py 会读取该键，必须由本初始化器生成。
        # 实际的完整性检查已按决策 D1 抽离为独立入口 download_data/check_download_file.py（默认只报告，不修改文件）。
        "check_download_file": "False\n;下载完成后是否自动执行文件完整性检查(预留开关)\n;实际的检查入口为 download_data/check_download_file.py,默认只报告不修改文件\n;Whether to auto-run file completeness check after download (reserved). The actual check entry is download_data/check_download_file.py, which only reports by default.",
    }
    return config


def generate_config(output_path=None):
    """生成 MAVEN 下载配置文件并返回写出路径。"""
    output_path = output_path or DEFAULT_CONFIG_PATH
    config = build_config()
    with open(output_path, "w", encoding='utf-8') as file:
        config.write(file)

    # 清理多行注释值的缩进（历史兼容写法：把续行顶格，使 ; 开头的行为注释行被 configparser 忽略）。
    with open(output_path, 'r', encoding='utf-8') as file:
        lines = file.readlines()
    with open(output_path, 'w', encoding='utf-8') as file:
        file.writelines([line.lstrip() for line in lines])
    return output_path


if __name__ == '__main__':
    generate_config()
