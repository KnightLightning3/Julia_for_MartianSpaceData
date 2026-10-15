"""Julia/Python 共用的 TOML 配置；不再读取 INI，也不静默回退到默认目录。"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import date
import os
from pathlib import Path, PureWindowsPath
from typing import Any
import tomllib

PROJECT_ROOT = Path(__file__).resolve().parent.parent
TOML_PATH = PROJECT_ROOT / "config" / "settings.toml"
EXAMPLE_PATH = PROJECT_ROOT / "config" / "settings.example.toml"
with EXAMPLE_PATH.open("rb") as _file:
    DEFAULTS: dict[str, Any] = tomllib.load(_file)


@dataclass(frozen=True)
class Paths:
    maven_data_root: str
    tw_data_root: str
    mgs_data_root: str
    cdf_lib: str = ""
    fortran_dll_dir: str = ""


@dataclass(frozen=True)
class Server:
    index: int
    urls: list[str]
    username: str = ""
    password: str = ""


@dataclass(frozen=True)
class Proxy:
    outer_server: str
    ustc_server: str


@dataclass(frozen=True)
class Download:
    mode: str
    threads: int
    continue_flag: bool
    sleep_time: int
    step_time: int
    show_tqdm_bar: bool
    idm_program_path: str
    aria2c_program_path: str


@dataclass(frozen=True)
class Window:
    start: str
    end: str


@dataclass(frozen=True)
class Products:
    single_model: str
    models: list[str]
    skip: list[str]
    single_download: bool
    update_file_version: bool
    check_download_file: bool


@dataclass(frozen=True)
class Config:
    paths: Paths
    server: Server
    download: Download
    window: Window
    proxy: Proxy
    products: Products


def _resolve_path(value: str) -> str:
    """Resolve relative paths at the repository, preserving foreign Windows roots."""
    if not value:
        return value
    if PureWindowsPath(value).is_absolute() and not Path(value).is_absolute():
        return value
    path = Path(value)
    return os.path.normpath(path if path.is_absolute() else PROJECT_ROOT / path)


def _read_toml(path: str | Path) -> dict[str, Any]:
    with open(path, "rb") as file:
        return tomllib.load(file)


def _build_config(raw: dict[str, Any]) -> Config:
    """Validate types before constructing the shared configuration object."""
    if not isinstance(raw.get("paths"), dict):
        raise ValueError("Configuration requires a [paths] table")
    for key in ("maven_data_root", "tw_data_root", "mgs_data_root"):
        if key not in raw["paths"]:
            raise ValueError(f"Missing configuration key: paths.{key}")
    merged = deepcopy(DEFAULTS)
    for section, values in raw.items():
        if section not in DEFAULTS:
            raise ValueError(f"Unknown configuration table: {section}")
        if not isinstance(values, dict):
            raise ValueError(f"Configuration {section} must be a table")
        for key, value in values.items():
            if key not in DEFAULTS[section]:
                raise ValueError(f"Unknown configuration key: {section}.{key}")
            expected = DEFAULTS[section][key]
            if type(value) is not type(expected):
                raise ValueError(f"Configuration {section}.{key} must be {type(expected).__name__}")
            if isinstance(value, list) and not all(isinstance(x, str) and x.strip() for x in value):
                raise ValueError(f"Configuration {section}.{key} must contain nonempty strings")
            merged[section][key] = value
    p, s, dl, w, proxy, products = (
        merged[k] for k in ("paths", "server", "download", "window", "proxy", "products")
    )
    for key in ("maven_data_root", "tw_data_root", "mgs_data_root"):
        if not p[key].strip():
            raise ValueError(f"Configuration paths.{key} must not be empty")
    if not s["urls"] or not 0 <= s["index"] < len(s["urls"]):
        raise ValueError("Configuration server.index must select an entry in server.urls (0-based)")
    if dl["mode"] not in {"python.request", "win.idm", "Aria2c"}:
        raise ValueError("Configuration download.mode must be python.request, win.idm or Aria2c")
    if dl["threads"] < 1 or dl["sleep_time"] < 0 or dl["step_time"] < 0:
        raise ValueError("Configuration threads must be positive and wait times nonnegative")
    try:
        start, end = date.fromisoformat(w["start"]), date.fromisoformat(w["end"])
        if start.isoformat() != w["start"] or end.isoformat() != w["end"] or start > end:
            raise ValueError
    except ValueError as exc:
        raise ValueError("Configuration window requires YYYY-MM-DD strings with start <= end") from exc
    if products["single_download"] and not products["single_model"].strip():
        raise ValueError("Configuration products.single_model must not be empty in single mode")
    for key in p:
        p[key] = _resolve_path(p[key])
    for key in ("idm_program_path", "aria2c_program_path"):
        dl[key] = _resolve_path(dl[key])
    return Config(
        paths=Paths(**p), server=Server(**s), proxy=Proxy(**proxy),
        download=Download(continue_flag=dl["continue"], **{k: v for k, v in dl.items() if k != "continue"}),
        window=Window(**w), products=Products(**products),
    )


def load_config(toml_path: str | Path | None = None) -> Config:
    """Read settings.toml only; explicit paths never fall back to another file."""
    path = Path(toml_path) if toml_path is not None else TOML_PATH
    if path.suffix.lower() != ".toml":
        raise ValueError("INI is no longer supported; use config/settings.toml")
    if not path.is_file():
        raise FileNotFoundError(
            f"Configuration file not found: {path}. "
            "Run python download_data/initialize_download_parameters.py, then edit config/settings.toml."
        )
    return _build_config(_read_toml(path))
