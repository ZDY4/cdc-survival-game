import { describe, expect, it } from "vitest";
import { resolveMapEditorShortcut } from "./mapEditorShortcuts";

describe("mapEditorShortcuts", () => {
  it("maps save shortcuts even when focus is inside inputs", () => {
    expect(
      resolveMapEditorShortcut({
        key: "s",
        ctrlKey: true,
        metaKey: false,
        altKey: false,
        target: null,
      }),
    ).toEqual({ type: "save" });
  });

  it("maps tool switching and level stepping shortcuts", () => {
    expect(
      resolveMapEditorShortcut({
        key: "2",
        ctrlKey: false,
        metaKey: false,
        altKey: false,
        target: null,
      }),
    ).toEqual({ type: "set-tool", tool: "pickup" });

    expect(
      resolveMapEditorShortcut({
        key: "]",
        ctrlKey: false,
        metaKey: false,
        altKey: false,
        target: null,
      }),
    ).toEqual({ type: "level-step", delta: 1 });
  });

  it("ignores plain typing shortcuts inside input-like targets", () => {
    expect(
      resolveMapEditorShortcut({
        key: "v",
        ctrlKey: false,
        metaKey: false,
        altKey: false,
        target: { tagName: "INPUT" } as unknown as EventTarget,
      }),
    ).toBeNull();
  });
});
