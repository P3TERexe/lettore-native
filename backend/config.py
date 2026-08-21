"""Configurazione del backend Lettore."""

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class BackendConfig:
    host: str = "127.0.0.1"
    port: int = 7788
    model: str = "supertonic-3"
    auto_download: bool = True
    capture_enabled: bool = True
    capture_delay_ms: int = 400
    config_dir: Path = field(
        default_factory=lambda: Path(
            os.getenv("LETTORE_CONFIG_DIR", str(Path.home() / ".config" / "lettore"))
        )
    )

    @classmethod
    def from_env(cls) -> "BackendConfig":
        port = int(os.getenv("LETTORE_PORT", "7788"))
        host = os.getenv("LETTORE_HOST", "127.0.0.1")
        model = os.getenv("LETTORE_MODEL", "supertonic-3")
        auto_download = os.getenv("LETTORE_AUTO_DOWNLOAD", "1") not in ("0", "false", "no")
        return cls(host=host, port=port, model=model, auto_download=auto_download)
