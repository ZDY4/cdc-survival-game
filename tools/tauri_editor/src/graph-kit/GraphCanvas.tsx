import {
  Background,
  Connection,
  ConnectionMode,
  Controls,
  Edge,
  Handle,
  Node,
  NodeProps,
  Position,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import {
  type ComponentType,
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react";
import type { ValidationIssue } from "../types";
import { Badge } from "../components/Badge";
import { GraphContextMenu } from "./GraphContextMenu";
import { GraphValidationOverlay } from "./GraphValidationOverlay";
import type {
  GraphDocumentAdapter,
  GraphDocumentNode,
  GraphPoint,
  GraphSelection,
} from "./types";

type CanvasNodeData = {
  record: GraphDocumentNode;
  definition: {
    label: string;
    color: string;
    getSummaryLines: (node: GraphDocumentNode) => string[];
    getInputHandles: (node: GraphDocumentNode) => Array<{ id: string; label?: string }>;
    getOutputHandles: (node: GraphDocumentNode) => Array<{ id: string; label?: string }>;
  };
  issues: ValidationIssue[];
};

type GraphCanvasInnerProps<TDocument, TNode extends GraphDocumentNode> = {
  adapter: GraphDocumentAdapter<TDocument, TNode>;
  document: TDocument;
  issues: ValidationIssue[];
  selection: GraphSelection;
  onSelectionChange: (selection: GraphSelection) => void;
  onDocumentChange: (document: TDocument) => void;
};

export type GraphCanvasHandle = {
  centerView: () => void;
  createNodeAtViewportCenter: (type: string) => void;
  deleteSelection: () => void;
};

function GenericGraphNode({
  data,
  selected,
}: NodeProps<Node<CanvasNodeData>>) {
  const inputHandles = data.definition.getInputHandles(data.record);
  const outputHandles = data.definition.getOutputHandles(data.record);
  const summaryLines = data.definition.getSummaryLines(data.record);
  const errorCount = data.issues.filter((issue) => issue.severity === "error").length;
  const warningCount = data.issues.filter((issue) => issue.severity === "warning").length;
  const title =
    typeof data.record.title === "string" && data.record.title
      ? data.record.title
      : data.definition.label;

  return (
    <div
      className={`graph-node-card ${selected ? "graph-node-card-selected" : ""}`}
      style={{ borderColor: data.definition.color }}
    >
      {inputHandles.map((handle, index) => (
        <Handle
          key={`input-${handle.id}`}
          type="target"
          id={handle.id}
          position={Position.Left}
          style={{ top: `${((index + 1) / (inputHandles.length + 1)) * 100}%` }}
        />
      ))}

      <div className="graph-node-header">
        <strong>{title}</strong>
        <Badge tone="accent">{data.definition.label}</Badge>
      </div>
      <div className="graph-node-meta">
        <span>{String(data.record.id)}</span>
        {errorCount > 0 ? <Badge tone="danger">{errorCount}E</Badge> : null}
        {warningCount > 0 ? <Badge tone="warning">{warningCount}W</Badge> : null}
      </div>
      <div className="graph-node-summary">
        {summaryLines.map((line) => (
          <p key={`${data.record.id}-${line}`}>{line}</p>
        ))}
      </div>
      <div className="graph-node-handles">
        {outputHandles.map((handle, index) => (
          <div key={`label-${handle.id}`} className="graph-node-handle-label">
            {String(handle.label || handle.id)}
            <Handle
              type="source"
              id={handle.id}
              position={Position.Right}
              style={{ top: `${((index + 1) / (outputHandles.length + 1)) * 100}%` }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

function GraphCanvasInner<TDocument, TNode extends GraphDocumentNode>(
  {
    adapter,
    document,
    issues,
    selection,
    onSelectionChange,
    onDocumentChange,
  }: GraphCanvasInnerProps<TDocument, TNode>,
  ref: React.ForwardedRef<GraphCanvasHandle>,
) {
  const reactFlow = useReactFlow();
  const wrapperRef = useRef<HTMLDivElement | null>(null);
  const hasFittedDocumentRef = useRef(false);
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    flowPosition: GraphPoint;
  } | null>(null);

  const definitions = useMemo(() => adapter.getNodeTypes(), [adapter]);
  const definitionMap = useMemo(
    () => new Map(definitions.map((definition) => [definition.type, definition])),
    [definitions],
  );
  const graphData = useMemo(() => adapter.toGraph(document), [adapter, document]);

  const nodes = useMemo<Node<CanvasNodeData>[]>(
    () =>
      graphData.nodes.map((node) => {
        const definition = definitionMap.get(node.type);
        if (!definition) {
          throw new Error(`Unknown graph node type: ${node.type}`);
        }
        const nodeIssues =
          adapter.getIssuesForNode?.(issues, node.id) ??
          issues.filter((issue) => issue.nodeId === node.id);
        return {
          id: node.id,
          type: "graphNode",
          position: {
            x: node.position?.x ?? 0,
            y: node.position?.y ?? 0,
          },
          data: {
            record: node,
            definition: definition as unknown as CanvasNodeData["definition"],
            issues: nodeIssues,
          },
        };
      }),
    [adapter, definitionMap, graphData.nodes, issues],
  );

  const edges = useMemo<Edge[]>(
    () =>
      graphData.edges.map((edge) => {
        const edgeIssues =
          adapter.getIssuesForEdge?.(issues, edge.id) ??
          issues.filter((issue) => issue.edgeKey === edge.id);
        const isSelected = selection.edgeId === edge.id;
        return {
          id: edge.id,
          source: edge.source,
          sourceHandle: edge.sourceHandle ?? undefined,
          target: edge.target,
          targetHandle: edge.targetHandle ?? undefined,
          animated: isSelected,
          style: {
            stroke:
              edgeIssues.find((issue) => issue.severity === "error")
                ? "#d86b6b"
                : edgeIssues.find((issue) => issue.severity === "warning")
                  ? "#d8a15a"
                  : isSelected
                    ? "#f2c283"
                    : "#90a3b3",
            strokeWidth: isSelected ? 3 : 2,
          },
        };
      }),
    [adapter, graphData.edges, issues, selection.edgeId],
  );

  useImperativeHandle(
    ref,
    () => ({
      centerView: () => {
        void reactFlow.fitView({ padding: 0.18, duration: 250 });
      },
      createNodeAtViewportCenter: (type: string) => {
        const bounds = wrapperRef.current?.getBoundingClientRect();
        const viewportCenter = reactFlow.screenToFlowPosition({
          x: bounds ? bounds.left + bounds.width / 2 : window.innerWidth / 2,
          y: bounds ? bounds.top + bounds.height / 2 : window.innerHeight / 2,
        });
        const result = adapter.createNode(document, type, viewportCenter);
        onDocumentChange(result.document);
        onSelectionChange({ nodeId: result.nodeId, edgeId: null });
      },
      deleteSelection: () => {
        if (selection.edgeId) {
          onDocumentChange(adapter.deleteEdges(document, [selection.edgeId]));
          onSelectionChange({ nodeId: null, edgeId: null });
          return;
        }
        if (selection.nodeId) {
          onDocumentChange(adapter.deleteNodes(document, [selection.nodeId]));
          onSelectionChange({ nodeId: null, edgeId: null });
        }
      },
    }),
    [adapter, document, onDocumentChange, onSelectionChange, reactFlow, selection.edgeId, selection.nodeId],
  );

  useEffect(() => {
    if (hasFittedDocumentRef.current) {
      return;
    }
    hasFittedDocumentRef.current = true;
    void reactFlow.fitView({ padding: 0.18, duration: 0 });
  }, [reactFlow]);

  useEffect(() => {
    hasFittedDocumentRef.current = false;
  }, [adapter, adapter.getDocumentId(document)]);

  const nodeTypes = useMemo(
    () =>
      ({
        graphNode: GenericGraphNode as ComponentType<NodeProps>,
      }) as Record<string, ComponentType<NodeProps>>,
    [],
  );

  return (
    <div className="graph-canvas-shell" ref={wrapperRef}>
      <GraphValidationOverlay
        issues={issues}
        selectedNodeId={selection.nodeId}
        selectedEdgeId={selection.edgeId}
      />
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        fitView
        connectionMode={ConnectionMode.Loose}
        deleteKeyCode={["Backspace", "Delete"]}
        onConnect={(connection: Connection) => {
          if (!connection.source || !connection.target) {
            return;
          }
          const error = adapter.canConnect?.(document, {
            source: connection.source,
            sourceHandle: connection.sourceHandle,
            target: connection.target,
            targetHandle: connection.targetHandle,
          });
          if (error) {
            return;
          }
          onDocumentChange(
            adapter.connect(document, {
              source: connection.source,
              sourceHandle: connection.sourceHandle,
              target: connection.target,
              targetHandle: connection.targetHandle,
            }),
          );
        }}
        onNodeDragStop={(_, draggedNode) => {
          onDocumentChange(
            adapter.moveNodes(document, {
              [draggedNode.id]: {
                x: draggedNode.position.x,
                y: draggedNode.position.y,
              },
            }),
          );
        }}
        onNodesDelete={(deletedNodes) => {
          onDocumentChange(adapter.deleteNodes(document, deletedNodes.map((node) => node.id)));
          onSelectionChange({ nodeId: null, edgeId: null });
        }}
        onEdgesDelete={(deletedEdges) => {
          onDocumentChange(adapter.deleteEdges(document, deletedEdges.map((edge) => edge.id)));
          onSelectionChange({ nodeId: null, edgeId: null });
        }}
        onSelectionChange={({ nodes: selectedNodes, edges: selectedEdges }) => {
          onSelectionChange({
            nodeId: selectedNodes[0]?.id ?? null,
            edgeId: selectedEdges[0]?.id ?? null,
          });
        }}
        onEdgeClick={(_, edge) => {
          onSelectionChange({ nodeId: null, edgeId: edge.id });
        }}
        onPaneClick={() => {
          onSelectionChange({ nodeId: null, edgeId: null });
          setContextMenu(null);
        }}
        onPaneContextMenu={(event) => {
          event.preventDefault();
          const flowPosition = reactFlow.screenToFlowPosition({
            x: event.clientX,
            y: event.clientY,
          });
          setContextMenu({
            x: event.clientX,
            y: event.clientY,
            flowPosition,
          });
        }}
      >
        <Background gap={20} size={1} color="rgba(255,255,255,0.08)" />
        <Controls showInteractive={false} />
      </ReactFlow>
      {contextMenu ? (
        <GraphContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          nodeTypes={definitions}
          onAddNode={(type) => {
            const result = adapter.createNode(document, type, contextMenu.flowPosition);
            onDocumentChange(result.document);
            onSelectionChange({ nodeId: result.nodeId, edgeId: null });
            setContextMenu(null);
          }}
          onClose={() => setContextMenu(null)}
        />
      ) : null}
    </div>
  );
}

const ForwardedGraphCanvasInner = forwardRef(GraphCanvasInner) as <
  TDocument,
  TNode extends GraphDocumentNode,
>(
  props: GraphCanvasInnerProps<TDocument, TNode> & {
    ref?: React.ForwardedRef<GraphCanvasHandle>;
  },
) => JSX.Element;

type GraphCanvasProps<TDocument, TNode extends GraphDocumentNode> = GraphCanvasInnerProps<
  TDocument,
  TNode
>;

export const GraphCanvas = forwardRef(function GraphCanvas<
  TDocument,
  TNode extends GraphDocumentNode,
>(props: GraphCanvasProps<TDocument, TNode>, ref: React.ForwardedRef<GraphCanvasHandle>) {
  return (
    <ReactFlowProvider>
      <ForwardedGraphCanvasInner {...props} ref={ref} />
    </ReactFlowProvider>
  );
}) as <TDocument, TNode extends GraphDocumentNode>(
  props: GraphCanvasProps<TDocument, TNode> & {
    ref?: React.ForwardedRef<GraphCanvasHandle>;
  },
) => JSX.Element;
