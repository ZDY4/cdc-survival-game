import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Badge } from "../../components/Badge";
import {
  SelectField,
  TextareaField,
  TextField,
  TokenListField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { invokeCommand } from "../../lib/tauri";
import type {
  AiConnectionTestResult,
  AiSettings,
  CloudWorkspaceMeta,
  NarrativeAppSettings,
  NarrativeAction,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativeSyncSettings,
  NarrativeWorkspaceSyncResult,
  ProjectContextSnapshotExportResult,
  ProjectContextSnapshotUploadResult,
  NarrativeSelectionRange,
  NarrativeWorkspacePayload,
  SaveNarrativeDocumentResult,
  StructuringBundlePayload,
} from "../../types";
import {
  applySelectionRange,
  narrativeDiffSummary,
  toUtf8SelectionRange,
} from "./narrativeEditing";
import {
  defaultNarrativeMarkdown,
  defaultNarrativeTitle,
  docTypeDirectory,
  docTypeLabel,
  fallbackNarrativeMeta,
} from "./narrativeTemplates";

type EditableNarrativeDocument = NarrativeDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type NarrativeWorkspaceProps = {
  workspace: NarrativeWorkspacePayload;
  appSettings: NarrativeAppSettings;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  onOpenWorkspace: (workspaceRoot: string) => Promise<void>;
  onConnectProject: (projectRoot: string | null) => Promise<void>;
};

const GENERATOR_BUTTONS: Array<{ label: string; docType: NarrativeDocType }> = [
  { label: "生成项目大纲", docType: "project_brief" },
  { label: "生成人物设定", docType: "character_card" },
  { label: "生成章节大纲", docType: "chapter_outline" },
  { label: "生成分支设计", docType: "branch_sheet" },
  { label: "生成场景稿", docType: "scene_draft" },
];

const ACTION_OPTIONS: Array<{ value: NarrativeAction; label: string }> = [
  { value: "create", label: "创建文稿" },
  { value: "revise_document", label: "整篇改写" },
  { value: "rewrite_selection", label: "改写选中内容" },
  { value: "expand_selection", label: "扩写选中内容" },
  { value: "insert_after_selection", label: "在选中段后补写" },
  { value: "derive_new_doc", label: "派生为新文稿" },
];

function snapshotDocument(document: NarrativeDocumentPayload) {
  return JSON.stringify({ meta: document.meta, markdown: document.markdown });
}

function hydrateDocuments(documents: NarrativeDocumentPayload[]): EditableNarrativeDocument[] {
  return documents.map((document) => ({
    ...document,
    savedSnapshot: snapshotDocument(document),
    dirty: false,
    isDraft: false,
  }));
}

function documentDirty(document: NarrativeDocumentPayload, savedSnapshot: string) {
  return snapshotDocument(document) !== savedSnapshot;
}

function createFallbackDraft(docType: NarrativeDocType, slug: string): EditableNarrativeDocument {
  const meta = fallbackNarrativeMeta(docType, slug);
  return {
    documentKey: slug,
    originalSlug: slug,
    fileName: `${slug}.md`,
    relativePath: `narrative/${docTypeDirectory(docType)}/${slug}.md`,
    meta,
    markdown: defaultNarrativeMarkdown(docType, defaultNarrativeTitle(docType)),
    validation: [],
    savedSnapshot: "",
    dirty: true,
    isDraft: true,
  };
}

export function NarrativeWorkspace({
  workspace,
  appSettings,
  canPersist,
  onStatusChange,
  onReload,
  onOpenWorkspace,
  onConnectProject,
}: NarrativeWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableNarrativeDocument[]>(
    hydrateDocuments(workspace.documents),
  );
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [filterDocType, setFilterDocType] = useState("");
  const [busy, setBusy] = useState(false);
  const [aiAction, setAiAction] = useState<NarrativeAction>("create");
  const [userPrompt, setUserPrompt] = useState("");
  const [editorInstruction, setEditorInstruction] = useState("");
  const [derivedTargetDocType, setDerivedTargetDocType] =
    useState<NarrativeDocType>("branch_sheet");
  const [response, setResponse] = useState<NarrativeGenerateResponse | null>(null);
  const [lastRequest, setLastRequest] = useState<NarrativeGenerateRequest | null>(null);
  const [settings, setSettings] = useState<AiSettings | null>(null);
  const [settingsBusy, setSettingsBusy] = useState(false);
  const [settingsStatus, setSettingsStatus] = useState("");
  const [selectionRange, setSelectionRange] = useState<NarrativeSelectionRange | null>(null);
  const [selectionText, setSelectionText] = useState("");
  const [bundleSelection, setBundleSelection] = useState<string[]>([]);
  const [bundleResult, setBundleResult] = useState<StructuringBundlePayload | null>(null);
  const [syncSettings, setSyncSettings] = useState<NarrativeSyncSettings | null>(null);
  const [cloudWorkspaces, setCloudWorkspaces] = useState<CloudWorkspaceMeta[]>([]);
  const [cloudWorkspaceName, setCloudWorkspaceName] = useState("");
  const [syncResult, setSyncResult] = useState<NarrativeWorkspaceSyncResult | null>(null);
  const [snapshotExport, setSnapshotExport] = useState<ProjectContextSnapshotExportResult | null>(null);
  const [snapshotUpload, setSnapshotUpload] = useState<ProjectContextSnapshotUploadResult | null>(null);
  const [syncBusy, setSyncBusy] = useState(false);
  const [syncStatus, setSyncStatus] = useState("");
  const [workspaceInput, setWorkspaceInput] = useState(workspace.workspaceRoot || appSettings.lastWorkspace || "");
  const [projectInput, setProjectInput] = useState(
    workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "",
  );
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
    setBundleSelection([]);
    setBundleResult(null);
  }, [workspace]);

  useEffect(() => {
    void invokeCommand<AiSettings>("load_ai_settings")
      .then(setSettings)
      .catch((error) => setSettingsStatus(`Failed to load AI settings: ${String(error)}`));
    void invokeCommand<NarrativeSyncSettings>("load_narrative_sync_settings")
      .then(setSyncSettings)
      .catch((error) => setSyncStatus(`Failed to load sync settings: ${String(error)}`));
  }, []);

  useEffect(() => {
    setSelectionRange(null);
    setSelectionText("");
  }, [selectedKey]);

  useEffect(() => {
    setWorkspaceInput(workspace.workspaceRoot || appSettings.lastWorkspace || "");
  }, [appSettings.lastWorkspace, workspace.workspaceRoot]);

  useEffect(() => {
    setProjectInput(workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "");
  }, [appSettings.connectedProjectRoot, workspace.connectedProjectRoot]);

  const filteredDocuments = useMemo(
    () =>
      documents.filter((document) => {
        if (filterDocType && document.meta.docType !== filterDocType) {
          return false;
        }
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.meta.slug} ${document.meta.title} ${document.meta.docType}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, documents, filterDocType],
  );

  const selectedDocument =
    documents.find((document) => document.documentKey === selectedKey) ?? null;
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const hasSelection = Boolean(selectionText.trim()) && Boolean(selectionRange);
  const hasActiveWorkspace = Boolean(workspace.workspaceRoot.trim());

  function updateSelectedDocument(
    transform: (document: NarrativeDocumentPayload) => NarrativeDocumentPayload,
  ) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const next = transform(document);
        return {
          ...next,
          dirty: documentDirty(next, document.savedSnapshot),
          savedSnapshot: document.savedSnapshot,
          isDraft: document.isDraft,
        };
      }),
    );
  }

  async function createDraft(docType: NarrativeDocType) {
    if (!hasActiveWorkspace) {
      onStatusChange("Choose or create a workspace before creating narrative drafts.");
      return;
    }
    setBusy(true);
    try {
      let draft: EditableNarrativeDocument;
      if (canPersist) {
        const payload = await invokeCommand<NarrativeDocumentPayload>("create_narrative_document", {
          workspaceRoot: workspace.workspaceRoot,
          input: { docType, title: defaultNarrativeTitle(docType) },
        });
        draft = { ...payload, savedSnapshot: "", dirty: true, isDraft: true };
      } else {
        draft = createFallbackDraft(docType, `${docType}-${Date.now()}`);
      }

      setDocuments((current) => [draft, ...current]);
      setSelectedKey(draft.documentKey);
      setAiAction("create");
      setResponse(null);
      setLastRequest(null);
      onStatusChange(`Created narrative draft ${draft.meta.slug}.`);
    } catch (error) {
      onStatusChange(`Failed to create narrative draft: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved narrative changes.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot save narrative documents in UI fallback mode.");
      return;
    }
    if (!hasActiveWorkspace) {
      onStatusChange("Choose or create a workspace before saving.");
      return;
    }

    setBusy(true);
    try {
      for (const document of dirtyDocuments) {
        await invokeCommand<SaveNarrativeDocumentResult>("save_narrative_document", {
          workspaceRoot: workspace.workspaceRoot,
          input: {
            originalSlug: document.isDraft ? null : document.originalSlug,
            document,
          },
        });
      }
      await onReload();
      onStatusChange(`Saved ${dirtyDocuments.length} narrative documents.`);
    } catch (error) {
      onStatusChange(`Narrative save failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a narrative document first.");
      return;
    }
    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      onStatusChange("Removed unsaved narrative draft.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_narrative_document", {
        workspaceRoot: workspace.workspaceRoot,
        slug: selectedDocument.meta.slug,
      });
      await onReload();
      onStatusChange(`Deleted narrative document ${selectedDocument.meta.slug}.`);
    } catch (error) {
      onStatusChange(`Narrative delete failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  function updateSelectionFromEditor() {
    const editor = editorRef.current;
    const document = selectedDocument;
    if (!editor || !document) {
      return;
    }
    if (editor.selectionStart === editor.selectionEnd) {
      setSelectionRange(null);
      setSelectionText("");
      return;
    }
    const selected = document.markdown.slice(editor.selectionStart, editor.selectionEnd);
    setSelectionText(selected);
    setSelectionRange(
      toUtf8SelectionRange(document.markdown, editor.selectionStart, editor.selectionEnd),
    );
  }

  async function testSettings() {
    if (!settings) {
      return;
    }
    setSettingsBusy(true);
    try {
      const result = await invokeCommand<AiConnectionTestResult>("test_ai_provider", { settings });
      setSettingsStatus(result.ok ? "连接测试成功" : result.error || "连接测试失败");
    } catch (error) {
      setSettingsStatus(`连接测试失败: ${String(error)}`);
    } finally {
      setSettingsBusy(false);
    }
  }

  async function saveSettings() {
    if (!settings) {
      return;
    }
    setSettingsBusy(true);
    try {
      const saved = await invokeCommand<AiSettings>("save_ai_settings", { settings });
      setSettings(saved);
      setSettingsStatus("AI 设置已保存");
    } catch (error) {
      setSettingsStatus(`保存 AI 设置失败: ${String(error)}`);
    } finally {
      setSettingsBusy(false);
    }
  }

  async function saveSyncSettings() {
    if (!syncSettings) {
      return;
    }
    setSyncBusy(true);
    try {
      const saved = await invokeCommand<NarrativeSyncSettings>("save_narrative_sync_settings", {
        settings: syncSettings,
      });
      setSyncSettings(saved);
      setSyncStatus("Narrative Sync 设置已保存。");
    } catch (error) {
      setSyncStatus(`保存同步设置失败: ${String(error)}`);
    } finally {
      setSyncBusy(false);
    }
  }

  async function refreshCloudWorkspaces() {
    setSyncBusy(true);
    try {
      const result = await invokeCommand<CloudWorkspaceMeta[]>("list_cloud_workspaces");
      setCloudWorkspaces(result);
      setSyncStatus(`Cloud workspaces loaded: ${result.length}.`);
    } catch (error) {
      setSyncStatus(`加载云工作区失败: ${String(error)}`);
    } finally {
      setSyncBusy(false);
    }
  }

  async function createCloudWorkspace() {
    if (!cloudWorkspaceName.trim()) {
      setSyncStatus("请输入新的云工作区名称。");
      return;
    }
    setSyncBusy(true);
    try {
      const created = await invokeCommand<CloudWorkspaceMeta>("create_cloud_workspace", {
        input: { name: cloudWorkspaceName.trim() },
      });
      setCloudWorkspaces((current) => [created, ...current.filter((entry) => entry.workspaceId !== created.workspaceId)]);
      setSyncSettings((current) => ({
        ...(current ?? {
          serverUrl: "",
          authToken: "",
          workspaceId: "",
          deviceLabel: "desktop-local",
          lastSyncAt: null,
          lastSyncStatus: "",
        }),
        workspaceId: created.workspaceId,
      }));
      setCloudWorkspaceName("");
      setSyncStatus(`Created cloud workspace ${created.name}.`);
    } catch (error) {
      setSyncStatus(`创建云工作区失败: ${String(error)}`);
    } finally {
      setSyncBusy(false);
    }
  }

  async function syncWorkspaceNow() {
    if (!hasActiveWorkspace) {
      onStatusChange("Choose or create a workspace before syncing.");
      return;
    }
    if (dirtyCount > 0) {
      onStatusChange("Save local narrative changes before syncing to the cloud.");
      return;
    }
    setSyncBusy(true);
    try {
      const result = await invokeCommand<NarrativeWorkspaceSyncResult>("sync_narrative_workspace", {
        workspaceRoot: workspace.workspaceRoot,
      });
      setSyncResult(result);
      setSyncStatus(result.syncStatus);
      await onReload();
      onStatusChange(
        `Synced workspace: pushed ${result.pushedCount}, pulled ${result.pulledCount}, conflicts ${result.conflictCount}.`,
      );
    } catch (error) {
      setSyncStatus(`同步失败: ${String(error)}`);
      onStatusChange(`Workspace sync failed: ${String(error)}`);
    } finally {
      setSyncBusy(false);
    }
  }

  async function exportProjectSnapshot() {
    const nextProjectRoot = workspace.connectedProjectRoot ?? projectInput.trim();
    if (!nextProjectRoot) {
      setSyncStatus("请先连接项目目录，再导出项目上下文快照。");
      return;
    }
    setSyncBusy(true);
    try {
      const result = await invokeCommand<ProjectContextSnapshotExportResult>(
        "export_project_context_snapshot",
        {
          workspaceRoot: workspace.workspaceRoot,
          projectRoot: nextProjectRoot,
          maxContextRecords: 24,
        },
      );
      setSnapshotExport(result);
      setSyncStatus(`Project snapshot exported to ${result.exportPath}.`);
    } catch (error) {
      setSyncStatus(`导出项目快照失败: ${String(error)}`);
    } finally {
      setSyncBusy(false);
    }
  }

  async function uploadProjectSnapshot() {
    const nextProjectRoot = workspace.connectedProjectRoot ?? projectInput.trim();
    if (!nextProjectRoot) {
      setSyncStatus("请先连接项目目录，再上传项目上下文快照。");
      return;
    }
    setSyncBusy(true);
    try {
      const result = await invokeCommand<ProjectContextSnapshotUploadResult>(
        "upload_project_context_snapshot",
        {
          workspaceRoot: workspace.workspaceRoot,
          projectRoot: nextProjectRoot,
          maxContextRecords: 24,
        },
      );
      setSnapshotUpload(result);
      setSnapshotExport({
        snapshot: result.snapshot,
        exportPath: result.exportPath,
      });
      setSyncStatus(result.serverStatus);
    } catch (error) {
      setSyncStatus(`上传项目快照失败: ${String(error)}`);
    } finally {
      setSyncBusy(false);
    }
  }

  async function runGeneration() {
    if (!hasActiveWorkspace) {
      onStatusChange("Choose or create a workspace before running AI generation.");
      return;
    }
    if (!selectedDocument) {
      onStatusChange("Select or create a narrative document first.");
      return;
    }
    if (
      (aiAction === "rewrite_selection" ||
        aiAction === "expand_selection" ||
        aiAction === "insert_after_selection") &&
      !hasSelection
    ) {
      onStatusChange("Select a text region before running a selection-only action.");
      return;
    }

    const request: NarrativeGenerateRequest = {
      docType: selectedDocument.meta.docType,
      targetSlug: selectedDocument.meta.slug,
      action: aiAction,
      userPrompt,
      editorInstruction,
      currentMarkdown: selectedDocument.markdown,
      selectedRange: selectionRange,
      selectedText: selectionText,
      relatedDocSlugs: selectedDocument.meta.relatedDocs,
      derivedTargetDocType: aiAction === "derive_new_doc" ? derivedTargetDocType : null,
    };

    setBusy(true);
    try {
      const command =
        aiAction === "create" ? "generate_narrative_draft" : "revise_narrative_draft";
      const next = await invokeCommand<NarrativeGenerateResponse>(command, {
        workspaceRoot: workspace.workspaceRoot,
        projectRoot: workspace.connectedProjectRoot ?? null,
        request,
      });
      setResponse(next);
      setLastRequest(request);
      onStatusChange(next.providerError || next.summary || "Narrative draft ready for review.");
    } catch (error) {
      onStatusChange(`Narrative generation failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function prepareBundle() {
    if (!hasActiveWorkspace) {
      onStatusChange("Choose or create a workspace before preparing a structuring bundle.");
      return;
    }
    const documentSlugs = bundleSelection.length
      ? bundleSelection
      : selectedDocument
        ? [selectedDocument.meta.slug]
        : [];
    if (!documentSlugs.length) {
      onStatusChange("Select one or more narrative documents for structuring.");
      return;
    }

    try {
      const next = await invokeCommand<StructuringBundlePayload>("prepare_structuring_bundle", {
        workspaceRoot: workspace.workspaceRoot,
        projectRoot: workspace.connectedProjectRoot ?? null,
        input: { documentSlugs },
      });
      setBundleResult(next);
      onStatusChange(`Prepared structuring bundle for ${next.documentSlugs.length} documents.`);
    } catch (error) {
      onStatusChange(`Failed to prepare structuring bundle: ${String(error)}`);
    }
  }

  async function handleWorkspaceSubmit() {
    if (!workspaceInput.trim()) {
      onStatusChange("Enter a workspace path first.");
      return;
    }
    setBusy(true);
    try {
      await onOpenWorkspace(workspaceInput.trim());
    } catch (error) {
      onStatusChange(`Failed to open workspace: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function handleProjectSubmit(nextProjectRoot: string | null) {
    setBusy(true);
    try {
      await onConnectProject(nextProjectRoot?.trim() ? nextProjectRoot.trim() : null);
    } catch (error) {
      onStatusChange(`Failed to update project context: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function applyDraft(scope: "document" | "selection" | "insertion" | "new_doc") {
    if (!response || !selectedDocument) {
      return;
    }
    if (response.providerError || !response.draftMarkdown.trim()) {
      onStatusChange("Current draft cannot be applied.");
      return;
    }

    if (scope === "new_doc") {
      const nextDocType = derivedTargetDocType || selectedDocument.meta.docType;
      const nextDraft = canPersist
        ? {
            ...(await invokeCommand<NarrativeDocumentPayload>("create_narrative_document", {
              workspaceRoot: workspace.workspaceRoot,
              input: { docType: nextDocType, title: defaultNarrativeTitle(nextDocType) },
            })),
            savedSnapshot: "",
            dirty: true,
            isDraft: true,
          }
        : createFallbackDraft(nextDocType, `${nextDocType}-${Date.now()}`);
      nextDraft.markdown = response.draftMarkdown;
      nextDraft.meta.docType = nextDocType;
      setDocuments((current) => [nextDraft, ...current]);
      setSelectedKey(nextDraft.documentKey);
      setResponse(null);
      setLastRequest(null);
      onStatusChange("Applied AI draft as a new narrative document. Remember to save.");
      return;
    }

    updateSelectedDocument((document) => {
      let nextMarkdown = document.markdown;
      if (scope === "document") {
        nextMarkdown = response.draftMarkdown;
      } else if ((scope === "selection" || scope === "insertion") && lastRequest?.selectedRange) {
        nextMarkdown = applySelectionRange(
          document.markdown,
          lastRequest.selectedRange,
          response.draftMarkdown,
          scope === "selection" ? "replace" : "insert_after",
        );
      }
      return {
        ...document,
        markdown: nextMarkdown,
      };
    });
    setResponse(null);
    setLastRequest(null);
    onStatusChange("Applied AI draft to the editor. Remember to save.");
  }

  const actions = [
    ...GENERATOR_BUTTONS.map((item) => ({
      id: `create-${item.docType}`,
      label: item.label,
      onClick: () => {
        void createDraft(item.docType);
      },
      disabled: busy || !hasActiveWorkspace,
    })),
    {
      id: "save",
      label: "Save all",
      onClick: () => {
        void saveAll();
      },
      disabled: busy || dirtyCount === 0 || !hasActiveWorkspace,
    },
    {
      id: "reload",
      label: "Reload",
      onClick: () => {
        void onReload();
      },
      disabled: busy || !hasActiveWorkspace,
    },
    {
      id: "delete",
      label: "Delete current",
      onClick: () => {
        void deleteCurrent();
      },
      tone: "danger" as const,
      disabled: busy || !selectedDocument,
    },
  ];

  return (
    <div className="workspace">
      <Toolbar actions={actions} />

      <div className="workspace-grid narrative-grid">
        <aside className="column">
          <PanelSection
            label="Narrative Index"
            title={workspace.workspaceName ? `Narrative Lab · ${workspace.workspaceName}` : "Narrative Lab"}
          >
            <TextField
              label="Search"
              value={searchText}
              onChange={setSearchText}
              placeholder="Filter by slug, title, or type"
            />
            <SelectField
              label="Doc type"
              value={filterDocType}
              onChange={setFilterDocType}
              options={workspace.docTypes}
              hint={hasActiveWorkspace ? undefined : "Open a workspace to browse narrative documents."}
            />
            <div className="item-list">
              {!hasActiveWorkspace ? (
                <div className="empty-state">
                  <Badge tone="muted">Workspace</Badge>
                  <p>Open or create a narrative workspace to start collecting markdown docs.</p>
                </div>
              ) : null}
              {hasActiveWorkspace && filteredDocuments.length === 0 ? (
                <div className="empty-state">
                  <Badge tone="muted">Empty</Badge>
                  <p>Create your first narrative draft from the toolbar.</p>
                </div>
              ) : null}
              {filteredDocuments.map((document) => (
                <button
                  key={document.documentKey}
                  type="button"
                  className={`item-row ${document.documentKey === selectedKey ? "item-row-active" : ""}`}
                  onClick={() => setSelectedKey(document.documentKey)}
                >
                  <div className="item-row-top">
                    <strong>{document.meta.title}</strong>
                    {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                  </div>
                  <p>{document.meta.slug}</p>
                  <div className="row-badges">
                    <Badge tone="muted">{docTypeLabel(document.meta.docType)}</Badge>
                    <Badge tone="muted">{document.meta.status || "draft"}</Badge>
                    <label className="narrative-pick">
                      <input
                        type="checkbox"
                        checked={bundleSelection.includes(document.meta.slug)}
                        onChange={(event) => {
                          event.stopPropagation();
                          setBundleSelection((current) =>
                            event.target.checked
                              ? [...current, document.meta.slug]
                              : current.filter((slug) => slug !== document.meta.slug),
                          );
                        }}
                        onClick={(event) => event.stopPropagation()}
                      />
                      Bundle
                    </label>
                  </div>
                </button>
              ))}
            </div>
          </PanelSection>
        </aside>

        <main className="column column-main">
          {selectedDocument ? (
            <>
              <PanelSection label="Document" title={selectedDocument.meta.title}>
                <div className="stats-grid narrative-stats-grid">
                  <article className="stat-card">
                    <span>Type</span>
                    <strong>{docTypeLabel(selectedDocument.meta.docType)}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Slug</span>
                    <strong>{selectedDocument.meta.slug}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Status</span>
                    <strong>{selectedDocument.meta.status || "draft"}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Selection</span>
                    <strong>{selectionText ? `${selectionText.length} chars` : "none"}</strong>
                  </article>
                </div>

                <div className="narrative-editor-grid">
                  <label className="field">
                    <span className="field-label">Markdown editor</span>
                    <textarea
                      ref={editorRef}
                      className="field-input field-textarea field-code narrative-editor"
                      value={selectedDocument.markdown}
                      onChange={(event) =>
                        updateSelectedDocument((document) => ({
                          ...document,
                          markdown: event.target.value,
                        }))
                      }
                      onSelect={updateSelectionFromEditor}
                      onKeyUp={updateSelectionFromEditor}
                      onMouseUp={updateSelectionFromEditor}
                    />
                  </label>

                  <div className="field">
                    <span className="field-label">Preview</span>
                    <pre className="readonly-box narrative-preview">
                      {selectedDocument.markdown || "(empty document)"}
                    </pre>
                  </div>
                </div>
              </PanelSection>

              <PanelSection label="Metadata" title="Document metadata">
                <div className="form-grid">
                  <SelectField
                    label="Doc type"
                    value={selectedDocument.meta.docType}
                    onChange={(value) =>
                      updateSelectedDocument((document) => ({
                        ...document,
                        meta: { ...document.meta, docType: value as NarrativeDocType },
                      }))
                    }
                    allowBlank={false}
                    options={workspace.docTypes}
                  />
                  <TextField
                    label="Slug"
                    value={selectedDocument.meta.slug}
                    onChange={(value) =>
                      updateSelectedDocument((document) => ({
                        ...document,
                        meta: { ...document.meta, slug: value.trim() },
                      }))
                    }
                  />
                  <TextField
                    label="Title"
                    value={selectedDocument.meta.title}
                    onChange={(value) =>
                      updateSelectedDocument((document) => ({
                        ...document,
                        meta: { ...document.meta, title: value },
                      }))
                    }
                  />
                  <TextField
                    label="Status"
                    value={selectedDocument.meta.status}
                    onChange={(value) =>
                      updateSelectedDocument((document) => ({
                        ...document,
                        meta: { ...document.meta, status: value },
                      }))
                    }
                  />
                </div>
                <TokenListField
                  label="Tags"
                  values={selectedDocument.meta.tags}
                  onChange={(values) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, tags: values },
                    }))
                  }
                />
                <TokenListField
                  label="Related docs"
                  values={selectedDocument.meta.relatedDocs}
                  onChange={(values) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, relatedDocs: values },
                    }))
                  }
                />
                <TokenListField
                  label="Source refs"
                  values={selectedDocument.meta.sourceRefs}
                  onChange={(values) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, sourceRefs: values },
                    }))
                  }
                />
              </PanelSection>
            </>
          ) : (
            <PanelSection
              label="Selection"
              title={hasActiveWorkspace ? "No narrative document selected" : "No workspace selected"}
            >
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>
                  {hasActiveWorkspace
                    ? "Create a narrative draft from the toolbar to start authoring."
                    : "Enter a workspace path on the right, then open it to begin authoring."}
                </p>
              </div>
            </PanelSection>
          )}
        </main>

        <aside className="column">
          <PanelSection label="Workspace" title="Workspace / Project Context">
            <TextField
              label="Workspace path"
              value={workspaceInput}
              onChange={setWorkspaceInput}
              placeholder="D:/Writing/MyNarrativeLab"
            />
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void handleWorkspaceSubmit();
                }}
                disabled={busy || !canPersist || !workspaceInput.trim()}
              >
                打开/创建工作区
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  setWorkspaceInput(appSettings.lastWorkspace ?? "");
                }}
                disabled={busy || !appSettings.lastWorkspace}
              >
                恢复上次路径
              </button>
            </div>
            <TextField
              label="Connected project root"
              value={projectInput}
              onChange={setProjectInput}
              placeholder="Optional game project root"
            />
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void handleProjectSubmit(projectInput);
                }}
                disabled={busy || !canPersist}
              >
                连接项目
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  setProjectInput("");
                  void handleProjectSubmit(null);
                }}
                disabled={busy || !canPersist || !workspace.connectedProjectRoot}
              >
                断开项目
              </button>
            </div>
            <div className="toolbar-summary">
              <Badge tone={hasActiveWorkspace ? "accent" : "muted"}>
                workspace: {workspace.workspaceName || "none"}
              </Badge>
              <Badge tone={workspace.connectedProjectRoot ? "success" : "muted"}>
                project: {workspace.connectedProjectRoot ? "connected" : "none"}
              </Badge>
            </div>
            <label className="field">
              <span className="field-label">Context status</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={workspace.projectContextStatus}
              />
            </label>
            <label className="field">
              <span className="field-label">Recent workspaces</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={appSettings.recentWorkspaces.join("\n")}
              />
            </label>
            <div className="toolbar-actions">
              {appSettings.recentWorkspaces.slice(0, 3).map((path) => (
                <button
                  key={path}
                  type="button"
                  className="toolbar-button"
                  onClick={() => {
                    setWorkspaceInput(path);
                    void onOpenWorkspace(path).catch((error) => {
                      onStatusChange(`Failed to open workspace: ${String(error)}`);
                    });
                  }}
                  disabled={busy || !canPersist}
                >
                  {path.split("/")[path.split("/").length - 1] || path}
                </button>
              ))}
            </div>
            <label className="field">
              <span className="field-label">Recent project roots</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={appSettings.recentProjectRoots.join("\n")}
              />
            </label>
            <div className="toolbar-actions">
              {appSettings.recentProjectRoots.slice(0, 3).map((path) => (
                <button
                  key={path}
                  type="button"
                  className="toolbar-button"
                  onClick={() => {
                    setProjectInput(path);
                    void onConnectProject(path).catch((error) => {
                      onStatusChange(`Failed to update project context: ${String(error)}`);
                    });
                  }}
                  disabled={busy || !canPersist}
                >
                  {path.split("/")[path.split("/").length - 1] || path}
                </button>
              ))}
            </div>
          </PanelSection>

          <PanelSection label="Sync" title="Cloud sync / mobile handoff">
            <TextField
              label="Server URL"
              value={syncSettings?.serverUrl ?? ""}
              onChange={(value) =>
                setSyncSettings((current) => ({
                  ...(current ?? {
                    serverUrl: "",
                    authToken: "",
                    workspaceId: "",
                    deviceLabel: "desktop-local",
                    lastSyncAt: null,
                    lastSyncStatus: "",
                  }),
                  serverUrl: value,
                }))
              }
              placeholder="http://127.0.0.1:4852"
            />
            <TextField
              label="Auth token"
              value={syncSettings?.authToken ?? ""}
              onChange={(value) =>
                setSyncSettings((current) => ({
                  ...(current ?? {
                    serverUrl: "",
                    authToken: "",
                    workspaceId: "",
                    deviceLabel: "desktop-local",
                    lastSyncAt: null,
                    lastSyncStatus: "",
                  }),
                  authToken: value,
                }))
              }
            />
            <TextField
              label="Cloud workspace ID"
              value={syncSettings?.workspaceId ?? ""}
              onChange={(value) =>
                setSyncSettings((current) => ({
                  ...(current ?? {
                    serverUrl: "",
                    authToken: "",
                    workspaceId: "",
                    deviceLabel: "desktop-local",
                    lastSyncAt: null,
                    lastSyncStatus: "",
                  }),
                  workspaceId: value,
                }))
              }
              placeholder="workspace-123"
            />
            <TextField
              label="Device label"
              value={syncSettings?.deviceLabel ?? "desktop-local"}
              onChange={(value) =>
                setSyncSettings((current) => ({
                  ...(current ?? {
                    serverUrl: "",
                    authToken: "",
                    workspaceId: "",
                    deviceLabel: "desktop-local",
                    lastSyncAt: null,
                    lastSyncStatus: "",
                  }),
                  deviceLabel: value,
                }))
              }
            />
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void refreshCloudWorkspaces();
                }}
                disabled={syncBusy || !canPersist}
              >
                刷新云工作区
              </button>
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void saveSyncSettings();
                }}
                disabled={syncBusy || !canPersist}
              >
                保存同步设置
              </button>
            </div>
            <TextField
              label="Create cloud workspace"
              value={cloudWorkspaceName}
              onChange={setCloudWorkspaceName}
              placeholder="My Narrative Cloud"
            />
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void createCloudWorkspace();
                }}
                disabled={syncBusy || !cloudWorkspaceName.trim()}
              >
                创建云工作区
              </button>
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void syncWorkspaceNow();
                }}
                disabled={syncBusy || !hasActiveWorkspace || !canPersist}
              >
                Sync now
              </button>
            </div>
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void exportProjectSnapshot();
                }}
                disabled={syncBusy || !hasActiveWorkspace || !canPersist}
              >
                导出项目快照
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void uploadProjectSnapshot();
                }}
                disabled={syncBusy || !hasActiveWorkspace || !canPersist}
              >
                上传项目快照
              </button>
            </div>
            <div className="toolbar-summary">
              <Badge tone="accent">executor: desktop_local</Badge>
              <Badge tone={syncResult?.conflictCount ? "warning" : "muted"}>
                conflicts: {syncResult?.conflictCount ?? 0}
              </Badge>
            </div>
            <label className="field">
              <span className="field-label">Sync status</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={
                  syncStatus ||
                  syncSettings?.lastSyncStatus ||
                  "Cloud sync keeps shared copies in sync while desktop editing remains local-first."
                }
              />
            </label>
            <label className="field">
              <span className="field-label">Known cloud workspaces</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={cloudWorkspaces.map((entry) => `${entry.name} (${entry.workspaceId})`).join("\n")}
              />
            </label>
            <label className="field">
              <span className="field-label">Pending operations</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={
                  syncResult
                    ? syncResult.pendingOperations
                        .map((operation) => `${operation.kind} ${operation.slug} @${operation.baseRevision}`)
                        .join("\n")
                    : ""
                }
              />
            </label>
            <label className="field">
              <span className="field-label">Snapshot summary</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={
                  snapshotUpload?.snapshot.summary ??
                  snapshotExport?.snapshot.summary ??
                  syncResult?.projectSnapshot?.summary ??
                  ""
                }
              />
            </label>
            <label className="field">
              <span className="field-label">Snapshot export path</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={snapshotUpload?.exportPath ?? snapshotExport?.exportPath ?? ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Conflict notes</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={
                  syncResult?.conflicts
                    .map((conflict) => `${conflict.slug} -> ${conflict.conflictDocSlug}: ${conflict.message}`)
                    .join("\n") ?? ""
                }
              />
            </label>
          </PanelSection>

          <PanelSection label="AI" title="Narrative operations">
            <div className="narrative-action-grid">
              {ACTION_OPTIONS.map((option) => {
                const disabled =
                  busy ||
                  !selectedDocument ||
                  !hasActiveWorkspace ||
                  ((option.value === "rewrite_selection" ||
                    option.value === "expand_selection" ||
                    option.value === "insert_after_selection") &&
                    !hasSelection);
                return (
                  <button
                    key={option.value}
                    type="button"
                    className={`toolbar-button ${aiAction === option.value ? "toolbar-accent" : ""}`}
                    disabled={disabled}
                    onClick={() => setAiAction(option.value)}
                  >
                    {option.label}
                  </button>
                );
              })}
            </div>
            <TextareaField
              label="主提示词"
              value={userPrompt}
              onChange={setUserPrompt}
              placeholder="描述这次想生成什么内容。"
            />
            <TextareaField
              label="修改意见 / 编辑指令"
              value={editorInstruction}
              onChange={setEditorInstruction}
              placeholder="说明你希望 AI 如何调整当前文稿或选区。"
            />
            {aiAction === "derive_new_doc" ? (
              <SelectField
                label="派生目标类型"
                value={derivedTargetDocType}
                onChange={(value) => setDerivedTargetDocType(value as NarrativeDocType)}
                allowBlank={false}
                options={workspace.docTypes}
              />
            ) : null}
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void runGeneration();
                }}
                disabled={busy || !selectedDocument || !hasActiveWorkspace}
              >
                生成草稿
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  setResponse(null);
                  setLastRequest(null);
                }}
                disabled={busy}
              >
                丢弃草稿
              </button>
            </div>
          </PanelSection>

          <PanelSection label="AI" title="Selection context">
            <div className="toolbar-summary">
              <Badge tone={hasSelection ? "accent" : "muted"}>
                range: {selectionRange ? `${selectionRange.start}-${selectionRange.end}` : "none"}
              </Badge>
              <Badge tone={selectedDocument ? "muted" : "danger"}>
                target: {selectedDocument?.meta.slug ?? "none"}
              </Badge>
            </div>
            <label className="field">
              <span className="field-label">Selected text</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={selectionText}
              />
            </label>
          </PanelSection>

          <PanelSection label="Review" title="AI draft review">
            <div className="toolbar-summary">
              <Badge tone="accent">engine: {response?.engineMode ?? "n/a"}</Badge>
              <Badge tone="muted">
                agents: {response?.agentRuns.length ?? 0}
              </Badge>
            </div>
            <label className="field">
              <span className="field-label">Summary</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={response?.summary ?? response?.providerError ?? ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Diff preview</span>
              <textarea
                className="field-input field-textarea field-code ai-readonly"
                readOnly
                value={narrativeDiffSummary(
                  selectedDocument?.markdown ?? "",
                  response,
                  selectionText,
                )}
              />
            </label>
            <label className="field">
              <span className="field-label">Draft markdown</span>
              <textarea
                className="field-input field-textarea field-code ai-readonly"
                readOnly
                value={response?.draftMarkdown ?? ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Review notes</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={response ? response.reviewNotes.join("\n") : ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Synthesis notes</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={response ? response.synthesisNotes.join("\n") : ""}
              />
            </label>
            <div className="agent-run-list">
              {(response?.agentRuns ?? []).map((agentRun) => (
                <article key={agentRun.agentId} className="agent-run-card">
                  <div className="agent-run-header">
                    <strong>{agentRun.label}</strong>
                    <div className="row-badges">
                      <Badge tone={agentRun.status === "completed" ? "success" : "danger"}>
                        {agentRun.status}
                      </Badge>
                      <Badge tone={agentRun.riskLevel === "high" ? "danger" : "muted"}>
                        {agentRun.riskLevel}
                      </Badge>
                    </div>
                  </div>
                  <p className="agent-run-focus">{agentRun.focus}</p>
                  <label className="field">
                    <span className="field-label">Agent summary</span>
                    <textarea
                      className="field-input field-textarea ai-readonly"
                      readOnly
                      value={agentRun.summary}
                    />
                  </label>
                  <label className="field">
                    <span className="field-label">Agent notes</span>
                    <textarea
                      className="field-input field-textarea ai-readonly"
                      readOnly
                      value={agentRun.notes.join("\n")}
                    />
                  </label>
                  <label className="field">
                    <span className="field-label">Agent draft</span>
                    <textarea
                      className="field-input field-textarea field-code ai-readonly"
                      readOnly
                      value={agentRun.draftMarkdown || agentRun.providerError}
                    />
                  </label>
                </article>
              ))}
            </div>
            <div className="toolbar-summary">
              <Badge tone={response?.riskLevel === "high" ? "danger" : "muted"}>
                risk: {response?.riskLevel ?? "n/a"}
              </Badge>
              <Badge tone="muted">scope: {response?.changeScope ?? "n/a"}</Badge>
            </div>
            <div className="toolbar-actions">
              {response?.changeScope === "document" ? (
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void applyDraft("document");
                  }}
                >
                  替换整篇
                </button>
              ) : null}
              {response?.changeScope === "selection" ? (
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void applyDraft("selection");
                  }}
                >
                  替换选区
                </button>
              ) : null}
              {response?.changeScope === "insertion" ? (
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void applyDraft("insertion");
                  }}
                >
                  插入到选区后
                </button>
              ) : null}
              {response?.changeScope === "new_doc" ? (
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void applyDraft("new_doc");
                  }}
                >
                  另存为新文稿
                </button>
              ) : null}
            </div>
          </PanelSection>

          <PanelSection label="AI" title="Provider settings">
            <TextField
              label="Base URL"
              value={settings?.baseUrl ?? ""}
              onChange={(value) =>
                setSettings((current) => ({
                  ...(current ?? {
                    baseUrl: "",
                    model: "",
                    apiKey: "",
                    timeoutSec: 45,
                    maxContextRecords: 24,
                  }),
                  baseUrl: value,
                }))
              }
            />
            <TextField
              label="Model"
              value={settings?.model ?? ""}
              onChange={(value) =>
                setSettings((current) => ({
                  ...(current ?? {
                    baseUrl: "",
                    model: "",
                    apiKey: "",
                    timeoutSec: 45,
                    maxContextRecords: 24,
                  }),
                  model: value,
                }))
              }
            />
            <TextField
              label="API Key"
              value={settings?.apiKey ?? ""}
              onChange={(value) =>
                setSettings((current) => ({
                  ...(current ?? {
                    baseUrl: "",
                    model: "",
                    apiKey: "",
                    timeoutSec: 45,
                    maxContextRecords: 24,
                  }),
                  apiKey: value,
                }))
              }
            />
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void testSettings();
                }}
                disabled={settingsBusy}
              >
                Test connection
              </button>
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void saveSettings();
                }}
                disabled={settingsBusy}
              >
                Save settings
              </button>
            </div>
            {settingsStatus ? <p className="field-hint">{settingsStatus}</p> : null}
          </PanelSection>

          <PanelSection label="Stage 2" title="Structuring bundle">
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void prepareBundle();
                }}
                disabled={(!selectedDocument && bundleSelection.length === 0) || !hasActiveWorkspace}
              >
                Prepare structuring bundle
              </button>
            </div>
            <label className="field">
              <span className="field-label">Bundle summary</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={bundleResult?.summary ?? ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Export path</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={bundleResult?.exportPath ?? ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Generated at</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={bundleResult?.generatedAt ?? ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Suggested targets</span>
              <textarea
                className="field-input field-textarea ai-readonly"
                readOnly
                value={bundleResult ? bundleResult.suggestedTargets.join("\n") : ""}
              />
            </label>
            <label className="field">
              <span className="field-label">Combined markdown</span>
              <textarea
                className="field-input field-textarea field-code ai-readonly"
                readOnly
                value={bundleResult?.combinedMarkdown ?? ""}
              />
            </label>
          </PanelSection>

          <PanelSection label="Debug" title="Prompt debug" compact>
            <textarea
              className="field-input field-textarea field-code ai-readonly"
              readOnly
              value={JSON.stringify(response?.promptDebug ?? {}, null, 2)}
            />
          </PanelSection>
        </aside>
      </div>
    </div>
  );
}
