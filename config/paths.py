"""路径解析模块（P1）：所有路径由脚本自身位置推导，与运行时 CWD 无关。"""
from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from config.config import Config

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def project_root() -> Path:
    """Return the repository root directory."""
    return PROJECT_ROOT


def config_dir() -> Path:
    """Return the config/ directory under project root."""
    return PROJECT_ROOT / "config"


def index_path() -> Path:
    """Return the default MAVEN filename-lists index path."""
    return PROJECT_ROOT / "MAVEN_data" / "filename_lists.json"


def lists_dir(data_root: str | Path) -> Path:
    """Return the lists/ subdirectory under a given data root."""
    return Path(data_root) / "lists"


def data_root(kind: str, config: Config | None = None) -> Path:
    """Return the data root for a mission kind ('maven', 'tw', 'mgs').

    Parameters
    ----------
    kind : one of "maven", "tw", "mgs" (case-insensitive).
    config : optional pre-loaded Config; if None, load_config() is called.

    Raises
    ------
    ValueError : if kind is not recognized.
    """
    k = kind.strip().lower()
    mapping = {
        "maven": "maven_data_root",
        "tw": "tw_data_root",
        "mgs": "mgs_data_root",
    }
    attr = mapping.get(k)
    if attr is None:
        raise ValueError(
            f"Unknown data-root kind {kind!r}; expected one of {list(mapping)}"
        )
    if config is None:
        from config.config import load_config
        config = load_config()
    return Path(getattr(config.paths, attr))


def product_dir(product_id: str, data_root: str | Path, data_model: dict) -> Path:
    """Return the product subdirectory for a given product_id.

    Parameters
    ----------
    product_id : key into data_model registry.
    data_root : mission data root path.
    data_model : dict from MAVEN_data_format.json ``data_model`` section;
                 value[2] is the relative product sub-path (e.g. "KP/cdf/").
    """
    sub = data_model[product_id][2]
    return Path(data_root) / sub
