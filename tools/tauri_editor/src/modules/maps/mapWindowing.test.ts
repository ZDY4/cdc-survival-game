import { beforeEach, describe, expect, it, vi } from "vitest";

const emitToMock = vi.fn();
const setFocusMock = vi.fn();
const getByLabelMock = vi.fn();
const createdWindows: Array<{ label: string; options: Record<string, unknown> }> = [];

vi.mock("../../lib/tauri", () => ({
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
        label: "main",
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

describe("mapWindowing", () => {
  beforeEach(() => {
    emitToMock.mockReset();
    setFocusMock.mockReset();
    getByLabelMock.mockReset();
    createdWindows.length = 0;
  });

  it("builds a map-editor URL with a document key", async () => {
    const { buildMapEditorWindowUrl } = await import("./mapWindowing");
    expect(buildMapEditorWindowUrl("map", "survivor_outpost_01_grid")).toBe(
      "/?surface=map-editor&documentType=map&documentKey=survivor_outpost_01_grid",
    );
  });

  it("focuses an existing window instead of creating a new one", async () => {
    getByLabelMock.mockResolvedValue({
      label: "map-editor",
      setFocus: setFocusMock,
    });

    const { MAP_EDITOR_OPEN_DOCUMENT_EVENT, openOrFocusMapEditor } = await import("./mapWindowing");
    await openOrFocusMapEditor("map", "survivor_outpost_01_grid");

    expect(createdWindows).toHaveLength(0);
    expect(setFocusMock).toHaveBeenCalledTimes(1);
    expect(emitToMock).toHaveBeenCalledWith(
      "map-editor",
      MAP_EDITOR_OPEN_DOCUMENT_EVENT,
      {
        documentType: "map",
        documentKey: "survivor_outpost_01_grid",
      },
    );
  });

  it("creates the dedicated map-editor window when none exists", async () => {
    getByLabelMock.mockResolvedValue(null);

    const { openOrFocusMapEditor } = await import("./mapWindowing");
    await openOrFocusMapEditor("map", "survivor_outpost_01_grid");

    expect(createdWindows).toHaveLength(1);
    expect(createdWindows[0]).toMatchObject({
      label: "map-editor",
      options: expect.objectContaining({
        title: "CDC Map Editor",
      }),
    });
  });
});
