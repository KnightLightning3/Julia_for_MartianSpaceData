"""根据 MAVEN 文件版本信息查找并移除重复的低版本数据文件。"""

import json
import os
import re
from collections import defaultdict


# 获取项目根目录
project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import sys
if project_path not in sys.path:
    sys.path.insert(0, project_path)

# 读取数据格式 JSON 文件
json_path = os.path.join(project_path, "MAVEN_data", "MAVEN_data_format.json")
with open(json_path, "r", encoding="utf-8") as file:
    json_data = json.load(file)

# 加载 TOML 下载配置
from config.config import load_config

cfg = load_config()
save_dir = cfg.paths.maven_data_root


def download_model(model):
    """根据产品标识生成本地目录与文件名匹配信息。"""
    global save_dir
    global json_data
    data_model = json_data["data_model"]
    model_key = {}
    for key, value in data_model.items():
        model_key[key] = value[:3]
    _, filename, pathname = model_key[model]
    save_path = os.path.join(save_dir, pathname)
    return [save_path, filename]


# ==================================================
# 2. 版本比对与物理清除逻辑
# ==================================================
def parse_file_info(file_path):
    """从 MAVEN 文件路径和名称中提取产品、日期及版本信息。"""
    """解析文件名，提取日期、版本号(v)和处理号(r)

    示例: "2014/10/mvn_swe_l2_svypad_20141013_v04_r01.cdf"
    """
    filename = os.path.basename(file_path)

    # 正则表达式匹配: 8位数字日期, _vXX, _rXX
    pattern = r"_(\d{8})_v(\d+)_r(\d+)"
    match = re.search(pattern, filename)

    if not match:
        return None

    date_str = match.group(1)
    version = int(match.group(2))
    revision = int(match.group(3))

    return {
        "original_path_in_json": file_path,  # JSON 记录的路径
        "filename": filename,  # 纯文件名
        "date": date_str,
        "v": version,
        "r": revision,
    }


def remove_low_version_files(filename_lists_json_path, dry_run=True):
    """识别同一数据产品的旧版本文件并按 dry-run 设置执行清理。"""
    """读取已下载文件的清单 JSON，动态匹配各 mode 磁盘目录并清理低版本"""
    if not os.path.exists(filename_lists_json_path):
        print(f"❌ 找不到已下载清单文件: {filename_lists_json_path}")
        return

    with open(filename_lists_json_path, "r", encoding="utf-8") as f:
        data_packets = json.load(f)

    # 遍历每个数据包类型 (如 "LPW_wave", "SWE_pad" 等，也就是 model/mode)
    for packet_type, file_list in data_packets.items():
        # 通过你提供的函数，动态获取当前 mode 在你电脑上的实际物理存储目录
        
        try:
            mode_save_path, _ = download_model(packet_type)
        except KeyError:
            print(
                f"⚠️ 警告: 在 data_model 中找不到对 [{packet_type}] 的配置解析，跳过该包类型。"
            )
            continue

        # 用一个字典将该包类型下，同一天的数据聚拢起来
        daily_groups = defaultdict(list)

        for file_path in file_list:
            info = parse_file_info(file_path)
            if info:
                daily_groups[info["date"]].append(info)

        # 开始在每一天的数据组内进行版本博弈
        for date, info_list in daily_groups.items():
            # 如果这一天只有一个文件，说明没有重复，安全通过
            if len(info_list) <= 1:
                continue

            # 排序逻辑: 优先对比 'v' 从大到小，其次对比 'r' 从大到小
            sorted_list = sorted(
                info_list, key=lambda x: (x["v"], x["r"]), reverse=True
            )

            keep_file = sorted_list[0]  # 要保留的最高版本
            remove_files = sorted_list[1:]  # 剩下的都是要移除的旧版本

            # 提取名字用于对账日志
            keep_name = keep_file["original_path_in_json"]
            remove_names = [item["original_path_in_json"] for item in remove_files]

            print(f"==================================================")
            print(f"🔍 数据包 [{packet_type}] 在 {date} 检测到版本重复:")
            print(f"   保留：{keep_name}")
            print(f"   移除：{', '.join(remove_names)}")

            # 物理操作循环
            for rem_item in remove_files:
                # 核心安全跨越：用 download_model 返回的物理 save_path 拼接纯文件名
                full_disk_path = os.path.join(mode_save_path, rem_item["original_path_in_json"])

                if dry_run:
                    print(f"   [测试模式] 准备执行物理删除 -> {full_disk_path}")
                else:
                    if os.path.exists(full_disk_path):
                        try:
                            os.remove(full_disk_path)
                            print(f"   ✅ 已成功删除磁盘文件 -> {full_disk_path}")
                        except Exception as e:
                            print(
                                f"   ❌ 删除失败 -> {full_disk_path}, 错误信息: {e}"
                            )
                    else:
                        print(
                            f"   ⚠️ 文件在磁盘上并未实际存在，跳过物理删除 -> {full_disk_path}"
                        )


# ==================================================
# 3. 脚本执行入口
# ==================================================
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="移除重复的低版本 MAVEN 文件（默认 dry-run，只报告不删除）。"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="显式启用物理删除；不传则只打印对账清单（dry-run）",
    )
    args = parser.parse_args()

    # 定位存放已知已下载文件列表的 JSON
    recorded_json = os.path.join(
        project_path, "MAVEN_data", "filename_lists.json"
    )

    print("🚀 MAVEN 自动化磁盘旧版本清理引擎启动...")
    print(f"当前项目根路径: {project_path}")
    print(f"当前数据存储主根目录(Save_dir): {save_dir}")
    print("模式: " + ("物理删除(--apply)" if args.apply else "dry-run(仅报告)"))

    remove_low_version_files(recorded_json, dry_run=not args.apply)
