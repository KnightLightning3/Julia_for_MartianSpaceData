#清理掉所有的下载问题文件
import os
from tqdm import tqdm
from time import sleep
import configparser
def get_list_from_ini(input_string):
    if input_string == 'Null':
        return []
    if input_string == 'None':
        return None
    stripped_string = input_string.replace(' ', '')
    items = stripped_string.split(',')
    return items

project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

config_file_path = os.path.join(project_path, "download_data", "MAVEN_download_config.ini")
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding='utf-8')

save_dir = config_data['DEFAULT']['Save_dir']#"E:/MAVEN/SWEA"#

def clean_pydownload_files(root_directory,end = ".pydownload"):
    """
    递归遍历文件夹，删除所有以 .pydownload 结尾的文件
    """
    # 确保路径存在
    if not os.path.exists(root_directory):
        print(f"错误: 路径 '{root_directory}' 不存在。")
        return

    count = 0
    print(f"正在扫描: {root_directory} ...")

    # os.walk 会递归遍历所有子目录
    for root, dirs, files in os.walk(root_directory):
        for filename in files:
            if filename.endswith(end):
                file_path = os.path.join(root, filename)
                try:
                    os.remove(file_path)
                    print(f"\033[1;31m已删除\033[0m: {file_path}")
                    count += 1
                except Exception as e:
                    print(f"无法删除 {file_path}: {e}")

    print("-" * 30)
    print(f"清理完成！共删除 \033[1;32m{count}\033[0m 个临时文件。")

if __name__ == "__main__":     
    # clean_pydownload_files(save_dir,end = ".f77_unformatted")
    # clean_pydownload_files(save_dir,end = ".aria2download")
    # clean_pydownload_files(save_dir,end = ".aria2")
    clean_pydownload_files(save_dir,end = "_compressed.cdf")