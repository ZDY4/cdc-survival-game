import { afterEach, describe, expect, it, vi } from "vitest";
import { EditableNarrativeDocument } from "./narrativeSessionHelpers";
import {
  applySavedDocumentResult,
  buildEditableDraftDocument,
  hydrateEditableDocuments,
  markDocumentDirtyState,
  removeEditableDocument,
  replaceEditableDocument,
  revertDocumentToSnapshot,
  snapshotNarrativeDocument,
  updateEditableDocument,
} from "./narrativeDocumentState";

describe("narrativeDocumentState", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("builds a draft document with predictable metadata", () => {
    vi.useFakeTimers();
    vi.setSystemTime(1_234_567_890_000);

    const draft = buildEditableDraftDocument("task_setup", "任务标题", "# content");

    expect(draft.documentKey).toBe("draft-1234567890000");
    expect(draft.meta.slug).toBe("draft-1234567890000");
    expect(draft.fileName).toBe("draft-1234567890000.md");
    expect(draft.relativePath).toBe("narrative/tasks/draft-1234567890000.md");
    expect(draft.isDraft).toBe(true);
    expect(draft.dirty).toBe(true);
    expect(draft.savedSnapshot).toBe(snapshotNarrativeDocument(draft));
  });

  it("applies saved results and resets draft flags", () => {
    const draft = buildEditableDraftDocument("task_setup", "任务标题", "# before");
    const saved = applySavedDocumentResult(draft, { savedSlug: "quest-001" });

    expect(saved.documentKey).toBe("quest-001");
    expect(saved.originalSlug).toBe("quest-001");
    expect(saved.fileName).toBe("quest-001.md");
    expect(saved.relativePath).toBe("narrative/tasks/quest-001.md");
    expect(saved.meta.slug).toBe("quest-001");
    expect(saved.isDraft).toBe(false);
    expect(saved.dirty).toBe(false);
    expect(saved.savedSnapshot).toBe(snapshotNarrativeDocument(saved));
  });

  it("reverts mutated document to a snapshot", () => {
    const draft = buildEditableDraftDocument("task_setup", "任务标题", "# before");
    const mutated: EditableNarrativeDocument = {
      ...draft,
      markdown: "# after",
      meta: { ...draft.meta, title: "改名" },
      dirty: true,
    };

    const reverted = revertDocumentToSnapshot(mutated, draft.savedSnapshot);

    expect(reverted.markdown).toBe(draft.markdown);
    expect(reverted.meta.title).toBe(draft.meta.title);
    expect(reverted.dirty).toBe(false);
  });

  it("returns original document when snapshot deserialization fails", () => {
    const draft = buildEditableDraftDocument("task_setup", "任务标题", "# before");
    const mutated = { ...draft, markdown: "broken" };

    const reverted = revertDocumentToSnapshot(mutated, "not-json");

    expect(reverted).toBe(mutated);
  });

  it("marks dirty flag based on provided snapshot", () => {
    const draft = buildEditableDraftDocument("task_setup", "任务标题", "# content");
    const sameState = markDocumentDirtyState(draft, draft.savedSnapshot);
    expect(sameState.dirty).toBe(true);

    const changed: EditableNarrativeDocument = { ...draft, markdown: draft.markdown + " extra" };
    const dirtyState = markDocumentDirtyState(changed, draft.savedSnapshot);
    expect(dirtyState.dirty).toBe(true);
    expect(dirtyState.savedSnapshot).toBe(draft.savedSnapshot);
  });

  it("hydrates saved documents as clean editable documents", () => {
    const [document] = hydrateEditableDocuments([
      {
        documentKey: "doc-1",
        originalSlug: "doc-1",
        fileName: "doc-1.md",
        relativePath: "narrative/tasks/doc-1.md",
        meta: {
          docType: "task_setup",
          slug: "doc-1",
          title: "文稿 1",
          status: "draft",
          tags: [],
          relatedDocs: [],
          sourceRefs: [],
        },
        markdown: "# 内容",
        validation: [],
      },
    ]);

    expect(document.dirty).toBe(false);
    expect(document.isDraft).toBe(false);
    expect(document.savedSnapshot).toBeTruthy();
  });

  it("updates and replaces editable document entries through pure helpers", () => {
    const draft = buildEditableDraftDocument("task_setup", "任务标题", "# before");

    const updated = updateEditableDocument([draft], draft.documentKey, (document) => ({
      ...document,
      markdown: "# after",
    }));
    expect(updated[0]?.markdown).toBe("# after");
    expect(updated[0]?.dirty).toBe(true);

    const saved = applySavedDocumentResult(draft, { savedSlug: "saved-doc" });
    const replaced = replaceEditableDocument(updated, draft.documentKey, saved);
    expect(replaced[0]?.documentKey).toBe("saved-doc");

    const removed = removeEditableDocument(replaced, "saved-doc");
    expect(removed).toHaveLength(0);
  });
});
