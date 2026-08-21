"""Registro voci: nomi amichevoli e lingue dichiarate.

Persistenza: <config_dir>/voices.json.
`langs == []` significa "compatibile con tutte le lingue".
"""

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

BUILTIN_NAMES = {
    "M1": "Marco",
    "M2": "Luca",
    "M3": "Nico",
    "M4": "Leo",
    "M5": "Davide",
    "F1": "Giulia",
    "F2": "Sofia",
    "F3": "Elena",
    "F4": "Aurora",
    "F5": "Luna",
}


class VoiceRegistry:
    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)
        self._data: dict[str, dict] = {}

    def _file(self) -> Path:
        return self.config_dir / "voices.json"

    def _load(self) -> None:
        try:
            self._data = json.loads(self._file().read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            self._data = {}

    def _save(self) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        tmp = self._file().with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.rename(self._file())

    def catalog(self, builtin_ids: list[str], custom_ids: list[str]):
        """Ritorna (builtin_entries, custom_entries), seminando i default mancanti."""
        self._load()
        changed = False
        for vid in builtin_ids:
            if vid not in self._data:
                self._data[vid] = {"name": BUILTIN_NAMES.get(vid, vid), "langs": []}
                changed = True
        for vid in custom_ids:
            if vid not in self._data:
                self._data[vid] = {"name": vid, "langs": []}
                changed = True
        if changed:
            self._save()

        def entry(vid: str, group: str) -> dict:
            e = self._data.get(vid, {"name": vid, "langs": []})
            return {
                "id": vid,
                "name": e.get("name", vid),
                "langs": list(e.get("langs", [])),
                "group": group,
            }

        return [entry(v, "builtin") for v in builtin_ids], [entry(v, "custom") for v in custom_ids]

    def name_for(self, voice_id: str) -> str:
        self._load()
        e = self._data.get(voice_id)
        return e.get("name", voice_id) if e else voice_id

    def update(
        self, voice_id: str, name: str | None = None, langs: list[str] | None = None
    ) -> dict | None:
        self._load()
        if voice_id not in self._data:
            return None
        if name is not None and name.strip():
            self._data[voice_id]["name"] = name.strip()
        if langs is not None:
            self._data[voice_id]["langs"] = sorted(
                {lang.strip().lower() for lang in langs if lang.strip()}
            )
        self._save()
        return dict(self._data[voice_id])
