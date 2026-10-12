# 独立的文件完整性检查入口（P0，决策 D1）。
#
# 默认只报告校验结果（CDF / KP 完整性），不删除、不隔离、不修改任何文件。
# 隔离或删除等破坏性操作必须通过 --action 显式启用，默认值为 report。
#
# 用法示例：
#     python download_data/check_download_file.py                    # 报告全部模型的检查结果
#     python download_data/check_download_file.py --models KP KP_cdf
#     python download_data/check_download_file.py --action isolate    # 显式启用：隔离损坏文件
#     python download_data/check_download_file.py --action delete     # 显式启用：删除损坏文件
import argparse
import os
import shutil

from check_exist_files import download_model, search_downloaded_files, load_config, load_schema


def read_last_line_large_file(filename):
    """从文件末尾分块读取最后一行，避免载入整个大文件。"""
    with open(filename, 'r', encoding='utf-8') as f:
        f.seek(0, 2)
        file_size = f.tell()
        block = 10240
        last_line = ''
        for pos in range(file_size, 0, -block):
            if pos < block:
                f.seek(0)
            else:
                f.seek(pos - block)
            data = f.read(min(block, pos))
            if '\n' in data:
                last_line = data.splitlines()[-1]
                break
        else:
            f.seek(0)
            last_line = f.read()
    return last_line


def check_cdf_file(path):
    """用 cdflib 打开文件校验其是否为合法 CDF。返回 (ok, reason)。"""
    try:
        from cdflib import cdfread
        cdfread.CDF(path)
        return True, ""
    except Exception as e:  # noqa: BLE001 - 校验失败的具体原因原样上报
        return False, str(e)


def check_kp_file(path):
    """按 KP 文本文件的末行长度与分钟字段校验完整性。返回 (ok, reason)。"""
    last_line = read_last_line_large_file(path)
    if len(last_line) < 3360:
        return False, f"末行长度 {len(last_line)} < 3360"
    try:
        minute = int(last_line[14:16])
    except (ValueError, IndexError) as e:
        return False, f"无法解析分钟字段: {e}"
    if minute < 59:
        return False, f"分钟字段 {minute} < 59"
    return True, ""


def _kind_for(model, filename):
    """根据模型与文件名推断检查类型；返回 'cdf' / 'kp' / None(不支持)。"""
    if filename.endswith(".cdf"):
        return "cdf"
    if model == "KP":
        return "kp"
    return None


def check_model(model, save_dir, data_model):
    """扫描单个模型的本地文件并逐文件校验。返回 (save_path, results)。

    该函数只读文件，不做任何修改或删除。
    """
    save_path, file_style = download_model(model, save_dir, data_model)
    results = []
    for rel in search_downloaded_files(save_path, file_style):
        full = os.path.join(save_path, rel.replace("/", os.sep))
        kind = _kind_for(model, rel)
        if kind is None:
            results.append({"file": rel, "kind": None, "ok": None, "reason": "unsupported"})
            continue
        if kind == "cdf":
            ok, reason = check_cdf_file(full)
        else:
            ok, reason = check_kp_file(full)
        results.append({"file": rel, "kind": kind, "ok": ok, "reason": reason})
    return save_path, results


def apply_action(save_path, results, action):
    """对校验失败的文件执行显式动作（isolate / delete）。返回更新后的 results。

    action 为 'report' 时不修改任何文件。
    """
    if action == "report":
        return results
    quarantine = os.path.join(save_path, "quarantine")
    for r in results:
        if r.get("ok") is False:
            full = os.path.join(save_path, r["file"].replace("/", os.sep))
            if action == "isolate":
                os.makedirs(quarantine, exist_ok=True)
                dest = os.path.join(quarantine, os.path.basename(r["file"]))
                shutil.move(full, dest)
                r["action"] = f"isolated -> {dest}"
            elif action == "delete":
                os.remove(full)
                r["action"] = "deleted"
    return results


def run_checks(save_dir, data_model, models=None, action="report"):
    """对指定模型（默认全部）执行检查，返回 {model: (save_path, results)}。"""
    if models is None:
        models = list(data_model.keys())
    report = {}
    for model in models:
        save_path, results = check_model(model, save_dir, data_model)
        results = apply_action(save_path, results, action)
        report[model] = (save_path, results)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="独立文件完整性检查（默认只报告，不修改文件）。"
    )
    parser.add_argument("--models", nargs="*", default=None,
                        help="要检查的模型列表；缺省为全部注册模型。")
    parser.add_argument("--action", choices=["report", "isolate", "delete"], default="report",
                        help="对损坏文件执行的动作；默认 report 仅报告。")
    parser.add_argument("--config", default=None,
                        help="配置文件路径；缺省为 download_data/MAVEN_download_config.ini。")
    args = parser.parse_args(argv)

    config_data = load_config(args.config)
    data_model = load_schema()["data_model"]
    save_dir = config_data['DEFAULT']['Save_dir']

    if args.action != "report":
        print(f"[!] 已显式启用动作: {args.action}（会修改/移动损坏文件）")
    report = run_checks(save_dir, data_model, models=args.models, action=args.action)

    for model, (save_path, results) in report.items():
        total = len(results)
        bad = [r for r in results if r.get("ok") is False]
        ok_count = sum(1 for r in results if r.get("ok") is True)
        skipped = sum(1 for r in results if r.get("ok") is None)
        print(f"\n[{model}] 目录: {save_path}  共 {total} 个文件: 有效 {ok_count} / 损坏 {len(bad)} / 跳过 {skipped}")
        for r in bad:
            print(f"  [损坏] {r['file']}  ({r['reason']})" + (f"  -> {r['action']}" if "action" in r else ""))
    return report


if __name__ == '__main__':
    main()
