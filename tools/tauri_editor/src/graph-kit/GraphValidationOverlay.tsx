import type { ValidationIssue } from "../types";
import { Badge } from "../components/Badge";

type GraphValidationOverlayProps = {
  issues: ValidationIssue[];
  selectedNodeId: string | null;
  selectedEdgeId: string | null;
};

export function GraphValidationOverlay({
  issues,
  selectedNodeId,
  selectedEdgeId,
}: GraphValidationOverlayProps) {
  const errorCount = issues.filter((issue) => issue.severity === "error").length;
  const warningCount = issues.filter((issue) => issue.severity === "warning").length;
  const focusedIssues = issues.filter(
    (issue) =>
      (selectedNodeId && issue.nodeId === selectedNodeId) ||
      (selectedEdgeId && issue.edgeKey === selectedEdgeId),
  );

  return (
    <div className="graph-overlay">
      <div className="toolbar-summary">
        <Badge tone={errorCount > 0 ? "danger" : "success"}>{errorCount} errors</Badge>
        <Badge tone={warningCount > 0 ? "warning" : "muted"}>{warningCount} warnings</Badge>
        {focusedIssues.length > 0 ? (
          <Badge tone="accent">{focusedIssues.length} focused</Badge>
        ) : null}
      </div>
    </div>
  );
}
