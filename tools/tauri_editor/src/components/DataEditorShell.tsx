import { Badge } from "./Badge";
import type { EditorBootstrap } from "../types";

type DataEditorShellProps = {
  title: string;
  subtitle: string;
  bootstrap: EditorBootstrap;
  runtimeLabel: string;
  status: string;
  shellClassName?: string;
  showHeader?: boolean;
  showStatusBar?: boolean;
  children: React.ReactNode;
};

export function DataEditorShell({
  title,
  subtitle,
  bootstrap,
  runtimeLabel,
  status,
  shellClassName = "",
  showHeader = true,
  showStatusBar = true,
  children,
}: DataEditorShellProps) {
  return (
    <div className={`data-editor-shell ${shellClassName}`.trim()}>
      {showHeader ? (
        <header className="data-editor-header">
          <div className="data-editor-header-copy">
            <div className="data-editor-title-row">
              <h1 className="data-editor-title">{title}</h1>
              <Badge tone="accent">{runtimeLabel}</Badge>
            </div>
            <p className="data-editor-subtitle">{subtitle}</p>
          </div>

          <div className="data-editor-meta">
            <article className="data-editor-meta-item">
              <span className="section-label">Workspace</span>
              <strong title={bootstrap.workspaceRoot}>{bootstrap.workspaceRoot}</strong>
            </article>
            <article className="data-editor-meta-item">
              <span className="section-label">Rust</span>
              <strong title={bootstrap.sharedRustPath}>{bootstrap.sharedRustPath}</strong>
            </article>
            <article className="data-editor-meta-item">
              <span className="section-label">Stage</span>
              <strong>{bootstrap.activeStage}</strong>
            </article>
          </div>
        </header>
      ) : null}

      <main className="data-editor-main">{children}</main>

      {showStatusBar ? (
        <footer className="status-bar data-editor-status-bar">
          <span className="status-dot" />
          <span>{status}</span>
        </footer>
      ) : null}
    </div>
  );
}
