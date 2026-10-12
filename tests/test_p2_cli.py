"""P2 阶段 CLI 与扫描/索引契约测试。

仅使用临时目录与合成文件，不进行任何网络下载，不触碰真实科学数据。
运行方式： python tests/test_p2_cli.py
"""
import os
import sys
import json
import shutil
import tempfile
import configparser
import importlib.util

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOWNLOAD = os.path.join(REPO, "download_data")
TOOLS = os.path.join(REPO, "tools")

for _p in (REPO, DOWNLOAD, TOOLS):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import check_exist_files as inventory  # noqa: E402
import get_download_files as manifest  # noqa: E402

# tools/ 不是包，用 importlib 直接加载 scan_and_index 模块。
_spec = importlib.util.spec_from_file_location(
    "scan_and_index", os.path.join(TOOLS, "scan_and_index.py")
)
scan_and_index = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scan_and_index)


def test_search_empty_dir():
    """空目录下 search_downloaded_files 返回 []。"""
    tmp = tempfile.mkdtemp(prefix="p2_empty_")
    try:
        save_path = os.path.join(tmp, "no_such_dir")
        result = inventory.search_downloaded_files(save_path, ".*")
        assert result == [], f"expected [], got {result!r}"
        print("  [PASS] test_search_empty_dir")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_search_regex_no_match():
    """年/月目录下有不匹配正则的文件时返回 []。"""
    tmp = tempfile.mkdtemp(prefix="p2_nomatch_")
    try:
        ym = os.path.join(tmp, "2014", "10")
        os.makedirs(ym)
        with open(os.path.join(ym, "unrelated_file.txt"), "w") as f:
            f.write("x\n")
        result = inventory.search_downloaded_files(tmp, r"^mvn_kp_insitu_.+\.tab$")
        assert result == [], f"expected [], got {result!r}"
        print("  [PASS] test_search_regex_no_match")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_search_path_separators():
    """返回路径必须使用正斜杠且不含反斜杠（跨平台契约）。"""
    tmp = tempfile.mkdtemp(prefix="p2_sep_")
    try:
        data_model = inventory.load_schema()["data_model"]
        mag_regex = data_model["MAG_ss"][1]
        mag_dir = os.path.join(tmp, "MAG", "l2", "2014", "10")
        os.makedirs(mag_dir)
        fname = "mvn_mag_l2_2014283ss_20141010_v01_r01.sts"
        with open(os.path.join(mag_dir, fname), "w") as f:
            f.write("dummy\n")

        save_path = os.path.join(tmp, "MAG", "l2")
        result = inventory.search_downloaded_files(save_path, mag_regex)
        assert len(result) == 1, f"expected 1 match, got {result!r}"
        rel = result[0]
        assert "\\" not in rel, f"path contains backslash: {rel!r}"
        expected = f"2014/10/{fname}"
        assert rel == expected, f"expected {expected!r}, got {rel!r}"
        print("  [PASS] test_search_path_separators")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_scan_empty_and_index():
    """最小 data_model 扫描空目录后索引可解析且对应键为空列表。"""
    tmp = tempfile.mkdtemp(prefix="p2_scan_empty_")
    try:
        save_dir = os.path.join(tmp, "MAVEN")
        os.makedirs(save_dir)
        minimal_model = {
            "KP_cdf": [
                ["KP/cdf/", "None", "None"],
                "^mvn_kp_insitu_.+\\.cdf$",
                "KP/cdf/",
                "load_cdf",
                "",
            ]
        }
        inventory.scan(save_dir, minimal_model)
        out_json = os.path.join(tmp, "index.json")
        manifest.write_index(save_dir, output_path=out_json)
        assert os.path.exists(out_json), "index json not written"
        with open(out_json, encoding="utf-8") as f:
            data = json.load(f)
        assert "KP_cdf" in data, f"KP_cdf key missing: {list(data.keys())}"
        assert data["KP_cdf"] == [], f"expected [], got {data['KP_cdf']!r}"
        print("  [PASS] test_scan_empty_and_index")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_cli_end_to_end():
    """CLI main() 端到端：临时 INI + 合成 KP 文件 + 未知产品被忽略。"""
    tmp = tempfile.mkdtemp(prefix="p2_cli_")
    try:
        save_dir = os.path.join(tmp, "MAVEN")
        kp_dir = os.path.join(save_dir, "KP", "insitu", "2014", "10")
        os.makedirs(kp_dir)
        fname = "mvn_kp_insitu_20141010_v01_r01.tab"
        with open(os.path.join(kp_dir, fname), "w") as f:
            f.write("line1\n")

        ini = os.path.join(tmp, "MAVEN_download_config.ini")
        cfg = configparser.ConfigParser()
        cfg.optionxform = str
        cfg["DEFAULT"] = {"Save_dir": save_dir}
        with open(ini, "w", encoding="utf-8") as f:
            cfg.write(f)

        out_json = os.path.join(tmp, "filename_lists.json")
        ret = scan_and_index.main([
            "--config", ini,
            "--index-output", out_json,
            "--models", "KP", "NotExist",
        ])
        assert ret == out_json, f"main returned {ret!r}, expected {out_json!r}"
        assert os.path.exists(out_json), "output index missing"
        with open(out_json, encoding="utf-8") as f:
            data = json.load(f)
        assert "KP" in data, f"KP key missing: {list(data.keys())}"
        expected_entry = f"2014/10/{fname}"
        assert expected_entry in data["KP"], f"{expected_entry!r} not in {data['KP']!r}"
        assert "NotExist" not in data, f"unknown product leaked into index: {list(data.keys())}"
        print("  [PASS] test_cli_end_to_end")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    tests = [
        test_search_empty_dir,
        test_search_regex_no_match,
        test_search_path_separators,
        test_scan_empty_and_index,
        test_cli_end_to_end,
    ]
    failed = []
    for t in tests:
        try:
            t()
        except Exception as e:  # noqa: BLE001
            import traceback
            print(f"  [FAIL] {t.__name__}: {e}")
            traceback.print_exc()
            failed.append(t.__name__)
    print("\n==== SUMMARY ====")
    print(f"PASS {len(tests) - len(failed)} / {len(tests)}")
    if failed:
        print("FAILED:", failed)
        sys.exit(1)
    print("ALL P2 TESTS PASSED")


if __name__ == "__main__":
    main()
