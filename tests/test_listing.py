import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader("downloads", str(Path(__file__).resolve().parents[1] / "bin/downloads"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class ListingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def make(self, name):
        path = self.root / name
        path.write_bytes(b"sample")
        return path

    def test_media_filters_hide_logs_partial_files_and_directories(self):
        self.make("image.png")
        self.make("movie.mp4")
        self.make("movie.mp4.log")
        self.make("movie.mp4.part")
        (self.root / "folder.png").mkdir()
        self.assertEqual([x["name"] for x in module.listing(str(self.root), "images")["files"]], ["image.png"])
        self.assertEqual([x["name"] for x in module.listing(str(self.root), "videos")["files"]], ["movie.mp4"])

    def test_downloads_preserve_folders_and_unusual_names(self):
        name = 'a\n";$(touch NOT_EXECUTED).png'
        self.make(name)
        (self.root / "folder").mkdir()
        self.make(".hidden")
        self.make("pending.crdownload")
        result = module.listing(str(self.root))["files"]
        self.assertEqual({x["name"] for x in result}, {name, "folder"})
        self.assertTrue(next(x for x in result if x["name"] == "folder")["isDir"])

    def test_active_recording_excluded_until_finalized(self):
        video = self.make("recording.mp4")
        with patch.object(module, "active_recording", return_value=str(video)):
            self.assertEqual(module.listing(str(self.root), "videos")["files"], [])
        with patch.object(module, "active_recording", return_value=""):
            self.assertEqual(len(module.listing(str(self.root), "videos")["files"]), 1)

    def test_filtering_before_cap_preserves_media(self):
        self.make("image.png")
        for index in range(205):
            self.make(f"file-{index}.zip")
        result = module.listing(str(self.root))
        self.assertIn("image.png", [x["name"] for x in result["files"]])
        self.assertEqual(result["hidden"], 5)

    def test_large_scan_is_disclosed_and_bounded(self):
        for index in range(5):
            self.make(f"{index}.png")
        with patch.object(module, "SCAN_CAP", 3):
            result = module.listing(str(self.root))
        self.assertTrue(result["truncated"])
        self.assertEqual(result["scanned"], 3)
        self.assertEqual(len(result["files"]), 3)

    def test_missing_folder_is_explicit(self):
        self.assertFalse(module.listing(str(self.root / "absent"))["ok"])


if __name__ == "__main__":
    unittest.main()
