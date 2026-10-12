"""manifest：索引清单读写（薄封装 download_data/get_download_files.py）。"""
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _p in (_ROOT, os.path.join(_ROOT, "download_data")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from download_data.get_download_files import (  # noqa: E402
    load_config,
    default_index_path,
    write_index,
    load_index,
)

__all__ = [
    "load_config",
    "default_index_path",
    "write_index",
    "load_index",
]
