type GraphContextMenuProps = {
  x: number;
  y: number;
  nodeTypes: Array<{ type: string; label: string }>;
  onAddNode: (type: string) => void;
  onClose: () => void;
};

export function GraphContextMenu({
  x,
  y,
  nodeTypes,
  onAddNode,
  onClose,
}: GraphContextMenuProps) {
  return (
    <>
      <button className="graph-context-backdrop" type="button" onClick={onClose} />
      <div className="graph-context-menu" style={{ left: x, top: y }}>
        <span className="section-label">Add node</span>
        <div className="graph-context-list">
          {nodeTypes.map((nodeType) => (
            <button
              key={nodeType.type}
              className="graph-context-item"
              type="button"
              onClick={() => onAddNode(nodeType.type)}
            >
              {nodeType.label}
            </button>
          ))}
        </div>
      </div>
    </>
  );
}
