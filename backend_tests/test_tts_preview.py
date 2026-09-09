import unittest
from pathlib import Path

import numpy as np
from fastapi.testclient import TestClient

from backend.engines.base import BaseTTSEngine
from backend.main import create_app
from backend.tts_manager import TTSManager


class MockEngine(BaseTTSEngine):
    @property
    def sample_rate(self) -> int | None:
        return 24000

    @property
    def voice_names(self) -> list[str]:
        return ["M1", "F1"]

    @property
    def supported_languages(self) -> list[str]:
        return ["it", "en"]

    def load(self) -> None:
        pass

    def unload(self) -> None:
        pass

    def synthesize(
        self, text: str, voice: str, lang: str, steps: int, speed: float
    ) -> tuple[np.ndarray, float]:
        waveform = np.zeros(12000, dtype=np.float32)
        return waveform, 0.5

    def discover_custom_voices(self, cache_dir: Path | None = None) -> list[str]:
        return []


class TestTTSPreview(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        mock_tts = TTSManager(model="test", engine="supertonic")
        mock_tts._engine = MockEngine()
        mock_tts.ready = True
        self.app.state.tts = mock_tts
        self.client = TestClient(self.app)

    def test_preview_endpoint(self):
        resp = self.client.get("/v1/tts/preview?voice=M1&lang=it")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.headers.get("content-type"), "audio/wav")
        self.assertIn("x-duration-ms", resp.headers)
        self.assertEqual(resp.headers.get("x-duration-ms"), "500")
        # Verifica WAV header RIFF
        content = resp.content
        self.assertTrue(content.startswith(b"RIFF"))


if __name__ == "__main__":
    unittest.main()
