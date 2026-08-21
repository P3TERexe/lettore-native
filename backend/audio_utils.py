"""Utility audio: numpy -> bytes WAV."""

import io

import numpy as np
import soundfile as sf


def numpy_to_wav_bytes(wav: np.ndarray, sample_rate: int) -> bytes:
    """Converte l'array (1, n) restituito da supertonic in WAV PCM16 bytes."""
    buf = io.BytesIO()
    sf.write(buf, wav.squeeze(), sample_rate, format="WAV", subtype="PCM_16")
    return buf.getvalue()
