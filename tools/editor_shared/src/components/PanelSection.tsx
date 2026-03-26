type PanelSectionProps = {
  label: string;
  title: string;
  children: React.ReactNode;
  compact?: boolean;
  collapsible?: boolean;
  collapsed?: boolean;
  onToggleCollapsed?: (collapsed: boolean) => void;
  headerActions?: React.ReactNode;
  summary?: React.ReactNode;
  dragHandle?: boolean;
  className?: string;
};

export function PanelSection({
  label,
  title,
  children,
  compact = false,
  collapsible = false,
  collapsed = false,
  onToggleCollapsed,
  headerActions,
  summary,
  dragHandle = false,
  className = "",
}: PanelSectionProps) {
  return (
    <section className={`panel ${compact ? "panel-compact" : ""} ${className}`.trim()}>
      <div className="panel-header">
        <div className="panel-title-group">
          <div className="panel-title-row">
            {dragHandle ? (
              <button
                type="button"
                className="panel-drag-handle"
                aria-label={`Drag ${title}`}
                title={`Drag ${title}`}
              >
                <span />
                <span />
                <span />
              </button>
            ) : null}
            <span className="section-label">{label}</span>
          </div>
          <div className="panel-heading-row">
            <h3 className="panel-title">{title}</h3>
            {summary ? <div className="panel-summary">{summary}</div> : null}
          </div>
        </div>
        {collapsible || headerActions ? (
          <div className="panel-header-actions">
            {headerActions}
            {collapsible ? (
              <button
                type="button"
                className="toolbar-button panel-toggle-button"
                onClick={() => onToggleCollapsed?.(!collapsed)}
              >
                {collapsed ? "Expand" : "Collapse"}
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
      {!collapsed ? <div className="panel-body">{children}</div> : null}
    </section>
  );
}
