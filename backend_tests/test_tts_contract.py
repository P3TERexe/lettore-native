from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np
from fastapi.testclient import TestClient

from backend.engines.base import BaseTTSEngine
from backend.main import create_app
from backend.models import CLIENT_CHUNK_MAX_CHARS
from backend.tts_manager import TTSManager


class RecordingEngine(BaseTTSEngine):
    def __init__(self) -> None:
        self.synthesized_texts: list[str] = []

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
        self.synthesized_texts.append(text)
        return np.zeros(2400, dtype=np.float32), 0.1

    def discover_custom_voices(self, cache_dir: Path | None = None) -> list[str]:
        return []


class TestTTSChunkContract(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.engine = RecordingEngine()
        mock_tts = TTSManager(model="test", engine="supertonic")
        mock_tts._engine = self.engine
        mock_tts.ready = True
        self.app.state.tts = mock_tts
        self.client = TestClient(self.app)

    def test_client_sized_chunk_reaches_engine_unchanged(self):
        text = "parola " * 33 + "fine"
        self.assertLessEqual(len(text), CLIENT_CHUNK_MAX_CHARS)
        self.assertGreater(len(text), 150)

        resp = self.client.post(
            "/v1/tts",
            json={
                "text": text,
                "lang": "it",
                "voice": "M1",
                "normalize_text": False,
            },
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_external_client_keeps_backend_normalization_by_default(self):
        resp = self.client.post(
            "/v1/tts",
            json={"text": "Il prezzo è 15€.", "lang": "it", "voice": "M1"},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, ["Il prezzo è 15 euro."])

    def test_removed_routes_are_not_exposed(self):
        self.assertEqual(self.client.get("/v1/queue").status_code, 404)
        self.assertEqual(self.client.get("/v1/blocks/status").status_code, 404)
        self.assertEqual(self.client.post("/v1/tts/export", json={"text": "ciao"}).status_code, 404)


if __name__ == "__main__":
    unittest.main()
