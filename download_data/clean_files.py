#清理掉所有的下载问题文件
import os
from tqdm import tqdm
from time import sleep
import configparser

project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

config_file_path = os.path.join(project_path, "download_data", "MAVEN_download_config.ini")
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding='utf-8')

save_dir = config_data['DEFAULT']['Save_dir']#"E:/MAVEN/SWEA"#

def clean_pydownload_files(root_directory, end=".pydownload", dry_run=True):
    """递归查找并清理未完成下载产生的临时文件（默认 dry-run 仅报告）。"""
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
                if dry_run:
                    print(f"   [dry-run] 将删除: {file_path}")
                    count += 1
                else:
                    try:
                        os.remove(file_path)
                        print(f"\033[1;31m已删除\033[0m: {file_path}")
                        count += 1
                    except Exception as e:
                        print(f"无法删除 {file_path}: {e}")

    print("-" * 30)
    if dry_run:
        print(f"dry-run 完成！共发现 \033[1;32m{count}\033[0m 个临时文件（未删除）。")
    else:
        print(f"清理完成！共删除 \033[1;32m{count}\033[0m 个临时文件。")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="清理未完成下载产生的临时文件（默认 dry-run，仅报告）。"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="显式启用删除；不传则只打印将删除的清单",
    )
    args = parser.parse_args()

    for end in (".aria2download", ".aria2", "_compressed.cdf"):
        clean_pydownload_files(save_dir, end=end, dry_run=not args.apply)