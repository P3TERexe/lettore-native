"""Configurazione del backend Lettore.

Provider ONNX e thread del motore TTS sono configurati direttamente in
``backend.engines.onnx_engine`` tramite ``LETTORE_TTS_PROVIDER``,
``LETTORE_TTS_COREML_SESSIONS``, ``LETTORE_TTS_INTRA_THREADS`` e
``LETTORE_TTS_INTER_THREADS``.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class BackendConfig:
    host: str = "127.0.0.1"
    port: int = 7788
    engine: str = "supertonic"
    model: str = "supertonic-3"
    auto_download: bool = True
    config_dir: Path = field(
        default_factory=lambda: Path(
            os.getenv("LETTORE_CONFIG_DIR", str(Path.home() / ".config" / "lettore"))
        )
    )

    @classmethod
    def from_env(cls) -> "BackendConfig":
        port = int(os.getenv("LETTORE_PORT", "7788"))
        host = os.getenv("LETTORE_HOST", "127.0.0.1")
        engine = os.getenv("LETTORE_ENGINE", "supertonic")
        model = os.getenv("LETTORE_MODEL", "supertonic-3")
        auto_download = os.getenv("LETTORE_AUTO_DOWNLOAD", "1") not in ("0", "false", "no")
        return cls(host=host, port=port, engine=engine, model=model, auto_download=auto_download)
