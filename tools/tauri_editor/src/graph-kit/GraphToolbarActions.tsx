import type { GraphDocumentAdapter, GraphDocumentNode } from "./types";

type GraphToolbarActionsProps<TDocument, TNode extends GraphDocumentNode> = {
  adapter: GraphDocumentAdapter<TDocument, TNode>;
  onAddNode: (type: string) => void;
  onAutoLayout: () => void;
  onCenterView: () => void;
  onDeleteSelection: () => void;
  disabled?: boolean;
};

export function GraphToolbarActions<TDocument, TNode extends GraphDocumentNode>({
  adapter,
  onAddNode,
  onAutoLayout,
  onCenterView,
  onDeleteSelection,
  disabled = false,
}: GraphToolbarActionsProps<TDocument, TNode>) {
  const nodeTypes = adapter.getNodeTypes();

  return (
    <div className="toolbar-actions">
      {nodeTypes.map((nodeType) => (
        <button
          key={nodeType.type}
          type="button"
          className="toolbar-button"
          onClick={() => onAddNode(nodeType.type)}
          disabled={disabled}
        >
          + {nodeType.label}
        </button>
      ))}
      <button type="button" className="toolbar-button" onClick={onAutoLayout} disabled={disabled}>
        Auto layout
      </button>
      <button type="button" className="toolbar-button" onClick={onCenterView} disabled={disabled}>
        Center
      </button>
      <button
        type="button"
        className="toolbar-button"
        onClick={onDeleteSelection}
        disabled={disabled}
      >
        Delete selection
      </button>
    </div>
  );
}
