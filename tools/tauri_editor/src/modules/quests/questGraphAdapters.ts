import type { GraphDocumentAdapter, GraphDocumentNode, GraphPoint } from "../../graph-kit/types";
import type {
  QuestChoiceOption,
  QuestConnection,
  QuestData,
  QuestNode,
} from "../../types";

type QuestFlowGraphNode = QuestNode & GraphDocumentNode;

export type QuestRelationshipDocument = {
  quests: QuestData[];
};

type QuestRelationshipNode = GraphDocumentNode & {
  title: string;
  description: string;
};

const QUEST_FLOW_NODE_TYPES = [
  {
    type: "start",
    label: "Start",
    color: "#54b17a",
    createNode: (id: string, position: GraphPoint): QuestNode => ({
      id,
      type: "start",
      title: "Start",
      position,
    }),
  },
  {
    type: "objective",
    label: "Objective",
    color: "#5a96d9",
    createNode: (id: string, position: GraphPoint): QuestNode => ({
      id,
      type: "objective",
      title: "Objective",
      description: "",
      objective_type: "travel",
      target: "",
      count: 1,
      position,
    }),
  },
  {
    type: "dialog",
    label: "Dialog",
    color: "#d58b45",
    createNode: (id: string, position: GraphPoint): QuestNode => ({
      id,
      type: "dialog",
      title: "Dialog",
      dialog_id: "",
      position,
    }),
  },
  {
    type: "choice",
    label: "Choice",
    color: "#d5bf45",
    createNode: (id: string, position: GraphPoint): QuestNode => ({
      id,
      type: "choice",
      title: "Choice",
      options: [{ text: "Option 1", next: "" }],
      position,
    }),
  },
  {
    type: "reward",
    label: "Reward",
    color: "#6ab067",
    createNode: (id: string, position: GraphPoint): QuestNode => ({
      id,
      type: "reward",
      title: "Reward",
      rewards: {
        items: [],
        experience: 0,
        skill_points: 0,
        unlock_location: "",
        unlock_recipes: [],
        title: "",
      },
      position,
    }),
  },
  {
    type: "end",
    label: "End",
    color: "#cf6666",
    createNode: (id: string, position: GraphPoint): QuestNode => ({
      id,
      type: "end",
      title: "End",
      position,
    }),
  },
] as const;

function cloneQuest(quest: QuestData): QuestData {
  return {
    ...quest,
    prerequisites: [...(quest.prerequisites ?? [])],
    flow: {
      ...quest.flow,
      nodes: Object.fromEntries(
        Object.entries(quest.flow?.nodes ?? {}).map(([nodeId, node]) => [
          nodeId,
          {
            ...node,
            options: node.options?.map((option) => ({ ...option })) ?? [],
            rewards: node.rewards
              ? {
                  ...node.rewards,
                  items: node.rewards.items?.map((item) => ({ ...item })) ?? [],
                  unlock_recipes: [...(node.rewards.unlock_recipes ?? [])],
                }
              : undefined,
          },
        ]),
      ),
      connections: (quest.flow?.connections ?? []).map((connection) => ({ ...connection })),
    },
    _editor: quest._editor
      ? {
          ...quest._editor,
          relationship_position: quest._editor.relationship_position
            ? { ...quest._editor.relationship_position }
            : null,
        }
      : { relationship_position: { x: 0, y: 0 } },
  };
}

function ensureQuestDefaults(quest: QuestData): QuestData {
  const next = cloneQuest(quest);
  next.quest_id = next.quest_id ?? "";
  next.title = next.title ?? "";
  next.description = next.description ?? "";
  next.prerequisites = next.prerequisites ?? [];
  next.time_limit = Number.isFinite(next.time_limit) ? next.time_limit : -1;
  next.flow = next.flow ?? { start_node_id: "start", nodes: {}, connections: [] };
  next.flow.start_node_id = next.flow.start_node_id?.trim() || "start";
  next.flow.nodes = next.flow.nodes ?? {};
  next.flow.connections = next.flow.connections ?? [];
  next._editor = next._editor ?? {};
  next._editor.relationship_position = next._editor.relationship_position ?? {
    x: 160,
    y: 120,
  };

  for (const [nodeId, node] of Object.entries(next.flow.nodes)) {
    node.id = node.id?.trim() || nodeId;
    node.type = node.type?.trim() || "objective";
    node.position = node.position ?? { x: 0, y: 0 };
    if (node.type === "choice") {
      node.options = node.options?.length ? node.options : [{ text: "Option 1", next: "" }];
    }
    if (node.type === "reward") {
      node.rewards = node.rewards ?? {
        items: [],
        experience: 0,
        skill_points: 0,
        unlock_location: "",
        unlock_recipes: [],
        title: "",
      };
    }
  }

  if (!next.flow.nodes[next.flow.start_node_id]) {
    next.flow.nodes[next.flow.start_node_id] = {
      id: next.flow.start_node_id,
      type: "start",
      title: "Start",
      position: { x: 160, y: 160 },
    };
  } else {
    next.flow.nodes[next.flow.start_node_id] = {
      ...next.flow.nodes[next.flow.start_node_id],
      type: "start",
    };
  }

  if (!Object.values(next.flow.nodes).some((node) => node.type === "end")) {
    next.flow.nodes.end = {
      id: "end",
      type: "end",
      title: "End",
      position: { x: 760, y: 160 },
    };
    if (!next.flow.connections.some((connection) => connection.to === "end")) {
      next.flow.connections.push({
        from: next.flow.start_node_id,
        from_port: 0,
        to: "end",
        to_port: 0,
      });
    }
  }

  return next;
}

function flowHandleId(node: QuestNode, port: number) {
  if (node.type === "choice") {
    return `option-${port}`;
  }
  if (node.type === "dialog") {
    return `branch-${port}`;
  }
  return "next";
}

function flowHandlePort(node: QuestNode, handleId?: string | null) {
  if (node.type === "choice" && handleId?.startsWith("option-")) {
    return Number(handleId.replace("option-", "")) || 0;
  }
  if (node.type === "dialog" && handleId?.startsWith("branch-")) {
    return Number(handleId.replace("branch-", "")) || 0;
  }
  return 0;
}

function questNodeSummary(node: QuestNode) {
  switch (node.type) {
    case "objective":
      return [node.objective_type || "objective", node.description || "No objective description"];
    case "dialog":
      return [node.dialog_id || "No dialog", branchLabels(node).join(" / ") || "Single branch"];
    case "choice":
      return (node.options ?? []).map((option, index) => `${index + 1}. ${option.text || "Option"}`);
    case "reward":
      return [
        `${node.rewards?.items?.length ?? 0} items`,
        `${node.rewards?.experience ?? 0} xp / ${node.rewards?.skill_points ?? 0} sp`,
      ];
    default:
      return [node.description || node.title || node.type];
  }
}

function branchLabels(node: QuestNode) {
  const labels = Array.isArray(node.branch_labels)
    ? (node.branch_labels as string[]).filter(Boolean)
    : [];
  return labels.length ? labels : ["Next"];
}

function uniqueNodeId(nodes: Record<string, QuestNode>, prefix: string) {
  let counter = Object.keys(nodes).length + 1;
  let candidate = `${prefix}_${counter}`;
  while (nodes[candidate]) {
    counter += 1;
    candidate = `${prefix}_${counter}`;
  }
  return candidate;
}

function autoLayoutQuestFlow(quest: QuestData): QuestData {
  const next = ensureQuestDefaults(quest);
  const levels = new Map<string, number>();
  const outgoing = new Map<string, string[]>();
  for (const connection of next.flow.connections) {
    if (!outgoing.has(connection.from)) {
      outgoing.set(connection.from, []);
    }
    outgoing.get(connection.from)?.push(connection.to);
  }

  const queue = [next.flow.start_node_id];
  levels.set(next.flow.start_node_id, 0);
  while (queue.length) {
    const current = queue.shift()!;
    const currentLevel = levels.get(current) ?? 0;
    for (const target of outgoing.get(current) ?? []) {
      if (!levels.has(target)) {
        levels.set(target, currentLevel + 1);
        queue.push(target);
      }
    }
  }

  const lanes = new Map<number, number>();
  for (const [nodeId, node] of Object.entries(next.flow.nodes)) {
    const level = levels.get(nodeId) ?? 0;
    const lane = lanes.get(level) ?? 0;
    lanes.set(level, lane + 1);
    node.position = { x: 160 + level * 280, y: 140 + lane * 180 };
  }

  return next;
}

function autoLayoutRelationships(document: QuestRelationshipDocument): QuestRelationshipDocument {
  return {
    quests: document.quests.map((quest, index) => ({
      ...cloneQuest(quest),
      _editor: {
        ...(quest._editor ?? {}),
        relationship_position: {
          x: 180 + (index % 4) * 260,
          y: 140 + Math.floor(index / 4) * 180,
        },
      },
    })),
  };
}

function updateQuestById(
  document: QuestRelationshipDocument,
  questId: string,
  transform: (quest: QuestData) => QuestData,
): QuestRelationshipDocument {
  return {
    quests: document.quests.map((quest) =>
      quest.quest_id === questId ? transform(cloneQuest(quest)) : cloneQuest(quest),
    ),
  };
}

export const questFlowGraphAdapter: GraphDocumentAdapter<QuestData, QuestFlowGraphNode> = {
  normalizeDocument: ensureQuestDefaults,
  getDocumentId: (document) => document.quest_id,
  setDocumentId: (document, nextId) => ({ ...ensureQuestDefaults(document), quest_id: nextId }),
  getNodeTypes: () =>
    QUEST_FLOW_NODE_TYPES.map((definition) => ({
      type: definition.type,
      label: definition.label,
      color: definition.color,
      createNode: definition.createNode,
      getSummaryLines: (node) => questNodeSummary(node),
      getInputHandles: (node) => (node.type === "start" ? [] : [{ id: "input", label: "In" }]),
      getOutputHandles: (node) => {
        if (node.type === "end") {
          return [];
        }
        if (node.type === "choice") {
          return (node.options ?? []).map((option, index) => ({
            id: `option-${index}`,
            label: option.text || `Option ${index + 1}`,
          }));
        }
        if (node.type === "dialog") {
          return branchLabels(node).map((label, index) => ({
            id: `branch-${index}`,
            label,
          }));
        }
        return [{ id: "next", label: "Next" }];
      },
    })),
  toGraph: (document) => {
    const normalized = ensureQuestDefaults(document);
    const nodes = Object.values(normalized.flow.nodes);
    return {
      nodes,
      edges: normalized.flow.connections.map((connection) => {
        const sourceNode = normalized.flow.nodes[connection.from];
        return {
          id: `${connection.from}:${connection.from_port}->${connection.to}:${connection.to_port}`,
          source: connection.from,
          sourceHandle: sourceNode ? flowHandleId(sourceNode, connection.from_port) : "next",
          target: connection.to,
          targetHandle: "input",
        };
      }),
    };
  },
  createNode: (document, type, position) => {
    const normalized = ensureQuestDefaults(document);
    const definition = QUEST_FLOW_NODE_TYPES.find((item) => item.type === type) ?? QUEST_FLOW_NODE_TYPES[1];
    const nodeId = uniqueNodeId(normalized.flow.nodes, type);
    normalized.flow.nodes[nodeId] = definition.createNode(nodeId, position);
    return { document: normalized, nodeId };
  },
  moveNodes: (document, positions) => {
    const normalized = ensureQuestDefaults(document);
    for (const [nodeId, position] of Object.entries(positions)) {
      if (normalized.flow.nodes[nodeId]) {
        normalized.flow.nodes[nodeId] = {
          ...normalized.flow.nodes[nodeId],
          position,
        };
      }
    }
    return normalized;
  },
  connect: (document, connection) => {
    const normalized = ensureQuestDefaults(document);
    if (!connection.source || !connection.target || connection.source === connection.target) {
      return normalized;
    }
    const sourceNode = normalized.flow.nodes[connection.source];
    if (!sourceNode) {
      return normalized;
    }
    const nextConnection: QuestConnection = {
      from: connection.source,
      from_port: flowHandlePort(sourceNode, connection.sourceHandle),
      to: connection.target,
      to_port: 0,
    };
    const edgeId = `${nextConnection.from}:${nextConnection.from_port}->${nextConnection.to}:0`;
    if (
      normalized.flow.connections.some(
        (edge) => `${edge.from}:${edge.from_port}->${edge.to}:${edge.to_port}` === edgeId,
      )
    ) {
      return normalized;
    }
    normalized.flow.connections = [...normalized.flow.connections, nextConnection];
    return normalized;
  },
  deleteNodes: (document, nodeIds) => {
    const normalized = ensureQuestDefaults(document);
    for (const nodeId of nodeIds) {
      delete normalized.flow.nodes[nodeId];
    }
    normalized.flow.connections = normalized.flow.connections.filter(
      (connection) => !nodeIds.includes(connection.from) && !nodeIds.includes(connection.to),
    );
    if (nodeIds.includes(normalized.flow.start_node_id)) {
      const nextStart = Object.values(normalized.flow.nodes).find((node) => node.type === "start");
      normalized.flow.start_node_id = nextStart?.id || "start";
    }
    return ensureQuestDefaults(normalized);
  },
  deleteEdges: (document, edgeIds) => {
    const normalized = ensureQuestDefaults(document);
    normalized.flow.connections = normalized.flow.connections.filter(
      (connection) =>
        !edgeIds.includes(`${connection.from}:${connection.from_port}->${connection.to}:${connection.to_port}`),
    );
    return normalized;
  },
  autoLayout: autoLayoutQuestFlow,
  canConnect: (document, connection) => {
    if (!connection.source || !connection.target) {
      return "Source and target are required.";
    }
    if (connection.source === connection.target) {
      return "Quest flow nodes cannot connect to themselves.";
    }
    const normalized = ensureQuestDefaults(document);
    const sourceNode = normalized.flow.nodes[connection.source];
    if (!sourceNode) {
      return "Missing source node.";
    }
    const fromPort = flowHandlePort(sourceNode, connection.sourceHandle);
    if (
      normalized.flow.connections.some(
        (edge) => edge.from === connection.source && edge.from_port === fromPort && edge.to === connection.target,
      )
    ) {
      return "That connection already exists.";
    }
    return null;
  },
};

export const questRelationshipGraphAdapter: GraphDocumentAdapter<
  QuestRelationshipDocument,
  QuestRelationshipNode
> = {
  normalizeDocument: (document) => ({
    quests: document.quests.map((quest, index) => {
      const next = ensureQuestDefaults(quest);
      next._editor = next._editor ?? {};
      next._editor.relationship_position = next._editor.relationship_position ?? {
        x: 180 + (index % 4) * 260,
        y: 140 + Math.floor(index / 4) * 180,
      };
      return next;
    }),
  }),
  getDocumentId: () => "relationships",
  setDocumentId: (document) => document,
  getNodeTypes: () => [
    {
      type: "quest",
      label: "Quest",
      color: "#4f7fb2",
      createNode: (id, position) => ({
        id,
        type: "quest",
        position,
        title: id,
        description: "",
      }),
      getSummaryLines: (node) => [node.description || "Quest relationship node"],
      getInputHandles: () => [{ id: "input", label: "Prereq" }],
      getOutputHandles: () => [{ id: "next", label: "Unlocks" }],
    },
  ],
  toGraph: (document) => {
    const normalized = document.quests.map((quest, index) => {
      const next = ensureQuestDefaults(quest);
      next._editor = next._editor ?? {};
      next._editor.relationship_position = next._editor.relationship_position ?? {
        x: 180 + (index % 4) * 260,
        y: 140 + Math.floor(index / 4) * 180,
      };
      return next;
    });
    return {
      nodes: normalized.map((quest) => ({
        id: quest.quest_id,
        type: "quest",
        title: quest.title || quest.quest_id,
        description: quest.description || `${quest.prerequisites.length} prerequisites`,
        position: quest._editor?.relationship_position ?? { x: 0, y: 0 },
      })),
      edges: normalized.flatMap((quest) =>
        quest.prerequisites.map((prerequisite) => ({
          id: `${prerequisite}->${quest.quest_id}`,
          source: prerequisite,
          sourceHandle: "next",
          target: quest.quest_id,
          targetHandle: "input",
        })),
      ),
    };
  },
  createNode: (document) => {
    return { document, nodeId: "" };
  },
  moveNodes: (document, positions) => ({
    quests: document.quests.map((quest) => ({
      ...cloneQuest(quest),
      _editor: {
        ...(quest._editor ?? {}),
        relationship_position:
          positions[quest.quest_id] ?? quest._editor?.relationship_position ?? { x: 0, y: 0 },
      },
    })),
  }),
  connect: (document, connection) => {
    if (!connection.source || !connection.target || connection.source === connection.target) {
      return document;
    }
    return updateQuestById(document, connection.target, (quest) => ({
      ...quest,
      prerequisites: Array.from(new Set([...(quest.prerequisites ?? []), connection.source!])),
    }));
  },
  deleteNodes: (document) => document,
  deleteEdges: (document, edgeIds) => ({
    quests: document.quests.map((quest) => ({
      ...cloneQuest(quest),
      prerequisites: (quest.prerequisites ?? []).filter(
        (prerequisite) => !edgeIds.includes(`${prerequisite}->${quest.quest_id}`),
      ),
    })),
  }),
  autoLayout: autoLayoutRelationships,
  canConnect: (document, connection) => {
    if (!connection.source || !connection.target) {
      return "Source and target are required.";
    }
    if (connection.source === connection.target) {
      return "Quests cannot depend on themselves.";
    }
    if (
      document.quests
        .find((quest) => quest.quest_id === connection.target)
        ?.prerequisites.includes(connection.source)
    ) {
      return "That prerequisite already exists.";
    }
    return null;
  },
};
