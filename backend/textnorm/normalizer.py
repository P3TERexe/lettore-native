"""Modulo di normalizzazione del testo per la sintesi vocale (TTS).

Include:
1. Filtro di esclusione stringhe (disclaimer email, note legali, firme, ecc.)
2. Regole di espansione fonetica per la lingua italiana (abbreviazioni, valute,
   link/email, numeri ordinali, percentuali, unità di misura, orari).
"""

from __future__ import annotations

import re
import urllib.parse

# Mappa abbreviazioni italiane ad alta frequenza (con gestione case-preserving)
_ABBREVIATIONS: list[tuple[re.Pattern[str], str]] = [
    # Titoli professionali e onorifici
    (re.compile(r"\b(dott|dr)\.ssa\b", re.IGNORECASE), "dottoressa"),
    (re.compile(r"\b(dott|dr)\b\.", re.IGNORECASE), "dottore"),
    (re.compile(r"\bprof\.ssa\b", re.IGNORECASE), "professoressa"),
    (re.compile(r"\bprof\b\.", re.IGNORECASE), "professore"),
    (re.compile(r"\bsig\.ra\b", re.IGNORECASE), "signora"),
    (re.compile(r"\bsig\b\.", re.IGNORECASE), "signor"),
    (re.compile(r"\bavv\b\.", re.IGNORECASE), "avvocato"),
    (re.compile(r"\bing\b\.", re.IGNORECASE), "ingegnere"),
    (re.compile(r"\barch\b\.", re.IGNORECASE), "architetto"),
    (re.compile(r"\bgeom\b\.", re.IGNORECASE), "geometra"),
    # Documenti, testi e norme
    (re.compile(r"\bpagg\b\.", re.IGNORECASE), "pagine"),
    (re.compile(r"\bpag\b\.", re.IGNORECASE), "pagina"),
    (re.compile(r"\bp\b\.\s*(?=\d+)", re.IGNORECASE), "pagina "),
    (re.compile(r"\bart\b\.", re.IGNORECASE), "articolo"),
    (re.compile(r"\bcap\b\.", re.IGNORECASE), "capitolo"),
    (re.compile(r"\bsez\b\.", re.IGNORECASE), "sezione"),
    (re.compile(r"\bpar\b\.", re.IGNORECASE), "paragrafo"),
    (re.compile(r"\ball\b\.", re.IGNORECASE), "allegato"),
    # Numerazione ed elenchi
    (re.compile(r"\b(n|num)\b\.\s*(?=\d+)", re.IGNORECASE), "numero "),
    (re.compile(r"\b(n|num)\b\.", re.IGNORECASE), "numero"),
    (re.compile(r"\becc\b\.", re.IGNORECASE), "eccetera"),
    (re.compile(r"\betc\b\.", re.IGNORECASE), "eccetera"),
    (re.compile(r"\bes\b\.\s*(?=[a-zA-Z0-9])", re.IGNORECASE), "esempio "),
    (re.compile(r"\bes\b\.", re.IGNORECASE), "esempio"),
    (re.compile(r"\bcfr\b\.", re.IGNORECASE), "confronta"),
    (re.compile(r"\bv\b\.\s*(?=[a-zA-Z0-9])", re.IGNORECASE), "vedi "),
    # Recapiti
    (re.compile(r"\btel\b\.", re.IGNORECASE), "telefono"),
    (re.compile(r"\bcell\b\.", re.IGNORECASE), "cellulare"),
    (re.compile(r"\bc\.a\.p\b\.", re.IGNORECASE), "C A P"),
    (re.compile(r"\bcap\b(?=\s+\d{5})", re.IGNORECASE), "C A P"),
]

# Ordinali maschili e femminili
_ORDINALS_M: dict[str, str] = {
    "1": "primo",
    "2": "secondo",
    "3": "terzo",
    "4": "quarto",
    "5": "quinto",
    "6": "sesto",
    "7": "settimo",
    "8": "ottavo",
    "9": "nono",
    "10": "decimo",
}

_ORDINALS_F: dict[str, str] = {
    "1": "prima",
    "2": "seconda",
    "3": "terza",
    "4": "quarta",
    "5": "quinta",
    "6": "sesta",
    "7": "settima",
    "8": "ottava",
    "9": "nona",
    "10": "decima",
}


class TextNormalizer:
    """Normalizzatore avanzato del testo prima della sintesi vocale."""

    @classmethod
    def filter_exclusions(cls, text: str, exclusions: list[str] | None) -> str:
        """Rimuove dal testo tutte le occorrenze esatte o le frasi blacklistate."""
        if not text or not exclusions:
            return text

        result = text
        for item in exclusions:
            pattern_str = item.strip()
            if not pattern_str:
                continue
            escaped = re.escape(pattern_str)
            result = re.sub(rf"(?i)[ \t]*{escaped}[ \t]*[.,;:!?-]?", " ", result)

        # Pulizia punteggiatura orfana o raddoppiata (es. ". .")
        result = re.sub(r"\s+([.,;:!?])", r"\1", result)
        result = re.sub(r"([.,;:!?])\s*\1+", r"\1", result)
        result = re.sub(r"[ \t]+", " ", result)
        result = re.sub(r"\n\s*\n\s*\n+", "\n\n", result)
        return result.strip()

    @classmethod
    def _normalize_urls(cls, text: str) -> str:
        """Converte link e URL in lettura fonetica naturale."""

        def _replace_url(match: re.Match[str]) -> str:
            full_url = match.group(0)
            parsed = urllib.parse.urlparse(full_url)
            netloc = parsed.netloc or parsed.path.split("/")[0]
            netloc = netloc.replace("www.", "")
            clean_domain = netloc.replace(".", " punto ")
            return f"link {clean_domain}"

        # URL completi con schema
        text = re.sub(r"https?://[^\s<>\"']+", _replace_url, text)
        # URL stile www.dominio.ext
        text = re.sub(r"\bwww\.[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s<>\"']*)?", _replace_url, text)
        return text

    @classmethod
    def _normalize_emails(cls, text: str) -> str:
        """Converte indirizzi email in lettura fonetica."""

        def _replace_email(match: re.Match[str]) -> str:
            user = match.group(1).replace(".", " punto ").replace("_", " trattino basso ")
            domain = match.group(2).replace(".", " punto ")
            return f"{user} chiocciola {domain}"

        return re.sub(
            r"\b([a-zA-Z0-9_.+-]+)@([a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)\b", _replace_email, text
        )

    @classmethod
    def _normalize_currencies(cls, text: str) -> str:
        """Espande importi monetari in euro, dollari e sterline."""

        # 12.50€ o 12,50 € o 12,50 euro
        def _replace_euro_cents(match: re.Match[str]) -> str:
            intero = match.group(1)
            decimali = match.group(2)
            if decimali in ("0", "00"):
                return f"{intero} euro"
            if intero == "0":
                return f"{int(decimali)} centesimi"
            return f"{intero} euro e {int(decimali)} centesimi"

        text = re.sub(
            r"\b(\d+)[.,](\d{1,2})\s*(?:€|\beuro\b)",
            _replace_euro_cents,
            text,
            flags=re.IGNORECASE,
        )
        text = re.sub(r"\b(\d+)\s*(?:€|\beuro\b)", r"\1 euro", text, flags=re.IGNORECASE)

        # $10 o 10 $ o 10 dollari
        def _replace_dollar_cents(match: re.Match[str]) -> str:
            intero = match.group(1)
            decimali = match.group(2)
            if decimali in ("0", "00"):
                return f"{intero} dollari"
            return f"{intero} dollari e {int(decimali)} centesimi"

        text = re.sub(r"\$\s*(\d+)[.,](\d{1,2})\b", _replace_dollar_cents, text)
        text = re.sub(
            r"\b(\d+)[.,](\d{1,2})\s*(?:\$|\bdollari\b)",
            _replace_dollar_cents,
            text,
            flags=re.IGNORECASE,
        )
        text = re.sub(r"\$\s*(\d+)\b", r"\1 dollari", text)
        text = re.sub(r"\b(\d+)\s*(?:\$|\bdollari\b)", r"\1 dollari", text, flags=re.IGNORECASE)

        # £5 o 5 £
        text = re.sub(r"£\s*(\d+)\b", r"\1 sterline", text)
        text = re.sub(r"\b(\d+)\s*(?:£|\bsterline\b)", r"\1 sterline", text, flags=re.IGNORECASE)

        return text

    @classmethod
    def _normalize_times(cls, text: str) -> str:
        """Espande formati orari (es. 14:30 -> 14 e 30, 08:15 -> 8 e 15)."""

        def _replace_time(match: re.Match[str]) -> str:
            ore = int(match.group(1))
            minuti = match.group(2)
            if minuti == "00":
                return f"{ore}"
            if minuti == "30":
                return f"{ore} e mezza"
            if minuti == "15":
                return f"{ore} e un quarto"
            return f"{ore} e {int(minuti)}"

        # Corrisponde ad orari hh:mm preceduti/seguiti da confini o 'alle', 'ore'
        return re.sub(r"\b([01]?[0-9]|2[0-3]):([0-5][0-9])\b", _replace_time, text)

    @classmethod
    def _normalize_ordinals(cls, text: str) -> str:
        """Espande numeri ordinali (1°, 2°, 1^, 1ª)."""

        # Ordinali maschili: 1° -> primo
        def _replace_ord_m(match: re.Match[str]) -> str:
            num = match.group(1)
            return _ORDINALS_M.get(num, f"{num}esimo")

        text = re.sub(r"\b([1-9]|10)°", _replace_ord_m, text)

        # Ordinali femminili: 1^ o 1ª -> prima
        def _replace_ord_f(match: re.Match[str]) -> str:
            num = match.group(1)
            return _ORDINALS_F.get(num, f"{num}esima")

        text = re.sub(r"\b([1-9]|10)[\^ª]", _replace_ord_f, text)
        return text

    @classmethod
    def _normalize_units_and_percentages(cls, text: str) -> str:
        """Espande percentuali e unità di misura metriche frequenti."""

        # Percentuali: 20% o 20,5%
        def _replace_pct(match: re.Match[str]) -> str:
            intero = match.group(1)
            dec = match.group(2)
            if dec:
                return f"{intero} virgola {dec} percento"
            return f"{intero} percento"

        text = re.sub(r"\b(\d+)(?:[.,](\d+))?\s*%", _replace_pct, text)

        # Unità metriche con numero
        text = re.sub(r"\b(\d+)\s*km\b", r"\1 chilometri", text, flags=re.IGNORECASE)
        text = re.sub(r"\b(\d+)\s*cm\b", r"\1 centimetri", text, flags=re.IGNORECASE)
        text = re.sub(r"\b(\d+)\s*mm\b", r"\1 millimetri", text, flags=re.IGNORECASE)
        text = re.sub(r"\b(\d+)\s*kg\b", r"\1 chilogrammi", text, flags=re.IGNORECASE)
        text = re.sub(r"\b(\d+)\s*g\b(?!\w)", r"\1 grammi", text, flags=re.IGNORECASE)

        return text

    @classmethod
    def _normalize_abbreviations(cls, text: str) -> str:
        """Espande abbreviazioni frequenti preservando la maiuscola iniziale."""
        for pattern, replacement in _ABBREVIATIONS:

            def _sub_abbr(match: re.Match[str], repl: str = replacement) -> str:
                matched_text = match.group(0)
                if matched_text[0].isupper():
                    return repl.capitalize()
                return repl

            text = pattern.sub(_sub_abbr, text)
        return text

    @classmethod
    def normalize_italian(cls, text: str) -> str:
        """Applica la catena di regole di normalizzazione per la lingua italiana."""
        if not text:
            return ""

        text = cls._normalize_urls(text)
        text = cls._normalize_emails(text)
        text = cls._normalize_currencies(text)
        text = cls._normalize_times(text)
        text = cls._normalize_ordinals(text)
        text = cls._normalize_units_and_percentages(text)
        text = cls._normalize_abbreviations(text)

        # Normalizzazione spaziature
        text = re.sub(r"[ \t]+", " ", text)
        return text.strip()

    @classmethod
    def normalize(
        cls,
        text: str,
        lang: str = "it",
        enabled: bool = True,
        exclusions: list[str] | None = None,
    ) -> str:
        """Pipeline completa di normalizzazione testo."""
        if not text:
            return ""

        processed = cls.filter_exclusions(text, exclusions)

        if enabled and (lang in ("it", "auto")):
            processed = cls.normalize_italian(processed)

        return processed
