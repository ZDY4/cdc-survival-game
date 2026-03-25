import { useEffect, useMemo, useState } from "react";
import { Badge } from "../../components/Badge";
import {
  NumberField,
  SelectField,
  TextareaField,
  TextField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import type {
  AiConnectionTestResult,
  AiDiffSummary,
  AiDraftPayload,
  AiGenerateRequest,
  AiGenerationResponse,
  AiSettings,
} from "../../types";

export type AiGeneratePanelProps<TRecord> = {
  open: boolean;
  title: string;
  targetType: string;
  targetId: string;
  currentRecord: TRecord;
  emptyRecord: TRecord;
  onClose: () => void;
  onGenerate: (request: AiGenerateRequest<TRecord>) => Promise<AiGenerationResponse<TRecord>>;
  onLoadSettings: () => Promise<AiSettings>;
  onSaveSettings: (settings: AiSettings) => Promise<AiSettings>;
  onTestSettings: (settings: AiSettings) => Promise<AiConnectionTestResult>;
  onApply: (draft: AiDraftPayload<TRecord>) => void;
};

function formatDiff(diffSummary: AiDiffSummary) {
  if (!diffSummary.summaryLines.length) {
    return "暂无差异信息";
  }

  const sections = [
    ["Summary", diffSummary.summaryLines],
    ["新增字段", diffSummary.addedPaths],
    ["修改字段", diffSummary.changedPaths],
    ["删除字段", diffSummary.removedPaths],
  ];

  return sections
    .map(([title, lines]) => `${title}\n${(lines as string[]).length ? (lines as string[]).map((line) => `- ${line}`).join("\n") : "- 无"}`)
    .join("\n\n");
}

export function AiGeneratePanel<TRecord>({
  open,
  title,
  targetType,
  targetId,
  currentRecord,
  emptyRecord,
  onClose,
  onGenerate,
  onLoadSettings,
  onSaveSettings,
  onTestSettings,
  onApply,
}: AiGeneratePanelProps<TRecord>) {
  const [mode, setMode] = useState<"create" | "revise">("revise");
  const [userPrompt, setUserPrompt] = useState("");
  const [adjustmentPrompt, setAdjustmentPrompt] = useState("");
  const [response, setResponse] = useState<AiGenerationResponse<TRecord> | null>(null);
  const [settings, setSettings] = useState<AiSettings | null>(null);
  const [busy, setBusy] = useState(false);
  const [settingsBusy, setSettingsBusy] = useState(false);
  const [settingsStatus, setSettingsStatus] = useState("");

  useEffect(() => {
    if (!open) {
      return;
    }
    setMode(targetId ? "revise" : "create");
    setResponse(null);
    void onLoadSettings()
      .then(setSettings)
      .catch((error) => {
        setSettingsStatus(`Failed to load AI settings: ${String(error)}`);
      });
  }, [open, onLoadSettings, targetId]);

  const effectiveCurrentRecord = mode === "create" ? emptyRecord : currentRecord;
  const currentSnapshot = useMemo(
    () => JSON.stringify(effectiveCurrentRecord, null, 2),
    [effectiveCurrentRecord],
  );
  const draftSnapshot = useMemo(
    () => JSON.stringify(response?.draft?.record ?? {}, null, 2),
    [response],
  );
  const hasBlockingValidation =
    Boolean(response?.providerError) ||
    Boolean(response?.validationErrors.length) ||
    !response?.draft;

  async function runGeneration(includePreviousDraft: boolean) {
    setBusy(true);
    try {
      const next = await onGenerate({
        mode,
        targetId,
        userPrompt,
        adjustmentPrompt,
        currentRecord: effectiveCurrentRecord,
        previousDraft: includePreviousDraft ? response?.draft?.record ?? null : null,
        previousValidationErrors: includePreviousDraft
          ? response?.validationErrors ?? []
          : [],
      });
      setResponse(next);
    } finally {
      setBusy(false);
    }
  }

  async function saveSettings() {
    if (!settings) {
      return;
    }
    setSettingsBusy(true);
    try {
      const saved = await onSaveSettings(settings);
      setSettings(saved);
      setSettingsStatus("AI 设置已保存");
    } catch (error) {
      setSettingsStatus(`保存 AI 设置失败: ${String(error)}`);
    } finally {
      setSettingsBusy(false);
    }
  }

  async function testSettings() {
    if (!settings) {
      return;
    }
    setSettingsBusy(true);
    try {
      const result = await onTestSettings(settings);
      setSettingsStatus(result.ok ? "连接测试成功" : result.error || "连接测试失败");
    } catch (error) {
      setSettingsStatus(`连接测试失败: ${String(error)}`);
    } finally {
      setSettingsBusy(false);
    }
  }

  async function copyJson() {
    if (!response?.draft) {
      return;
    }
    await navigator.clipboard.writeText(JSON.stringify(response.draft.record, null, 2));
  }

  if (!open) {
    return null;
  }

  return (
    <div className="ai-modal-backdrop" role="presentation" onClick={onClose}>
      <div className="ai-modal" role="dialog" aria-modal="true" onClick={(event) => event.stopPropagation()}>
        <div className="ai-modal-header">
          <div>
            <p className="eyebrow">AI Generate</p>
            <h3>{title}</h3>
          </div>
          <button type="button" className="toolbar-button" onClick={onClose}>
            Close
          </button>
        </div>

        <div className="ai-meta-row">
          <Badge tone="accent">{targetType}</Badge>
          <Badge tone="muted">target: {targetId || "new draft"}</Badge>
          <Badge tone={response?.diffSummary?.riskLevel === "high" ? "danger" : "muted"}>
            risk: {response?.diffSummary?.riskLevel ?? "n/a"}
          </Badge>
        </div>

        <div className="ai-layout">
          <div className="ai-column">
            <PanelSection label="Request" title="Prompting">
              <SelectField
                label="Mode"
                value={mode}
                onChange={(value) => setMode((value as "create" | "revise") || "create")}
                allowBlank={false}
                options={[
                  { value: "create", label: "Create" },
                  { value: "revise", label: "Revise current" },
                ]}
              />
              <TextareaField
                label="Main prompt"
                value={userPrompt}
                onChange={setUserPrompt}
                placeholder="描述你希望 AI 生成什么样的任务或对话..."
              />
              <TextareaField
                label="Adjustment prompt"
                value={adjustmentPrompt}
                onChange={setAdjustmentPrompt}
                placeholder="如果要在当前草稿基础上微调，请写在这里。"
              />
              <div className="toolbar-actions">
                <button type="button" className="toolbar-button toolbar-accent" onClick={() => void runGeneration(false)} disabled={busy}>
                  Generate draft
                </button>
                <button type="button" className="toolbar-button" onClick={() => void runGeneration(true)} disabled={busy || !response?.draft}>
                  Refine draft
                </button>
                <button
                  type="button"
                  className="toolbar-button"
                  onClick={() => {
                    setResponse(null);
                    setUserPrompt("");
                    setAdjustmentPrompt("");
                  }}
                  disabled={busy}
                >
                  Discard
                </button>
              </div>
            </PanelSection>

            <PanelSection label="Provider" title="AI settings">
              <TextField
                label="Base URL"
                value={settings?.baseUrl ?? ""}
                onChange={(value) => setSettings((current) => ({ ...(current ?? defaultSettings()), baseUrl: value }))}
              />
              <TextField
                label="Model"
                value={settings?.model ?? ""}
                onChange={(value) => setSettings((current) => ({ ...(current ?? defaultSettings()), model: value }))}
              />
              <TextField
                label="API Key"
                value={settings?.apiKey ?? ""}
                onChange={(value) => setSettings((current) => ({ ...(current ?? defaultSettings()), apiKey: value }))}
              />
              <NumberField
                label="Timeout (sec)"
                value={settings?.timeoutSec ?? 45}
                min={5}
                onChange={(value) => setSettings((current) => ({ ...(current ?? defaultSettings()), timeoutSec: Math.max(5, value) }))}
              />
              <NumberField
                label="Max context records"
                value={settings?.maxContextRecords ?? 24}
                min={6}
                onChange={(value) =>
                  setSettings((current) => ({
                    ...(current ?? defaultSettings()),
                    maxContextRecords: Math.max(6, value),
                  }))
                }
              />
              <div className="toolbar-actions">
                <button type="button" className="toolbar-button" onClick={() => void testSettings()} disabled={settingsBusy}>
                  Test connection
                </button>
                <button type="button" className="toolbar-button toolbar-accent" onClick={() => void saveSettings()} disabled={settingsBusy}>
                  Save settings
                </button>
              </div>
              {settingsStatus ? <p className="field-hint">{settingsStatus}</p> : null}
            </PanelSection>
          </div>

          <div className="ai-column ai-column-wide">
            <PanelSection label="Review" title="Snapshots">
              <div className="ai-snapshot-grid">
                <label className="field">
                  <span className="field-label">Current record snapshot</span>
                  <textarea className="field-input field-textarea field-code ai-readonly" readOnly value={currentSnapshot} />
                </label>
                <label className="field">
                  <span className="field-label">Draft record snapshot</span>
                  <textarea className="field-input field-textarea field-code ai-readonly" readOnly value={draftSnapshot} />
                </label>
              </div>
            </PanelSection>

            <PanelSection label="Review" title="Diff preview">
              <textarea
                className="field-input field-textarea field-code ai-readonly"
                readOnly
                value={response ? formatDiff(response.diffSummary) : "暂无差异信息"}
              />
            </PanelSection>

            <PanelSection label="Review" title="Summary and validation">
              <label className="field">
                <span className="field-label">Summary</span>
                <textarea
                  className="field-input field-textarea ai-readonly"
                  readOnly
                  value={response?.draft?.summary ?? ""}
                />
              </label>
              <label className="field">
                <span className="field-label">Validation</span>
                <textarea
                  className="field-input field-textarea ai-readonly"
                  readOnly
                  value={
                    response?.providerError
                      ? response.providerError
                      : response?.validationErrors.length
                        ? response.validationErrors.join("\n")
                        : "校验通过"
                  }
                />
              </label>
              <label className="field">
                <span className="field-label">Review warnings</span>
                <textarea
                  className="field-input field-textarea ai-readonly"
                  readOnly
                  value={response?.reviewWarnings.join("\n") ?? ""}
                />
              </label>
              <div className="toolbar-actions">
                <button type="button" className="toolbar-button" onClick={() => void copyJson()} disabled={!response?.draft}>
                  Copy JSON
                </button>
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    if (response?.draft) {
                      onApply(response.draft);
                    }
                  }}
                  disabled={hasBlockingValidation}
                >
                  {response?.diffSummary.riskLevel === "high" ? "Apply high-risk draft" : "Apply to editor"}
                </button>
              </div>
            </PanelSection>

            <PanelSection label="Debug" title="Raw output and prompt debug">
              <label className="field">
                <span className="field-label">Raw output / error</span>
                <textarea
                  className="field-input field-textarea field-code ai-readonly"
                  readOnly
                  value={response?.rawOutput ?? ""}
                />
              </label>
              <label className="field">
                <span className="field-label">Prompt debug</span>
                <textarea
                  className="field-input field-textarea field-code ai-readonly"
                  readOnly
                  value={JSON.stringify(response?.promptDebug ?? {}, null, 2)}
                />
              </label>
            </PanelSection>
          </div>
        </div>
      </div>
    </div>
  );
}

function defaultSettings(): AiSettings {
  return {
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4.1-mini",
    apiKey: "",
    timeoutSec: 45,
    maxContextRecords: 24,
  };
}
