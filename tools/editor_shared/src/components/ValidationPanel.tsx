import type { ValidationIssue } from "../types";
import { Badge } from "./Badge";
import { PanelSection } from "./PanelSection";

type ValidationPanelProps = {
  issues: ValidationIssue[];
};

export function ValidationPanel({ issues }: ValidationPanelProps) {
  return (
    <PanelSection label="Validation" title="Current document health" compact>
      {issues.length === 0 ? (
        <div className="empty-state">
          <Badge tone="success">Clean</Badge>
          <p>No validation issues for the current document.</p>
        </div>
      ) : (
        <div className="issue-list">
          {issues.map((issue, index) => (
            <article className={`issue issue-${issue.severity}`} key={`${issue.field}-${index}`}>
              <div className="issue-head">
                <Badge tone={issue.severity === "error" ? "danger" : "warning"}>
                  {issue.severity}
                </Badge>
                <strong>{issue.field}</strong>
                {issue.scope ? <Badge tone="muted">{issue.scope}</Badge> : null}
                {issue.nodeId ? <Badge tone="accent">{issue.nodeId}</Badge> : null}
                {issue.edgeKey ? <Badge tone="muted">{issue.edgeKey}</Badge> : null}
              </div>
              <p>{issue.message}</p>
            </article>
          ))}
        </div>
      )}
    </PanelSection>
  );
}
