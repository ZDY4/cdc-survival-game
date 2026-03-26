import {
  useEffect,
  useMemo,
  useRef,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
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
  topbarSearchPlaceholder = "搜索工作区",
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

    function handleResize(event: PointerEvent) {
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

    window.addEventListener("pointermove", handleResize);
    window.addEventListener("pointerup", stopResize);
    window.addEventListener("pointercancel", stopResize);

    return () => {
      window.removeEventListener("pointermove", handleResize);
      window.removeEventListener("pointerup", stopResize);
      window.removeEventListener("pointercancel", stopResize);
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

  function startResize(axis: ResizeAxis, event: ReactPointerEvent<HTMLButtonElement>) {
    if (event.button !== 0) {
      return;
    }
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
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
            <span className="toolbar-button-main">资源</span>
          </button>
          <button type="button" className="toolbar-button" onClick={onOpenQuickOpen}>
            <span className="toolbar-button-main">快速打开</span>
            <span className="toolbar-button-hint">Ctrl+P</span>
          </button>
          <button type="button" className="toolbar-button" onClick={onOpenCommandPalette}>
            <span className="toolbar-button-main">命令</span>
            <span className="toolbar-button-hint">Ctrl+Shift+P</span>
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
          onPointerDown={(event) => startResize("left", event)}
          aria-label="调整左侧边栏大小"
          title="拖动以调整资源栏宽度"
        />

        <main className="ide-main-column">
          <section className="ide-editor-surface">{editorArea}</section>

          <button
            type="button"
            className="ide-divider ide-divider-horizontal"
            onPointerDown={(event) => startResize("bottom", event)}
            aria-label="调整底部面板大小"
            title="拖动以调整底部面板高度"
          />

          <section className="ide-bottom-panel">{bottomPanel}</section>
        </main>

        <button
          type="button"
          className="ide-divider ide-divider-vertical"
          onPointerDown={(event) => startResize("right", event)}
          aria-label="调整右侧边栏大小"
          title="拖动以调整检查器宽度"
        />

        <aside className="ide-right-sidebar">{rightSidebar}</aside>

        <div className="ide-right-rail">
          <button
            type="button"
            className="ide-right-rail-toggle"
            onClick={onToggleRightSidebar}
            aria-label={rightSidebarVisible ? "收起右侧边栏" : "展开右侧边栏"}
            title={rightSidebarVisible ? "收起右侧边栏" : "展开右侧边栏"}
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
              {bottomPanelVisible ? "隐藏面板" : "显示面板"}
            </button>
          </div>
        </footer>
      ) : null}

      {overlays}
    </div>
  );
}
