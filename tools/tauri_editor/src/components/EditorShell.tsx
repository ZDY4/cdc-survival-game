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
  children,
}: EditorShellProps) {
  return (
    <div className="shell">
      <aside className="shell-sidebar">
        <div className="brand-block">
          <p className="eyebrow">CDC Editor</p>
          <h1>{title}</h1>
          <p className="shell-copy">{subtitle}</p>
        </div>

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
      </aside>

      <section className="shell-main">
        <header className="topbar">
          <div>
            <p className="eyebrow">Workspace</p>
            <h2>Shared Rust data, standalone editor UI, real project content.</h2>
          </div>
          <div className="workspace-meta">
            <div>
              <span className="meta-label">Repo</span>
              <strong>{bootstrap.workspaceRoot}</strong>
            </div>
            <div>
              <span className="meta-label">Rust</span>
              <strong>{bootstrap.sharedRustPath}</strong>
            </div>
          </div>
        </header>

        <div className="shell-content">{children}</div>

        <footer className="status-bar">
          <span className="status-dot" />
          <span>{status}</span>
        </footer>
      </section>
    </div>
  );
}
