import type { NarrativeCandidatePatch, NarrativePatchSet } from "../../types";

// Markdown patch 构建层：
// 负责分块、标题归属、patch 类型判定，以及无法稳定拆块时的整篇回退逻辑。
type MarkdownBlockType = "heading" | "list" | "quote" | "code" | "paragraph";

type MarkdownBlock = {
  text: string;
  type: MarkdownBlockType;
  sectionTitle: string | null;
};

export function normalizeNarrativeMarkdown(markdown: string): string {
  return markdown.replace(/\r\n/g, "\n").trim();
}

function isHeadingLine(line: string) {
  return /^#{1,6}(\s|$)/.test(line.trim());
}

function detectBlockType(text: string): MarkdownBlockType {
  const firstLine = text.split("\n").find((line) => line.trim())?.trim() ?? "";
  if (!firstLine) {
    return "paragraph";
  }
  if (isHeadingLine(firstLine)) {
    return "heading";
  }
  if (/^```/.test(firstLine)) {
    return "code";
  }
  if (/^>/.test(firstLine)) {
    return "quote";
  }
  if (/^(?:[-*+]|\d+\.)\s/.test(firstLine)) {
    return "list";
  }
  return "paragraph";
}

function extractHeadingTitle(text: string): string | null {
  const heading = text
    .split("\n")
    .map((line) => line.trim())
    .find((line) => isHeadingLine(line));

  if (!heading) {
    return null;
  }

  return heading.replace(/^#{1,6}\s*/, "").trim() || null;
}

function splitMarkdownBlocks(markdown: string): MarkdownBlock[] {
  const normalized = normalizeNarrativeMarkdown(markdown);
  if (!normalized) {
    return [];
  }

  const blocks: MarkdownBlock[] = [];
  let buffer: string[] = [];
  let inCodeFence = false;
  let currentSection: string | null = null;

  const flush = () => {
    if (!buffer.length) {
      return;
    }
    const chunk = buffer.join("\n").trim();
    if (chunk) {
      const headingTitle = extractHeadingTitle(chunk);
      const sectionTitle = headingTitle ?? currentSection;
      blocks.push({
        text: chunk,
        type: detectBlockType(chunk),
        sectionTitle,
      });
      if (headingTitle) {
        currentSection = headingTitle;
      }
    }
    buffer = [];
  };

  for (const line of normalized.split("\n")) {
    const trimmed = line.trim();

    if (/^```/.test(trimmed)) {
      buffer.push(line);
      inCodeFence = !inCodeFence;
      if (!inCodeFence) {
        flush();
      }
      continue;
    }

    if (inCodeFence) {
      buffer.push(line);
      continue;
    }

    if (!trimmed) {
      flush();
      continue;
    }

    if (isHeadingLine(line) && buffer.length) {
      flush();
    }

    buffer.push(line);
  }
  flush();

  return blocks;
}

function joinMarkdownBlocks(blocks: MarkdownBlock[]): string {
  return blocks.map((block) => block.text.trim()).filter(Boolean).join("\n\n").trim();
}

export function splitNarrativeMarkdownBlocks(markdown: string): string[] {
  return splitMarkdownBlocks(markdown).map((block) => block.text);
}

function buildLcsMatrix(currentBlocks: MarkdownBlock[], draftBlocks: MarkdownBlock[]): number[][] {
  const matrix = Array.from({ length: currentBlocks.length + 1 }, () =>
    Array.from({ length: draftBlocks.length + 1 }, () => 0),
  );

  for (let currentIndex = currentBlocks.length - 1; currentIndex >= 0; currentIndex -= 1) {
    for (let draftIndex = draftBlocks.length - 1; draftIndex >= 0; draftIndex -= 1) {
      matrix[currentIndex][draftIndex] =
        currentBlocks[currentIndex].text === draftBlocks[draftIndex].text
          ? matrix[currentIndex + 1][draftIndex + 1] + 1
          : Math.max(matrix[currentIndex + 1][draftIndex], matrix[currentIndex][draftIndex + 1]);
    }
  }

  return matrix;
}

function buildLcsMatches(currentBlocks: MarkdownBlock[], draftBlocks: MarkdownBlock[]) {
  const matrix = buildLcsMatrix(currentBlocks, draftBlocks);
  const matches: Array<{ currentIndex: number; draftIndex: number }> = [];
  let currentIndex = 0;
  let draftIndex = 0;

  while (currentIndex < currentBlocks.length && draftIndex < draftBlocks.length) {
    if (currentBlocks[currentIndex].text === draftBlocks[draftIndex].text) {
      matches.push({ currentIndex, draftIndex });
      currentIndex += 1;
      draftIndex += 1;
      continue;
    }

    if (matrix[currentIndex + 1][draftIndex] >= matrix[currentIndex][draftIndex + 1]) {
      currentIndex += 1;
    } else {
      draftIndex += 1;
    }
  }

  return matches;
}

function findAnchoredMatch(currentBlocks: MarkdownBlock[], draftBlocks: MarkdownBlock[]) {
  for (let currentIndex = 0; currentIndex < currentBlocks.length; currentIndex += 1) {
    const entry = currentBlocks[currentIndex];
    for (let draftIndex = 0; draftIndex < draftBlocks.length; draftIndex += 1) {
      if (entry.text === draftBlocks[draftIndex].text) {
        return { currentIndex, draftIndex };
      }
    }
  }
  return null;
}

function resolveSectionTitle(
  currentBlocks: MarkdownBlock[],
  draftBlocks: MarkdownBlock[],
  currentStart: number,
  draftStart: number,
): string | null {
  return (
    draftBlocks[draftStart]?.sectionTitle ??
    currentBlocks[currentStart]?.sectionTitle ??
    draftBlocks[draftStart - 1]?.sectionTitle ??
    currentBlocks[currentStart - 1]?.sectionTitle ??
    "未命名区块"
  );
}

function resolvePatchKind(originalText: string, replacementText: string) {
  if (!originalText && replacementText) {
    return "insert";
  }
  if (originalText && !replacementText) {
    return "delete";
  }
  return "replace";
}

function buildPatchTitle(index: number, patchKind: NarrativeCandidatePatch["patchKind"], sectionTitle: string | null) {
  const kindLabel =
    patchKind === "insert" ? "插入" : patchKind === "delete" ? "删除" : "替换";
  return sectionTitle ? `建议 ${index} · ${sectionTitle} · ${kindLabel}` : `建议 ${index} · ${kindLabel}`;
}

export function buildNarrativePatchSet(
  currentMarkdown: string,
  draftMarkdown: string,
): NarrativePatchSet {
  const currentBlocks = splitMarkdownBlocks(currentMarkdown);
  const draftBlocks = splitMarkdownBlocks(draftMarkdown);

  if (!normalizeNarrativeMarkdown(draftMarkdown)) {
    return {
      mode: "full_document",
      currentMarkdown,
      draftMarkdown,
      patches: [],
    };
  }

  let matches = buildLcsMatches(currentBlocks, draftBlocks);
  if (!matches.length) {
    const anchor = findAnchoredMatch(currentBlocks, draftBlocks);
    if (anchor) {
      matches = [anchor];
    } else {
      return {
        mode: "full_document",
        currentMarkdown,
        draftMarkdown,
        patches: [],
      };
    }
  }

  const patches: NarrativeCandidatePatch[] = [];
  let currentCursor = 0;
  let draftCursor = 0;

  for (const match of matches) {
    if (match.currentIndex > currentCursor || match.draftIndex > draftCursor) {
      const originalText = joinMarkdownBlocks(currentBlocks.slice(currentCursor, match.currentIndex));
      const replacementText = joinMarkdownBlocks(draftBlocks.slice(draftCursor, match.draftIndex));
      if (originalText !== replacementText) {
        const patchKind = resolvePatchKind(originalText, replacementText);
        const sectionTitle = resolveSectionTitle(
          currentBlocks,
          draftBlocks,
          currentCursor,
          draftCursor,
        );
        patches.push({
          id: `patch-${patches.length + 1}`,
          title: buildPatchTitle(patches.length + 1, patchKind, sectionTitle),
          sectionTitle,
          patchKind,
          startBlock: currentCursor,
          endBlock: match.currentIndex,
          originalText,
          replacementText,
        });
      }
    }
    currentCursor = match.currentIndex + 1;
    draftCursor = match.draftIndex + 1;
  }

  if (currentCursor < currentBlocks.length || draftCursor < draftBlocks.length) {
    const originalText = joinMarkdownBlocks(currentBlocks.slice(currentCursor));
    const replacementText = joinMarkdownBlocks(draftBlocks.slice(draftCursor));
    if (originalText !== replacementText) {
      const patchKind = resolvePatchKind(originalText, replacementText);
      const sectionTitle = resolveSectionTitle(currentBlocks, draftBlocks, currentCursor, draftCursor);
      patches.push({
        id: `patch-${patches.length + 1}`,
        title: buildPatchTitle(patches.length + 1, patchKind, sectionTitle),
        sectionTitle,
        patchKind,
        startBlock: currentCursor,
        endBlock: currentBlocks.length,
        originalText,
        replacementText,
      });
    }
  }

  if (!patches.length) {
    return {
      mode: "full_document",
      currentMarkdown,
      draftMarkdown,
      patches: [],
    };
  }

  return {
    mode: "patches",
    currentMarkdown,
    draftMarkdown,
    patches,
  };
}

export function applyNarrativePatch(
  sourceMarkdown: string,
  patch: NarrativeCandidatePatch,
): string {
  const blocks = splitMarkdownBlocks(sourceMarkdown);
  const replacementBlocks = splitMarkdownBlocks(patch.replacementText);

  const nextBlocks = [
    ...blocks.slice(0, patch.startBlock),
    ...replacementBlocks,
    ...blocks.slice(patch.endBlock),
  ];

  return joinMarkdownBlocks(nextBlocks);
}
