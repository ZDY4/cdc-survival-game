import { beforeEach, describe, expect, it, vi } from "vitest";
import { EDITOR_MENU_COMMANDS } from "../menu/menuCommands";

const emitToMock = vi.fn();
const setFocusMock = vi.fn();
const getByLabelMock = vi.fn();
const createdWindows: Array<{ label: string; options: Record<string, unknown> }> = [];

vi.mock("./tauri", () => ({
  isTauriRuntime: () => true,
  formatError: (error: unknown) => String(error),
}));

vi.mock("@tauri-apps/api/webviewWindow", () => {
  class MockWebviewWindow {
    label: string;
    options: Record<string, unknown>;

    constructor(label: string, options: Record<string, unknown> = {}) {
      this.label = label;
      this.options = options;
      createdWindows.push({ label, options });
    }

    static getByLabel(label: string) {
      return getByLabelMock(label);
    }

    static getCurrent() {
      return {
        label: "items",
        emitTo: emitToMock,
      };
    }

    async once(event: string, handler: () => void) {
      if (event === "tauri://created") {
        handler();
      }
      return () => {};
    }

    async setFocus() {
      return setFocusMock();
    }
  }

  return {
    WebviewWindow: MockWebviewWindow,
  };
});

describe("editorWindows", () => {
  beforeEach(() => {
    emitToMock.mockReset();
    setFocusMock.mockReset();
    getByLabelMock.mockReset();
    createdWindows.length = 0;
  });

  it("builds module editor URLs", async () => {
    const { buildEditorWindowUrl } = await import("./editorWindows");
    expect(buildEditorWindowUrl("items")).toBe("/?surface=items");
    expect(buildEditorWindowUrl("characters")).toBe("/?surface=characters");
    expect(buildEditorWindowUrl("dialogues")).toBe("/?surface=dialogues");
    expect(buildEditorWindowUrl("quests")).toBe("/?surface=quests");
  });

  it("maps supported module menu commands to dedicated editor surfaces", async () => {
    const { getSurfaceForModuleCommand } = await import("./editorWindows");
    expect(getSurfaceForModuleCommand(EDITOR_MENU_COMMANDS.MODULE_ITEMS)).toBe("items");
    expect(getSurfaceForModuleCommand(EDITOR_MENU_COMMANDS.MODULE_CHARACTERS)).toBe("characters");
    expect(getSurfaceForModuleCommand(EDITOR_MENU_COMMANDS.MODULE_DIALOGUES)).toBe("dialogues");
    expect(getSurfaceForModuleCommand(EDITOR_MENU_COMMANDS.MODULE_QUESTS)).toBe("quests");
  });

  it("focuses an existing module editor window", async () => {
    getByLabelMock.mockResolvedValue({
      label: "items",
      setFocus: setFocusMock,
    });

    const { openOrFocusEditorWindow } = await import("./editorWindows");
    await openOrFocusEditorWindow("items");

    expect(createdWindows).toHaveLength(0);
    expect(setFocusMock).toHaveBeenCalledTimes(1);
  });

  it("creates the dedicated module editor window when none exists", async () => {
    getByLabelMock.mockResolvedValue(null);

    const { openOrFocusEditorWindow } = await import("./editorWindows");
    await openOrFocusEditorWindow("dialogues");

    expect(createdWindows).toHaveLength(1);
    expect(createdWindows[0]).toMatchObject({
      label: "dialogues",
      options: expect.objectContaining({
        title: "CDC Dialogue Editor",
        url: "/?surface=dialogues",
      }),
    });
  });

  it("falls back to items for an invalid startup surface", async () => {
    const { getConfiguredStartupSurface } = await import("./editorWindows");
    expect(getConfiguredStartupSurface("maps")).toBe("items");
    expect(getConfiguredStartupSurface("invalid")).toBe("items");
    expect(getConfiguredStartupSurface(undefined)).toBe("items");
  });
});
