"""P3 阶段验证：索引 v2 元数据写入与向后兼容读取。

仅使用临时目录与合成文件，不进行任何网络下载，不触碰真实科学数据。
运行方式： python tests/test_p3.py
"""
import os
import re
import sys
import json
import shutil
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOWNLOAD = os.path.join(REPO, "download_data")
sys.path.insert(0, REPO)
sys.path.insert(0, DOWNLOAD)

from get_download_files import write_index, load_index, default_index_path  # noqa: E402
from check_exist_files import load_schema  # noqa: E402
from config.paths import resolve_output_product  # noqa: E402


def test_index_v2_metadata():
    """write_index 输出的 JSON 含 schema_version==2、generated_at 字符串，且产品键正确。"""
    tmp = tempfile.mkdtemp(prefix="p3_v2write_")
    try:
        save_dir = os.path.join(tmp, "save")
        lists_dir = os.path.join(save_dir, "lists")
        os.makedirs(lists_dir)
        with open(os.path.join(lists_dir, "MAG_ss_list.txt"), 'w', encoding='utf-8') as f:
            f.write("2014/10/x.sts\n")

        idx = os.path.join(tmp, "filename_lists.json")
        out = write_index(save_dir, output_path=idx)
        assert out == idx and os.path.exists(idx)

        with open(idx, encoding='utf-8') as f:
            data = json.load(f)
        assert data["schema_version"] == 2
        assert isinstance(data["generated_at"], str) and len(data["generated_at"]) > 0
        assert data["MAG_ss"] == ["2014/10/x.sts"]
        print("  [PASS] test_index_v2_metadata")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_load_index_v2():
    """load_index 对 v2 索引返回 (metadata, products)，metadata 含版本与时间戳，products 不含元数据键。"""
    tmp = tempfile.mkdtemp(prefix="p3_v2load_")
    try:
        save_dir = os.path.join(tmp, "save")
        lists_dir = os.path.join(save_dir, "lists")
        os.makedirs(lists_dir)
        with open(os.path.join(lists_dir, "MAG_ss_list.txt"), 'w', encoding='utf-8') as f:
            f.write("2014/10/x.sts\n")

        idx = os.path.join(tmp, "filename_lists.json")
        write_index(save_dir, output_path=idx)

        metadata, products = load_index(idx)
        assert metadata["schema_version"] == 2
        assert "generated_at" in metadata and isinstance(metadata["generated_at"], str)
        assert products == {"MAG_ss": ["2014/10/x.sts"]}
        assert "schema_version" not in products
        assert "generated_at" not in products
        print("  [PASS] test_load_index_v2")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_load_index_legacy():
    """load_index 对旧版扁平 JSON（无元数据）返回空 metadata 与完整 products。"""
    tmp = tempfile.mkdtemp(prefix="p3_legacy_")
    try:
        idx = os.path.join(tmp, "legacy.json")
        with open(idx, 'w', encoding='utf-8') as f:
            json.dump({"KP": ["a"]}, f)

        metadata, products = load_index(idx)
        assert metadata == {}
        assert products == {"KP": ["a"]}
        print("  [PASS] test_load_index_legacy")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_resolve_output_product_mag():
    """MAG_ss 应解析到派生产品 MAG_ss_cdf，且其正则能匹配合成 CDF 文件名。"""
    dm = load_schema()["data_model"]
    pid, pdir, regex = resolve_output_product("MAG_ss", dm)
    assert (pid, pdir) == ("MAG_ss_cdf", "MAG/l3/")
    assert regex == dm["MAG_ss_cdf"][1]
    assert re.match(regex, "mvn_mag_l2_2014283ss_20141010_v01_r01.cdf")
    print("  [PASS] test_resolve_output_product_mag")


def test_resolve_output_product_kp():
    """KP 应解析到派生产品 KP_cdf 及其注册子目录与正则。"""
    dm = load_schema()["data_model"]
    pid, pdir, regex = resolve_output_product("KP", dm)
    assert (pid, pdir) == ("KP_cdf", "KP/cdf/")
    assert regex == dm["KP_cdf"][1]
    print("  [PASS] test_resolve_output_product_kp")


def test_resolve_output_product_unknown():
    """不存在的产品 id 应抛 KeyError。"""
    dm = load_schema()["data_model"]
    try:
        resolve_output_product("NOPE", dm)
        raise AssertionError("expected KeyError for unknown product NOPE")
    except KeyError:
        pass
    print("  [PASS] test_resolve_output_product_unknown")


def main():
    tests = [
        test_index_v2_metadata,
        test_load_index_v2,
        test_load_index_legacy,
        test_resolve_output_product_mag,
        test_resolve_output_product_kp,
        test_resolve_output_product_unknown,
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
    print("ALL P3 TESTS PASSED")


if __name__ == "__main__":
    main()
