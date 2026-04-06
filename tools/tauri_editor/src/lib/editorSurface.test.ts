import { describe, expect, it } from "vitest";
import {
  getRequestedDocumentKey,
  getRequestedDocumentType,
  getRequestedSettingsSection,
  resolveEditorSurface,
} from "./editorSurface";

describe("editorSurface", () => {
  it("prefers module surfaces from the query string", () => {
    expect(resolveEditorSurface({ search: "?surface=items" })).toBe("items");
    expect(resolveEditorSurface({ search: "?surface=dialogues" })).toBe("dialogues");
    expect(resolveEditorSurface({ search: "?surface=quests" })).toBe("quests");
  });

  it("falls back to module surfaces when the current label matches a dedicated editor window", () => {
    expect(resolveEditorSurface({ label: "items" })).toBe("items");
    expect(resolveEditorSurface({ label: "dialogues" })).toBe("dialogues");
    expect(resolveEditorSurface({ label: "quests" })).toBe("quests");
  });

  it("prefers the dedicated settings surface from query string", () => {
    expect(resolveEditorSurface({ search: "?surface=settings&section=ai" })).toBe("settings");
  });

  it("falls back to settings surface when the current label is settings", () => {
    expect(resolveEditorSurface({ label: "settings" })).toBe("settings");
  });

  it("defaults to the bootstrap surface otherwise", () => {
    expect(resolveEditorSurface({ search: "?surface=main" })).toBe("main");
    expect(resolveEditorSurface({ label: "main" })).toBe("main");
  });

  it("still reads the requested document key from the query string", () => {
    expect(getRequestedDocumentKey("?surface=map-editor&documentKey=survivor_outpost_01_grid")).toBe(
      "survivor_outpost_01_grid",
    );
  });

  it("still reads the requested document type from the query string", () => {
    expect(getRequestedDocumentType("?surface=map-editor&documentType=overworld")).toBe(
      "overworld",
    );
    expect(getRequestedDocumentType("?surface=map-editor&documentType=map")).toBe("map");
  });

  it("reads the requested settings section from the query string", () => {
    expect(getRequestedSettingsSection("?surface=settings&section=ai")).toBe("ai");
  });

  it("falls back to ai settings section for invalid input", () => {
    expect(getRequestedSettingsSection("?surface=settings&section=invalid")).toBe("ai");
  });
});
