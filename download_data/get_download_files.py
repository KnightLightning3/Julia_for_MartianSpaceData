# 汇总 lists/ 下各模型清单，写为索引 JSON（filename_lists.json）。
# 索引输出路径固定由本脚本所在位置推导（仓库根/MAVEN_data/），不再依赖运行时的 CWD。
import os
import json
import configparser
import tempfile

PROJECT_PATH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_config(config_path=None):
    """读取下载配置；config_path 为空时使用仓库内的默认配置文件。"""
    if config_path is None:
        config_path = os.path.join(PROJECT_PATH, "download_data", "MAVEN_download_config.ini")
    config_data = configparser.ConfigParser()
    config_data.optionxform = str
    config_data.read(config_path, encoding='utf-8')
    return config_data


def default_index_path():
    """返回默认索引 JSON 的绝对路径（由脚本位置推导，与 CWD 无关）。"""
    return os.path.join(PROJECT_PATH, "MAVEN_data", "filename_lists.json")


def write_index(save_dir, output_path=None):
    """汇总 save_dir/lists/*.txt 为索引 JSON 并写入。返回输出文件路径。"""
    if output_path is None:
        output_path = default_index_path()
    list_dir = os.path.join(save_dir, "lists")
    list_dict = {}
    listnames = []
    if os.path.isdir(list_dir):
        listnames = sorted(x for x in os.listdir(list_dir) if x.endswith(".txt"))
        for listname in listnames:
            model = listname[: -len("_list.txt")]
            with open(os.path.join(list_dir, listname), 'r', encoding='utf-8') as f:
                lines = [line.rstrip() for line in f]
            list_dict[model] = lines
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(output_path) or ".", prefix=".filename_lists.", suffix=".tmp")
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as json_file:
            json.dump(list_dict, json_file, indent=4)
        os.replace(tmp_path, output_path)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
    return output_path


def main():
    config_data = load_config()
    save_dir = config_data['DEFAULT']['Save_dir']
    output_path = write_index(save_dir)
    print("\033[1;32m成功录入以下数据模块目录:\033[0m")
    list_dir = os.path.join(save_dir, "lists")
    if os.path.isdir(list_dir):
        for ls in sorted(os.listdir(list_dir)):
            if ls.endswith(".txt"):
                print("    " + ls)
    return output_path


if __name__ == '__main__':
    main()
