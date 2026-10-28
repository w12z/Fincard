"""Generator checks with an in-memory image provider; never call a paid API."""
from io import BytesIO
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("generate_card_art", ROOT / "tools" / "generate_card_art.py")
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


class IllustrationTests(unittest.TestCase):
    def fake_provider(self, request, **_kwargs):
        if isinstance(request, str):
            self.assertEqual(request, "https://image.invalid/test.png")
            image = BytesIO()
            Image.new("RGB", (1280, 1280), "#cab78e").save(image, format="PNG")
            return BytesIO(image.getvalue())
        payload = json.loads(request.data)
        self.assertEqual(payload["model"], "glm-image")
        self.assertEqual(payload["size"], "1280x1280")
        self.assertIn("完全无字", payload["prompt"])
        return BytesIO(json.dumps({"data": [{"url": "https://image.invalid/test.png"}]}).encode())

    def test_all_events_and_new_reform_have_explicit_scenes(self):
        events = [json.loads(path.read_text(encoding="utf-8-sig")) for path in (ROOT / "data" / "events").glob("*.json")]
        self.assertEqual(len(events), 26)
        self.assertTrue(all(event["id"] in art.SCENES for event in events))
        self.assertIn("reform_permanent_coordination", art.SCENES)

    def test_event_without_display_name_saves_separate_banner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "assets" / "events").mkdir(parents=True)
            with patch.object(art, "ROOT", root), patch.object(art.urllib.request, "urlopen", side_effect=self.fake_provider):
                identifier, entry = art.generate({"id": "arcadia_ev_bank_run", "title": "test", "description": "test", "_art_kind": "events"}, "test-local-key", False, threading.Event())
            self.assertEqual(identifier, "arcadia_ev_bank_run")
            with Image.open(root / "assets" / "events" / (identifier + ".png")) as image:
                self.assertEqual(image.size, (768, 384))
            self.assertNotIn("test-local-key", json.dumps(entry))
            self.assertNotIn("image.invalid", json.dumps(entry))
            self.assertFalse((root / "assets" / "cards").exists())

    def test_card_keeps_existing_dimensions(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            with patch.object(art, "OUTPUT", output), patch.object(art.urllib.request, "urlopen", side_effect=self.fake_provider):
                art.generate({"id": "reform_permanent_coordination", "display_name": "test"}, "test-local-key", False, threading.Event())
            with Image.open(output / "reform_permanent_coordination.png") as image:
                self.assertEqual(image.size, (512, 288))

    def test_existing_art_never_generates_again_without_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            target = output / "existing.png"
            target.write_bytes(b"original-user-art")
            with patch.object(art, "OUTPUT", output), patch.object(art.urllib.request, "urlopen") as provider:
                result = art.generate({"id": "existing"}, "test-local-key", False, threading.Event())
                provider.assert_not_called()
            self.assertEqual(result, ("existing", None))
            self.assertEqual(target.read_bytes(), b"original-user-art")


if __name__ == "__main__":
    unittest.main()
