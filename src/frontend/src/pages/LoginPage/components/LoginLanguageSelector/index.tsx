import LanguageSelector from "@/components/core/appHeaderComponent/components/LanguageSelector";

const LOGIN_LANGUAGE_TRIGGER_CLASS =
  "h-9 border-0 bg-transparent px-2 text-sm font-medium text-foreground shadow-none hover:bg-background/60 focus-visible:ring-1 focus-visible:ring-ring focus-visible:ring-offset-0";

/**
 * Renders the compact language selector used on login screens.
 *
 * @returns The top-right login language selector wrapper.
 */
const LoginLanguageSelector = () => (
  <div className="absolute right-6 top-5 z-10">
    <LanguageSelector
      showIcon
      triggerClassName={LOGIN_LANGUAGE_TRIGGER_CLASS}
    />
  </div>
);

export default LoginLanguageSelector;
