import { useTranslation } from "react-i18next";
import LanguageSelector from "@/components/core/appHeaderComponent/components/LanguageSelector";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "../../../../../../components/ui/card";

/**
 * Renders the language settings card on the General settings page.
 *
 * @returns The settings language selector card.
 */
const LanguageFormComponent = () => {
  const { t } = useTranslation();

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("settings.languageTitle")}</CardTitle>
        <CardDescription>{t("settings.languageDescription")}</CardDescription>
      </CardHeader>
      <CardContent>
        <LanguageSelector triggerClassName="w-full" />
      </CardContent>
    </Card>
  );
};

export default LanguageFormComponent;
