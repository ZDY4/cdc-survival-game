import type {
  NarrativeGenerateResponse,
  NarrativeSelectionRange,
} from "../../types";

export function toUtf8SelectionRange(source: string, startUtf16: number, endUtf16: number): NarrativeSelectionRange {
  const encoder = new TextEncoder();
  const start = encoder.encode(source.slice(0, startUtf16)).length;
  const end = encoder.encode(source.slice(0, endUtf16)).length;
  return { start, end };
}

export function applySelectionRange(
  source: string,
  range: NarrativeSelectionRange,
  replacement: string,
  mode: "replace" | "insert_after",
): string {
  const startIndex = utf8ByteOffsetToJsIndex(source, range.start);
  const endIndex = utf8ByteOffsetToJsIndex(source, range.end);
  if (mode === "insert_after") {
    return `${source.slice(0, endIndex)}${replacement}${source.slice(endIndex)}`;
  }
  return `${source.slice(0, startIndex)}${replacement}${source.slice(endIndex)}`;
}

export function narrativeDiffSummary(
  currentMarkdown: string,
  response: NarrativeGenerateResponse | null,
  selectedText: string,
): string {
  if (!response) {
    return "暂无草稿可预览";
  }
  if (response.diffPreview.trim()) {
    return response.diffPreview;
  }

  switch (response.changeScope) {
    case "selection":
      return `Current selection\n${selectedText || "(empty)"}\n\nDraft replacement\n${response.draftMarkdown || "(empty)"}`;
    case "insertion":
      return `Insert after selection\n${selectedText || "(empty)"}\n\nInserted text\n${response.draftMarkdown || "(empty)"}`;
    default:
      return `Current document\n${currentMarkdown || "(empty)"}\n\nDraft document\n${response.draftMarkdown || "(empty)"}`;
  }
}

function utf8ByteOffsetToJsIndex(source: string, offset: number): number {
  if (offset <= 0) {
    return 0;
  }

  const encoder = new TextEncoder();
  let jsIndex = 0;
  while (jsIndex < source.length) {
    const nextIndex = jsIndex + 1;
    const bytes = encoder.encode(source.slice(0, nextIndex)).length;
    if (bytes >= offset) {
      return nextIndex;
    }
    jsIndex = nextIndex;
  }
  return source.length;
}
