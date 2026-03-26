import { Badge } from "./Badge";
import type { EditorBootstrap } from "../types";

type ModuleItem = {
  id: string;
  label: string;
  state: "active" | "planned";
};

type EditorShellProps = {
  title: string;
  subtitle: string;
  bootstrap: EditorBootstrap;
  modules: ModuleItem[];
  activeModule: string;
  onModuleChange: (moduleId: string) => void;
  status: string;
  runtimeLabel: string;
  primaryMetaLabel?: string;
  secondaryMetaLabel?: string;
  primaryMetaValue?: string;
  secondaryMetaValue?: string;
  shellMode?: "default" | "narrative";
  brandEyebrow?: string;
  topbarEyebrow?: string;
  topbarHeadline?: string;
  showSidebar?: boolean;
  showStatusBar?: boolean;
  children: React.ReactNode;
};

export function EditorShell({
  title,
  subtitle,
  bootstrap,
  modules,
  activeModule,
  onModuleChange,
  status,
  runtimeLabel,
  primaryMetaLabel = "Repo",
  secondaryMetaLabel = "Rust",
  primaryMetaValue,
  secondaryMetaValue,
  shellMode = "default",
  brandEyebrow = "CDC Editor",
  topbarEyebrow,
  topbarHeadline,
  showSidebar = true,
  showStatusBar = true,
  children,
}: EditorShellProps) {
  const narrativeMode = shellMode === "narrative";
  const resolvedPrimaryMeta = primaryMetaValue ?? bootstrap.workspaceRoot;
  const resolvedSecondaryMeta = secondaryMetaValue ?? bootstrap.sharedRustPath;

  return (
    <div className={`shell ${showSidebar ? "" : "shell-no-sidebar"}`.trim()}>
      {showSidebar ? (
        <aside className="shell-sidebar">
          <div className="shell-sidebar-top">
            <div className="sidebar-section sidebar-section-compact">
              <div className="section-header">
                <span className="section-label">Modules</span>
                <Badge tone="accent">{runtimeLabel}</Badge>
              </div>
              <nav className="module-nav">
                {modules.map((module) => (
                  <button
                    key={module.id}
                    className={`module-button ${module.id === activeModule ? "module-button-active" : ""}`}
                    type="button"
                    onClick={() => {
                      if (module.state === "active") {
                        onModuleChange(module.id);
                      }
                    }}
                    disabled={module.state !== "active"}
                  >
                    <span>{module.label}</span>
                    <Badge tone={module.state === "active" ? "success" : "muted"}>
                      {module.state === "active" ? "Ready" : "Planned"}
                    </Badge>
                  </button>
                ))}
              </nav>
            </div>
          </div>

          <div className="shell-sidebar-bottom">
            <div className="sidebar-section sidebar-section-compact">
              <span className="section-label">{narrativeMode ? "Session" : "Workspace"}</span>
              <div className="list-summary">
                <div className="summary-row summary-row-compact">
                  <div className="summary-row-main">
                    <strong>{primaryMetaLabel}</strong>
                    <p>{resolvedPrimaryMeta}</p>
                  </div>
                </div>
                <div className="summary-row summary-row-compact">
                  <div className="summary-row-main">
                    <strong>{secondaryMetaLabel}</strong>
                    <p>{resolvedSecondaryMeta}</p>
                  </div>
                </div>
              </div>
            </div>

            <div className="sidebar-section sidebar-section-compact">
              <span className="section-label">{narrativeMode ? "Context" : "Runtime"}</span>
              <div className="shell-sidebar-notes">
                <div className="summary-row summary-row-compact">
                  <div className="summary-row-main">
                    <strong>Stage</strong>
                    <p>{bootstrap.activeStage}</p>
                  </div>
                </div>
                <div className="row-badges">
                  {bootstrap.editorDomains.slice(0, 4).map((domain) => (
                    <Badge key={domain} tone="muted">
                      {domain}
                    </Badge>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </aside>
      ) : null}

      <section className="shell-main">
        <header className="topbar">
          {topbarEyebrow || topbarHeadline ? (
            <div className="topbar-copy">
              {topbarEyebrow ? <p className="eyebrow">{topbarEyebrow}</p> : null}
              {topbarHeadline ? <h2>{topbarHeadline}</h2> : null}
            </div>
          ) : null}
          <div className="workspace-meta">
            <div>
              <span className="meta-label">{primaryMetaLabel}</span>
              <strong>{resolvedPrimaryMeta}</strong>
            </div>
            <div>
              <span className="meta-label">{secondaryMetaLabel}</span>
              <strong>{resolvedSecondaryMeta}</strong>
            </div>
          </div>
        </header>

        <div className="shell-content">{children}</div>

        {showStatusBar ? (
          <footer className="status-bar">
            <span className="status-dot" />
            <span>{status}</span>
          </footer>
        ) : null}
      </section>
    </div>
  );
}
