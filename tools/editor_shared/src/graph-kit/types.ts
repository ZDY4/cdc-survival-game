import type { ValidationIssue } from "../types";

export type GraphDocumentNode = {
  id: string;
  type: string;
  position?: { x: number; y: number } | null;
  [key: string]: unknown;
};

export type GraphPoint = {
  x: number;
  y: number;
};

export type GraphHandleDefinition = {
  id: string;
  label?: string;
};

export type GraphNodeTypeDefinition<TNode extends GraphDocumentNode> = {
  type: string;
  label: string;
  color: string;
  createNode: (id: string, position: GraphPoint) => TNode;
  getSummaryLines: (node: TNode) => string[];
  getInputHandles: (node: TNode) => GraphHandleDefinition[];
  getOutputHandles: (node: TNode) => GraphHandleDefinition[];
};

export type GraphEdgeRecord = {
  id: string;
  source: string;
  sourceHandle?: string | null;
  target: string;
  targetHandle?: string | null;
};

export type GraphConnectionRecord = {
  source: string;
  sourceHandle?: string | null;
  target: string;
  targetHandle?: string | null;
};

export type GraphSelection = {
  nodeId: string | null;
  edgeId: string | null;
};

export type GraphDocumentAdapter<TDocument, TNode extends GraphDocumentNode> = {
  normalizeDocument: (document: TDocument) => TDocument;
  getDocumentId: (document: TDocument) => string;
  setDocumentId: (document: TDocument, nextId: string) => TDocument;
  getNodeTypes: () => GraphNodeTypeDefinition<TNode>[];
  toGraph: (document: TDocument) => {
    nodes: TNode[];
    edges: GraphEdgeRecord[];
  };
  createNode: (
    document: TDocument,
    type: string,
    position: GraphPoint,
  ) => { document: TDocument; nodeId: string };
  moveNodes: (
    document: TDocument,
    positions: Record<string, GraphPoint>,
  ) => TDocument;
  connect: (
    document: TDocument,
    connection: GraphConnectionRecord,
  ) => TDocument;
  deleteNodes: (document: TDocument, nodeIds: string[]) => TDocument;
  deleteEdges: (document: TDocument, edgeIds: string[]) => TDocument;
  autoLayout: (document: TDocument) => TDocument;
  canConnect?: (
    document: TDocument,
    connection: GraphConnectionRecord,
  ) => string | null;
  getIssuesForNode?: (issues: ValidationIssue[], nodeId: string) => ValidationIssue[];
  getIssuesForEdge?: (issues: ValidationIssue[], edgeId: string) => ValidationIssue[];
};
