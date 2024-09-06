import os
import configparser
# 此程序只需要运行一次，用于生成下载MAVEN数据的配置文件，修改下载设置时只需要修改对应的配置文件即可

def add_comments_to_ini(file_path, option, comment):
    # 读取整个文件到内存
    with open(file_path, 'r') as file:
        lines = file.readlines()
    # 处理文件内容，添加注释
    with open(file_path, 'w') as file:
        for line in lines:
            if line.strip().startswith(f'{option}='):
                # 添加注释到该行
                line = line.strip() + f"; {comment}\n"
            file.write(line)

data_format_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
config_file_path = os.path.join(data_format_path, "download_data", "MAVEN_download_config.ini")

config = configparser.ConfigParser()
config.optionxform = str
config['DEFAULT'] = {
    'MAVEN_Server_url': 'https://lasp.colorado.edu/maven/sdc/public/data/sci/',
    'USTC_Server_url': 'http://222.195.76.155:8000/MAVEN/',
    'Username': '待定用户007',
    'Password': '待定用户007的密码是待定用户007',
    "sleep_time": "60 \n;下载错误时的休眠时间",
    "step_time": "0 \n;每个请求之间间隔的时间，以防被ban", 
}
config['VPN_proxy'] = {
    "MAVEN_server":"http://127.0.0.1:7890",
    "USTC_server": "None\n;vpn设置,None为不使用VPN,校外访问时可以忽略",
}
config['Settings'] = {
    "start_date": "2014-10-01 \n;下载数据的起始日期",
    "end_date": "2023-06-01 \n;下载数据的终止日期",
    "single_model": "LPW_lpiv \n;单次模式下载的模块,如果single_download为true，则下载此模块",
    "muti_models": "Null\n;填入想要批量下载的仪器模块，如果为Null，则下载所有模块",
    "models_pass" : "MAG_ss,MAG_ss1s,MAG_pc1s,MAG_pc,KP \n;从USTC服务器上批量下载的时候默认跳过的模块,MAG数据的l3为占用更小的二进制格式,所以不需要下载l2的数据,不同模块间用英文逗号分隔",
    "models_pass_MAVEN_server":"MAG_ss_l3,MAG_ss1s_l3,MAG_pc1s_l3,MAG_pc_l3,NGIMS_den_l4,KP_l3\n;从MAVEN官网批量下载的时候默认跳过的模块,这些模块为本地自制模块,lasp服务器上不存在,不同模块间用英文逗号分隔",
    "single_download": "False \n;为true时下载single_model，为false时下载muti_models",
}
with open(config_file_path, "w") as file:
    config.write(file)

with open(config_file_path, 'r') as file:
    lines = file.readlines()
stripped_lines = [line.lstrip() for line in lines]
with open(config_file_path, 'w') as file:
    file.writelines(stripped_lines)
