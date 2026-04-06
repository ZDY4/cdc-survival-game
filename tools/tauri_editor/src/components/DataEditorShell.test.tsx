import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { DataEditorShell } from "./DataEditorShell";
import type { EditorBootstrap } from "../types";

const bootstrap: EditorBootstrap = {
  appName: "CDC Content Editor",
  workspaceRoot: "G:/Projects/cdc_survival_game",
  sharedRustPath: "G:/Projects/cdc_survival_game/rust",
  activeStage: "Stage 2",
  stages: [],
  editorDomains: ["items", "dialogues"],
};

describe("DataEditorShell", () => {
  it("renders a lightweight header without the legacy modules sidebar", () => {
    const markup = renderToStaticMarkup(
      <DataEditorShell
        title="Items"
        subtitle="Item definitions and validation."
        bootstrap={bootstrap}
        runtimeLabel="Tauri host connected"
        status="Ready."
      >
        <div>Workspace content</div>
      </DataEditorShell>,
    );

    expect(markup).toContain("Items");
    expect(markup).toContain("Workspace content");
    expect(markup).not.toContain("Modules");
    expect(markup).not.toContain("module-nav");
  });
});
