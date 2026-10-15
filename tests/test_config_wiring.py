"""Exercise production downloader configuration without network/optional packages."""
from copy import deepcopy
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))
from config import config as app


def load_downloader(name, cfg):
    requests = types.ModuleType("requests")
    requests.Session = Mock(return_value=types.SimpleNamespace(auth=None))
    requests.get = Mock(side_effect=AssertionError("Network access is forbidden in tests"))
    bs4 = types.ModuleType("bs4")
    bs4.BeautifulSoup = Mock()
    tqdm = types.ModuleType("tqdm")
    tqdm.tqdm = Mock()
    with patch.dict(sys.modules, {"requests": requests, "bs4": bs4, "tqdm": tqdm}), \
         patch.object(app, "load_config", return_value=cfg), redirect_stdout(io.StringIO()):
        spec = importlib.util.spec_from_file_location("config_probe_" + name, REPO / "download_data" / (name + ".py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


class WiringTests(unittest.TestCase):
    def test_main_downloader_consumes_complete_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            for mode in ("python.request", "win.idm", "Aria2c"):
                for server in (0, 2):
                    with self.subTest(mode=mode, server=server):
                        raw = deepcopy(app.DEFAULTS)
                        raw["paths"]["maven_data_root"] = tmp
                        raw["server"].update(index=server, username="user", password="pass")
                        raw["download"].update(mode=mode, threads=9, sleep_time=12, step_time=2,
                                               show_tqdm_bar=True, idm_program_path="bin/IDMan.exe")
                        raw["download"]["continue"] = False
                        raw["proxy"].update(ustc_server="http://internal:10", outer_server="http://external:20")
                        raw["products"].update(single_download=True, single_model="KP", models=["KP"],
                                               skip=["LPW_lpiv"], update_file_version=True,
                                               check_download_file=True)
                        cfg = app._build_config(raw)
                        mod = load_downloader("MAVEN_download", cfg)
                        self.assertEqual(mod.save_dir, tmp)
                        self.assertEqual(mod.Server_ind, server)
                        self.assertEqual(mod.url_path_0, cfg.server.urls[server])
                        self.assertEqual(mod.download_mode, mode)
                        self.assertEqual(mod.max_threads, 9)
                        self.assertFalse(mod.continue_download)
                        self.assertFalse(mod.disable_tqdm_bar)
                        self.assertEqual(mod.sleep_time, 12)
                        self.assertEqual(mod.step_time, 0 if server == 0 else 2)
                        self.assertEqual(mod.muti_models, ["KP"])
                        self.assertEqual(mod.models_pass, ["LPW_lpiv"])
                        self.assertTrue(mod.single_download)
                        self.assertTrue(mod.update_file_version)
                        self.assertTrue(mod.check_download_file)
                        proxy = cfg.proxy.ustc_server if server == 0 else cfg.proxy.outer_server
                        self.assertEqual(mod.vpn_proxy, {"http": proxy, "https": proxy})
                        self.assertEqual(mod.start_date.isoformat(), cfg.window.start)
                        self.assertEqual(mod.end_date.isoformat(), cfg.window.end)
                        if server == 0:
                            self.assertEqual(mod.session.auth, (b"user", b"pass"))
                        url, directory, _ = mod.download_model("KP")
                        self.assertEqual(directory, str(Path(tmp) / "KP/insitu" ) + "/")
                        self.assertTrue(url.startswith(cfg.server.urls[server]))
                        target = Path(tmp) / "idm"
                        with patch.object(mod.subprocess, "run", return_value=types.SimpleNamespace(returncode=0)) as run:
                            mod.idm_add_download_links("https://example.invalid/data", str(target), "file.tab")
                        self.assertEqual(run.call_args.args[0][0], cfg.download.idm_program_path)

    def test_directory_downloader_honors_server_and_disabled_proxy(self):
        for index in (0, 2):
            raw = deepcopy(app.DEFAULTS)
            raw["server"]["index"] = index
            raw["proxy"] = dict(ustc_server="", outer_server="")
            cfg = app._build_config(raw)
            mod = load_downloader("download_files", cfg)
            self.assertEqual(mod.Server_ind, index)
            self.assertEqual(mod.url_path_0, cfg.server.urls[index])
            self.assertIsNone(mod.vpn_proxy)

    def test_clean_explicit_config_does_not_require_default(self):
        from martian_pipeline import cli
        with tempfile.TemporaryDirectory() as tmp:
            raw = deepcopy(app.DEFAULTS)
            for key in ("maven_data_root", "tw_data_root", "mgs_data_root"):
                raw["paths"][key] = tmp
            text = ''.join('\n[' + section + ']\n' + ''.join(key + ' = ' + (str(v).lower() if type(v) is bool else json.dumps(v)) + '\n' for key, v in values.items()) for section, values in raw.items())
            config = Path(tmp) / "settings.toml"
            config.write_text(text)
            marker = Path(tmp) / "fake.aria2"
            marker.write_text("unfinished")
            tqdm = types.ModuleType("tqdm")
            tqdm.tqdm = Mock()
            sys.modules.pop("download_data.clean_files", None)
            with patch.dict(sys.modules, {"tqdm": tqdm}), patch.object(app, "TOML_PATH", Path(tmp) / "missing.toml"), redirect_stdout(io.StringIO()):
                self.assertEqual(cli.main(["clean", "--config", str(config)]), 0)
            self.assertTrue(marker.exists(), "clean defaults to report only")


if __name__ == "__main__":
    unittest.main()
