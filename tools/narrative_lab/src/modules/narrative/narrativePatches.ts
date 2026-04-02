import type { NarrativeCandidatePatch, NarrativePatchSet } from "../../types";

type MarkdownBlock = {
  text: string;
};

export function normalizeNarrativeMarkdown(markdown: string): string {
  return markdown.replace(/\r\n/g, "\n").trim();
}

function isHeadingLine(line: string) {
  return /^#{1,6}(\s|$)/.test(line.trim());
}

function splitMarkdownBlocks(markdown: string): MarkdownBlock[] {
  const normalized = normalizeNarrativeMarkdown(markdown);
  if (!normalized) {
    return [];
  }

  const blocks: MarkdownBlock[] = [];
  let buffer: string[] = [];
  const flush = () => {
    if (!buffer.length) {
      return;
    }
    const chunk = buffer.join("\n").trim();
    if (chunk) {
      blocks.push({ text: chunk });
    }
    buffer = [];
  };

  for (const line of normalized.split("\n")) {
    if (!line.trim()) {
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

function findAnchoredMatch(
  currentBlocks: MarkdownBlock[],
  draftBlocks: MarkdownBlock[],
) {
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
        patches.push({
          id: `patch-${patches.length + 1}`,
          title: `建议 ${patches.length + 1}`,
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
      patches.push({
        id: `patch-${patches.length + 1}`,
        title: `建议 ${patches.length + 1}`,
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
