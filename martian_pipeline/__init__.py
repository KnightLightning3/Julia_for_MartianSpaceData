"""martian_pipeline：MAVEN/TW/MGS 数据下载与索引工具链的包化入口。

对既有函数化模块（config/、download_data/）的薄封装/再导出，
提供统一公共 API 与 `python -m martian_pipeline <子命令>` CLI。
旧脚本（python download_data/xxx.py）仍可独立运行。
"""
from config.config import load_config, Config, Paths, Server, Download, Window, DEFAULTS
from config.paths import (
    project_root,
    config_dir,
    index_path,
    lists_dir,
    data_root,
    product_dir,
    resolve_output_product,
)
from config.utils import get_list_from_ini, read_last_line_large_file
from .inventory import scan, load_schema, download_model, search_downloaded_files
from .manifest import write_index, load_index, default_index_path

__all__ = [
    # config
    "load_config", "Config", "Paths", "Server", "Download", "Window", "DEFAULTS",
    # paths
    "project_root", "config_dir", "index_path", "lists_dir", "data_root",
    "product_dir", "resolve_output_product",
    # utils
    "get_list_from_ini", "read_last_line_large_file",
    # inventory
    "scan", "load_schema", "download_model", "search_downloaded_files",
    # manifest
    "write_index", "load_index", "default_index_path",
]
