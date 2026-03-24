import { describe, expect, it } from "vitest";
import { getRequestedDocumentKey, resolveEditorSurface } from "./editorSurface";

describe("editorSurface", () => {
  it("prefers the dedicated map-editor surface from query string", () => {
    expect(resolveEditorSurface({ search: "?surface=map-editor" })).toBe("map-editor");
  });

  it("falls back to map-editor surface when the current label is map-editor", () => {
    expect(resolveEditorSurface({ label: "map-editor" })).toBe("map-editor");
  });

  it("defaults to the main surface otherwise", () => {
    expect(resolveEditorSurface({ search: "?surface=main" })).toBe("main");
  });

  it("reads the requested document key from the query string", () => {
    expect(getRequestedDocumentKey("?surface=map-editor&documentKey=safehouse_grid")).toBe(
      "safehouse_grid",
    );
  });
});
