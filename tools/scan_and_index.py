"""独立 CLI：扫描本地文件并刷新索引（scan -> manifest）。

不依赖 runpy / exit()，可被其它脚本以函数方式调用 main()。
用法：
    python tools/scan_and_index.py
    python tools/scan_and_index.py --models MAG_ss KP
    python tools/scan_and_index.py --config <ini> --index-output <json>
"""
import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DOWNLOAD_DIR = PROJECT_ROOT / "download_data"
for _p in (str(PROJECT_ROOT), str(DOWNLOAD_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from check_exist_files import load_config, load_schema, scan  # noqa: E402
from get_download_files import write_index  # noqa: E402


def main(argv=None):
    parser = argparse.ArgumentParser(description="扫描本地 MAVEN 文件并刷新索引。")
    parser.add_argument("--config", default=None, help="配置文件路径（默认 download_data/MAVEN_download_config.ini）")
    parser.add_argument("--index-output", default=None, help="索引输出路径（默认 MAVEN_data/filename_lists.json）")
    parser.add_argument("--models", nargs="*", default=None, help="要扫描的产品列表；缺省为全部注册产品")
    args = parser.parse_args(argv)

    config_data = load_config(args.config)
    save_dir = config_data['DEFAULT']['Save_dir']
    full_model = load_schema()["data_model"]

    if args.models:
        unknown = [m for m in args.models if m not in full_model]
        if unknown:
            print("[warn] ignore unknown products: " + repr(unknown))
        selected = {m: full_model[m] for m in args.models if m in full_model}
    else:
        selected = full_model

    scan(save_dir, selected)
    index_path = write_index(save_dir, output_path=args.index_output)
    print("index updated: " + str(index_path))
    return index_path


if __name__ == "__main__":
    main()
