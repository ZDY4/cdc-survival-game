import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import type { CSSProperties } from "react";
import { Badge } from "../../components/Badge";
import { CheckboxField, NumberField, SelectField, TextField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { invokeCommand } from "../../lib/tauri";
import type {
  AiPreviewModuleRef,
  CharacterAiPreview,
  CharacterAiPreviewContext,
  CharacterAiPreviewRequest,
  CharacterDefinition,
  CharacterDocumentSummary,
  CharacterWorkspacePayload,
  ScheduleDay,
  ValidationIssue,
} from "../../types";

type CharacterWorkspaceProps = {
  workspace: CharacterWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  indexVisible?: boolean;
};

type CharacterTab = "summary" | "life" | "aiPreview";
type ReferenceKind = "settlement" | "behavior" | "schedule" | "personality" | "need" | "access";
type ActiveReference = { kind: ReferenceKind; id: string } | null;

const TAB_LABELS: Array<{ id: CharacterTab; label: string }> = [
  { id: "summary", label: "摘要" },
  { id: "life", label: "生活" },
  { id: "aiPreview", label: "AI 预览" },
];

const DAY_OPTIONS: Array<{ value: ScheduleDay; label: string }> = [
  { value: "monday", label: "周一" },
  { value: "tuesday", label: "周二" },
  { value: "wednesday", label: "周三" },
  { value: "thursday", label: "周四" },
  { value: "friday", label: "周五" },
  { value: "saturday", label: "周六" },
  { value: "sunday", label: "周日" },
];

const EMPTY_CONTEXT: CharacterAiPreviewContext = {
  day: "monday",
  minute_of_day: 540,
  hunger: 60,
  energy: 85,
  morale: 50,
  world_alert_active: false,
  current_anchor: "",
  active_guards: 0,
  min_guard_on_duty: 0,
  availability: {
    guard_post_available: true,
    meal_object_available: true,
    leisure_object_available: true,
    medical_station_available: true,
    patrol_route_available: true,
    bed_available: true,
  },
};

function countIssues(issues: ValidationIssue[]) {
  let errors = 0;
  let warnings = 0;
  for (const issue of issues) {
    if (issue.severity === "error") {
      errors += 1;
    } else {
      warnings += 1;
    }
  }
  return { errors, warnings };
}

function roleLabel(role: string) {
  switch (role) {
    case "guard":
      return "守卫";
    case "cook":
      return "厨师";
    case "doctor":
      return "医生";
    case "resident":
      return "居民";
    default:
      return role || "无角色";
  }
}

function formatMinute(minute: number) {
  const bounded = Math.max(0, Math.min(1440, Math.round(minute)));
  const hour = Math.floor(bounded / 60);
  const minutePart = bounded % 60;
  return `${String(hour).padStart(2, "0")}:${String(minutePart).padStart(2, "0")}`;
}

function createPreviewContext(document: CharacterDocumentSummary): CharacterAiPreviewContext {
  return document.previewContext
    ? {
        ...document.previewContext,
        current_anchor: document.previewContext.current_anchor ?? "",
      }
    : {
        ...EMPTY_CONTEXT,
        current_anchor: document.character?.life?.home_anchor ?? "",
      };
}

function renderDetailRows(rows: Array<{ label: string; value: React.ReactNode }>) {
  return (
    <div className="character-detail-grid">
      {rows.map((row) => (
        <article key={row.label} className="character-detail-card">
          <span className="field-label">{row.label}</span>
          <div>{row.value}</div>
        </article>
      ))}
    </div>
  );
}

function renderModuleTokens(items: AiPreviewModuleRef[]) {
  if (items.length === 0) {
    return <Badge tone="muted">无</Badge>;
  }

  return (
    <div className="row-badges">
      {items.map((item) => (
        <Badge key={item.id} tone="muted">
          {item.display_name}
        </Badge>
      ))}
    </div>
  );
}

function renderOverrideSummary(source: Record<string, unknown> | null | undefined) {
  if (!source) {
    return "无覆盖";
  }

  const entries = Object.entries(source).filter(([, value]) => {
    if (value === null || value === undefined) {
      return false;
    }
    if (typeof value === "string") {
      return value.trim().length > 0;
    }
    return true;
  });

  if (entries.length === 0) {
    return "无覆盖";
  }

  return (
    <div className="character-key-list">
      {entries.map(([key, value]) => (
        <span key={key} className="character-key-item">
          <strong>{key}</strong>: {String(value)}
        </span>
      ))}
    </div>
  );
}

function renderCompactActionList(preview: CharacterAiPreview) {
  return (
    <div className="character-compact-list">
      {preview.available_actions.map((action) => (
        <article key={action.action_id} className="character-compact-row">
          <div className="section-header">
            <strong>{action.display_name}</strong>
            <Badge tone={action.available ? "success" : "warning"}>
              {action.available ? "可用" : "阻断"}
            </Badge>
          </div>
          {!action.available && action.blocked_by.length > 0 ? (
            <p className="field-hint">{action.blocked_by.join(" · ")}</p>
          ) : null}
        </article>
      ))}
    </div>
  );
}

function renderCompactGoalList(preview: CharacterAiPreview) {
  return (
    <div className="character-compact-list">
      {preview.goal_scores.map((goal) => (
        <article key={goal.goal_id} className="character-compact-row">
          <div className="section-header">
            <strong>{goal.display_name}</strong>
            <Badge tone="accent">{goal.score}</Badge>
          </div>
          {goal.matched_rule_ids.length > 0 ? (
            <div className="row-badges">
              {goal.matched_rule_ids.map((ruleId) => (
                <Badge key={`${goal.goal_id}-${ruleId}`} tone="muted">
                  {ruleId}
                </Badge>
              ))}
            </div>
          ) : null}
        </article>
      ))}
    </div>
  );
}

function renderValidation(issues: ValidationIssue[]) {
  if (issues.length === 0) {
    return <Badge tone="success">正常</Badge>;
  }

  return (
    <div className="issue-list">
      {issues.map((issue, index) => (
        <article key={`${issue.field}-${index}`} className="issue">
          <div className="issue-head">
            <Badge tone={issue.severity === "error" ? "danger" : "warning"}>
              {issue.severity === "error" ? "错误" : "警告"}
            </Badge>
            <Badge tone="muted">{issue.field}</Badge>
          </div>
          <p>{issue.message}</p>
        </article>
      ))}
    </div>
  );
}

function renderReferenceButton(
  label: string,
  kind: ReferenceKind,
  id: string,
  setActiveReference: (reference: ActiveReference) => void,
) {
  if (!id) {
    return "无";
  }

  return (
    <button
      type="button"
      className="character-reference-button"
      title={`查看引用详情：${label} (${id})`}
      onClick={() => setActiveReference({ kind, id })}
    >
      {label}
    </button>
  );
}

export function CharacterWorkspace({
  workspace,
  canPersist,
  onStatusChange,
  indexVisible = true,
}: CharacterWorkspaceProps) {
  const splitLayoutRef = useRef<HTMLDivElement | null>(null);
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [settlementFilter, setSettlementFilter] = useState("");
  const [roleFilter, setRoleFilter] = useState("");
  const [behaviorFilter, setBehaviorFilter] = useState("");
  const [indexWidth, setIndexWidth] = useState(272);
  const [isResizingIndex, setIsResizingIndex] = useState(false);
  const [activeTab, setActiveTab] = useState<CharacterTab>("summary");
  const [activeReference, setActiveReference] = useState<ActiveReference>(null);
  const [warningsCollapsed, setWarningsCollapsed] = useState(true);
  const [presentationCollapsed, setPresentationCollapsed] = useState(true);
  const [attributesCollapsed, setAttributesCollapsed] = useState(true);
  const [previewContext, setPreviewContext] = useState<CharacterAiPreviewContext>(EMPTY_CONTEXT);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewError, setPreviewError] = useState("");
  const [preview, setPreview] = useState<CharacterAiPreview | null>(null);
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    const nextDocument = workspace.documents[0] ?? null;
    setSelectedKey(nextDocument?.documentKey ?? "");
    setActiveTab("summary");
    setActiveReference(null);
    setPreview(null);
    setPreviewError("");
    setWarningsCollapsed(true);
    setPresentationCollapsed(true);
    setAttributesCollapsed(true);
    setPreviewContext(nextDocument ? createPreviewContext(nextDocument) : EMPTY_CONTEXT);
  }, [workspace]);

  const filteredDocuments = useMemo(() => {
    const query = deferredSearch.trim().toLowerCase();
    return workspace.documents.filter((document) => {
      if (settlementFilter && document.settlementId !== settlementFilter) {
        return false;
      }
      if (roleFilter && document.role !== roleFilter) {
        return false;
      }
      if (behaviorFilter && document.behaviorProfileId !== behaviorFilter) {
        return false;
      }
      if (!query) {
        return true;
      }
      return [
        document.displayName,
        document.characterId,
        document.settlementId,
        document.role,
        document.behaviorProfileId,
      ]
        .join(" ")
        .toLowerCase()
        .includes(query);
    });
  }, [behaviorFilter, deferredSearch, roleFilter, settlementFilter, workspace.documents]);

  const selectedDocument =
    filteredDocuments.find((document) => document.documentKey === selectedKey) ??
    workspace.documents.find((document) => document.documentKey === selectedKey) ??
    null;

  const selectedCharacter: CharacterDefinition | null = selectedDocument?.character ?? null;
  const selectedLife = selectedCharacter?.life ?? null;
  const totalIssues = workspace.documents.reduce(
    (accumulator, document) => {
      const counts = countIssues(document.validation);
      accumulator.errors += counts.errors;
      accumulator.warnings += counts.warnings;
      return accumulator;
    },
    { errors: 0, warnings: 0 },
  );

  useEffect(() => {
    if (!selectedDocument) {
      return;
    }
    setPreview(null);
    setPreviewError("");
    setActiveReference(null);
    setPresentationCollapsed(true);
    setAttributesCollapsed(true);
    setPreviewContext(createPreviewContext(selectedDocument));
  }, [selectedDocument?.documentKey]);

  useEffect(() => {
    if (!selectedDocument || !selectedCharacter || activeTab !== "aiPreview") {
      return;
    }

    const timer = window.setTimeout(() => {
      const request: CharacterAiPreviewRequest = {
        character_id: selectedDocument.characterId,
        context: previewContext,
      };
      setPreviewBusy(true);
      void invokeCommand<CharacterAiPreview>("build_character_ai_preview", { request })
        .then(
          (payload) => {
            setPreview(payload);
            setPreviewError("");
            onStatusChange(`已加载 ${payload.display_name} 的 AI 预览。`);
          },
          (error) => {
            setPreview(null);
            setPreviewError(String(error));
            onStatusChange(`构建 ${selectedDocument.displayName} 的 AI 预览失败：${String(error)}`);
          },
        )
        .finally(() => {
          setPreviewBusy(false);
        });
    }, 180);

    return () => {
      window.clearTimeout(timer);
    };
  }, [activeTab, onStatusChange, previewContext, selectedCharacter, selectedDocument]);

  useEffect(() => {
    if (!isResizingIndex) {
      return;
    }

    function handlePointerMove(event: PointerEvent) {
      const container = splitLayoutRef.current;
      if (!container) {
        return;
      }
      const bounds = container.getBoundingClientRect();
      const relativeX = event.clientX - bounds.left;
      const minWidth = 220;
      const maxWidth = Math.max(minWidth, Math.min(520, bounds.width - 360));
      setIndexWidth(Math.max(minWidth, Math.min(maxWidth, relativeX)));
    }

    function handlePointerUp() {
      setIsResizingIndex(false);
    }

    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
    return () => {
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    };
  }, [isResizingIndex]);

  const selectedCounts = selectedDocument ? countIssues(selectedDocument.validation) : { errors: 0, warnings: 0 };
  const settlementRefs = useMemo(
    () => new Map(workspace.references.settlements.map((entry) => [entry.id, entry])),
    [workspace.references.settlements],
  );
  const behaviorRefs = useMemo(
    () => new Map(workspace.references.behaviors.map((entry) => [entry.id, entry])),
    [workspace.references.behaviors],
  );
  const scheduleRefs = useMemo(
    () => new Map(workspace.references.schedules.map((entry) => [entry.id, entry])),
    [workspace.references.schedules],
  );
  const personalityRefs = useMemo(
    () => new Map(workspace.references.personalities.map((entry) => [entry.id, entry])),
    [workspace.references.personalities],
  );
  const needRefs = useMemo(
    () => new Map(workspace.references.needs.map((entry) => [entry.id, entry])),
    [workspace.references.needs],
  );
  const accessRefs = useMemo(
    () => new Map(workspace.references.smartObjectAccess.map((entry) => [entry.id, entry])),
    [workspace.references.smartObjectAccess],
  );

  function renderReferencePanel() {
    if (!activeReference) {
      return null;
    }

    if (activeReference.kind === "settlement") {
      const settlement = settlementRefs.get(activeReference.id);
      if (!settlement) {
        return null;
      }
      return (
        <PanelSection
          label="引用"
          title={`据点 · ${settlement.id}`}
          summary={<Badge tone="accent">{settlement.mapId}</Badge>}
          headerActions={
            <button type="button" className="toolbar-button" onClick={() => setActiveReference(null)}>
              关闭
            </button>
          }
        >
          {renderDetailRows([
            { label: "地图", value: settlement.mapId },
            { label: "锚点数", value: settlement.anchorIds.length },
            { label: "路线数", value: settlement.routeIds.length },
            { label: "智能物件数", value: settlement.smartObjects.length },
            { label: "最低值守守卫", value: settlement.minGuardOnDuty },
          ])}
          {settlement.routeIds.length > 0 ? (
            <div>
              <span className="field-label">路线 ID</span>
              <div className="character-key-list">
                {settlement.routeIds.map((routeId) => (
                  <span key={routeId} className="character-key-item">
                    {routeId}
                  </span>
                ))}
              </div>
            </div>
          ) : null}
          {settlement.smartObjects.length > 0 ? (
            <div>
              <span className="field-label">智能物件</span>
              <div className="character-key-list">
                {settlement.smartObjects.map((smartObjectId) => (
                  <span key={smartObjectId} className="character-key-item">
                    {smartObjectId}
                  </span>
                ))}
              </div>
            </div>
          ) : null}
        </PanelSection>
      );
    }

    if (activeReference.kind === "behavior") {
      const behavior = behaviorRefs.get(activeReference.id);
      if (!behavior) {
        return null;
      }
      return (
        <PanelSection
          label="引用"
          title={`行为 · ${behavior.display_name}`}
          summary={<Badge tone="muted">{behavior.id}</Badge>}
          headerActions={
            <button type="button" className="toolbar-button" onClick={() => setActiveReference(null)}>
              关闭
            </button>
          }
        >
          {behavior.description ? <p className="field-hint">{behavior.description}</p> : null}
          {renderDetailRows([
            { label: "事实", value: behavior.facts.length },
            { label: "目标", value: behavior.goals.length },
            { label: "动作", value: behavior.actions.length },
            { label: "执行器", value: behavior.executors.length },
          ])}
          <div className="character-module-stack">
            <div>
              <span className="field-label">事实</span>
              {renderModuleTokens(behavior.facts)}
            </div>
            <div>
              <span className="field-label">目标</span>
              {renderModuleTokens(behavior.goals)}
            </div>
            <div>
              <span className="field-label">动作</span>
              {renderModuleTokens(behavior.actions)}
            </div>
            <div>
              <span className="field-label">执行器</span>
              {renderModuleTokens(behavior.executors)}
            </div>
          </div>
        </PanelSection>
      );
    }

    if (activeReference.kind === "schedule") {
      const schedule = scheduleRefs.get(activeReference.id);
      if (!schedule) {
        return null;
      }
      return (
        <PanelSection
          label="引用"
          title={`日程 · ${schedule.displayName}`}
          summary={<Badge tone="muted">{schedule.id}</Badge>}
          headerActions={
            <button type="button" className="toolbar-button" onClick={() => setActiveReference(null)}>
              关闭
            </button>
          }
        >
          {schedule.description ? <p className="field-hint">{schedule.description}</p> : null}
          <div className="character-compact-list">
            {schedule.entries.map((entry, index) => (
              <article key={`${entry.label}-${index}`} className="character-compact-row">
                <div className="section-header">
                  <strong>{entry.label || `日程 ${index + 1}`}</strong>
                  <Badge tone="muted">
                    {formatMinute(entry.start_minute)} - {formatMinute(entry.end_minute)}
                  </Badge>
                </div>
                <p className="field-hint">
                  {entry.days.join(", ")} · {formatMinute(entry.start_minute)} - {formatMinute(entry.end_minute)}
                </p>
                <div className="row-badges">
                  {entry.tags.map((tag) => (
                    <Badge key={`${entry.label}-${tag}`} tone="muted">{tag}</Badge>
                  ))}
                </div>
              </article>
            ))}
          </div>
        </PanelSection>
      );
    }

    if (activeReference.kind === "personality") {
      const personality = personalityRefs.get(activeReference.id);
      if (!personality) {
        return null;
      }
      return (
        <PanelSection
          label="引用"
          title={`性格 · ${personality.displayName}`}
          summary={<Badge tone="muted">{personality.id}</Badge>}
          headerActions={
            <button type="button" className="toolbar-button" onClick={() => setActiveReference(null)}>
              关闭
            </button>
          }
        >
          {personality.description ? <p className="field-hint">{personality.description}</p> : null}
          {renderDetailRows([
            { label: "安全倾向", value: personality.safetyBias },
            { label: "社交倾向", value: personality.socialBias },
            { label: "职责倾向", value: personality.dutyBias },
            { label: "舒适倾向", value: personality.comfortBias },
            { label: "警觉倾向", value: personality.alertnessBias },
          ])}
        </PanelSection>
      );
    }

    if (activeReference.kind === "need") {
      const need = needRefs.get(activeReference.id);
      if (!need) {
        return null;
      }
      return (
        <PanelSection
          label="引用"
          title={`需求配置 · ${need.displayName}`}
          summary={<Badge tone="muted">{need.id}</Badge>}
          headerActions={
            <button type="button" className="toolbar-button" onClick={() => setActiveReference(null)}>
              关闭
            </button>
          }
        >
          {need.description ? <p className="field-hint">{need.description}</p> : null}
          {renderDetailRows([
            { label: "饥饿衰减", value: need.hungerDecayPerHour },
            { label: "精力衰减", value: need.energyDecayPerHour },
            { label: "士气衰减", value: need.moraleDecayPerHour },
            { label: "安全倾向", value: need.safetyBias },
          ])}
        </PanelSection>
      );
    }

    const access = accessRefs.get(activeReference.id);
    if (!access) {
      return null;
    }
    return (
      <PanelSection
        label="引用"
        title={`访问配置 · ${access.display_name}`}
        summary={<Badge tone="muted">{access.id}</Badge>}
        headerActions={
          <button type="button" className="toolbar-button" onClick={() => setActiveReference(null)}>
            关闭
          </button>
        }
      >
        {access.description ? <p className="field-hint">{access.description}</p> : null}
        <div className="character-compact-list">
          {access.rules.map((rule, index) => (
            <article key={`${rule.kind}-${index}`} className="character-compact-row">
              <div className="section-header">
                <strong>{rule.kind}</strong>
                <Badge tone={rule.fallback_to_any ? "success" : "warning"}>
                  {rule.fallback_to_any ? "可回退" : "严格"}
                </Badge>
              </div>
              <p className="field-hint">{rule.preferred_tags.join(", ") || "无偏好标签"}</p>
              <Badge tone="muted">{rule.preferred_tags.length} 个偏好标签</Badge>
            </article>
          ))}
        </div>
      </PanelSection>
    );
  }

  return (
    <div className="workspace workspace-characters">
      <div className="form-grid character-filter-grid">
        <TextField label="搜索" value={searchText} onChange={setSearchText} placeholder="名称、ID、行为" />
        <SelectField label="据点" value={settlementFilter} onChange={setSettlementFilter} options={workspace.catalogs.settlementIds} />
        <SelectField
          label="角色职责"
          value={roleFilter}
          onChange={setRoleFilter}
          options={workspace.catalogs.roles.map((role) => ({ value: role, label: roleLabel(role) }))}
        />
        <SelectField label="行为配置" value={behaviorFilter} onChange={setBehaviorFilter} options={workspace.catalogs.behaviorProfileIds} />
      </div>

      {workspace.warnings.length > 0 ? (
        <PanelSection
          label="工作区"
          title="警告"
          compact
          collapsible
          collapsed={warningsCollapsed}
          onToggleCollapsed={setWarningsCollapsed}
          summary={
            <div className="toolbar-summary">
              <Badge tone="warning">{workspace.warnings.length} 条警告</Badge>
            </div>
          }
        >
          <div className="issue-list">
            {workspace.warnings.map((warning) => (
              <article key={warning} className="issue">
                <div className="issue-head">
                  <Badge tone="warning">警告</Badge>
                </div>
                <p>{warning}</p>
              </article>
            ))}
          </div>
        </PanelSection>
      ) : null}

      <div
        ref={splitLayoutRef}
        className={`workspace-grid workspace-grid-characters ${indexVisible ? "workspace-grid-characters-resizable" : "workspace-grid-left-hidden"}`.trim()}
        style={indexVisible ? ({ ["--character-index-width" as string]: `${indexWidth}px` } as CSSProperties) : undefined}
      >
        {indexVisible ? (
          <div className="column workspace-index-column character-pane-scroll">
            <PanelSection
              label="角色索引"
              title="项目角色"
              summary={
                <div className="toolbar-summary">
                  <Badge tone="muted" title="当前筛选条件下可见的角色数量">
                    {filteredDocuments.length} 个可见
                  </Badge>
                </div>
              }
            >
              <div className="item-list">
                {filteredDocuments.map((document) => {
                  const counts = countIssues(document.validation);
                  return (
                    <button
                      key={document.documentKey}
                      type="button"
                      className={`item-row ${document.documentKey === selectedDocument?.documentKey ? "item-row-active" : ""}`}
                      title={`查看角色详情：${document.displayName || document.characterId || document.fileName}`}
                      onClick={() => setSelectedKey(document.documentKey)}
                    >
                      <div className="character-index-row">
                        <strong>{document.displayName || document.characterId || document.fileName}</strong>
                        <span className="character-index-id">{document.characterId || document.fileName}</span>
                      </div>
                      <div className="row-badges">
                        {document.role ? (
                          <Badge tone="accent" title="角色在生活模拟中的职责">
                            {roleLabel(document.role)}
                          </Badge>
                        ) : null}
                        {document.settlementId ? (
                          <Badge tone="muted" title="角色所属据点 ID">
                            {document.settlementId}
                          </Badge>
                        ) : null}
                        {counts.errors > 0 ? (
                          <Badge tone="danger" title="该角色数据存在的错误数量">
                            {counts.errors} 个错误
                          </Badge>
                        ) : null}
                        {counts.warnings > 0 ? (
                          <Badge tone="warning" title="该角色数据存在的警告数量">
                            {counts.warnings} 条警告
                          </Badge>
                        ) : null}
                      </div>
                    </button>
                  );
                })}
                {filteredDocuments.length === 0 ? <p className="field-hint">没有匹配当前筛选条件的角色。</p> : null}
              </div>
            </PanelSection>
          </div>
        ) : null}

        {indexVisible ? (
          <div
            className={`character-pane-divider ${isResizingIndex ? "character-pane-divider-active" : ""}`}
            onPointerDown={(event) => {
              event.preventDefault();
              setIsResizingIndex(true);
            }}
            title="拖拽调整左侧角色列表与右侧详情区的宽度"
            role="separator"
            aria-orientation="vertical"
            aria-label="Resize character list"
          />
        ) : null}

        <div className="column-main character-pane-scroll">
          {selectedDocument ? (
            <>
              <PanelSection
                label="当前选择"
                title={selectedDocument.displayName || selectedDocument.characterId || selectedDocument.fileName}
                summary={
                  <div className="toolbar-summary">
                    {selectedDocument.role ? (
                      <Badge tone="accent" title="当前角色的生活职责">
                        {roleLabel(selectedDocument.role)}
                      </Badge>
                    ) : null}
                    {selectedDocument.settlementId ? (
                      <Badge tone="muted" title="当前角色绑定的据点 ID">
                        {selectedDocument.settlementId}
                      </Badge>
                    ) : null}
                  </div>
                }
              >
                <div className="character-selection-strip">
                  <span className="character-selection-id" title="当前角色的稳定 ID">
                    {selectedDocument.characterId || selectedDocument.fileName}
                  </span>
                  <span className="character-selection-path" title={selectedDocument.relativePath}>
                    {selectedDocument.relativePath}
                  </span>
                  {selectedCounts.errors > 0 ? (
                    <Badge tone="danger" title="当前角色数据存在的错误数量">
                      {selectedCounts.errors} 个错误
                    </Badge>
                  ) : null}
                  {selectedCounts.warnings > 0 ? (
                    <Badge tone="warning" title="当前角色数据存在的警告数量">
                      {selectedCounts.warnings} 条警告
                    </Badge>
                  ) : null}
                </div>

                <div className="character-tabs">
                  {TAB_LABELS.map((tab) => (
                    <button
                      key={tab.id}
                      type="button"
                      className={`character-tab ${activeTab === tab.id ? "character-tab-active" : ""}`}
                      title={
                        tab.id === "summary"
                          ? "查看角色基础信息、战斗参数和校验结果"
                          : tab.id === "life"
                            ? "查看生活绑定、配置引用和本地日程覆盖"
                            : "查看指定上下文下的 AI 决策预览"
                      }
                      onClick={() => setActiveTab(tab.id)}
                    >
                      {tab.label}
                    </button>
                  ))}
                </div>
              </PanelSection>

              {activeTab === "summary" ? (
                <>
                  <PanelSection
                    label="摘要"
                    title="身份、战斗与诊断"
                    summary={
                      selectedCharacter ? (
                        <div className="toolbar-summary">
                          <Badge tone="muted" title="角色的稳定唯一 ID">
                            {selectedCharacter.id}
                          </Badge>
                          <Badge tone="accent" title="角色对玩家或阵营的基础态度">
                            {selectedCharacter.faction.disposition}
                          </Badge>
                          {selectedCharacter.faction.camp_id ? (
                            <Badge tone="muted" title="角色所属营地 ID">
                              {selectedCharacter.faction.camp_id}
                            </Badge>
                          ) : null}
                        </div>
                      ) : null
                    }
                  >
                    {selectedCharacter ? (
                      renderDetailRows([
                        { label: "显示名", value: selectedCharacter.identity.display_name || "未命名" },
                        { label: "角色 ID", value: selectedCharacter.id },
                        { label: "原型", value: selectedCharacter.archetype },
                        { label: "阵营倾向", value: selectedCharacter.faction.disposition },
                        { label: "营地", value: selectedCharacter.faction.camp_id || "无营地" },
                        { label: "等级", value: selectedCharacter.progression.level },
                        { label: "战斗行为", value: selectedCharacter.combat.behavior || "无" },
                        { label: "经验奖励", value: selectedCharacter.combat.xp_reward },
                        { label: "仇恨范围", value: selectedCharacter.ai.aggro_range },
                        { label: "攻击范围", value: selectedCharacter.ai.attack_range },
                        { label: "游荡半径", value: selectedCharacter.ai.wander_radius },
                        { label: "脱战距离", value: selectedCharacter.ai.leash_distance },
                        { label: "决策间隔", value: selectedCharacter.ai.decision_interval },
                        { label: "攻击冷却", value: selectedCharacter.ai.attack_cooldown },
                      ])
                    ) : (
                      <p className="field-hint">角色记录不可用，源文件可能解析失败。</p>
                    )}
                  </PanelSection>

                  {selectedCharacter ? (
                    <PanelSection
                      label="表现"
                      title="表现资源"
                      compact
                      collapsible
                      collapsed={presentationCollapsed}
                      onToggleCollapsed={setPresentationCollapsed}
                      summary={<Badge tone="muted" title="表现资源默认折叠，需要时再展开查看">默认折叠</Badge>}
                    >
                      {renderDetailRows([
                        { label: "立绘", value: selectedCharacter.presentation.portrait_path || "无" },
                        { label: "头像", value: selectedCharacter.presentation.avatar_path || "无" },
                        { label: "模型", value: selectedCharacter.presentation.model_path || "无" },
                        {
                          label: "占位色",
                          value: Object.entries(selectedCharacter.presentation.placeholder_colors)
                            .map(([key, value]) => `${key}: ${value}`)
                            .join(" · "),
                        },
                      ])}
                    </PanelSection>
                  ) : null}

                  {selectedCharacter ? (
                    <PanelSection
                      label="属性"
                      title="属性与资源"
                      compact
                      collapsible
                      collapsed={attributesCollapsed}
                      onToggleCollapsed={setAttributesCollapsed}
                      summary={
                        <div className="toolbar-summary">
                          <Badge tone="muted" title="该角色定义中的属性组数量">
                            {Object.keys(selectedCharacter.attributes.sets).length} 组
                          </Badge>
                          <Badge tone="muted" title="该角色定义中的资源池数量">
                            {Object.keys(selectedCharacter.attributes.resources).length} 个资源
                          </Badge>
                        </div>
                      }
                    >
                      <div className="character-module-stack">
                        <div>
                          <span className="field-label">属性组</span>
                          {Object.keys(selectedCharacter.attributes.sets).length > 0 ? (
                            <div className="character-key-list">
                              {Object.entries(selectedCharacter.attributes.sets).map(([key, values]) => (
                                <span key={key} className="character-key-item">
                                  <strong>{key}</strong>:{" "}
                                  {Object.entries(values)
                                    .map(([statKey, statValue]) => `${statKey} ${statValue}`)
                                    .join(" · ")}
                                </span>
                              ))}
                            </div>
                          ) : (
                            <p className="field-hint">无属性组。</p>
                          )}
                        </div>
                        <div>
                          <span className="field-label">资源</span>
                          {Object.keys(selectedCharacter.attributes.resources).length > 0 ? (
                            <div className="character-key-list">
                              {Object.entries(selectedCharacter.attributes.resources).map(([key, value]) => (
                                <span key={key} className="character-key-item">
                                  <strong>{key}</strong>: 当前值 {value.current}
                                </span>
                              ))}
                            </div>
                          ) : (
                            <p className="field-hint">无资源。</p>
                          )}
                        </div>
                      </div>
                    </PanelSection>
                  ) : null}

                  <PanelSection label="校验" title="当前问题" compact>
                    {renderValidation(selectedDocument.validation)}
                  </PanelSection>
                </>
              ) : null}

              {activeTab === "life" ? (
                <>
                  <PanelSection
                    label="生活"
                    title="生活绑定与覆盖"
                    summary={
                      selectedLife ? (
                        <div className="toolbar-summary">
                          <Badge tone="accent" title="当前生活配置里的角色职责">
                            {roleLabel(selectedLife.role)}
                          </Badge>
                          <Badge tone="muted" title="当前生活配置绑定的据点 ID">
                            {selectedLife.settlement_id}
                          </Badge>
                        </div>
                      ) : null
                    }
                  >
                    {selectedLife ? (
                      renderDetailRows([
                        {
                          label: "据点",
                          value: renderReferenceButton(
                            selectedLife.settlement_id,
                            "settlement",
                            selectedLife.settlement_id,
                            setActiveReference,
                          ),
                        },
                        { label: "职责", value: roleLabel(selectedLife.role) },
                        {
                          label: "行为配置",
                          value: renderReferenceButton(
                            selectedLife.ai_behavior_profile_id,
                            "behavior",
                            selectedLife.ai_behavior_profile_id,
                            setActiveReference,
                          ),
                        },
                        {
                          label: "日程配置",
                          value: renderReferenceButton(
                            selectedLife.schedule_profile_id,
                            "schedule",
                            selectedLife.schedule_profile_id,
                            setActiveReference,
                          ),
                        },
                        {
                          label: "性格配置",
                          value: renderReferenceButton(
                            selectedLife.personality_profile_id,
                            "personality",
                            selectedLife.personality_profile_id,
                            setActiveReference,
                          ),
                        },
                        {
                          label: "需求配置",
                          value: renderReferenceButton(
                            selectedLife.need_profile_id,
                            "need",
                            selectedLife.need_profile_id,
                            setActiveReference,
                          ),
                        },
                        {
                          label: "访问配置",
                          value: renderReferenceButton(
                            selectedLife.smart_object_access_profile_id,
                            "access",
                            selectedLife.smart_object_access_profile_id,
                            setActiveReference,
                          ),
                        },
                        { label: "居住锚点", value: selectedLife.home_anchor },
                        { label: "值勤路线", value: selectedLife.duty_route_id || "无" },
                        {
                          label: "需求覆盖",
                          value: renderOverrideSummary(selectedLife.need_profile_override),
                        },
                        {
                          label: "性格覆盖",
                          value: renderOverrideSummary(selectedLife.personality_override),
                        },
                      ])
                    ) : (
                      <p className="field-hint">该角色没有生活配置。</p>
                    )}
                  </PanelSection>

                  {selectedLife ? (
                    <PanelSection
                      label="日程"
                      title="本地日程补丁"
                      compact
                      summary={<Badge tone="muted" title="当前角色本地覆盖的日程区块数量">{selectedLife.schedule.length} 个区块</Badge>}
                    >
                      {selectedLife.schedule.length > 0 ? (
                        <div className="character-compact-list">
                          {selectedLife.schedule.map((block, index) => (
                            <article key={`${block.label}-${index}`} className="character-compact-row">
                              <div className="section-header">
                                <strong>{block.label || `区块 ${index + 1}`}</strong>
                                <Badge tone="muted">
                                  {formatMinute(block.start_minute)} - {formatMinute(block.end_minute)}
                                </Badge>
                              </div>
                              <p className="field-hint">
                                {(block.days.length > 0 ? block.days : [block.day ?? ""])
                                  .filter(Boolean)
                                  .join(", ")}
                              </p>
                              <div className="row-badges">
                                {block.tags.map((tag) => (
                                  <Badge key={`${block.label}-${tag}`} tone="muted">
                                    {tag}
                                  </Badge>
                                ))}
                              </div>
                            </article>
                          ))}
                        </div>
                      ) : (
                        <p className="field-hint">没有本地日程覆盖。</p>
                      )}
                    </PanelSection>
                  ) : null}
                </>
              ) : null}

              {activeTab === "aiPreview" ? (
                <>
                  <PanelSection label="AI 预览" title="预览上下文" compact>
                    <div className="form-grid character-context-grid">
                      <SelectField
                        label="日期"
                        value={previewContext.day}
                        onChange={(value) => setPreviewContext((current) => ({ ...current, day: value as ScheduleDay }))}
                        options={DAY_OPTIONS}
                        allowBlank={false}
                      />
                      <NumberField
                        label="当天分钟"
                        value={previewContext.minute_of_day}
                        min={0}
                        step={15}
                        onChange={(value) =>
                          setPreviewContext((current) => ({
                            ...current,
                            minute_of_day: Math.max(0, Math.min(1440, value)),
                          }))
                        }
                      />
                      <TextField
                        label="当前锚点"
                        value={previewContext.current_anchor ?? ""}
                        onChange={(value) => setPreviewContext((current) => ({ ...current, current_anchor: value }))}
                      />
                      <NumberField label="饥饿" value={previewContext.hunger} min={0} step={5} onChange={(value) => setPreviewContext((current) => ({ ...current, hunger: value }))} />
                      <NumberField label="精力" value={previewContext.energy} min={0} step={5} onChange={(value) => setPreviewContext((current) => ({ ...current, energy: value }))} />
                      <NumberField label="士气" value={previewContext.morale} min={0} step={5} onChange={(value) => setPreviewContext((current) => ({ ...current, morale: value }))} />
                      <NumberField label="在岗守卫" value={previewContext.active_guards} min={0} onChange={(value) => setPreviewContext((current) => ({ ...current, active_guards: Math.max(0, value) }))} />
                      <NumberField label="最低值守" value={previewContext.min_guard_on_duty} min={0} onChange={(value) => setPreviewContext((current) => ({ ...current, min_guard_on_duty: Math.max(0, value) }))} />
                    </div>

                    <div className="character-toggle-grid">
                      <CheckboxField label="世界警报激活" value={previewContext.world_alert_active} onChange={(value) => setPreviewContext((current) => ({ ...current, world_alert_active: value }))} />
                      <CheckboxField label="岗哨可用" value={previewContext.availability.guard_post_available} onChange={(value) => setPreviewContext((current) => ({ ...current, availability: { ...current.availability, guard_post_available: value } }))} />
                      <CheckboxField label="餐饮物件可用" value={previewContext.availability.meal_object_available} onChange={(value) => setPreviewContext((current) => ({ ...current, availability: { ...current.availability, meal_object_available: value } }))} />
                      <CheckboxField label="娱乐物件可用" value={previewContext.availability.leisure_object_available} onChange={(value) => setPreviewContext((current) => ({ ...current, availability: { ...current.availability, leisure_object_available: value } }))} />
                      <CheckboxField label="医疗站可用" value={previewContext.availability.medical_station_available} onChange={(value) => setPreviewContext((current) => ({ ...current, availability: { ...current.availability, medical_station_available: value } }))} />
                      <CheckboxField label="巡逻路线可用" value={previewContext.availability.patrol_route_available} onChange={(value) => setPreviewContext((current) => ({ ...current, availability: { ...current.availability, patrol_route_available: value } }))} />
                      <CheckboxField label="床位可用" value={previewContext.availability.bed_available} onChange={(value) => setPreviewContext((current) => ({ ...current, availability: { ...current.availability, bed_available: value } }))} />
                    </div>

                    {previewBusy ? <Badge tone="accent" title="正在根据当前上下文重新计算 AI 预览">正在加载预览...</Badge> : null}
                    {previewError ? <p className="field-hint">{previewError}</p> : null}
                  </PanelSection>

                  {preview ? (
                    <>
                      <PanelSection
                        label="性格"
                        title={preview.personality.display_name}
                        compact
                        summary={
                          <div className="toolbar-summary">
                            <button
                              type="button"
                              className="character-reference-button"
                              title="查看该角色当前使用的性格配置详情"
                              onClick={() => setActiveReference({ kind: "personality", id: preview.personality.id })}
                            >
                              {preview.personality.id}
                            </button>
                            <button
                              type="button"
                              className="character-reference-button"
                              title="查看该角色当前使用的需求配置详情"
                              onClick={() => setActiveReference({ kind: "need", id: preview.need_profile.id })}
                            >
                              {preview.need_profile.id}
                            </button>
                            <button
                              type="button"
                              className="character-reference-button"
                              title="查看该角色当前使用的智能物件访问配置详情"
                              onClick={() =>
                                setActiveReference({ kind: "access", id: preview.smart_object_access.id })
                              }
                            >
                              {preview.smart_object_access.id}
                            </button>
                          </div>
                        }
                      >
                        <div className="character-key-list">
                          <span className="character-key-item">
                            <strong>安全</strong>: {preview.personality.safety_bias}
                          </span>
                          <span className="character-key-item">
                            <strong>社交</strong>: {preview.personality.social_bias}
                          </span>
                          <span className="character-key-item">
                            <strong>职责</strong>: {preview.personality.duty_bias}
                          </span>
                          <span className="character-key-item">
                            <strong>舒适</strong>: {preview.personality.comfort_bias}
                          </span>
                          <span className="character-key-item">
                            <strong>警觉</strong>: {preview.personality.alertness_bias}
                          </span>
                          <span className="character-key-item">
                            <strong>需求衰减</strong>: 饥饿 {preview.need_profile.hunger_decay_per_hour} · 精力{" "}
                            {preview.need_profile.energy_decay_per_hour} · 士气{" "}
                            {preview.need_profile.morale_decay_per_hour}
                          </span>
                          <span className="character-key-item">
                            <strong>访问规则</strong>: {preview.smart_object_access.rules.length}
                          </span>
                        </div>
                      </PanelSection>

                      <PanelSection
                        label="日程"
                        title={preview.schedule.profile_id}
                        compact
                        summary={
                          preview.life.current_schedule_entry ? (
                            <div className="toolbar-summary">
                              <Badge tone="accent" title="当前上下文命中的日程区块标签">
                                {preview.life.current_schedule_entry.label}
                              </Badge>
                              <Badge tone="muted" title="当前命中日程区块的时间范围">
                                {formatMinute(preview.life.current_schedule_entry.start_minute)} - {formatMinute(preview.life.current_schedule_entry.end_minute)}
                              </Badge>
                            </div>
                          ) : null
                        }
                      >
                        <div className="character-compact-list">
                          {preview.schedule.entries.map((entry, index) => (
                            <article
                              key={`${entry.label}-${index}`}
                              className={`character-compact-row ${preview.life.current_schedule_entry?.label === entry.label ? "character-detail-card-active" : ""}`}
                            >
                              <div className="section-header">
                                <strong>{entry.label || `日程 ${index + 1}`}</strong>
                                <Badge tone="muted">
                                  {formatMinute(entry.start_minute)} - {formatMinute(entry.end_minute)}
                                </Badge>
                              </div>
                              <p className="field-hint">
                                {entry.days.join(", ")} · {formatMinute(entry.start_minute)} - {formatMinute(entry.end_minute)}
                              </p>
                              <div className="row-badges">
                                {entry.tags.map((tag) => (
                                  <Badge key={`${entry.label}-${tag}`} tone="muted">{tag}</Badge>
                                ))}
                              </div>
                            </article>
                          ))}
                        </div>
                      </PanelSection>

                      <PanelSection
                        label="行为"
                        title={preview.behavior.display_name}
                        compact
                        summary={
                          <div className="toolbar-summary">
                            <button
                              type="button"
                              className="character-reference-button"
                              title="查看当前行为配置详情"
                              onClick={() => setActiveReference({ kind: "behavior", id: preview.behavior.id })}
                            >
                              {preview.behavior.id}
                            </button>
                            {preview.behavior.default_goal_id ? (
                              <Badge tone="accent" title="正常状态下优先采用的默认目标">
                                默认: {preview.behavior.default_goal_id}
                              </Badge>
                            ) : null}
                            {preview.behavior.alert_goal_id ? (
                              <Badge tone="warning" title="警报激活时优先采用的目标">
                                警报: {preview.behavior.alert_goal_id}
                              </Badge>
                            ) : null}
                          </div>
                        }
                      >
                        <div className="character-module-stack">
                          <div>
                            <span className="field-label">事实</span>
                            {renderModuleTokens(preview.behavior.facts)}
                          </div>
                          <div>
                            <span className="field-label">目标</span>
                            {renderModuleTokens(preview.behavior.goals)}
                          </div>
                          <div>
                            <span className="field-label">动作</span>
                            {renderModuleTokens(preview.behavior.actions)}
                          </div>
                          <div>
                            <span className="field-label">执行器</span>
                            {renderModuleTokens(preview.behavior.executors)}
                          </div>
                        </div>
                      </PanelSection>

                      <PanelSection label="决策快照" title="事实、目标与动作" compact>
                        <div className="character-preview-columns">
                          <div className="character-preview-column">
                            <span className="field-label">事实</span>
                            <div className="row-badges">
                              {preview.fact_ids.length > 0 ? preview.fact_ids.map((factId) => (
                                <Badge key={factId} tone="accent">{factId}</Badge>
                              )) : <Badge tone="muted">无事实</Badge>}
                            </div>
                          </div>
                          <div className="character-preview-column">
                            <span className="field-label">目标评分</span>
                            {renderCompactGoalList(preview)}
                          </div>
                          <div className="character-preview-column">
                            <span className="field-label">动作</span>
                            {renderCompactActionList(preview)}
                          </div>
                        </div>
                      </PanelSection>
                    </>
                  ) : !previewBusy && !previewError ? (
                    <PanelSection label="AI 预览" title="无可用预览">
                      <p className="field-hint">
                        {selectedCharacter
                          ? "打开带有生活配置的有效角色后，才能查看 AI 预览。"
                          : "该源文件不包含有效的角色记录。"}
                      </p>
                    </PanelSection>
                  ) : null}
                </>
              ) : null}

              {renderReferencePanel()}
            </>
          ) : (
            <PanelSection label="当前选择" title="未选择角色">
              <p className="field-hint">请先从左侧索引中选择一个角色。</p>
            </PanelSection>
          )}
        </div>
      </div>
    </div>
  );
}
