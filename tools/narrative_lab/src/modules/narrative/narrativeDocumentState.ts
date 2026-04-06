import type {
  NarrativeDocumentPayload,
  SaveNarrativeDocumentResult,
} from "../../types";
import type { EditableNarrativeDocument } from "./narrativeSessionHelpers";
import { docTypeDirectory } from "./narrativeTemplates";

// 文档本地生命周期的纯状态更新：
// 草稿创建、dirty 判断、保存结果映射、快照回滚，以及列表级纯函数更新。
export function snapshotNarrativeDocument(document: NarrativeDocumentPayload): string {
  return JSON.stringify({
    meta: document.meta,
    markdown: document.markdown,
  });
}

export function hydrateEditableDocuments(
  documents: NarrativeDocumentPayload[],
): EditableNarrativeDocument[] {
  return documents.map((document) => ({
    ...document,
    savedSnapshot: snapshotNarrativeDocument(document),
    dirty: false,
    isDraft: false,
  }));
}

export function documentIsDirty(
  document: NarrativeDocumentPayload,
  savedSnapshot: string,
): boolean {
  return snapshotNarrativeDocument(document) !== savedSnapshot;
}

export function buildEditableDraftDocument(
  docType: NarrativeDocumentPayload["meta"]["docType"],
  title: string,
  markdown: string,
): EditableNarrativeDocument {
  const stamp = Date.now();
  const slug = `draft-${stamp}`;
  const document: NarrativeDocumentPayload = {
    documentKey: slug,
    originalSlug: slug,
    fileName: `${slug}.md`,
    relativePath: `narrative/${docTypeDirectory(docType)}/${slug}.md`,
    meta: {
      docType,
      slug,
      title,
      status: "draft",
      tags: [],
      relatedDocs: [],
      sourceRefs: [],
    },
    markdown,
    validation: [],
  };
  return {
    ...document,
    savedSnapshot: snapshotNarrativeDocument(document),
    dirty: true,
    isDraft: true,
  };
}

export function applySavedDocumentResult(
  document: EditableNarrativeDocument,
  result: SaveNarrativeDocumentResult,
): EditableNarrativeDocument {
  const savedSlug = result.savedSlug;
  const nextDocument: EditableNarrativeDocument = {
    ...document,
    documentKey: savedSlug,
    originalSlug: savedSlug,
    fileName: `${savedSlug}.md`,
    relativePath: `narrative/${docTypeDirectory(document.meta.docType)}/${savedSlug}.md`,
    meta: {
      ...document.meta,
      slug: savedSlug,
    },
    dirty: false,
    isDraft: false,
    savedSnapshot: "",
  };
  nextDocument.savedSnapshot = snapshotNarrativeDocument(nextDocument);
  return nextDocument;
}

export function mergeSavedDocumentIntoCurrent(
  currentDocument: EditableNarrativeDocument,
  savedDocument: EditableNarrativeDocument,
  savedRequestSnapshot: string,
): EditableNarrativeDocument {
  if (snapshotNarrativeDocument(currentDocument) === savedRequestSnapshot) {
    return savedDocument;
  }

  return markDocumentDirtyState(
    {
      ...currentDocument,
      documentKey: savedDocument.documentKey,
      originalSlug: savedDocument.originalSlug,
      fileName: savedDocument.fileName,
      relativePath: savedDocument.relativePath,
      meta: {
        ...currentDocument.meta,
        slug: savedDocument.meta.slug,
      },
      isDraft: false,
    },
    savedDocument.savedSnapshot,
  );
}

export function revertDocumentToSnapshot(
  document: EditableNarrativeDocument,
  snapshot: string,
): EditableNarrativeDocument {
  try {
    const parsed = JSON.parse(snapshot) as Pick<
      NarrativeDocumentPayload,
      "meta" | "markdown"
    >;
    return {
      ...document,
      meta: parsed.meta,
      markdown: parsed.markdown,
      dirty: false,
    };
  } catch {
    return document;
  }
}

export function markDocumentDirtyState(
  document: EditableNarrativeDocument,
  savedSnapshot: string,
): EditableNarrativeDocument {
  return {
    ...document,
    dirty: document.isDraft || documentIsDirty(document, savedSnapshot),
    savedSnapshot,
  };
}

export function updateEditableDocument(
  documents: EditableNarrativeDocument[],
  documentKey: string,
  transform: (document: EditableNarrativeDocument) => EditableNarrativeDocument,
): EditableNarrativeDocument[] {
  return documents.map((document) => {
    if (document.documentKey !== documentKey) {
      return document;
    }

    return markDocumentDirtyState(transform(document), document.savedSnapshot);
  });
}

export function removeEditableDocument(
  documents: EditableNarrativeDocument[],
  documentKey: string,
): EditableNarrativeDocument[] {
  return documents.filter((document) => document.documentKey !== documentKey);
}

export function replaceEditableDocument(
  documents: EditableNarrativeDocument[],
  documentKey: string,
  nextDocument: EditableNarrativeDocument,
): EditableNarrativeDocument[] {
  return documents.map((document) =>
    document.documentKey === documentKey ? nextDocument : document,
  );
}
