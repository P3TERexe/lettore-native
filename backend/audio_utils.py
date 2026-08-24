"""Utility audio: numpy -> bytes WAV."""

import io

import numpy as np
import soundfile as sf


def numpy_to_wav_bytes(wav: np.ndarray, sample_rate: int) -> bytes:
    """Converte l'array (1, n) restituito da supertonic in WAV PCM16 bytes."""
    buf = io.BytesIO()
    sf.write(buf, wav.squeeze(), sample_rate, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def concat_wav_bytes(parts: list[bytes], sample_rate: int) -> bytes:
    """Concatena più WAV PCM16 (stesso sample rate) in un unico WAV."""
    arrays = [sf.read(io.BytesIO(p), dtype="int16")[0] for p in parts]
    buf = io.BytesIO()
    sf.write(buf, np.concatenate(arrays), sample_rate, format="WAV", subtype="PCM_16")
    return buf.getvalue()
