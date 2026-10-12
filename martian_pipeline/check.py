"""check：文件完整性检查（薄封装 download_data/check_download_file.py）。"""
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _p in (_ROOT, os.path.join(_ROOT, "download_data")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import check_download_file as _check  # noqa: E402

run_checks = _check.run_checks
load_config = _check.load_config
load_schema = _check.load_schema
main = _check.main

__all__ = ["run_checks", "load_config", "load_schema", "main"]
