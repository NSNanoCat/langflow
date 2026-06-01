import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import {
  AUTO_LANGUAGE,
  SUPPORTED_LANGUAGES,
  type SupportedLanguage,
} from "./constants/languages";
import en from "./locales/en.json";

type LocaleMessages = Record<string, string>;

const LANGUAGE_LOADERS: Record<
  SupportedLanguage,
  () => Promise<LocaleMessages>
> = {
  en: async () => en,
  fr: async () => (await import("./locales/fr.json")).default,
  es: async () => (await import("./locales/es.json")).default,
  de: async () => (await import("./locales/de.json")).default,
  pt: async () => (await import("./locales/pt.json")).default,
  ja: async () => (await import("./locales/ja.json")).default,
  "zh-Hans": async () => (await import("./locales/zh-Hans.json")).default,
  ru: async () => (await import("./locales/ru.json")).default,
  ko: async () => (await import("./locales/ko.json")).default,
};

i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
  },
  lng: "en",
  fallbackLng: "en",
  interpolation: {
    escapeValue: false,
  },
});

/**
 * Normalizes a browser or stored language value into a supported locale.
 *
 * @param lang - Raw language value from local storage or the browser.
 * @returns A supported language code, or English when the value cannot be resolved.
 */
export function normalizeLanguage(lang?: string | null): SupportedLanguage {
  const rawLanguage = lang?.trim();

  if (!rawLanguage || rawLanguage === AUTO_LANGUAGE) {
    return "en";
  }

  const language = rawLanguage.toLowerCase();

  switch (true) {
    case language.startsWith("zh-hant") ||
      language === "zh-tw" ||
      language.startsWith("zh-tw-") ||
      language === "zh-hk" ||
      language.startsWith("zh-hk-") ||
      language === "zh-mo" ||
      language.startsWith("zh-mo-"):
      return "en";
    case language.startsWith("zh"):
      return "zh-Hans";
    case language.startsWith("ko"):
      return "ko";
    case language.startsWith("ru"):
      return "ru";
    default:
      break;
  }

  const exactLanguage = SUPPORTED_LANGUAGES.find(
    (supportedLanguage) => supportedLanguage.code.toLowerCase() === language,
  );

  if (exactLanguage) {
    return exactLanguage.code;
  }

  const baseLanguage = language.split("-")[0];
  const baseMatch = SUPPORTED_LANGUAGES.find(
    (supportedLanguage) =>
      supportedLanguage.code.toLowerCase() === baseLanguage,
  );

  return baseMatch?.code ?? "en";
}

/**
 * Reads the browser-preferred language and normalizes it into a supported locale.
 *
 * @returns A supported browser language, or English when no browser language is available.
 */
export function getBrowserLanguage(): SupportedLanguage {
  return normalizeLanguage(
    typeof navigator === "undefined" ? undefined : navigator.language,
  );
}

/**
 * Loads and switches i18n to the requested supported language.
 *
 * @param lang - Raw language value to load.
 * @returns The supported language code that was applied.
 */
export async function loadLanguage(
  lang?: string | null,
): Promise<SupportedLanguage> {
  const normalizedLanguage = normalizeLanguage(lang);

  if (!i18n.hasResourceBundle(normalizedLanguage, "translation")) {
    const messages = await LANGUAGE_LOADERS[normalizedLanguage]();
    i18n.addResourceBundle(normalizedLanguage, "translation", messages);
  }

  await i18n.changeLanguage(normalizedLanguage);
  return normalizedLanguage;
}

export default i18n;
