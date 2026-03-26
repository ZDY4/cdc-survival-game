type ToolbarAction = {
  id: string;
  label: string;
  onClick: () => void;
  tone?: "default" | "accent" | "danger";
  disabled?: boolean;
};

type ToolbarProps = {
  actions: ToolbarAction[];
  children?: React.ReactNode;
};

export function Toolbar({ actions, children }: ToolbarProps) {
  return (
    <div className="toolbar">
      <div className="toolbar-actions">
        {actions.map((action) => (
          <button
            key={action.id}
            type="button"
            className={`toolbar-button toolbar-${action.tone ?? "default"}`}
            onClick={action.onClick}
            disabled={action.disabled}
          >
            {action.label}
          </button>
        ))}
      </div>
      {children ? <div className="toolbar-extra">{children}</div> : null}
    </div>
  );
}
