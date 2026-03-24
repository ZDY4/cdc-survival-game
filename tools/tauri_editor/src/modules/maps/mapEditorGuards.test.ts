import { describe, expect, it } from "vitest";
import { shouldDeferPendingIntent } from "./mapEditorGuards";

describe("mapEditorGuards", () => {
  it("requires a prompt when switching away from a dirty document", () => {
    expect(
      shouldDeferPendingIntent(true, "safehouse_grid", {
        type: "switch-document",
        documentKey: "street_block",
      }),
    ).toBe(true);
  });

  it("does not prompt when re-opening the same document", () => {
    expect(
      shouldDeferPendingIntent(true, "safehouse_grid", {
        type: "switch-document",
        documentKey: "safehouse_grid",
      }),
    ).toBe(false);
  });

  it("does not prompt for a clean document", () => {
    expect(shouldDeferPendingIntent(false, "safehouse_grid", { type: "close-window" })).toBe(
      false,
    );
  });
});
