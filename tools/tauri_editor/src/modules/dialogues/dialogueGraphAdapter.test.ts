import { describe, expect, it } from "vitest";
import type { DialogueData } from "../../types";
import {
  getDialogueNodeCatalog,
  setDialogueNodeOptions,
  dialogueGraphAdapter,
} from "./dialogueGraphAdapter";

describe("dialogueGraphAdapter", () => {
  it("normalizes legacy dialogue documents with deterministic auto layout", () => {
    const legacyDialog: DialogueData = {
      dialog_id: "legacy_case",
      quest_hook: "intro",
      nodes: [
        {
          id: "start",
          type: "dialog",
          title: "Start",
          speaker: "Guide",
          text: "Welcome",
          is_start: true,
          next: "branch",
          legacy_flag: true,
        },
        {
          id: "branch",
          type: "choice",
          title: "Branch",
          options: [
            { text: "Accept", next: "end_accept", mood: "up" },
            { text: "Decline", next: "end_decline" },
          ],
        },
        {
          id: "end_accept",
          type: "end",
          title: "Accepted",
          end_type: "success",
        },
        {
          id: "end_decline",
          type: "end",
          title: "Declined",
          end_type: "normal",
        },
      ],
      connections: [],
    };

    const normalized = dialogueGraphAdapter.normalizeDocument(legacyDialog);
    const normalizedAgain = dialogueGraphAdapter.normalizeDocument(normalized);

    expect(normalized.connections).toHaveLength(3);
    expect(normalized.nodes.every((node) => Number.isFinite(node.position?.x))).toBe(true);
    expect(normalized.nodes.every((node) => Number.isFinite(node.position?.y))).toBe(true);
    expect(normalized.quest_hook).toBe("intro");
    expect(normalized.nodes[0].legacy_flag).toBe(true);
    expect(normalized.nodes[1].options?.[0].mood).toBe("up");
    expect(normalizedAgain).toEqual(normalized);
  });

  it("clears linked next fields when an edge is deleted", () => {
    const document: DialogueData = {
      dialog_id: "delete_edge_case",
      nodes: [
        {
          id: "start",
          type: "dialog",
          title: "Start",
          text: "Hello",
          is_start: true,
          next: "end",
        },
        {
          id: "end",
          type: "end",
          title: "End",
          end_type: "normal",
        },
      ],
      connections: [
        {
          from: "start",
          from_port: 0,
          to: "end",
          to_port: 0,
        },
      ],
    };

    const nextDocument = dialogueGraphAdapter.deleteEdges(document, ["start:0->end:0"]);
    const startNode = nextDocument.nodes.find((node) => node.id === "start");

    expect(nextDocument.connections).toEqual([]);
    expect(startNode?.next).toBe("");
  });

  it("keeps choice output handles in sync with option count", () => {
    const document: DialogueData = {
      dialog_id: "choice_ports_case",
      nodes: [
        {
          id: "start",
          type: "dialog",
          title: "Start",
          text: "Hello",
          is_start: true,
          next: "choice_1",
        },
        {
          id: "choice_1",
          type: "choice",
          title: "Choice",
          options: [
            { text: "One", next: "end_1" },
            { text: "Two", next: "end_2" },
          ],
        },
        { id: "end_1", type: "end", title: "End 1", end_type: "normal" },
        { id: "end_2", type: "end", title: "End 2", end_type: "normal" },
      ],
      connections: [
        { from: "start", from_port: 0, to: "choice_1", to_port: 0 },
        { from: "choice_1", from_port: 0, to: "end_1", to_port: 0 },
        { from: "choice_1", from_port: 1, to: "end_2", to_port: 0 },
      ],
    };

    const trimmed = setDialogueNodeOptions(document, "choice_1", [{ text: "Only", next: "end_1" }]);
    const choiceNode = trimmed.nodes.find((node) => node.id === "choice_1");
    const choiceDefinition = getDialogueNodeCatalog().find((definition) => definition.type === "choice");

    expect(choiceNode?.options).toHaveLength(1);
    expect(trimmed.connections.filter((connection) => connection.from === "choice_1")).toHaveLength(1);
    expect(choiceDefinition?.getOutputHandles(choiceNode!)).toEqual([{ id: "option-0", label: "Only" }]);
  });

  it("uses fixed true and false handles for condition nodes", () => {
    const conditionDefinition = getDialogueNodeCatalog().find(
      (definition) => definition.type === "condition",
    );

    expect(
      conditionDefinition?.getOutputHandles({
        id: "condition_1",
        type: "condition",
        title: "Condition",
        condition: "player.has_bandage",
        position: { x: 0, y: 0 },
      }),
    ).toEqual([
      { id: "true", label: "true" },
      { id: "false", label: "false" },
    ]);
  });

  it("prevents wiring arbitrary branches back into the start node", () => {
    const document: DialogueData = {
      dialog_id: "start_guard_case",
      nodes: [
        {
          id: "start",
          type: "dialog",
          title: "Start",
          text: "Intro",
          is_start: true,
          next: "branch",
        },
        {
          id: "branch",
          type: "dialog",
          title: "Branch",
          text: "Branch",
          next: "",
        },
      ],
      connections: [{ from: "start", from_port: 0, to: "branch", to_port: 0 }],
    };

    expect(
      dialogueGraphAdapter.canConnect?.(document, {
        source: "branch",
        sourceHandle: "next",
        target: "start",
        targetHandle: "input",
      }),
    ).toBe("Start node cannot have incoming rewires from arbitrary branches.");
  });
});
