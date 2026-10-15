"""martian_pipeline 包化验证。"""
import os
import sys
import tempfile
import shutil
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

import martian_pipeline as mp  # noqa: E402
from martian_pipeline import cli  # noqa: E402


def test_import_public_api():
    assert callable(mp.scan)
    assert callable(mp.write_index)
    assert callable(mp.load_index)
    assert callable(mp.resolve_output_product)
    assert callable(mp.load_config)
    assert mp.project_root() == REPO
    assert str(mp.index_path()).endswith("MAVEN_data" + os.sep + "filename_lists.json")
    print("  [PASS] import public API")


def _make_toml_and_tree(tmp):
    save_dir = os.path.join(tmp, "MAVEN")
    os.makedirs(os.path.join(save_dir, "KP", "insitu", "2014", "10"))
    with open(os.path.join(save_dir, "KP", "insitu", "2014", "10", "mvn_kp_insitu_20141010_v01_r01.tab"), "w") as f:
        f.write("x\n")
    config_path = os.path.join(tmp, "settings.toml")
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(
            '[paths]\n'
            f'maven_data_root = {json.dumps(save_dir)}\n'
            f'tw_data_root = {json.dumps(tmp)}\n'
            f'mgs_data_root = {json.dumps(tmp)}\n'
        )
    return config_path


def test_cli_scan_e2e():
    tmp = tempfile.mkdtemp(prefix="mp_pkg_")
    try:
        config_path = _make_toml_and_tree(tmp)
        out = os.path.join(tmp, "index.json")
        idx = cli.main(["scan", "--config", config_path, "--index-output", out, "--models", "KP"])
        assert idx is not None and os.path.exists(out)
        data = json.load(open(out, encoding="utf-8"))
        assert data["KP"] == ["2014/10/mvn_kp_insitu_20141010_v01_r01.tab"]
        assert data["schema_version"] == 2
        print("  [PASS] cli scan e2e")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    tests = [test_import_public_api, test_cli_scan_e2e]
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
    print("ALL PACKAGE TESTS PASSED")


if __name__ == "__main__":
    main()
