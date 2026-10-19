/**
 * Catalogo ufficiale Supertonic 3.
 *
 * Fonti:
 * - https://github.com/supertone-oss-archive/supertonic
 * - https://github.com/supertone-oss-archive/supertonic-py/blob/main/docs/voices.md
 *
 * Gli ID M1-M5 e F1-F5 sono quelli ufficiali del modello. Gli alias
 * (Marco, Giulia, ...) sono i nomi usati dal simulatore di Lettore Native.
 */
export const SUPERTONIC_VOICES = [
  {
    id: 'M1',
    gender: 'male',
    alias: 'Marco',
    description: {
      it: 'Vivace e sicura, con un tono chiaro e standard.',
      en: 'Lively, upbeat, with confident energy and a standard, clear tone.'
    }
  },
  {
    id: 'M2',
    gender: 'male',
    alias: 'Luca',
    description: {
      it: 'Profonda e robusta, calma e composta, con una presenza solida.',
      en: 'Deep and robust, calm and composed, with a grounded presence.'
    }
  },
  {
    id: 'M3',
    gender: 'male',
    alias: 'Nico',
    description: {
      it: 'Autorevole e curata, sicura e affidabile nelle presentazioni.',
      en: 'Polished and authoritative, confident and trustworthy in presentations.'
    }
  },
  {
    id: 'M4',
    gender: 'male',
    alias: 'Leo',
    description: {
      it: 'Morbida e neutra, giovane e amichevole.',
      en: 'Soft and neutral-toned, youthful and friendly.'
    }
  },
  {
    id: 'M5',
    gender: 'male',
    alias: 'Davide',
    description: {
      it: 'Calda e pacata, naturale nel racconto.',
      en: 'Warm and soft-spoken, with a natural storytelling quality.'
    }
  },
  {
    id: 'F1',
    gender: 'female',
    alias: 'Giulia',
    description: {
      it: 'Calma e leggermente grave, stabile e composta.',
      en: 'Calm, with a slightly low tone; steady and composed.'
    }
  },
  {
    id: 'F2',
    gender: 'female',
    alias: 'Sofia',
    description: {
      it: 'Luminosa e allegra, vivace e giovanile.',
      en: 'Bright and cheerful, lively and youthful.'
    }
  },
  {
    id: 'F3',
    gender: 'female',
    alias: 'Elena',
    description: {
      it: 'Chiara e professionale, dal taglio da annunciatrice.',
      en: 'Clear and professional, with an announcer-style delivery.'
    }
  },
  {
    id: 'F4',
    gender: 'female',
    alias: 'Aurora',
    description: {
      it: 'Decisa e sicura, espressiva e nitida.',
      en: 'Crisp and confident, expressive and distinct.'
    }
  },
  {
    id: 'F5',
    gender: 'female',
    alias: 'Luna',
    description: {
      it: 'Gentile e dolce, calma e rassicurante.',
      en: 'Kind and gentle, calm and soothing.'
    }
  }
];

export const SUPERTONIC_LANGUAGES = [
  { code: 'ar', it: 'Arabo', en: 'Arabic', native: 'العربية' },
  { code: 'bg', it: 'Bulgaro', en: 'Bulgarian', native: 'Български' },
  { code: 'hr', it: 'Croato', en: 'Croatian', native: 'Hrvatski' },
  { code: 'cs', it: 'Ceco', en: 'Czech', native: 'Čeština' },
  { code: 'da', it: 'Danese', en: 'Danish', native: 'Dansk' },
  { code: 'nl', it: 'Olandese', en: 'Dutch', native: 'Nederlands' },
  { code: 'en', it: 'Inglese', en: 'English', native: 'English' },
  { code: 'et', it: 'Estone', en: 'Estonian', native: 'Eesti' },
  { code: 'fi', it: 'Finlandese', en: 'Finnish', native: 'Suomi' },
  { code: 'fr', it: 'Francese', en: 'French', native: 'Français' },
  { code: 'de', it: 'Tedesco', en: 'German', native: 'Deutsch' },
  { code: 'el', it: 'Greco', en: 'Greek', native: 'Ελληνικά' },
  { code: 'hi', it: 'Hindi', en: 'Hindi', native: 'हिन्दी' },
  { code: 'hu', it: 'Ungherese', en: 'Hungarian', native: 'Magyar' },
  { code: 'id', it: 'Indonesiano', en: 'Indonesian', native: 'Bahasa Indonesia' },
  { code: 'it', it: 'Italiano', en: 'Italian', native: 'Italiano' },
  { code: 'ja', it: 'Giapponese', en: 'Japanese', native: '日本語' },
  { code: 'ko', it: 'Coreano', en: 'Korean', native: '한국어' },
  { code: 'lv', it: 'Lettone', en: 'Latvian', native: 'Latviešu' },
  { code: 'lt', it: 'Lituano', en: 'Lithuanian', native: 'Lietuvių' },
  { code: 'pl', it: 'Polacco', en: 'Polish', native: 'Polski' },
  { code: 'pt', it: 'Portoghese', en: 'Portuguese', native: 'Português' },
  { code: 'ro', it: 'Rumeno', en: 'Romanian', native: 'Română' },
  { code: 'ru', it: 'Russo', en: 'Russian', native: 'Русский' },
  { code: 'sk', it: 'Slovacco', en: 'Slovak', native: 'Slovenčina' },
  { code: 'sl', it: 'Sloveno', en: 'Slovenian', native: 'Slovenščina' },
  { code: 'es', it: 'Spagnolo', en: 'Spanish', native: 'Español' },
  { code: 'sv', it: 'Svedese', en: 'Swedish', native: 'Svenska' },
  { code: 'tr', it: 'Turco', en: 'Turkish', native: 'Türkçe' },
  { code: 'uk', it: 'Ucraino', en: 'Ukrainian', native: 'Українська' },
  { code: 'vi', it: 'Vietnamita', en: 'Vietnamese', native: 'Tiếng Việt' }
];
