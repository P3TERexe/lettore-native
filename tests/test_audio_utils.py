import io
import unittest

import numpy as np
import soundfile as sf

from backend.audio_utils import concat_wav_bytes


class TestConcatWavBytes(unittest.TestCase):
    def test_concat_preserves_samples_and_format(self):
        sr = 24000
        first = np.zeros(sr, dtype=np.int16)
        second = np.full(5 * sr, 1000, dtype=np.int16)
        wavs = []
        for arr in (first, second):
            buf = io.BytesIO()
            sf.write(buf, arr, sr, format="WAV", subtype="PCM_16")
            wavs.append(buf.getvalue())

        combined = concat_wav_bytes(wavs, sr)

        data, out_sr = sf.read(io.BytesIO(combined), dtype="int16")
        self.assertEqual(out_sr, sr)
        self.assertEqual(len(data), len(first) + len(second))


if __name__ == "__main__":
    unittest.main()
