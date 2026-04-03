import { describe, expect, it } from "vitest";
import { applyNarrativePatch, buildNarrativePatchSet } from "./narrativePatches";

import { splitNarrativeMarkdownBlocks } from "./narrativePatches";

describe("narrativePatches", () => {
  it("builds block-level patches for changed markdown sections", () => {
    const current = "# A\n\nkeep\n\nold block\n\n# Tail";
    const draft = "# A\n\nkeep\n\nnew block\n\n# Tail";

    const patchSet = buildNarrativePatchSet(current, draft);

    expect(patchSet.mode).toBe("patches");
    expect(patchSet.patches).toHaveLength(1);
    expect(patchSet.patches[0].originalText).toBe("old block");
    expect(patchSet.patches[0].replacementText).toBe("new block");
    expect(patchSet.patches[0].sectionTitle).toBe("A");
    expect(patchSet.patches[0].patchKind).toBe("replace");
  });

  it("applies a single block patch back into the source markdown", () => {
    const current = "# A\n\nkeep\n\nold block\n\n# Tail";
    const patchSet = buildNarrativePatchSet(current, "# A\n\nkeep\n\nnew block\n\n# Tail");

    expect(patchSet.mode).toBe("patches");
    const next = applyNarrativePatch(current, patchSet.patches[0]);

    expect(next).toContain("new block");
    expect(next).not.toContain("old block");
    expect(next).toContain("# Tail");
  });

  it("falls back to apply-all when no stable shared blocks exist", () => {
    const patchSet = buildNarrativePatchSet("alpha", "totally different");

    expect(patchSet.mode).toBe("full_document");
    expect(patchSet.patches).toHaveLength(0);
  });

  it("treats heading plus following text as a single block", () => {
    const blocks = splitNarrativeMarkdownBlocks("# 标题\n段落 A\n\n# 另一个标题\n段落 B");

    expect(blocks[0]).toContain("# 标题");
    expect(blocks[0]).toContain("段落 A");
    expect(blocks).toHaveLength(2);
  });

  it("uses anchor match to avoid full-document fallback when heading matches", () => {
    const current = "# 章节\n\nkeep\n\nold";
    const draft = "# 章节\n\nkeep\n\nnew";

    const patchSet = buildNarrativePatchSet(current, draft);

    expect(patchSet.mode).toBe("patches");
    expect(patchSet.patches).toHaveLength(1);
    expect(patchSet.patches[0].originalText).toBe("old");
  });

  it("marks insertions and deletions with patch kinds", () => {
    const insertion = buildNarrativePatchSet("# 标题\n\n原文", "# 标题\n\n原文\n\n新增段落");
    const deletion = buildNarrativePatchSet("# 标题\n\n原文\n\n删掉我", "# 标题\n\n原文");

    expect(insertion.patches[0]?.patchKind).toBe("insert");
    expect(deletion.patches[0]?.patchKind).toBe("delete");
  });

  it("keeps code fences as standalone blocks", () => {
    const blocks = splitNarrativeMarkdownBlocks("# 标题\n\n```ts\nconst value = 1;\n```\n\n普通段落");

    expect(blocks).toHaveLength(3);
    expect(blocks[1]).toContain("```ts");
  });
});
