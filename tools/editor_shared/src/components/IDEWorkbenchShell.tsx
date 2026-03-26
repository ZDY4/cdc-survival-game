import {
  useEffect,
  useMemo,
  useRef,
  type CSSProperties,
  type MouseEvent as ReactMouseEvent,
  type ReactNode,
} from "react";
import { Badge } from "./Badge";

type WorkbenchBadgeTone = "accent" | "muted" | "warning" | "danger" | "success";

export type WorkbenchActivityItem = {
  id: string;
  label: string;
  glyph: string;
  badge?: string | number | null;
};

export type WorkbenchStatusItem = {
  id: string;
  label: string;
  tone?: WorkbenchBadgeTone;
};

type ResizeAxis = "left" | "right" | "bottom";

type IDEWorkbenchShellProps = {
  title: string;
  workspaceLabel?: string;
  runtimeLabel: string;
  topbarSearchValue?: string;
  topbarSearchPlaceholder?: string;
  onTopbarSearchChange?: (value: string) => void;
  onOpenQuickOpen?: () => void;
  onOpenCommandPalette?: () => void;
  activities: WorkbenchActivityItem[];
  activeActivityId: string;
  onActivityChange: (activityId: string) => void;
  leftSidebarVisible: boolean;
  leftSidebarWidth: number;
  onLeftSidebarWidthChange: (width: number) => void;
  onToggleLeftSidebar: () => void;
  rightSidebarVisible: boolean;
  rightSidebarWidth: number;
  onRightSidebarWidthChange: (width: number) => void;
  onToggleRightSidebar: () => void;
  bottomPanelVisible: boolean;
  bottomPanelHeight: number;
  onBottomPanelHeightChange: (height: number) => void;
  onToggleBottomPanel: () => void;
  status: string;
  statusItems?: WorkbenchStatusItem[];
  showStatusBar?: boolean;
  zenMode?: boolean;
  topbarActions?: ReactNode;
  leftSidebar: ReactNode;
  editorArea: ReactNode;
  rightSidebar?: ReactNode;
  bottomPanel?: ReactNode;
  overlays?: ReactNode;
};

type ResizeState = {
  axis: ResizeAxis;
  startX: number;
  startY: number;
  startWidth: number;
  startHeight: number;
} | null;

export function IDEWorkbenchShell({
  title,
  workspaceLabel,
  runtimeLabel,
  topbarSearchValue = "",
  topbarSearchPlaceholder = "Search workspace",
  onTopbarSearchChange,
  onOpenQuickOpen,
  onOpenCommandPalette,
  activities,
  activeActivityId,
  onActivityChange,
  leftSidebarVisible,
  leftSidebarWidth,
  onLeftSidebarWidthChange,
  onToggleLeftSidebar,
  rightSidebarVisible,
  rightSidebarWidth,
  onRightSidebarWidthChange,
  onToggleRightSidebar,
  bottomPanelVisible,
  bottomPanelHeight,
  onBottomPanelHeightChange,
  onToggleBottomPanel,
  status,
  statusItems = [],
  showStatusBar = true,
  zenMode = false,
  topbarActions,
  leftSidebar,
  editorArea,
  rightSidebar,
  bottomPanel,
  overlays,
}: IDEWorkbenchShellProps) {
  const resizeStateRef = useRef<ResizeState>(null);

  useEffect(() => {
    function stopResize() {
      if (!resizeStateRef.current) {
        return;
      }
      resizeStateRef.current = null;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    }

    function handleResize(event: MouseEvent) {
      const resizeState = resizeStateRef.current;
      if (!resizeState) {
        return;
      }

      if (resizeState.axis === "left") {
        const nextWidth = resizeState.startWidth + (event.clientX - resizeState.startX);
        onLeftSidebarWidthChange(Math.max(220, Math.min(460, nextWidth)));
        return;
      }

      if (resizeState.axis === "right") {
        const nextWidth = resizeState.startWidth + (resizeState.startX - event.clientX);
        onRightSidebarWidthChange(Math.max(260, Math.min(520, nextWidth)));
        return;
      }

      const nextHeight = resizeState.startHeight + (resizeState.startY - event.clientY);
      onBottomPanelHeightChange(Math.max(180, Math.min(440, nextHeight)));
    }

    window.addEventListener("mousemove", handleResize);
    window.addEventListener("mouseup", stopResize);

    return () => {
      window.removeEventListener("mousemove", handleResize);
      window.removeEventListener("mouseup", stopResize);
      stopResize();
    };
  }, [onBottomPanelHeightChange, onLeftSidebarWidthChange, onRightSidebarWidthChange]);

  const shellStyle = useMemo(
    () =>
      ({
        "--ide-left-sidebar-width": `${leftSidebarWidth}px`,
        "--ide-right-sidebar-width": `${rightSidebarWidth}px`,
        "--ide-bottom-panel-height": `${bottomPanelHeight}px`,
      }) as CSSProperties,
    [bottomPanelHeight, leftSidebarWidth, rightSidebarWidth],
  );

  function startResize(axis: ResizeAxis, event: ReactMouseEvent<HTMLButtonElement>) {
    event.preventDefault();
    resizeStateRef.current = {
      axis,
      startX: event.clientX,
      startY: event.clientY,
      startWidth: axis === "left" ? leftSidebarWidth : rightSidebarWidth,
      startHeight: bottomPanelHeight,
    };
    document.body.style.cursor = axis === "bottom" ? "row-resize" : "col-resize";
    document.body.style.userSelect = "none";
  }

  return (
    <div
      className={[
        "ide-shell",
        zenMode ? "ide-shell-zen" : "",
        leftSidebarVisible ? "" : "ide-shell-left-hidden",
        rightSidebarVisible ? "" : "ide-shell-right-hidden",
        bottomPanelVisible ? "" : "ide-shell-bottom-hidden",
      ]
        .filter(Boolean)
        .join(" ")}
      style={shellStyle}
    >
      <header className="ide-topbar">
        <div className="ide-topbar-brand">
          <strong>{title}</strong>
          {workspaceLabel ? (
            <span className="ide-topbar-context" title={workspaceLabel}>
              {workspaceLabel}
            </span>
          ) : null}
        </div>

        <div className="ide-topbar-search">
          <input
            className="field-input ide-topbar-search-input"
            type="text"
            value={topbarSearchValue}
            onChange={(event) => onTopbarSearchChange?.(event.target.value)}
            placeholder={topbarSearchPlaceholder}
          />
        </div>

        <div className="ide-topbar-actions">
          <button type="button" className="toolbar-button" onClick={onToggleLeftSidebar}>
            Explorer
          </button>
          <button type="button" className="toolbar-button" onClick={onOpenQuickOpen}>
            Quick Open
          </button>
          <button type="button" className="toolbar-button" onClick={onOpenCommandPalette}>
            Commands
          </button>
          {topbarActions}
          <Badge tone="accent">{runtimeLabel}</Badge>
        </div>
      </header>

      <div className="ide-workbench">
        <aside className="ide-activitybar">
          {activities.map((activity) => (
            <button
              key={activity.id}
              type="button"
              className={`ide-activity-button ${activity.id === activeActivityId ? "ide-activity-button-active" : ""}`.trim()}
              onClick={() => onActivityChange(activity.id)}
              title={activity.label}
            >
              <span className="ide-activity-glyph">{activity.glyph}</span>
              <span className="ide-activity-label">{activity.label}</span>
              {activity.badge !== undefined && activity.badge !== null ? (
                <span className="ide-activity-badge">{activity.badge}</span>
              ) : null}
            </button>
          ))}
        </aside>

        <aside className="ide-left-sidebar">{leftSidebar}</aside>

        <button
          type="button"
          className="ide-divider ide-divider-vertical"
          onMouseDown={(event) => startResize("left", event)}
          aria-label="Resize left sidebar"
          title="Drag to resize explorer"
        />

        <main className="ide-main-column">
          <section className="ide-editor-surface">{editorArea}</section>

          <button
            type="button"
            className="ide-divider ide-divider-horizontal"
            onMouseDown={(event) => startResize("bottom", event)}
            aria-label="Resize bottom panel"
            title="Drag to resize bottom panel"
          />

          <section className="ide-bottom-panel">{bottomPanel}</section>
        </main>

        <button
          type="button"
          className="ide-divider ide-divider-vertical"
          onMouseDown={(event) => startResize("right", event)}
          aria-label="Resize right sidebar"
          title="Drag to resize inspector"
        />

        <aside className="ide-right-sidebar">{rightSidebar}</aside>

        <div className="ide-right-rail">
          <button
            type="button"
            className="ide-right-rail-toggle"
            onClick={onToggleRightSidebar}
            aria-label={rightSidebarVisible ? "Collapse right sidebar" : "Expand right sidebar"}
            title={rightSidebarVisible ? "Collapse right sidebar" : "Expand right sidebar"}
          >
            {rightSidebarVisible ? "<" : ">"}
          </button>
        </div>
      </div>

      {showStatusBar ? (
        <footer className="ide-statusbar">
          <div className="ide-statusbar-main">
            <span className="status-dot" />
            <span>{status}</span>
          </div>
          <div className="ide-statusbar-items">
            {statusItems.map((item) => (
              <Badge key={item.id} tone={item.tone ?? "muted"}>
                {item.label}
              </Badge>
            ))}
            <button type="button" className="toolbar-button ide-statusbar-toggle" onClick={onToggleBottomPanel}>
              {bottomPanelVisible ? "Hide Panel" : "Show Panel"}
            </button>
          </div>
        </footer>
      ) : null}

      {overlays}
    </div>
  );
}
