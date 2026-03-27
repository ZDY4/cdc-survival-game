import { describe, expect, it } from "vitest";
import {
  closeNarrativeTab,
  createDocumentAgentSession,
  ensureDocumentAgentSession,
  openNarrativeTab,
  updateDocumentAgentSession,
} from "./narrativeSessions";

describe("narrativeSessions", () => {
  it("opens tabs without duplicating existing entries", () => {
    const initial = { openTabs: ["doc-a"], activeTabKey: "doc-a" as string | null };
    const next = openNarrativeTab(initial, "doc-b");
    const deduped = openNarrativeTab(next, "doc-a");

    expect(next.openTabs).toEqual(["doc-a", "doc-b"]);
    expect(deduped.openTabs).toEqual(["doc-a", "doc-b"]);
    expect(deduped.activeTabKey).toBe("doc-a");
  });

  it("closes the active tab and falls back to the previous open tab", () => {
    const next = closeNarrativeTab(
      { openTabs: ["doc-a", "doc-b", "doc-c"], activeTabKey: "doc-c" },
      "doc-c",
    );

    expect(next.openTabs).toEqual(["doc-a", "doc-b"]);
    expect(next.activeTabKey).toBe("doc-b");
  });

  it("keeps document sessions isolated per tab", () => {
    const sessions = ensureDocumentAgentSession({}, "doc-a");
    const withDocA = updateDocumentAgentSession(sessions, "doc-a", (session) => ({
      ...session,
      composerText: "hello from a",
    }));
    const withDocB = updateDocumentAgentSession(withDocA, "doc-b", () =>
      createDocumentAgentSession({ composerText: "hello from b" }),
    );

    expect(withDocB["doc-a"].composerText).toBe("hello from a");
    expect(withDocB["doc-b"].composerText).toBe("hello from b");
  });
});
