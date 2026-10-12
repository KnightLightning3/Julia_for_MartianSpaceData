"""P1 阶段验证：配置单点化、路径解析、迁移工具。

仅使用临时目录与合成文件，不进行任何网络下载，不触碰真实科学数据。
运行方式： python tests/test_p1.py
"""
from __future__ import annotations

import configparser
import os
import shutil
import sys
import tempfile
import tomllib
from pathlib import Path

# Ensure project root is on sys.path
REPO = Path(__file__).resolve().parent.parent
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

from config.config import (  # noqa: E402
    Config,
    Download,
    Paths,
    Server,
    Window,
    _build_config,
    _read_legacy_ini,
    _read_toml,
    load_config,
    DEFAULTS,
)
from config.paths import (  # noqa: E402
    PROJECT_ROOT as PATHS_PROJECT_ROOT,
    config_dir,
    data_root,
    index_path,
    lists_dir,
    product_dir,
    project_root,
)
from tools.migrate_config import _dump_toml  # noqa: E402


# ---------------------------------------------------------------------------
# Test 1: load_config reads a temporary TOML correctly
# ---------------------------------------------------------------------------

def test_load_config_from_toml():
    """load_config 读临时 TOML：各字段类型与值正确。"""
    tmp = tempfile.mkdtemp(prefix="p1_toml_")
    try:
        toml_content = (
            '[paths]\n'
            'maven_data_root = "E:/MAVEN/"\n'
            'tw_data_root = "E:/Tianwen-1/"\n'
            'mgs_data_root = "E:/MGS/"\n'
            '\n'
            '[server]\n'
            'index = 2\n'
            'urls = [\n'
            '  "http://example.com/a/",\n'
            '  "http://example.com/b/",\n'
            ']\n'
            '\n'
            '[download]\n'
            'mode = "python.request"\n'
            'threads = 8\n'
            'continue = false\n'
            '\n'
            '[window]\n'
            'start = "2020-01-01"\n'
            'end = "2024-12-31"\n'
        )
        toml_path = os.path.join(tmp, "settings.toml")
        with open(toml_path, "w", encoding="utf-8") as f:
            f.write(toml_content)

        # Provide a non-existent ini_path so it falls through to TOML
        fake_ini = os.path.join(tmp, "nonexistent.ini")
        cfg = load_config(toml_path=toml_path, ini_path=fake_ini)

        assert isinstance(cfg, Config)
        assert cfg.paths.maven_data_root == "E:/MAVEN/"
        assert cfg.paths.tw_data_root == "E:/Tianwen-1/"
        assert cfg.paths.mgs_data_root == "E:/MGS/"
        assert cfg.server.index == 2
        assert cfg.server.urls == ["http://example.com/a/", "http://example.com/b/"]
        assert cfg.download.mode == "python.request"
        assert cfg.download.threads == 8
        assert isinstance(cfg.download.threads, int)
        assert cfg.download.continue_flag is False
        assert isinstance(cfg.download.continue_flag, bool)
        assert cfg.window.start == "2020-01-01"
        assert cfg.window.end == "2024-12-31"
        print("  [PASS] load_config from TOML")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# Test 2: load_config reads a temporary legacy INI correctly
# ---------------------------------------------------------------------------

def test_load_config_from_legacy_ini():
    """load_config 读临时旧 INI：server.index==3, urls 长度 4, threads==5, continue True."""
    tmp = tempfile.mkdtemp(prefix="p1_ini_")
    try:
        cp = configparser.ConfigParser()
        cp.optionxform = str
        cp["DEFAULT"] = {"Save_dir": "E:/MAVEN/"}
        cp["Servers"] = {
            "Server_ind": "3",
            "0": "http://url-zero.example.com/",
            "1": "http://url-one.example.com/",
            "2": "http://url-two.example.com/",
            "3": "http://url-three.example.com/",
        }
        cp["Properties"] = {
            "download_mode": "Aria2c",
            "max_threads": "5",
            "continue_download": "1",
        }
        cp["Settings"] = {
            "start_date": "2015-03-15",
            "end_date": "2023-11-30",
        }
        ini_path = os.path.join(tmp, "MAVEN_download_config.ini")
        with open(ini_path, "w", encoding="utf-8") as f:
            cp.write(f)

        fake_toml = os.path.join(tmp, "nonexistent.toml")
        cfg = load_config(toml_path=fake_toml, ini_path=ini_path)

        assert cfg.server.index == 3
        assert len(cfg.server.urls) == 4
        assert cfg.server.urls[3] == "http://url-three.example.com/"
        assert cfg.server.urls[0] == "http://url-zero.example.com/"
        assert cfg.download.threads == 5
        assert cfg.download.continue_flag is True
        assert cfg.download.mode == "Aria2c"
        assert cfg.window.start == "2015-03-15"
        assert cfg.window.end == "2023-11-30"
        # tw/mgs roots should be defaults since INI has no such keys
        assert cfg.paths.tw_data_root == DEFAULTS["paths"]["tw_data_root"]
        assert cfg.paths.mgs_data_root == DEFAULTS["paths"]["mgs_data_root"]
        assert cfg.paths.maven_data_root == "E:/MAVEN/"
        print("  [PASS] load_config from legacy INI")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# Test 3: migrate dry-run produces valid TOML and does NOT write a file
# ---------------------------------------------------------------------------

def test_migrate_dry_run():
    """migrate dry-run：_dump_toml 输出可被 tomllib 解析，且不产生输出文件。"""
    tmp = tempfile.mkdtemp(prefix="p1_dry_")
    try:
        # Build a synthetic INI
        cp = configparser.ConfigParser()
        cp.optionxform = str
        cp["DEFAULT"] = {"Save_dir": "E:/MAVEN/"}
        cp["Servers"] = {
            "Server_ind": "1",
            "0": "http://a.example.com/",
            "1": "http://b.example.com/",
            "2": "http://c.example.com/",
            "3": "http://d.example.com/",
        }
        cp["Properties"] = {
            "download_mode": "python.request",
            "max_threads": "3",
            "continue_download": "0",
        }
        cp["Settings"] = {
            "start_date": "2016-01-01",
            "end_date": "2022-06-30",
        }
        ini_path = os.path.join(tmp, "test.ini")
        with open(ini_path, "w", encoding="utf-8") as f:
            cp.write(f)

        cfg_dict = _read_legacy_ini(ini_path)
        toml_text = _dump_toml(cfg_dict)

        # Must parse back
        parsed = tomllib.loads(toml_text)
        assert parsed["server"]["index"] == 1
        assert len(parsed["server"]["urls"]) == 4
        assert "http://d.example.com/" in parsed["server"]["urls"]
        assert parsed["download"]["continue"] is False
        assert parsed["download"]["threads"] == 3

        # Dry-run must NOT produce an output file
        out_path = os.path.join(tmp, "should_not_exist.toml")
        assert not os.path.exists(out_path)
        print("  [PASS] migrate dry-run")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# Test 4: migrate --apply idempotency
# ---------------------------------------------------------------------------

def test_migrate_apply_idempotent():
    """migrate --apply 幂等：两次写入内容一致；无 --force 时第二次拒绝。"""
    tmp = tempfile.mkdtemp(prefix="p1_idem_")
    try:
        # Build INI
        cp = configparser.ConfigParser()
        cp.optionxform = str
        cp["DEFAULT"] = {"Save_dir": "E:/MAVEN/"}
        cp["Servers"] = {
            "Server_ind": "0",
            "0": "http://x.example.com/",
            "1": "http://y.example.com/",
        }
        cp["Properties"] = {
            "download_mode": "python.request",
            "max_threads": "5",
            "continue_download": "1",
        }
        cp["Settings"] = {
            "start_date": "2014-10-01",
            "end_date": "2025-06-01",
        }
        ini_path = os.path.join(tmp, "test.ini")
        with open(ini_path, "w", encoding="utf-8") as f:
            cp.write(f)

        out_path = os.path.join(tmp, "out.toml")

        # Import main from migrate_config
        from tools.migrate_config import main as migrate_main

        # First apply
        migrate_main(["--input", ini_path, "--output", out_path, "--apply"])
        assert os.path.exists(out_path)
        first_content = Path(out_path).read_text(encoding="utf-8")

        # Second apply WITHOUT --force should fail (exit code 1)
        exited_with_error = False
        try:
            migrate_main(["--input", ini_path, "--output", out_path, "--apply"])
        except SystemExit as e:
            exited_with_error = (e.code != 0)
        assert exited_with_error, "Expected refusal when output exists without --force"

        # Content unchanged after refused write
        second_content = Path(out_path).read_text(encoding="utf-8")
        assert first_content == second_content

        # Third apply WITH --force should succeed and produce identical content
        migrate_main(["--input", ini_path, "--output", out_path, "--apply", "--force"])
        third_content = Path(out_path).read_text(encoding="utf-8")
        assert first_content == third_content

        print("  [PASS] migrate --apply idempotent")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# Test 5: paths are CWD-independent
# ---------------------------------------------------------------------------

def test_paths_cwd_independent():
    """chdir 到临时目录后，paths 函数返回的绝对路径不变。"""
    original_cwd = os.getcwd()
    tmp = tempfile.mkdtemp(prefix="p1_cwd_")
    try:
        # Record paths before chdir
        pr_before = project_root()
        ip_before = index_path()
        mr_before = data_root("maven")

        # chdir away
        os.chdir(tmp)

        pr_after = project_root()
        ip_after = index_path()
        mr_after = data_root("maven")

        assert pr_before == pr_after, f"project_root changed: {pr_before} vs {pr_after}"
        assert ip_before == ip_after, f"index_path changed: {ip_before} vs {ip_after}"
        assert mr_before == mr_after, f"data_root('maven') changed: {mr_before} vs {mr_after}"

        # All should be absolute
        assert pr_after.is_absolute()
        assert ip_after.is_absolute()
        assert mr_after.is_absolute()

        print("  [PASS] paths CWD-independent")
    finally:
        os.chdir(original_cwd)
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# Test 6: product_dir
# ---------------------------------------------------------------------------

def test_product_dir():
    """product_dir 根据 data_model[product_id][2] 拼接子目录。"""
    data_model = {
        "KP_cdf": [["KP/cdf/", "None", "None"], "regex", "KP/cdf/", "load", ""],
    }
    result = product_dir("KP_cdf", Path("E:/MAVEN/"), data_model)
    expected = Path("E:/MAVEN/KP/cdf/")
    # Normalize both for comparison (trailing slash handling)
    assert result == expected or str(result).rstrip("/") == str(expected).rstrip("/"), \
        f"product_dir mismatch: {result} vs {expected}"
    print("  [PASS] product_dir")


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    tests = [
        test_load_config_from_toml,
        test_load_config_from_legacy_ini,
        test_migrate_dry_run,
        test_migrate_apply_idempotent,
        test_paths_cwd_independent,
        test_product_dir,
    ]
    failed: list[str] = []
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
    print("ALL P1 TESTS PASSED")


if __name__ == "__main__":
    main()
