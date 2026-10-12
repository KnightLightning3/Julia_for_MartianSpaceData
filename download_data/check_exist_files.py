# 检查本地所有存在的文件，并将扫描结果写为各模型的清单文件。
# 本模块不再依赖 runpy / exit(0)，所有逻辑都收敛为可显式调用的函数，
# 供 MAVEN_download.py 下载完成后调用，也可独立运行（python download_data/check_exist_files.py）。
import os
import re
import json
import configparser

PROJECT_PATH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_config(config_path=None):
    """读取下载配置；config_path 为空时使用仓库内的默认配置文件。"""
    if config_path is None:
        config_path = os.path.join(PROJECT_PATH, "download_data", "MAVEN_download_config.ini")
    config_data = configparser.ConfigParser()
    config_data.optionxform = str
    config_data.read(config_path, encoding='utf-8')
    return config_data


def load_schema():
    """读取模型注册表 MAVEN_data_format.json。"""
    with open(os.path.join(PROJECT_PATH, "MAVEN_data", "MAVEN_data_format.json"), "r", encoding='utf-8') as file:
        return json.load(file)


def download_model(model, save_dir, data_model):
    """根据产品标识取得其本地保存目录与文件命名正则。返回 (save_path, file_style)。"""
    model_key = {key: value[:3] for key, value in data_model.items()}
    _, file_style, pathname = model_key[model]
    save_path = os.path.join(save_dir, pathname)
    return save_path, file_style


def search_downloaded_files(save_path, file_style):
    """遍历本地年/月目录并查找符合命名正则的数据文件，返回相对路径列表。"""
    filenames = []
    if not os.path.exists(save_path):
        return filenames
    for iy in os.listdir(save_path):
        year_dir = os.path.join(save_path, iy)
        if not os.path.isdir(year_dir):
            continue
        for im in os.listdir(year_dir):
            month_dir = os.path.join(year_dir, im)
            if not os.path.isdir(month_dir):
                continue
            filepaths = [f"{iy}/{im}/{file}" for file in os.listdir(month_dir) if re.match(file_style, file)]
            filenames.extend(filepaths)
    return filenames


def scan(save_dir, data_model):
    """扫描全部模型并写出 lists/{model}_list.txt。返回写入的清单文件路径列表。"""
    lists_dir = os.path.join(save_dir, "lists")
    os.makedirs(lists_dir, exist_ok=True)
    written = []
    for model in data_model.keys():
        save_path, file_style = download_model(model, save_dir, data_model)
        file_names = search_downloaded_files(save_path, file_style)
        list_file_path = os.path.join(lists_dir, f"{model}_list.txt")
        with open(list_file_path, 'w', encoding='utf-8') as file:
            if file_names:
                for item in file_names:
                    file.write(str(item) + '\n')
        written.append(list_file_path)
    return written


def main(config_path=None, index_path=None):
    """扫描本地文件并刷新索引 JSON。

    config_path / index_path 仅用于测试指向临时路径；默认使用仓库内的真实配置与索引位置。
    返回索引文件路径。
    """
    config_data = load_config(config_path)
    data_model = load_schema()["data_model"]
    save_dir = config_data['DEFAULT']['Save_dir']
    scan(save_dir, data_model)

    from get_download_files import write_index
    index_path = write_index(save_dir, output_path=index_path)
    print(f"索引已更新: {index_path}")
    return index_path


if __name__ == '__main__':
    main()
