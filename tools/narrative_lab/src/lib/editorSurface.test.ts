import { describe, expect, it } from "vitest";
import { getRequestedDocumentKey, getRequestedSettingsSection, resolveEditorSurface } from "./editorSurface";

describe("editorSurface", () => {
  it("prefers the dedicated map-editor surface from query string", () => {
    expect(resolveEditorSurface({ search: "?surface=map-editor" })).toBe("main");
  });

  it("prefers the dedicated settings surface from query string", () => {
    expect(resolveEditorSurface({ search: "?surface=settings&section=ai" })).toBe("settings");
  });

  it("falls back to settings surface when the current label is settings", () => {
    expect(resolveEditorSurface({ label: "settings" })).toBe("settings");
  });

  it("defaults to the main surface otherwise", () => {
    expect(resolveEditorSurface({ search: "?surface=main" })).toBe("main");
  });

  it("reads the requested document key from the query string", () => {
    expect(getRequestedDocumentKey("?surface=map-editor&documentKey=survivor_outpost_01")).toBe(
      "survivor_outpost_01",
    );
  });

  it("reads the requested settings section from the query string", () => {
    expect(getRequestedSettingsSection("?surface=settings&section=narrative-sync")).toBe(
      "narrative-sync",
    );
  });

  it("falls back to ai settings section for invalid input", () => {
    expect(getRequestedSettingsSection("?surface=settings&section=invalid")).toBe("ai");
  });
});
