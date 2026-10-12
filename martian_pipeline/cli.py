"""martian_pipeline 统一 CLI。

用法：
    python -m martian_pipeline scan [--config INI] [--index-output JSON] [--models M ...]
    python -m martian_pipeline manifest [--config INI] [--index-output JSON]
    python -m martian_pipeline migrate [--input INI] [--output TOML] [--apply] [--force]
"""
import argparse
import sys

from . import inventory, manifest


def _cmd_scan(args):
    """扫描本地文件并刷新索引（scan -> manifest）。返回索引路径。"""
    config_data = inventory.load_config(args.config)
    save_dir = config_data['DEFAULT']['Save_dir']
    full_model = inventory.load_schema()["data_model"]
    if args.models:
        unknown = [m for m in args.models if m not in full_model]
        if unknown:
            print("[warn] ignore unknown products: " + repr(unknown))
        selected = {m: full_model[m] for m in args.models if m in full_model}
    else:
        selected = full_model
    inventory.scan(save_dir, selected)
    index_path = manifest.write_index(save_dir, output_path=args.index_output)
    print("index updated: " + str(index_path))
    return index_path


def _cmd_manifest(args):
    """仅汇总 lists/ 写索引。返回索引路径。"""
    config_data = manifest.load_config(args.config)
    save_dir = config_data['DEFAULT']['Save_dir']
    index_path = manifest.write_index(save_dir, output_path=args.index_output)
    print("index updated: " + str(index_path))
    return index_path


def _cmd_migrate(args):
    """INI -> TOML 一次性迁移。"""
    from tools.migrate_config import main as migrate_main

    argv = []
    if args.input:
        argv += ["--input", args.input]
    if args.output:
        argv += ["--output", args.output]
    if args.apply:
        argv.append("--apply")
    if args.force:
        argv.append("--force")
    return migrate_main(argv)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="martian_pipeline",
        description="MAVEN/TW/MGS 数据下载与索引工具链 CLI",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("scan", help="扫描本地文件并刷新索引（scan -> manifest）")
    p.add_argument("--config", default=None, help="配置文件路径")
    p.add_argument("--index-output", default=None, help="索引输出路径")
    p.add_argument("--models", nargs="*", default=None, help="要扫描的产品列表")

    p = sub.add_parser("manifest", help="仅汇总 lists/ 写索引")
    p.add_argument("--config", default=None)
    p.add_argument("--index-output", default=None)

    p = sub.add_parser("migrate", help="INI -> TOML 一次性迁移")
    p.add_argument("--input", default=None)
    p.add_argument("--output", default=None)
    p.add_argument("--apply", action="store_true", help="实际写入（默认 dry-run）")
    p.add_argument("--force", action="store_true", help="覆盖已存在输出（仅配合 --apply）")

    args = parser.parse_args(argv)

    if args.cmd == "scan":
        return _cmd_scan(args)
    if args.cmd == "manifest":
        return _cmd_manifest(args)
    if args.cmd == "migrate":
        return _cmd_migrate(args)
    parser.error("unknown command: " + args.cmd)


if __name__ == "__main__":
    main()
