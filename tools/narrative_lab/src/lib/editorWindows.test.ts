import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  getByLabelMock,
  getCurrentMock,
  emitToMock,
  focusExistingMock,
  focusNewMock,
  onceMock,
} = vi.hoisted(() => ({
  getByLabelMock: vi.fn(),
  getCurrentMock: vi.fn(),
  emitToMock: vi.fn(),
  focusExistingMock: vi.fn(),
  focusNewMock: vi.fn(),
  onceMock: vi.fn(),
}));

vi.mock("./tauri", () => ({
  formatError: (value: unknown) => String(value),
  isTauriRuntime: () => true,
}));

vi.mock("../modules/settings/settingsWindowing", () => ({
  SETTINGS_WINDOW_LABEL: "editor-settings",
  SETTINGS_OPEN_SECTION_EVENT: "settings:open-section",
  buildSettingsWindowUrl: (section: string) => `/settings?section=${section}`,
}));

vi.mock("@tauri-apps/api/webviewWindow", () => {
  class MockWebviewWindow {
    constructor(_label: string, _options: unknown) {
      setTimeout(() => {
        const createdHandler = onceMock.mock.calls.find(
          ([eventName]: [string]) => eventName === "tauri://created",
        )?.[1];
        createdHandler?.();
      }, 0);
    }

    static getByLabel = getByLabelMock;
    static getCurrent = getCurrentMock;

    once(eventName: string, handler: () => void) {
      onceMock(eventName, handler);
      return Promise.resolve(() => undefined);
    }

    setFocus = focusNewMock;
  }

  return {
    WebviewWindow: MockWebviewWindow,
  };
});

import { openOrFocusSettingsWindow } from "./editorWindows";

describe("editorWindows", () => {
  beforeEach(() => {
    getByLabelMock.mockReset();
    getCurrentMock.mockReset();
    emitToMock.mockReset();
    focusExistingMock.mockReset();
    focusNewMock.mockReset();
    onceMock.mockReset();
    getCurrentMock.mockReturnValue({ emitTo: emitToMock });
    focusExistingMock.mockResolvedValue(undefined);
    focusNewMock.mockResolvedValue(undefined);
  });

  it("focuses and reuses the existing settings window when already open", async () => {
    getByLabelMock.mockResolvedValue({ setFocus: focusExistingMock });

    await openOrFocusSettingsWindow("ai");

    expect(focusExistingMock).toHaveBeenCalledTimes(1);
    expect(emitToMock).toHaveBeenCalledWith("editor-settings", "settings:open-section", {
      section: "ai",
    });
  });

  it("creates a new settings window when none exists", async () => {
    getByLabelMock.mockResolvedValue(null);

    await openOrFocusSettingsWindow("ai");

    expect(focusNewMock).toHaveBeenCalledTimes(1);
  });
});
