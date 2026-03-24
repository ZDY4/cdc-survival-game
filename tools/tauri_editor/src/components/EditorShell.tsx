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
  topbarEyebrow = "Workspace",
  topbarHeadline = "Shared Rust data, standalone editor UI, real project content.",
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
          <div className="brand-block">
            <p className="eyebrow">{brandEyebrow}</p>
            <h1>{title}</h1>
            <p className="shell-copy">{subtitle}</p>
            {narrativeMode ? (
              <div className="row-badges">
                <Badge tone="accent">{runtimeLabel}</Badge>
                <Badge tone="muted">standalone writing studio</Badge>
              </div>
            ) : null}
          </div>

          {narrativeMode ? (
            <>
              <div className="sidebar-section">
                <span className="section-label">Session</span>
                <div className="list-summary">
                  <div className="summary-row">
                    <div className="summary-row-main">
                      <strong>{primaryMetaLabel}</strong>
                      <p>{resolvedPrimaryMeta}</p>
                    </div>
                  </div>
                  <div className="summary-row">
                    <div className="summary-row-main">
                      <strong>{secondaryMetaLabel}</strong>
                      <p>{resolvedSecondaryMeta}</p>
                    </div>
                  </div>
                </div>
              </div>

              <div className="sidebar-section">
                <span className="section-label">Focus</span>
                <ul className="domain-list">
                  <li>Draft, revise, and compare markdown narrative documents.</li>
                  <li>Arrange the workbench layout around your writing flow.</li>
                  <li>Configure AI providers and cloud sync without leaving the lab.</li>
                </ul>
              </div>
            </>
          ) : (
            <>
              <div className="sidebar-section">
                <div className="section-header">
                  <span className="section-label">Modules</span>
                  <Badge tone="accent">{runtimeLabel}</Badge>
                </div>

                <nav className="module-nav">
                  {modules.map((module) => (
                    <button
                      key={module.id}
                      className={`module-button ${
                        module.id === activeModule ? "module-button-active" : ""
                      }`}
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

              <div className="sidebar-section">
                <span className="section-label">Migration focus</span>
                <strong className="focus-heading">{bootstrap.activeStage}</strong>
                <div className="phase-stack">
                  {bootstrap.stages.map((stage) => (
                    <article className="phase-card" key={stage.id}>
                      <h2>{stage.title}</h2>
                      <p>{stage.description}</p>
                    </article>
                  ))}
                </div>
              </div>
            </>
          )}
        </aside>
      ) : null}

      <section className="shell-main">
        <header className="topbar">
          <div>
            <p className="eyebrow">{topbarEyebrow}</p>
            <h2>{topbarHeadline}</h2>
          </div>
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
