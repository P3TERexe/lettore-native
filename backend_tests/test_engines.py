import os
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from backend.engines import onnx_engine
from backend.engines.base import BaseTTSEngine
from backend.engines.factory import create_engine
from backend.engines.onnx_engine import SupertonicONNXEngine
from backend.tts_manager import TTSManager


class DummyEngine(BaseTTSEngine):
    def __init__(self) -> None:
        self.loaded = False
        self.calls = 0

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
        self.loaded = True

    def unload(self) -> None:
        self.loaded = False

    def synthesize(
        self, text: str, voice: str, lang: str, steps: int, speed: float
    ) -> tuple[np.ndarray, float]:
        self.calls += 1
        waveform = np.zeros(24000, dtype=np.float32)
        return waveform, 1.0

    def discover_custom_voices(self, cache_dir: Path | None = None) -> list[str]:
        return ["custom_voice_1"]


class TestTTSEngines(unittest.TestCase):
    def test_factory_create_supertonic(self):
        engine = create_engine(engine_type="supertonic", model="supertonic-3", auto_download=False)
        self.assertIsInstance(engine, SupertonicONNXEngine)
        self.assertEqual(engine.model, "supertonic-3")
        self.assertIn("it", engine.supported_languages)
        self.assertIn("en", engine.supported_languages)

    def test_factory_unknown_engine_raises(self):
        with self.assertRaises(ValueError) as ctx:
            create_engine(engine_type="nonexistent_engine")
        self.assertIn("sconosciuto", str(ctx.exception))

    def test_tts_manager_with_engine(self):
        dummy = DummyEngine()
        manager = TTSManager(model="test-model", engine="supertonic")
        manager._engine = dummy
        manager.ready = True

        self.assertEqual(manager.sample_rate, 24000)
        builtin, custom = manager.voices()
        self.assertEqual(builtin, ["M1", "F1"])
        self.assertEqual(custom, ["custom_voice_1"])

        langs = manager.languages()
        lang_codes = [lang_item["code"] for lang_item in langs]
        self.assertIn("it", lang_codes)
        self.assertIn("na", lang_codes)

        # Sintesi mock
        wav_bytes, duration_ms = manager.synthesize(
            text="Test", lang="it", voice="M1", steps=5, speed=1.0
        )
        self.assertTrue(len(wav_bytes) > 44)  # WAV header + data
        self.assertEqual(duration_ms, 1000)

        # La seconda richiesta identica deve arrivare dalla cache, non al motore.
        manager.synthesize(text="Test", lang="it", voice="M1", steps=5, speed=1.0)
        self.assertEqual(dummy.calls, 1)


class FakeSupertonicTTS:
    """Sostituto minimale di ``supertonic.TTS`` per i test di ``load()``."""

    sample_rate = 24000
    voice_style_names = ["M1", "F1"]

    def __init__(self, **kwargs):
        self.init_kwargs = kwargs
        self.calls = []

    def get_voice_style(self, name: str) -> str:
        return f"style:{name}"

    def synthesize(self, **kwargs):
        self.calls.append(kwargs)
        return np.zeros((1, 100), dtype=np.float32), np.array([0.1], dtype=np.float32)


class TestONNXLoad(unittest.TestCase):
    def test_load_builds_the_session_without_synthesizing(self):
        fake = FakeSupertonicTTS()
        with patch.object(onnx_engine, "TTS", return_value=fake):
            engine = SupertonicONNXEngine(auto_download=False)
            engine.load()

        # Il costo di avvio è solo la creazione della sessione: nessuna
        # inferenza usa-e-getta e nessuno stile pre-caricato in cache.
        self.assertEqual(fake.calls, [])
        self.assertEqual(engine._style_cache, {})
        self.assertEqual(engine.sample_rate, 24000)

    def test_synthesize_leaves_internal_silence_to_the_runtime(self):
        fake = FakeSupertonicTTS()
        with patch.object(onnx_engine, "TTS", return_value=fake):
            engine = SupertonicONNXEngine(auto_download=False)
            engine.load()

        engine.synthesize(text="Test", voice="M1", lang="it", steps=5, speed=1.0)

        self.assertEqual(fake.calls[-1]["text"], "Test")
        # Il default del runtime resta valido: non lo forziamo dal backend.
        self.assertNotIn("silence_duration", fake.calls[-1])


class TestONNXProviderConfig(unittest.TestCase):
    def test_hybrid_uses_coreml_only_for_configured_sessions(self):
        available = ["CoreMLExecutionProvider", "CPUExecutionProvider"]
        with (
            patch.dict(os.environ, {"LETTORE_TTS_PROVIDER": "hybrid"}),
            patch.object(onnx_engine.ort, "get_available_providers", return_value=available),
        ):
            self.assertEqual(
                onnx_engine._resolve_providers(None, "vector_estimator"),
                ["CoreMLExecutionProvider", "CPUExecutionProvider"],
            )
            self.assertEqual(
                onnx_engine._resolve_providers(None, "vocoder"),
                ["CPUExecutionProvider"],
            )

    def test_cpu_mode_ignores_supertonic_cpu_default(self):
        available = ["CoreMLExecutionProvider", "CPUExecutionProvider"]
        with (
            patch.dict(os.environ, {"LETTORE_TTS_PROVIDER": "cpu"}),
            patch.object(onnx_engine.ort, "get_available_providers", return_value=available),
        ):
            self.assertEqual(
                onnx_engine._resolve_providers(["CPUExecutionProvider"], "vector_estimator"),
                ["CPUExecutionProvider"],
            )

    def test_explicit_accelerator_is_honored(self):
        available = ["CoreMLExecutionProvider", "CPUExecutionProvider"]
        with patch.object(onnx_engine.ort, "get_available_providers", return_value=available):
            self.assertEqual(
                onnx_engine._resolve_providers(["CoreMLExecutionProvider"], "vocoder"),
                ["CoreMLExecutionProvider", "CPUExecutionProvider"],
            )

    def test_invalid_provider_mode_falls_back_to_hybrid(self):
        with patch.dict(os.environ, {"LETTORE_TTS_PROVIDER": "bogus"}):
            self.assertEqual(onnx_engine._provider_mode(), "hybrid")

    def test_env_int_rejects_invalid_values(self):
        with patch.dict(os.environ, {"LETTORE_TEST_THREADS": "non-un-numero"}):
            self.assertEqual(onnx_engine._env_int("LETTORE_TEST_THREADS", 4), 4)


if __name__ == "__main__":
    unittest.main()
