import { describe, expect, it } from "vitest";
import { applyNarrativePatch, buildNarrativePatchSet } from "./narrativePatches";

describe("narrativePatches", () => {
  it("builds block-level patches for changed markdown sections", () => {
    const current = "# A\n\nkeep\n\nold block\n\n# Tail";
    const draft = "# A\n\nkeep\n\nnew block\n\n# Tail";

    const patchSet = buildNarrativePatchSet(current, draft);

    expect(patchSet.mode).toBe("patches");
    expect(patchSet.patches).toHaveLength(1);
    expect(patchSet.patches[0].originalText).toBe("old block");
    expect(patchSet.patches[0].replacementText).toBe("new block");
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
});
