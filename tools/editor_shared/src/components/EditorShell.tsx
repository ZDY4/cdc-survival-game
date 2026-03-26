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
  topbarHeadline,
  showSidebar = true,
  showStatusBar = true,
  children,
}: EditorShellProps) {
  const narrativeMode = shellMode === "narrative";
  const resolvedPrimaryMeta = primaryMetaValue ?? bootstrap.workspaceRoot;
  const resolvedSecondaryMeta = secondaryMetaValue ?? bootstrap.sharedRustPath;
  const resolvedHeadline = topbarHeadline ?? title;

  return (
    <div
      className={`shell ${showSidebar ? "" : "shell-no-sidebar"} ${narrativeMode ? "shell-narrative" : ""}`.trim()}
    >
      {showSidebar ? (
        <aside className="shell-sidebar">
          <div className="shell-sidebar-top">
            <div className="sidebar-section sidebar-section-compact">
              <div className="shell-sidebar-heading">
                <strong>{title}</strong>
                <p>{subtitle}</p>
              </div>
            </div>
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

          {!narrativeMode ? (
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
          ) : null}
        </aside>
      ) : null}

      <section className="shell-main">
        <header className="topbar">
          <div className="topbar-copy">
            <div className="topbar-title-row">
              <h1 className="topbar-title">{resolvedHeadline}</h1>
              {resolvedPrimaryMeta ? (
                <span className="topbar-context" title={resolvedPrimaryMeta}>
                  {resolvedPrimaryMeta}
                </span>
              ) : null}
              <Badge tone="accent">{runtimeLabel}</Badge>
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
