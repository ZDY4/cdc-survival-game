import type {
  DialogueAction,
  DialogueConnection,
  DialogueData,
  DialogueNode,
  DialogueOption,
  GraphPosition,
  ValidationIssue,
} from "../../types";
import type {
  GraphConnectionRecord,
  GraphDocumentAdapter,
  GraphDocumentNode,
  GraphEdgeRecord,
  GraphNodeTypeDefinition,
  GraphPoint,
} from "../../graph-kit/types";

type DialogueGraphNode = DialogueNode & GraphDocumentNode;

const DIALOGUE_NODE_TYPES = [
  {
    type: "dialog",
    label: "Dialog",
    color: "#4f8ed8",
  },
  {
    type: "choice",
    label: "Choice",
    color: "#d8a15a",
  },
  {
    type: "condition",
    label: "Condition",
    color: "#c874d8",
  },
  {
    type: "action",
    label: "Action",
    color: "#6ec59c",
  },
  {
    type: "end",
    label: "End",
    color: "#d86b6b",
  },
] as const;

function cloneDialogue(dialog: DialogueData): DialogueData {
  return {
    ...dialog,
    nodes: dialog.nodes.map((node) => ({
      ...node,
      position: node.position ? { ...node.position } : undefined,
      options: node.options?.map((option) => ({ ...option })) ?? [],
      actions: node.actions?.map((action) => ({ ...action })) ?? [],
    })),
    connections: dialog.connections.map((connection) => ({ ...connection })),
  };
}

function makeEdgeId(
  source: string,
  sourcePort: number,
  target: string,
): string {
  return `${source}:${sourcePort}->${target}:0`;
}

function getSourceHandle(node: DialogueNode, port: number): string {
  if (node.type === "condition") {
    return port === 0 ? "true" : "false";
  }
  if (node.type === "choice") {
    return `option-${port}`;
  }
  return "next";
}

function getSourcePort(node: DialogueNode, handle: string | null | undefined): number {
  if (node.type === "condition") {
    return handle === "false" ? 1 : 0;
  }
  if (node.type === "choice") {
    const match = /^option-(\d+)$/.exec(handle ?? "");
    return match ? Number(match[1]) : 0;
  }
  return 0;
}

function dialogueConnectionToEdge(
  connection: DialogueConnection,
  nodeMap: Map<string, DialogueNode>,
): GraphEdgeRecord {
  const sourceNode = nodeMap.get(connection.from);
  const sourceHandle = sourceNode ? getSourceHandle(sourceNode, connection.from_port) : "next";
  return {
    id: makeEdgeId(connection.from, connection.from_port, connection.to),
    source: connection.from,
    sourceHandle,
    target: connection.to,
    targetHandle: "input",
  };
}

function ensureNodeDefaults(node: DialogueNode): DialogueNode {
  const next = cloneNode(node);
  next.title = next.title ?? "";
  next.speaker = next.speaker ?? "";
  next.text = next.text ?? "";
  next.portrait = next.portrait ?? "";
  next.next = next.next ?? "";
  next.options = next.options?.map((option) => ({ ...option })) ?? [];
  next.actions = next.actions?.map((action) => ({ ...action })) ?? [];
  next.condition = next.condition ?? "";
  next.true_next = next.true_next ?? "";
  next.false_next = next.false_next ?? "";
  next.end_type = next.end_type ?? "";

  switch (next.type) {
    case "dialog":
      next.title ||= next.is_start ? "Start" : "Dialog";
      next.speaker ||= "NPC";
      break;
    case "choice":
      next.title ||= "Choice";
      if (next.options.length === 0) {
        next.options = [
          { text: "Option 1", next: "" },
          { text: "Option 2", next: "" },
        ];
      }
      break;
    case "condition":
      next.title ||= "Condition";
      break;
    case "action":
      next.title ||= "Action";
      if (next.actions.length === 0) {
        next.actions = [{ type: "open_trade" }];
      }
      break;
    case "end":
      next.title ||= "End";
      next.end_type ||= "normal";
      break;
  }

  return next;
}

function cloneNode(node: DialogueNode): DialogueNode {
  return {
    ...node,
    position: node.position ? { ...node.position } : undefined,
    options: node.options?.map((option) => ({ ...option })) ?? [],
    actions: node.actions?.map((action) => ({ ...action })) ?? [],
  };
}

function buildNodeDefinitions(): GraphNodeTypeDefinition<DialogueGraphNode>[] {
  return DIALOGUE_NODE_TYPES.map((nodeType) => ({
    ...nodeType,
    createNode: (id: string, position: GraphPoint) =>
      ensureNodeDefaults({
        id,
        type: nodeType.type,
        position,
        is_start: false,
      }),
    getSummaryLines: (node) => {
      switch (node.type) {
        case "dialog":
          return [node.speaker || "NPC", (node.text || "Empty dialog").slice(0, 80)];
        case "choice":
          return [
            `${node.options?.length ?? 0} options`,
            ...(node.options ?? []).slice(0, 2).map((option) => option.text || "Untitled option"),
          ];
        case "condition":
          return [node.condition || "Condition is empty"];
        case "action":
          return [`${node.actions?.length ?? 0} actions`];
        case "end":
          return [node.end_type || "normal"];
        default:
          return [node.type];
      }
    },
    getInputHandles: () => [{ id: "input", label: "in" }],
    getOutputHandles: (node) => {
      switch (node.type) {
        case "dialog":
        case "action":
          return [{ id: "next", label: "next" }];
        case "choice":
          return (node.options ?? []).map((option, index) => ({
            id: `option-${index}`,
            label: option.text || `option ${index + 1}`,
          }));
        case "condition":
          return [
            { id: "true", label: "true" },
            { id: "false", label: "false" },
          ];
        default:
          return [];
      }
    },
  }));
}

function deriveConnectionsFromNodeFields(dialog: DialogueData): DialogueConnection[] {
  const connections: DialogueConnection[] = [];

  for (const node of dialog.nodes) {
    if ((node.type === "dialog" || node.type === "action") && node.next?.trim()) {
      connections.push({
        from: node.id,
        from_port: 0,
        to: node.next,
        to_port: 0,
      });
    }
    if (node.type === "choice") {
      for (const [index, option] of (node.options ?? []).entries()) {
        if (!option.next?.trim()) {
          continue;
        }
        connections.push({
          from: node.id,
          from_port: index,
          to: option.next,
          to_port: 0,
        });
      }
    }
    if (node.type === "condition") {
      if (node.true_next?.trim()) {
        connections.push({
          from: node.id,
          from_port: 0,
          to: node.true_next,
          to_port: 0,
        });
      }
      if (node.false_next?.trim()) {
        connections.push({
          from: node.id,
          from_port: 1,
          to: node.false_next,
          to_port: 0,
        });
      }
    }
  }

  return connections;
}

function mergeConnections(dialog: DialogueData): DialogueConnection[] {
  const merged = new Map<string, DialogueConnection>();
  for (const connection of dialog.connections ?? []) {
    const key = `${connection.from}:${connection.from_port}->${connection.to}:${connection.to_port}`;
    merged.set(key, { ...connection });
  }
  for (const connection of deriveConnectionsFromNodeFields(dialog)) {
    const key = `${connection.from}:${connection.from_port}->${connection.to}:${connection.to_port}`;
    if (!merged.has(key)) {
      merged.set(key, connection);
    }
  }
  return [...merged.values()];
}

function syncNodeFieldsFromConnections(dialog: DialogueData): DialogueData {
  const next = cloneDialogue(dialog);
  const nodeMap = new Map(next.nodes.map((node) => [node.id, ensureNodeDefaults(node)]));
  next.nodes = [...nodeMap.values()];

  for (const node of next.nodes) {
    if (node.type === "dialog" || node.type === "action") {
      node.next = "";
    }
    if (node.type === "choice") {
      node.options = (node.options ?? []).map((option) => ({ ...option, next: "" }));
    }
    if (node.type === "condition") {
      node.true_next = "";
      node.false_next = "";
    }
  }

  for (const connection of next.connections) {
    const sourceNode = nodeMap.get(connection.from);
    if (!sourceNode) {
      continue;
    }
    if ((sourceNode.type === "dialog" || sourceNode.type === "action") && connection.from_port === 0) {
      sourceNode.next = connection.to;
    }
    if (sourceNode.type === "choice") {
      const option = sourceNode.options?.[connection.from_port];
      if (option) {
        option.next = connection.to;
      }
    }
    if (sourceNode.type === "condition") {
      if (connection.from_port === 0) {
        sourceNode.true_next = connection.to;
      }
      if (connection.from_port === 1) {
        sourceNode.false_next = connection.to;
      }
    }
  }

  next.nodes = next.nodes.map((node) => nodeMap.get(node.id) ?? node);
  return next;
}

function ensureSingleStart(dialog: DialogueData): DialogueData {
  const next = cloneDialogue(dialog);
  let startNodeId =
    next.nodes.find((node) => node.is_start)?.id ??
    next.nodes.find((node) => node.id === "start")?.id ??
    next.nodes[0]?.id;

  if (!startNodeId && next.nodes.length === 0) {
    return next;
  }

  next.nodes = next.nodes.map((node) => ({
    ...node,
    is_start: node.id === startNodeId,
  }));

  const startNode = next.nodes.find((node) => node.id === startNodeId);
  if (startNode && startNode.type !== "dialog") {
    startNode.type = "dialog";
    startNode.title ||= "Start";
  }

  return next;
}

function autoLayoutDialogue(dialog: DialogueData): DialogueData {
  const next = cloneDialogue(dialog);
  const edges = mergeConnections(next);
  const adjacency = new Map<string, string[]>();
  for (const connection of edges) {
    const list = adjacency.get(connection.from) ?? [];
    list.push(connection.to);
    adjacency.set(connection.from, list);
  }

  const startId =
    next.nodes.find((node) => node.is_start)?.id ??
    next.nodes.find((node) => node.id === "start")?.id ??
    next.nodes[0]?.id;
  const layers = new Map<number, string[]>();
  const depthMap = new Map<string, number>();
  const queue = startId ? [startId] : [];
  if (startId) {
    depthMap.set(startId, 0);
  }

  while (queue.length > 0) {
    const current = queue.shift()!;
    const depth = depthMap.get(current) ?? 0;
    const layer = layers.get(depth) ?? [];
    if (!layer.includes(current)) {
      layer.push(current);
      layers.set(depth, layer);
    }
    for (const target of adjacency.get(current) ?? []) {
      if (!depthMap.has(target)) {
        depthMap.set(target, depth + 1);
        queue.push(target);
      }
    }
  }

  let fallbackDepth = layers.size;
  for (const node of next.nodes) {
    if (!depthMap.has(node.id)) {
      depthMap.set(node.id, fallbackDepth);
      layers.set(fallbackDepth, [...(layers.get(fallbackDepth) ?? []), node.id]);
      fallbackDepth += 1;
    }
  }

  for (const [depth, nodeIds] of layers.entries()) {
    nodeIds.forEach((nodeId, index) => {
      const node = next.nodes.find((entry) => entry.id === nodeId);
      if (!node) {
        return;
      }
      const centeredIndex = index - (nodeIds.length - 1) / 2;
      node.position = {
        x: 140 + depth * 320,
        y: 220 + centeredIndex * 180,
      };
    });
  }

  return next;
}

function normalizeDialogue(dialog: DialogueData): DialogueData {
  let next = cloneDialogue(dialog);
  next.nodes = next.nodes.map((node) => ensureNodeDefaults(node));
  next = ensureSingleStart(next);
  next.connections = mergeConnections(next);
  next = syncNodeFieldsFromConnections(next);

  const needsLayout = next.nodes.some(
    (node) =>
      node.position == null ||
      !Number.isFinite(node.position.x) ||
      !Number.isFinite(node.position.y),
  );
  if (needsLayout) {
    next = autoLayoutDialogue(next);
  }

  return next;
}

function getNodeTypeDefinition(type: string): GraphNodeTypeDefinition<DialogueGraphNode> {
  const definition = buildNodeDefinitions().find((entry) => entry.type === type);
  if (!definition) {
    throw new Error(`Unknown dialogue node type: ${type}`);
  }
  return definition;
}

function replaceNode(
  dialog: DialogueData,
  nodeId: string,
  transform: (node: DialogueNode) => DialogueNode,
): DialogueData {
  const next = cloneDialogue(dialog);
  next.nodes = next.nodes.map((node) => (node.id === nodeId ? transform(cloneNode(node)) : node));
  next.connections = mergeConnections(next);
  return syncNodeFieldsFromConnections(next);
}

function updateDialogueNodeId(dialog: DialogueData, nodeId: string, nextId: string): DialogueData {
  const trimmed = nextId.trim();
  if (!trimmed || trimmed === nodeId) {
    return dialog;
  }
  const next = cloneDialogue(dialog);
  if (next.nodes.some((node) => node.id === trimmed)) {
    return dialog;
  }
  next.nodes = next.nodes.map((node) => {
    const copy = cloneNode(node);
    if (copy.id === nodeId) {
      copy.id = trimmed;
    }
    if (copy.next === nodeId) {
      copy.next = trimmed;
    }
    if (copy.true_next === nodeId) {
      copy.true_next = trimmed;
    }
    if (copy.false_next === nodeId) {
      copy.false_next = trimmed;
    }
    copy.options = (copy.options ?? []).map((option) => ({
      ...option,
      next: option.next === nodeId ? trimmed : option.next,
    }));
    return copy;
  });
  next.connections = next.connections.map((connection) => ({
    ...connection,
    from: connection.from === nodeId ? trimmed : connection.from,
    to: connection.to === nodeId ? trimmed : connection.to,
  }));
  return normalizeDialogue(next);
}

function setNodeStart(dialog: DialogueData, nodeId: string, isStart: boolean): DialogueData {
  const next = cloneDialogue(dialog);
  next.nodes = next.nodes.map((node) => ({
    ...node,
    is_start: isStart ? node.id === nodeId : node.id === nodeId ? false : node.is_start,
  }));
  return normalizeDialogue(next);
}

function updateNodeOptions(
  dialog: DialogueData,
  nodeId: string,
  options: DialogueOption[],
): DialogueData {
  let next = replaceNode(dialog, nodeId, (node) => ({
    ...node,
    options: options.map((option) => ({ ...option })),
  }));
  next.connections = next.connections.filter((connection) => {
    if (connection.from !== nodeId) {
      return true;
    }
    return connection.from_port < options.length;
  });
  return normalizeDialogue(next);
}

function updateNodeActions(
  dialog: DialogueData,
  nodeId: string,
  actions: DialogueAction[],
): DialogueData {
  return replaceNode(dialog, nodeId, (node) => ({
    ...node,
    actions: actions.map((action) => ({ ...action })),
  }));
}

export function getDialogueNode(
  dialog: DialogueData,
  nodeId: string | null,
): DialogueNode | null {
  if (!nodeId) {
    return null;
  }
  return dialog.nodes.find((node) => node.id === nodeId) ?? null;
}

export function updateDialogueNode(
  dialog: DialogueData,
  nodeId: string,
  transform: (node: DialogueNode) => DialogueNode,
): DialogueData {
  return normalizeDialogue(replaceNode(dialog, nodeId, transform));
}

export function renameDialogueNode(
  dialog: DialogueData,
  nodeId: string,
  nextId: string,
): DialogueData {
  return updateDialogueNodeId(dialog, nodeId, nextId);
}

export function setDialogueNodeStart(
  dialog: DialogueData,
  nodeId: string,
  isStart: boolean,
): DialogueData {
  return setNodeStart(dialog, nodeId, isStart);
}

export function setDialogueNodeOptions(
  dialog: DialogueData,
  nodeId: string,
  options: DialogueOption[],
): DialogueData {
  return updateNodeOptions(dialog, nodeId, options);
}

export function setDialogueNodeActions(
  dialog: DialogueData,
  nodeId: string,
  actions: DialogueAction[],
): DialogueData {
  return updateNodeActions(dialog, nodeId, actions);
}

export function getDialogueEdgeTarget(
  dialog: DialogueData,
  nodeId: string,
  handleId: string,
): string {
  const normalized = normalizeDialogue(dialog);
  const edge = normalized.connections
    .map((connection) => dialogueConnectionToEdge(connection, new Map(normalized.nodes.map((node) => [node.id, node]))))
    .find((entry) => entry.source === nodeId && (entry.sourceHandle ?? "next") === handleId);
  return edge?.target ?? "";
}

export function edgeIdToTarget(edgeId: string): string {
  const match = /^.+:\d+->(.+):0$/.exec(edgeId);
  return match?.[1] ?? edgeId;
}

function buildConnection(
  document: DialogueData,
  connection: GraphConnectionRecord,
): DialogueConnection {
  const sourceNode = document.nodes.find((node) => node.id === connection.source);
  return {
    from: connection.source,
    from_port: sourceNode ? getSourcePort(sourceNode, connection.sourceHandle) : 0,
    to: connection.target,
    to_port: 0,
  };
}

export const dialogueGraphAdapter: GraphDocumentAdapter<DialogueData, DialogueGraphNode> = {
  normalizeDocument: normalizeDialogue,
  getDocumentId: (document) => document.dialog_id,
  setDocumentId: (document, nextId) => ({
    ...document,
    dialog_id: nextId,
  }),
  getNodeTypes: buildNodeDefinitions,
  toGraph: (document) => {
    const normalized = normalizeDialogue(document);
    const nodeMap = new Map(normalized.nodes.map((node) => [node.id, node]));
    return {
      nodes: normalized.nodes,
      edges: normalized.connections.map((connection) =>
        dialogueConnectionToEdge(connection, nodeMap),
      ),
    };
  },
  createNode: (document, type, position) => {
    const normalized = normalizeDialogue(document);
    const existingIds = new Set(normalized.nodes.map((node) => node.id));
    let index = 1;
    let nextId = `${type}_${index}`;
    while (existingIds.has(nextId)) {
      index += 1;
      nextId = `${type}_${index}`;
    }
    const definition = getNodeTypeDefinition(type);
    const nextDocument = normalizeDialogue({
      ...normalized,
      nodes: [...normalized.nodes, definition.createNode(nextId, position)],
    });
    return { document: nextDocument, nodeId: nextId };
  },
  moveNodes: (document, positions) => {
    const next = cloneDialogue(document);
    next.nodes = next.nodes.map((node) =>
      positions[node.id]
        ? {
            ...node,
            position: positions[node.id],
          }
        : node,
    );
    return next;
  },
  connect: (document, connection) => {
    const normalized = normalizeDialogue(document);
    const nextConnection = buildConnection(normalized, connection);
    const sourceNode = normalized.nodes.find((node) => node.id === connection.source);
    const nextConnections = normalized.connections.filter((entry) => {
      if (entry.from !== nextConnection.from) {
        return true;
      }
      if (!sourceNode) {
        return true;
      }
      return getSourceHandle(sourceNode, entry.from_port) !== (connection.sourceHandle ?? "next");
    });
    nextConnections.push(nextConnection);
    return normalizeDialogue({
      ...normalized,
      connections: nextConnections,
    });
  },
  deleteNodes: (document, nodeIds) => {
    const nodeIdSet = new Set(nodeIds);
    const nextDocument = syncNodeFieldsFromConnections({
      ...cloneDialogue(document),
      nodes: document.nodes.filter((node) => !nodeIdSet.has(node.id)),
      connections: document.connections.filter(
        (connection) => !nodeIdSet.has(connection.from) && !nodeIdSet.has(connection.to),
      ),
    });
    return normalizeDialogue(nextDocument);
  },
  deleteEdges: (document, edgeIds) => {
    const edgeSet = new Set(edgeIds);
    const normalized = normalizeDialogue(document);
    const nodeMap = new Map(normalized.nodes.map((node) => [node.id, node]));
    const nextDocument = syncNodeFieldsFromConnections({
      ...normalized,
      connections: normalized.connections.filter(
        (connection) => !edgeSet.has(dialogueConnectionToEdge(connection, nodeMap).id),
      ),
    });
    return normalizeDialogue(nextDocument);
  },
  autoLayout: autoLayoutDialogue,
  canConnect: (document, connection) => {
    if (connection.source === connection.target) {
      return "Self connections are not supported.";
    }
    const normalized = normalizeDialogue(document);
    const targetNode = normalized.nodes.find((node) => node.id === connection.target);
    if (targetNode?.is_start) {
      return "Start node cannot have incoming rewires from arbitrary branches.";
    }
    return null;
  },
  getIssuesForNode: (issues, nodeId) => issues.filter((issue) => issue.nodeId === nodeId),
  getIssuesForEdge: (issues, edgeId) => issues.filter((issue) => issue.edgeKey === edgeId),
};

export function getDialogueNodeCatalog() {
  return buildNodeDefinitions();
}
