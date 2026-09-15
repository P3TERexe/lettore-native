#!/usr/bin/env python3
"""Script per generare tutti i campioni audio con Supertonic 3 a 16 step (massima qualità)."""

import os
import subprocess
import tempfile
from pathlib import Path
import soundfile as sf
from supertonic import TTS

DOCUMENTS = {
    'calvino': {
        'lang': 'it',
        'sentences': [
            "Prendete la vita con leggerezza, che leggerezza non è superficialità, ma planare sulle cose dall'alto, non avere macigni sul cuore.",
            "La leggerezza per me si associa con la precisione e la determinazione, non con la vaghezza e l'abbandono al caso.",
            "Nei momenti in cui il regno dell'umano mi sembra condannato alla pesantezza, penso che dovrei volare in un altro spazio, come Perseo."
        ]
    },
    'neuroscience': {
        'lang': 'it',
        'sentences': [
            "L'ascolto combinato alla scansione visiva riduce il carico cognitivo della memoria di lavoro fino al quaranta percento durante lo studio intensivo.",
            "La segmentazione del discorso in unità sintattiche complete consente al cervello di anticipare la struttura della frase senza interruzioni ritmiche.",
            "Per questo motivo la sincronizzazione istantanea tra voce neurale e marcatore visivo è essenziale per la comprensione profonda."
        ]
    },
    'english': {
        'lang': 'en',
        'sentences': [
            "There is no doubt that consciousness is an active, continuous creation of the human mind and memory.",
            "Perception is never purely passive; it involves an immediate synthesis of sensory input and narrative focus.",
            "Language gives our inner thoughts a lasting architecture that transcends the fleeting present moment."
        ]
    }
}

VOICES = ['M1', 'M2', 'M3', 'M4', 'M5', 'F1', 'F2', 'F3', 'F4', 'F5']
TOTAL_STEPS = 16

def main():
    out_dir = Path("website/public/assets/audio")
    out_dir.mkdir(parents=True, exist_ok=True)
    
    print("Inizializzazione modello Supertonic 3...")
    tts = TTS(auto_download=False, model="supertonic-3")
    print(f"Modello caricato. Sample rate: {tts.sample_rate} Hz. Step impostati: {TOTAL_STEPS}")

    total_tasks = len(DOCUMENTS) * 3 * len(VOICES)
    done = 0

    for doc_key, doc_data in DOCUMENTS.items():
        lang = doc_data['lang']
        for sent_idx, sentence in enumerate(doc_data['sentences']):
            for voice_id in VOICES:
                out_mp3 = out_dir / f"{doc_key}_{voice_id}_{sent_idx}.mp3"
                print(f"[{done+1}/{total_tasks}] Sintesi {doc_key} ({voice_id}, frase {sent_idx}) a {TOTAL_STEPS} step...")
                
                style = tts.get_voice_style(voice_id)
                wav, _ = tts.synthesize(
                    text=sentence,
                    voice_style=style,
                    total_steps=TOTAL_STEPS,
                    speed=1.0,
                    lang=lang
                )
                
                # Salva wav temporaneo e converti in MP3 ad alta fedeltà
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_wav:
                    tmp_wav_path = tmp_wav.name
                
                try:
                    # wav shape: (1, samples)
                    sf.write(tmp_wav_path, wav[0], tts.sample_rate, subtype="PCM_16")
                    cmd = [
                        "ffmpeg", "-y", "-i", tmp_wav_path,
                        "-codec:a", "libmp3lame", "-b:a", "256k",
                        "-ar", str(tts.sample_rate),
                        str(out_mp3)
                    ]
                    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                finally:
                    if os.path.exists(tmp_wav_path):
                        os.remove(tmp_wav_path)
                
                done += 1

            # Copia anche il fallback di default (M1) per {doc_key}_{sent_idx}.mp3
            default_mp3 = out_dir / f"{doc_key}_M1_{sent_idx}.mp3"
            fallback_mp3 = out_dir / f"{doc_key}_{sent_idx}.mp3"
            if default_mp3.exists():
                import shutil
                shutil.copy2(default_mp3, fallback_mp3)

    print("\n✅ Generazione completata con successo a 16 step per tutti i file audio!")

if __name__ == "__main__":
    main()
