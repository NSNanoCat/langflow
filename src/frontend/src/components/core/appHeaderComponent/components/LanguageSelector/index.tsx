import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import ForwardedIconComponent from "@/components/common/genericIconComponent";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  AUTO_LANGUAGE,
  LANGUAGE_PREFERENCE_STORAGE_KEY,
  SUPPORTED_LANGUAGES,
  type LanguagePreference,
} from "@/constants/languages";
import { getBrowserLanguage, loadLanguage, normalizeLanguage } from "@/i18n";
import { useTypesStore } from "@/stores/typesStore";
import {
  getLocalStorage,
  removeLocalStorage,
  setLocalStorage,
} from "@/utils/local-storage-util";

type LanguageSelectorProps = {
  className?: string;
  showIcon?: boolean;
  triggerClassName?: string;
};

/**
 * Renders the shared language selector and keeps language-dependent caches fresh.
 *
 * @param props - Styling and icon options for the selector trigger.
 * @returns The language selector with Auto and manual language options.
 */
export const LanguageSelector = ({
  className,
  showIcon = false,
  triggerClassName,
}: LanguageSelectorProps) => {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const setTypes = useTypesStore((state) => state.setTypes);
  const [languagePreference, setLanguagePreference] =
    useState<LanguagePreference>(() => {
      const storedLanguagePreference = getLocalStorage(
        LANGUAGE_PREFERENCE_STORAGE_KEY,
      );

      return storedLanguagePreference &&
        storedLanguagePreference !== AUTO_LANGUAGE
        ? normalizeLanguage(storedLanguagePreference)
        : AUTO_LANGUAGE;
    });

  const handleChange = async (code: LanguagePreference) => {
    if (code === AUTO_LANGUAGE) {
      removeLocalStorage(LANGUAGE_PREFERENCE_STORAGE_KEY);
      setLanguagePreference(AUTO_LANGUAGE);
      await loadLanguage(getBrowserLanguage());
    } else {
      const normalizedLanguage = normalizeLanguage(code);
      setLocalStorage(LANGUAGE_PREFERENCE_STORAGE_KEY, normalizedLanguage);
      setLanguagePreference(normalizedLanguage);
      await loadLanguage(normalizedLanguage);
    }

    setTypes({});
    queryClient.invalidateQueries({ queryKey: ["useGetTypes"] });
  };

  return (
    <Select
      value={languagePreference}
      onValueChange={(code) => handleChange(code as LanguagePreference)}
    >
      <SelectTrigger
        aria-label={t("settings.languageSelectAriaLabel")}
        className={[className, triggerClassName].filter(Boolean).join(" ")}
      >
        {showIcon && (
          <ForwardedIconComponent name="Globe" className="h-4 w-4 shrink-0" />
        )}
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={AUTO_LANGUAGE}>
          {t("settings.languageAuto")} ({t("settings.languageRecommended")})
        </SelectItem>
        {SUPPORTED_LANGUAGES.map((lang) => (
          <SelectItem key={lang.code} value={lang.code}>
            {lang.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
};

export default LanguageSelector;
