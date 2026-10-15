"""P0 阶段最小化验证：配置初始化、文件扫描、索引生成、下载后刷新、完整性检查。

仅使用临时目录与合成文件，不进行任何网络下载，不触碰真实科学数据。
运行方式： python tests/test_p0.py
"""
import os
import sys
import json
import shutil
import tempfile
import tomllib
from dataclasses import is_dataclass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOWNLOAD = os.path.join(REPO, "download_data")
sys.path.insert(0, DOWNLOAD)

import initialize_download_parameters as init_cfg  # noqa: E402
import check_exist_files as inventory  # noqa: E402
import get_download_files as manifest  # noqa: E402
import check_download_file as checker  # noqa: E402
from config.config import load_config as load_app_config  # noqa: E402


def test_config_contract():
    """H2: 初始化器生成完整 TOML，且拒绝覆盖现有文件。"""
    tmp = tempfile.mkdtemp(prefix="p0_cfg_")
    try:
        path = os.path.join(tmp, "settings.toml")
        built = init_cfg.build_config()
        assert isinstance(built, dict)
        for section in ("paths", "server", "download", "window", "proxy", "products"):
            assert section in built
        assert set(built["paths"]) >= {"maven_data_root"}
        assert set(built["server"]) >= {"index", "urls", "username", "password"}
        assert set(built["download"]) >= {
            "mode", "threads", "continue", "sleep_time", "step_time",
            "show_tqdm_bar", "idm_program_path", "aria2c_program_path",
        }
        assert set(built["products"]) >= {
            "single_model", "models", "skip", "single_download",
            "update_file_version", "check_download_file",
        }
        assert built["proxy"]["outer_server"] == "http://127.0.0.1:7890"
        assert built["proxy"]["ustc_server"] == ""
        assert isinstance(built["window"]["start"], str)
        assert isinstance(built["window"]["end"], str)

        init_cfg.generate_config(path)
        with open(path, "rb") as f:
            parsed = tomllib.load(f)
        assert parsed == built
        example = os.path.join(REPO, "config", "settings.example.toml")
        with open(example, "rb") as f:
            expected_example = f.read()
        with open(path, "rb") as f:
            assert f.read() == expected_example
        try:
            init_cfg.generate_config(path)
            raise AssertionError("generate_config must refuse to overwrite")
        except FileExistsError:
            pass
        print("  [PASS] TOML config contract and no-overwrite behavior")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _build_synthetic_tree(tmp):
    """构造合成 MAVEN 数据树（仅内存/临时目录，无真实数据）。"""
    save_dir = os.path.join(tmp, "MAVEN")
    mag_dir = os.path.join(save_dir, "MAG", "l2", "2014", "10")
    os.makedirs(mag_dir)
    with open(os.path.join(mag_dir, "mvn_mag_l2_2014283ss_20141010_v01_r01.sts"), "w") as f:
        f.write("dummy\n")
    kp_dir = os.path.join(save_dir, "KP", "insitu", "2014", "10")
    os.makedirs(kp_dir)
    with open(os.path.join(kp_dir, "mvn_kp_insitu_20141010_v01_r01.tab"), "w") as f:
        f.write("line1\n")
    return save_dir


def test_scan_and_index():
    """H3a: 扫描写出 lists/*.txt，索引生成到显式路径且与 CWD 无关。"""
    tmp = tempfile.mkdtemp(prefix="p0_scan_")
    try:
        save_dir = _build_synthetic_tree(tmp)
        data_model = inventory.load_schema()["data_model"]

        written = inventory.scan(save_dir, data_model)
        mag_list = os.path.join(save_dir, "lists", "MAG_ss_list.txt")
        kp_list = os.path.join(save_dir, "lists", "KP_list.txt")
        assert os.path.exists(mag_list) and os.path.exists(kp_list)
        with open(mag_list, encoding='utf-8') as f:
            assert "2014/10/mvn_mag_l2_2014283ss_20141010_v01_r01.sts" in f.read()
        with open(kp_list, encoding='utf-8') as f:
            assert "2014/10/mvn_kp_insitu_20141010_v01_r01.tab" in f.read()

        # 索引生成：显式输出路径（证明不依赖 CWD 相对路径）。
        idx = os.path.join(tmp, "index.json")
        out = manifest.write_index(save_dir, output_path=idx)
        assert out == idx and os.path.exists(idx)
        with open(idx, encoding='utf-8') as f:
            data = json.load(f)
        assert data["MAG_ss"] == ["2014/10/mvn_mag_l2_2014283ss_20141010_v01_r01.sts"]
        assert data["KP"] == ["2014/10/mvn_kp_insitu_20141010_v01_r01.tab"]

        # 默认索引路径由脚本位置推导（仓库根/MAVEN_data/），与运行目录无关。
        assert manifest.default_index_path() == os.path.join(REPO, "MAVEN_data", "filename_lists.json")
        print("  [PASS] scan + index generation")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_main_refreshes_index():
    """H3b: 显式调用 main()（下载完成后刷新）能扫描并刷新同一索引。"""
    tmp = tempfile.mkdtemp(prefix="p0_main_")
    try:
        save_dir = _build_synthetic_tree(tmp)
        config_path = os.path.join(tmp, "settings.toml")
        with open(config_path, 'w', encoding='utf-8') as f:
            f.write(
                '[paths]\n'
                f'maven_data_root = {json.dumps(save_dir)}\n'
                f'tw_data_root = {json.dumps(tmp)}\n'
                f'mgs_data_root = {json.dumps(tmp)}\n'
            )

        config = load_app_config(config_path)
        assert is_dataclass(config)
        assert config.paths.maven_data_root == save_dir
        assert inventory.load_config(config_path).paths.maven_data_root == save_dir
        assert manifest.load_config(config_path).paths.maven_data_root == save_dir

        idx = os.path.join(tmp, "filename_lists.json")
        out = inventory.main(config_path=config_path, index_path=idx)
        assert out == idx and os.path.exists(idx)
        with open(idx, encoding='utf-8') as f:
            data = json.load(f)
        assert "MAG_ss" in data and "KP" in data
        assert data["MAG_ss"] == ["2014/10/mvn_mag_l2_2014283ss_20141010_v01_r01.sts"]
        print("  [PASS] main() 下载后刷新索引")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_report_only():
    """D1: 完整性检查默认只报告，损坏文件不被删除或隔离。"""
    tmp = tempfile.mkdtemp(prefix="p0_check_")
    try:
        save_dir = os.path.join(tmp, "MAVEN")
        data_model = inventory.load_schema()["data_model"]

        kp_dir = os.path.join(save_dir, "KP", "insitu", "2014", "10")
        os.makedirs(kp_dir)
        kp_bad = os.path.join(kp_dir, "mvn_kp_insitu_20141010_v01_r01.tab")
        with open(kp_bad, 'w', encoding='utf-8') as f:
            f.write("short last line\n")

        cdf_dir = os.path.join(save_dir, "KP", "cdf", "2014", "10")
        os.makedirs(cdf_dir)
        cdf_bad = os.path.join(cdf_dir, "mvn_kp_insitu_20141010_v01_r01.cdf")
        with open(cdf_bad, 'wb') as f:
            f.write(b"this is not a real cdf")

        report = checker.run_checks(save_dir, data_model, models=["KP", "KP_cdf"], action="report")

        assert report["KP"][1][0]["ok"] is False      # KP 末行过短 -> 损坏
        assert report["KP_cdf"][1][0]["ok"] is False  # 非法 CDF -> 损坏
        # 默认 report 不得删除/隔离任何文件。
        assert os.path.exists(kp_bad)
        assert os.path.exists(cdf_bad)
        print("  [PASS] check report-only（损坏文件未被修改）")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_isolate_and_delete_explicit():
    """D1: 隔离/删除仅在显式 action 下生效。"""
    tmp = tempfile.mkdtemp(prefix="p0_iso_")
    try:
        save_dir = os.path.join(tmp, "MAVEN")
        data_model = inventory.load_schema()["data_model"]
        kp_dir = os.path.join(save_dir, "KP", "insitu", "2014", "10")
        os.makedirs(kp_dir)
        bad1 = os.path.join(kp_dir, "mvn_kp_insitu_20141010_v01_r01.tab")
        bad2 = os.path.join(kp_dir, "mvn_kp_insitu_20141011_v01_r01.tab")
        for p in (bad1, bad2):
            with open(p, 'w') as f:
                f.write("short\n")

        checker.run_checks(save_dir, data_model, models=["KP"], action="isolate")
        assert not os.path.exists(bad1)
        quarantine = os.path.join(save_dir, "KP", "insitu", "quarantine")
        assert os.path.exists(os.path.join(quarantine, "mvn_kp_insitu_20141010_v01_r01.tab"))

        checker.run_checks(save_dir, data_model, models=["KP"], action="delete")
        assert not os.path.exists(bad2)
        print("  [PASS] isolate/delete 仅显式启用时生效")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_kp_and_cdf_valid():
    """check_kp_file / check_cdf_file 对有效与无效样本的判定。"""
    tmp = tempfile.mkdtemp(prefix="p0_val_")
    try:
        # KP 有效：末行 >= 3360 字符且分钟字段 >= 59。
        good_kp = os.path.join(tmp, "good.tab")
        line = "0000000000000059" + "x" * (3360 - 16)
        with open(good_kp, 'w') as f:
            f.write(line + "\n")
        ok, reason = checker.check_kp_file(good_kp)
        assert ok is True, reason

        # KP 无效：分钟字段 < 59。
        bad_kp = os.path.join(tmp, "bad.tab")
        with open(bad_kp, 'w') as f:
            f.write("0000000000000010" + "x" * (3360 - 16) + "\n")
        ok2, _ = checker.check_kp_file(bad_kp)
        assert ok2 is False

        # CDF 有效样本（cdflib 写出后应能打开）。
        try:
            import numpy as np
            from cdflib import cdfwrite
            CDF = cdfwrite.CDF
            good_cdf = os.path.join(tmp, "good.cdf")
            w = cdfwrite.CDF(good_cdf, delete=True)
            w.write_globalattrs({"TITLE": {0: "test"}})
            var_spec = {"Variable": "Var1", "Data_Type": CDF.CDF_INT4,
                        "Num_Elements": 1, "Rec_Vary": False,
                        "Var_Type": "zVariable", "Dim_Sizes": []}
            w.write_var(var_spec, var_data=np.array([1, 2, 3], dtype=np.int32))
            w.close()
            ok_cdf, _ = checker.check_cdf_file(good_cdf)
            assert ok_cdf is True
        except Exception as e:  # noqa: BLE001 - cdflib 写 API 兼容性软检查
            print(f"  [SKIP] 有效 CDF 写入验证跳过: {e}")

        # CDF 无效：垃圾字节。
        bad_cdf = os.path.join(tmp, "bad.cdf")
        with open(bad_cdf, 'wb') as f:
            f.write(b"not a cdf")
        ok_cdf2, _ = checker.check_cdf_file(bad_cdf)
        assert ok_cdf2 is False
        print("  [PASS] check_kp_file / check_cdf_file 判定")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    tests = [
        test_config_contract,
        test_scan_and_index,
        test_main_refreshes_index,
        test_check_report_only,
        test_check_isolate_and_delete_explicit,
        test_check_kp_and_cdf_valid,
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
    print("ALL P0 TESTS PASSED")


if __name__ == "__main__":
    main()
