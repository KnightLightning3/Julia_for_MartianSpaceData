"""配置加载模块（P1）：TOML 优先，旧 INI 只读兼容，DEFAULTS 兜底。"""
from __future__ import annotations

import configparser
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parent.parent
TOML_PATH = PROJECT_ROOT / "config" / "settings.toml"
LEGACY_INI_PATH = PROJECT_ROOT / "download_data" / "MAVEN_download_config.ini"


@dataclass(frozen=True)
class Paths:
    maven_data_root: str
    tw_data_root: str
    mgs_data_root: str


@dataclass(frozen=True)
class Server:
    index: int
    urls: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Download:
    mode: str
    threads: int
    continue_flag: bool  # corresponds to TOML key "continue" (Python keyword)


@dataclass(frozen=True)
class Window:
    start: str
    end: str


@dataclass(frozen=True)
class Config:
    paths: Paths
    server: Server
    download: Download
    window: Window


# --------------- DEFAULTS ---------------

DEFAULTS: dict[str, Any] = {
    "paths": {
        "maven_data_root": "E:/MAVEN/",
        "tw_data_root": "E:/Tianwen-1/",
        "mgs_data_root": "E:/MGS/",
    },
    "server": {
        "index": 0,
        "urls": [
            "http://222.195.76.155:8000/MAVEN/",
            "https://pds-ppi.igpp.ucla.edu/data/",
            "https://lasp.colorado.edu/maven/sdc/public/data/sci/",
        ],
    },
    "download": {
        "mode": "python.request",
        "threads": 5,
        "continue": True,
    },
    "window": {
        "start": "2014-10-01",
        "end": "2025-06-01",
    },
}


def _build_config(d: dict[str, Any]) -> Config:
    """Construct a Config from a normalized dict (keys match TOML structure)."""
    p = d["paths"]
    s = d["server"]
    dl = d["download"]
    w = d["window"]
    return Config(
        paths=Paths(
            maven_data_root=str(p["maven_data_root"]),
            tw_data_root=str(p["tw_data_root"]),
            mgs_data_root=str(p["mgs_data_root"]),
        ),
        server=Server(
            index=int(s["index"]),
            urls=[str(u) for u in s["urls"]],
        ),
        download=Download(
            mode=str(dl["mode"]),
            threads=int(dl["threads"]),
            continue_flag=bool(dl["continue"]),
        ),
        window=Window(
            start=str(w["start"]),
            end=str(w["end"]),
        ),
    )


# --------------- Readers ---------------

def _read_toml(path: str | Path) -> dict[str, Any]:
    """Read a TOML file and return its contents as a nested dict."""
    with open(path, "rb") as f:
        return tomllib.load(f)


def _read_legacy_ini(path: str | Path) -> dict[str, Any]:
    """Read the legacy MAVEN_download_config.ini and map to normalized dict."""
    cp = configparser.ConfigParser()
    cp.optionxform = str  # preserve case
    cp.read(str(path), encoding="utf-8")

    defaults = DEFAULTS

    # paths
    maven_root = (
        cp.get("DEFAULT", "Save_dir").strip()
        if cp.has_option("DEFAULT", "Save_dir")
        else defaults["paths"]["maven_data_root"]
    )
    paths_section = {
        "maven_data_root": maven_root,
        "tw_data_root": defaults["paths"]["tw_data_root"],
        "mgs_data_root": defaults["paths"]["mgs_data_root"],
    }

    # server
    server_ind = (
        cp.getint("Servers", "Server_ind")
        if cp.has_option("Servers", "Server_ind")
        else defaults["server"]["index"]
    )
    # Collect numeric-string keys from [Servers], sort by integer value
    url_entries: list[tuple[int, str]] = []
    if cp.has_section("Servers"):
        for key, val in cp.items("Servers"):
            if key.isdigit():
                url_entries.append((int(key), val.strip()))
    url_entries.sort(key=lambda x: x[0])
    urls = [v for _, v in url_entries] if url_entries else list(defaults["server"]["urls"])

    server_section = {
        "index": server_ind,
        "urls": urls,
    }

    # download
    dl_mode = (
        cp.get("Properties", "download_mode").strip()
        if cp.has_option("Properties", "download_mode")
        else defaults["download"]["mode"]
    )
    dl_threads = (
        cp.getint("Properties", "max_threads")
        if cp.has_option("Properties", "max_threads")
        else defaults["download"]["threads"]
    )
    dl_continue = (
        cp.getboolean("Properties", "continue_download")
        if cp.has_option("Properties", "continue_download")
        else defaults["download"]["continue"]
    )

    download_section = {
        "mode": dl_mode,
        "threads": dl_threads,
        "continue": dl_continue,
    }

    # window
    w_start = (
        cp.get("Settings", "start_date").strip()
        if cp.has_option("Settings", "start_date")
        else defaults["window"]["start"]
    )
    w_end = (
        cp.get("Settings", "end_date").strip()
        if cp.has_option("Settings", "end_date")
        else defaults["window"]["end"]
    )

    window_section = {
        "start": w_start,
        "end": w_end,
    }

    return {
        "paths": paths_section,
        "server": server_section,
        "download": download_section,
        "window": window_section,
    }


def load_config(
    toml_path: str | Path | None = None,
    ini_path: str | Path | None = None,
) -> Config:
    """Load configuration: TOML > legacy INI > DEFAULTS.

    Parameters
    ----------
    toml_path : optional override for TOML file location.
    ini_path : optional override for legacy INI file location.

    Returns
    -------
    Config dataclass instance.
    """
    tp = Path(toml_path) if toml_path is not None else TOML_PATH
    ip = Path(ini_path) if ini_path is not None else LEGACY_INI_PATH

    if tp.exists():
        raw = _read_toml(tp)
    elif ip.exists():
        raw = _read_legacy_ini(ip)
    else:
        raw = dict(DEFAULTS)

    return _build_config(raw)
