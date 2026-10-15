"""TOML-only configuration contracts; synthetic files only, no network or data."""
from __future__ import annotations

from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))
from config import config as app
from config.paths import data_root, index_path, product_dir, project_root
from download_data.initialize_download_parameters import build_config, generate_config


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mars_config_")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, text, name="settings.toml"):
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_complete_template_and_initialize(self):
        path = self.root / "settings.toml"
        generate_config(path)
        self.assertEqual(path.read_bytes(), app.EXAMPLE_PATH.read_bytes())
        self.assertEqual(tomllib.loads(path.read_text()), build_config())
        cfg = app.load_config(path)
        self.assertEqual(cfg.download.threads, 5)
        self.assertTrue(cfg.download.continue_flag)
        self.assertEqual(cfg.products.models, [])
        self.assertEqual(cfg.proxy.ustc_server, "")
        self.assertIn("IDMan.exe", cfg.download.idm_program_path)
        self.assertIs(type(cfg.download.threads), int)
        with self.assertRaises(FileExistsError):
            generate_config(path)
        self.assertEqual(path.read_bytes(), app.EXAMPLE_PATH.read_bytes())
        copy = build_config()
        copy["server"]["urls"].append("modified")
        self.assertNotEqual(copy, build_config())

    def test_all_former_download_settings_preserved(self):
        raw = deepcopy(app.DEFAULTS)
        raw["server"].update(index=1, username="user % 中文", password='a"b\\c')
        raw["proxy"].update(outer_server="http://proxy:1234", ustc_server="")
        raw["download"].update(mode="Aria2c", threads=8, sleep_time=7, step_time=2,
                               show_tqdm_bar=True, idm_program_path=r'C:\a b\IDMan.exe')
        raw["download"]["continue"] = False
        raw["products"].update(models=["KP", "MAG_ss"], skip=["LPW_lpiv"],
                               single_download=True, single_model="KP", update_file_version=True,
                               check_download_file=True)
        cfg = app._build_config(raw)
        self.assertEqual(cfg.server.password, 'a"b\\c')
        self.assertEqual(cfg.server.username, "user % 中文")
        self.assertEqual(cfg.server.index, 1)
        self.assertEqual(cfg.download.mode, "Aria2c")
        self.assertFalse(cfg.download.continue_flag)
        self.assertEqual(cfg.download.idm_program_path, r'C:\a b\IDMan.exe')
        self.assertEqual(cfg.products.models, ["KP", "MAG_ss"])
        self.assertTrue(cfg.products.update_file_version)
        self.assertTrue(cfg.products.check_download_file)
        self.assertEqual(cfg.paths.cdf_lib, app.DEFAULTS["paths"]["cdf_lib"])

    def test_missing_file_and_ini_never_fall_back(self):
        path = self.root / "settings.toml"
        self.write('[DEFAULT]\nSave_dir = wrong\n', "MAVEN_download_config.ini")
        with patch.object(app, "TOML_PATH", path):
            with self.assertRaisesRegex(FileNotFoundError, "initialize_download_parameters"):
                app.load_config()
        with self.assertRaisesRegex(ValueError, "INI is no longer supported"):
            app.load_config(self.root / "MAVEN_download_config.ini")
        with self.assertRaises(TypeError):
            app.load_config(ini_path="old.ini")
        with self.assertRaises(ValueError):
            generate_config(self.root / "old.ini")

    def test_partial_optional_tables_and_required_paths(self):
        path = self.write('[paths]\nmaven_data_root="data/MAVEN"\ntw_data_root="data/TW"\nmgs_data_root="data/MGS"\n')
        cfg = app.load_config(path)
        self.assertEqual(cfg.paths.maven_data_root, str(REPO / "data/MAVEN"))
        self.assertEqual(cfg.download.mode, "python.request")
        self.assertEqual(cfg.paths.fortran_dll_dir, "")
        for missing in ("maven_data_root", "tw_data_root", "mgs_data_root"):
            raw = deepcopy(app.DEFAULTS)
            del raw["paths"][missing]
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, missing):
                app._build_config(raw)

    def test_strict_type_and_value_errors(self):
        cases = [("download", "threads", True), ("download", "threads", 0),
                 ("download", "continue", "false"), ("download", "mode", "requests"),
                 ("download", "sleep_time", -1), ("download", "step_time", 0.5),
                 ("server", "index", -1), ("server", "index", 3),
                 ("server", "urls", []), ("server", "urls", [1]),
                 ("products", "models", "KP,MAG"), ("products", "skip", [""]),
                 ("paths", "maven_data_root", " "), ("paths", "mgs_data_root", 1),
                 ("paths", "fortran_dll_dir", 1), ("proxy", "outer_server", False),
                 ("window", "start", "20250101"), ("window", "end", "2010-01-01")]
        for section, key, value in cases:
            raw = deepcopy(app.DEFAULTS)
            raw[section][key] = value
            with self.subTest(section=section, key=key, value=value), self.assertRaises(ValueError):
                app._build_config(raw)
        raw = deepcopy(app.DEFAULTS)
        raw["download"]["threds"] = 5
        with self.assertRaisesRegex(ValueError, "threds"):
            app._build_config(raw)
        raw = deepcopy(app.DEFAULTS)
        raw["typo"] = {}
        with self.assertRaisesRegex(ValueError, "typo"):
            app._build_config(raw)
        malformed = self.write('[paths\n')
        with self.assertRaises(tomllib.TOMLDecodeError):
            app.load_config(malformed)

    def test_paths_do_not_depend_on_cwd(self):
        path = self.write('[paths]\nmaven_data_root="data/MAVEN"\ntw_data_root="data/TW"\nmgs_data_root="data/MGS"\n')
        before = app.load_config(path)
        previous = Path.cwd()
        try:
            os.chdir(self.root)
            after = app.load_config(path)
            self.assertEqual(before, after)
            self.assertEqual(project_root(), REPO)
            self.assertEqual(index_path(), REPO / "MAVEN_data/filename_lists.json")
            self.assertEqual(data_root("maven", after), REPO / "data/MAVEN")
        finally:
            os.chdir(previous)
        for value in (r"C:\data\MAVEN", "E:/MAVEN/", r"\\server\share\MAVEN"):
            self.assertEqual(app._resolve_path(value), value)
        model = {"KP": [None, "regex", "KP/insitu/"]}
        self.assertEqual(product_dir("KP", self.root, model), self.root / "KP/insitu")

    def test_initializer_from_external_cwd(self):
        target = self.root / "custom.toml"
        command = [sys.executable, str(REPO / "download_data/initialize_download_parameters.py"), "--output", str(target)]
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        first = subprocess.run(command, cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        second = subprocess.run(command, cwd=self.root, env=env, capture_output=True, text=True)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(target.read_bytes(), app.EXAMPLE_PATH.read_bytes())


if __name__ == "__main__":
    unittest.main()
