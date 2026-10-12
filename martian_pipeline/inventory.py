"""inventory：本地文件扫描（薄封装 download_data/check_exist_files.py）。"""
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _p in (_ROOT, os.path.join(_ROOT, "download_data")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from download_data.check_exist_files import (  # noqa: E402
    load_config,
    load_schema,
    download_model,
    search_downloaded_files,
    scan,
)

__all__ = [
    "load_config",
    "load_schema",
    "download_model",
    "search_downloaded_files",
    "scan",
]
