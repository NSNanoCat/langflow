import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AUTO_LANGUAGE, SUPPORTED_LANGUAGES } from "@/constants/languages";

const mockInvalidateQueries = jest.fn();
const mockSetTypes = jest.fn();
const mockLoadLanguage = jest.fn().mockResolvedValue("en");
const mockGetBrowserLanguage = jest.fn(() => "zh-Hans");
const mockNormalizeLanguage = jest.fn((lang: string) =>
  lang === "fr-FR" ? "fr" : lang,
);

jest.mock("@/i18n", () => ({
  getBrowserLanguage: mockGetBrowserLanguage,
  loadLanguage: mockLoadLanguage,
  normalizeLanguage: mockNormalizeLanguage,
}));

jest.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string) => key,
  }),
}));

jest.mock("@tanstack/react-query", () => ({
  ...jest.requireActual("@tanstack/react-query"),
  useQueryClient: () => ({ invalidateQueries: mockInvalidateQueries }),
}));

jest.mock("@/stores/typesStore", () => ({
  useTypesStore: (
    selector: (state: { setTypes: typeof mockSetTypes }) => unknown,
  ) => selector({ setTypes: mockSetTypes }),
}));

jest.mock("@/components/common/genericIconComponent", () => ({
  __esModule: true,
  default: ({ name }: { name: string }) => <span data-testid={name} />,
}));

jest.mock("@/components/ui/select", () => ({
  Select: ({
    children,
    value,
    onValueChange,
  }: {
    children: React.ReactNode;
    value?: string;
    onValueChange?: (v: string) => void;
  }) => (
    <select
      aria-label="settings.languageSelectAriaLabel"
      value={value}
      onChange={(event) => onValueChange?.(event.target.value)}
    >
      {children}
    </select>
  ),
  SelectTrigger: () => null,
  SelectValue: () => null,
  SelectContent: ({ children }: { children: React.ReactNode }) => (
    <>{children}</>
  ),
  SelectItem: ({
    children,
    value,
  }: {
    children: React.ReactNode;
    value: string;
  }) => <option value={value}>{children}</option>,
}));

import LanguageSelector from "../index";

describe("LanguageSelector", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    localStorage.clear();
  });

  it("renders Auto plus manual language options in locale file order", () => {
    render(<LanguageSelector />);

    const options = screen.getAllByRole("option");
    expect(options).toHaveLength(SUPPORTED_LANGUAGES.length + 1);
    expect(options.map((option) => option.getAttribute("value"))).toEqual([
      AUTO_LANGUAGE,
      "de",
      "en",
      "es",
      "fr",
      "ja",
      "ko",
      "pt",
      "ru",
      "zh-Hans",
    ]);
    expect(
      screen.getByRole("option", { name: /settings.languageAuto/i }),
    ).toBeInTheDocument();
    SUPPORTED_LANGUAGES.forEach((lang) => {
      expect(
        screen.getByRole("option", { name: new RegExp(lang.label) }),
      ).toBeInTheDocument();
    });
  });

  it("selects Auto by default", () => {
    render(<LanguageSelector />);

    expect(screen.getByRole("combobox")).toHaveValue(AUTO_LANGUAGE);
  });

  it("normalizes stored manual preferences before displaying them", () => {
    localStorage.setItem("languagePreference", "fr-FR");

    render(<LanguageSelector />);

    expect(mockNormalizeLanguage).toHaveBeenCalledWith("fr-FR");
    expect(screen.getByRole("combobox")).toHaveValue("fr");
  });

  it("saves manual selections and refreshes type data", async () => {
    const user = userEvent.setup();
    render(<LanguageSelector />);

    await user.selectOptions(screen.getByRole("combobox"), "de");

    await waitFor(() => {
      expect(localStorage.getItem("languagePreference")).toBe("de");
      expect(mockLoadLanguage).toHaveBeenCalledWith("de");
      expect(mockSetTypes).toHaveBeenCalledWith({});
      expect(mockInvalidateQueries).toHaveBeenCalledWith({
        queryKey: ["useGetTypes"],
      });
    });
  });

  it("clears manual preference and loads browser language when selecting Auto", async () => {
    const user = userEvent.setup();
    localStorage.setItem("languagePreference", "fr");

    render(<LanguageSelector />);
    await user.selectOptions(screen.getByRole("combobox"), AUTO_LANGUAGE);

    await waitFor(() => {
      expect(localStorage.getItem("languagePreference")).toBeNull();
      expect(mockGetBrowserLanguage).toHaveBeenCalled();
      expect(mockLoadLanguage).toHaveBeenCalledWith("zh-Hans");
      expect(mockSetTypes).toHaveBeenCalledWith({});
      expect(mockInvalidateQueries).toHaveBeenCalledWith({
        queryKey: ["useGetTypes"],
      });
    });
  });
});
