import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Responsive, WidthProvider, type Layout, type Layouts } from "react-grid-layout";
import { Badge } from "../../components/Badge";
import { SelectField, TextareaField, TextField, TokenListField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { invokeCommand } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  AiConnectionTestResult,
  AiSettings,
  CloudWorkspaceMeta,
  NarrativeAction,
  NarrativeAppSettings,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativePanelId,
  NarrativePanelLayoutItem,
  NarrativeSelectionRange,
  NarrativeSyncSettings,
  NarrativeWorkspaceLayout,
  NarrativeWorkspacePayload,
  NarrativeWorkspaceSyncResult,
  ProjectContextSnapshotExportResult,
  ProjectContextSnapshotUploadResult,
  SaveNarrativeDocumentResult,
  StructuringBundlePayload,
} from "../../types";
import { applySelectionRange, narrativeDiffSummary, toUtf8SelectionRange } from "./narrativeEditing";
import {
  buildStackedLayout,
  defaultNarrativeLayout,
  NARRATIVE_CORE_PANELS,
  normalizeNarrativeLayout,
  sortLayoutItems,
  togglePanelValue,
} from "./workbench";
import {
  defaultNarrativeMarkdown,
  defaultNarrativeTitle,
  docTypeDirectory,
  docTypeLabel,
  fallbackNarrativeMeta,
} from "./narrativeTemplates";

const ResponsiveGridLayout = WidthProvider(Responsive);

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
  onSaveAppSettings: (settings: NarrativeAppSettings) => Promise<NarrativeAppSettings>;
};

type ReviewMode = "diff" | "draft" | "original";
type NarrativeBreakpoint = "lg" | "md";

const ACTION_OPTIONS: Array<{ value: NarrativeAction; label: string }> = [
  { value: "create", label: "创建文稿" },
  { value: "revise_document", label: "整篇改写" },
  { value: "rewrite_selection", label: "改写选中内容" },
  { value: "expand_selection", label: "扩写选中内容" },
  { value: "insert_after_selection", label: "在选中段后补写" },
  { value: "derive_new_doc", label: "派生为新文稿" },
];

const ADVANCED_PANELS: NarrativePanelId[] = [
  "workspace_context",
  "sync_tools",
  "provider_settings",
  "structuring_bundle",
  "prompt_debug",
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

function toGridLayout(items: NarrativePanelLayoutItem[]): Layout[] {
  return sortLayoutItems(items).map((item) => ({
    i: item.panelId,
    x: item.x,
    y: item.y,
    w: item.w,
    h: item.h,
    minW: item.minW,
    minH: item.minH,
  }));
}

function mergeGridLayout(
  currentLayout: NarrativeWorkspaceLayout,
  nextGridLayout: Layout[],
): NarrativeWorkspaceLayout {
  const byId = new Map(nextGridLayout.map((item) => [item.i, item]));
  return {
    ...currentLayout,
    items: currentLayout.items.map((item) => {
      const grid = byId.get(item.panelId);
      if (!grid) {
        return item;
      }
      return { ...item, x: grid.x, y: grid.y, w: grid.w, h: grid.h };
    }),
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
  onSaveAppSettings,
}: NarrativeWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableNarrativeDocument[]>(hydrateDocuments(workspace.documents));
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [filterDocType, setFilterDocType] = useState("");
  const [busy, setBusy] = useState(false);
  const [aiAction, setAiAction] = useState<NarrativeAction>("create");
  const [userPrompt, setUserPrompt] = useState("");
  const [editorInstruction, setEditorInstruction] = useState("");
  const [derivedTargetDocType, setDerivedTargetDocType] = useState<NarrativeDocType>("branch_sheet");
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
  const [projectInput, setProjectInput] = useState(workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "");
  const [reviewMode, setReviewMode] = useState<ReviewMode>("diff");
  const [currentBreakpoint, setCurrentBreakpoint] = useState<NarrativeBreakpoint>("lg");
  const [selectionExpanded, setSelectionExpanded] = useState(false);
  const [reviewDetailsExpanded, setReviewDetailsExpanded] = useState(false);
  const [agentDetailsExpanded, setAgentDetailsExpanded] = useState(false);
  const [layoutState, setLayoutState] = useState<NarrativeWorkspaceLayout>(() => normalizeNarrativeLayout(defaultNarrativeLayout()));
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const deferredSearch = useDeferredValue(searchText);
  const latestAppSettingsRef = useRef(appSettings);
  const layoutSaveTimerRef = useRef<number | null>(null);

  useEffect(() => {
    latestAppSettingsRef.current = appSettings;
  }, [appSettings]);

  useEffect(() => {
    return () => {
      if (layoutSaveTimerRef.current !== null) {
        window.clearTimeout(layoutSaveTimerRef.current);
      }
    };
  }, []);

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
    setReviewMode("diff");
  }, [selectedKey]);

  useEffect(() => {
    setWorkspaceInput(workspace.workspaceRoot || appSettings.lastWorkspace || "");
  }, [appSettings.lastWorkspace, workspace.workspaceRoot]);

  useEffect(() => {
    setProjectInput(workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "");
  }, [appSettings.connectedProjectRoot, workspace.connectedProjectRoot]);

  useEffect(() => {
    const nextLayout = workspace.workspaceRoot
      ? normalizeNarrativeLayout(appSettings.workspaceLayouts?.[workspace.workspaceRoot])
      : normalizeNarrativeLayout(defaultNarrativeLayout());
    setLayoutState(nextLayout);
  }, [appSettings.workspaceLayouts, workspace.workspaceRoot]);

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

  const selectedDocument = documents.find((document) => document.documentKey === selectedKey) ?? null;
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const hasSelection = Boolean(selectionText.trim()) && Boolean(selectionRange);
  const hasActiveWorkspace = Boolean(workspace.workspaceRoot.trim());
  const hiddenPanels = layoutState.hiddenPanels;
  const collapsedPanels = layoutState.collapsedPanels;
  const visibleLayoutItems = useMemo(
    () => layoutState.items.filter((item) => !hiddenPanels.includes(item.panelId)),
    [hiddenPanels, layoutState.items],
  );
  const wideGridLayout = useMemo(() => toGridLayout(visibleLayoutItems), [visibleLayoutItems]);
  const compactGridLayout = useMemo(
    () => toGridLayout(buildStackedLayout(layoutState.items, hiddenPanels)),
    [hiddenPanels, layoutState.items],
  );
  const gridLayouts = useMemo<Layouts>(
    () => ({
      lg: wideGridLayout,
      md: compactGridLayout,
    }),
    [compactGridLayout, wideGridLayout],
  );
  const compactLayout = currentBreakpoint !== "lg";

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
      const remaining = documents.filter((document) => document.documentKey !== selectedDocument.documentKey);
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
    setSelectionRange(toUtf8SelectionRange(document.markdown, editor.selectionStart, editor.selectionEnd));
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
      setCloudWorkspaces((current) => [
        created,
        ...current.filter((entry) => entry.workspaceId !== created.workspaceId),
      ]);
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
      const command = aiAction === "create" ? "generate_narrative_draft" : "revise_narrative_draft";
      const next = await invokeCommand<NarrativeGenerateResponse>(command, {
        workspaceRoot: workspace.workspaceRoot,
        projectRoot: workspace.connectedProjectRoot ?? null,
        request,
      });
      setResponse(next);
      setLastRequest(request);
      setReviewMode("diff");
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
      return { ...document, markdown: nextMarkdown };
    });
    setResponse(null);
    setLastRequest(null);
    onStatusChange("Applied AI draft to the editor. Remember to save.");
  }

  function queueLayoutSave(nextLayout: NarrativeWorkspaceLayout, immediate = false) {
    if (!canPersist || !workspace.workspaceRoot) {
      return;
    }
    if (layoutSaveTimerRef.current !== null) {
      window.clearTimeout(layoutSaveTimerRef.current);
      layoutSaveTimerRef.current = null;
    }

    const persist = () => {
      const currentSettings = latestAppSettingsRef.current;
      void onSaveAppSettings({
        ...currentSettings,
        workspaceLayouts: {
          ...(currentSettings.workspaceLayouts ?? {}),
          [workspace.workspaceRoot]: nextLayout,
        },
      }).catch((error) => {
        onStatusChange(`Failed to save layout: ${String(error)}`);
      });
    };

    if (immediate) {
      persist();
      return;
    }

    layoutSaveTimerRef.current = window.setTimeout(() => {
      layoutSaveTimerRef.current = null;
      persist();
    }, 220);
  }

  function applyLayout(nextLayout: NarrativeWorkspaceLayout, immediate = false) {
    setLayoutState(nextLayout);
    queueLayoutSave(nextLayout, immediate);
  }

  function updateLayoutFromGrid(nextGridLayout: Layout[]) {
    if (compactLayout) {
      return;
    }
    applyLayout(mergeGridLayout(layoutState, nextGridLayout));
  }

  function togglePanelCollapsed(panelId: NarrativePanelId) {
    applyLayout(
      {
        ...layoutState,
        collapsedPanels: togglePanelValue(
          layoutState.collapsedPanels,
          panelId,
          !layoutState.collapsedPanels.includes(panelId),
        ),
      },
      true,
    );
  }

  function setPanelHidden(panelId: NarrativePanelId, hidden: boolean) {
    if (NARRATIVE_CORE_PANELS.has(panelId)) {
      return;
    }
    applyLayout(
      {
        ...layoutState,
        hiddenPanels: togglePanelValue(layoutState.hiddenPanels, panelId, hidden),
      },
      true,
    );
  }

  function revealPanel(panelId: NarrativePanelId) {
    applyLayout(
      {
        ...layoutState,
        hiddenPanels: togglePanelValue(layoutState.hiddenPanels, panelId, false),
        collapsedPanels: togglePanelValue(layoutState.collapsedPanels, panelId, false),
      },
      true,
    );
  }

  function resetLayoutPositions() {
    applyLayout(
      normalizeNarrativeLayout({
        ...layoutState,
        items: defaultNarrativeLayout().items,
      }),
      true,
    );
  }

  function restoreDefaultLayout() {
    applyLayout(normalizeNarrativeLayout(defaultNarrativeLayout()), true);
  }

  function expandAllPanels() {
    applyLayout({ ...layoutState, collapsedPanels: [] }, true);
  }

  function collapseAdvancedPanels() {
    applyLayout(
      {
        ...layoutState,
        collapsedPanels: ADVANCED_PANELS.filter((panelId) => !hiddenPanels.includes(panelId)),
      },
      true,
    );
  }

  useRegisterEditorMenuCommands({
    [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
      execute: async () => {
        await createDraft("scene_draft");
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
      execute: async () => {
        await saveAll();
      },
      isEnabled: () => !busy && dirtyCount > 0 && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
      execute: async () => {
        await onReload();
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
      execute: async () => {
        await deleteCurrent();
      },
      isEnabled: () => !busy && Boolean(selectedDocument),
    },
    [EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT]: {
      execute: () => {
        resetLayoutPositions();
      },
    },
    [EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT]: {
      execute: () => {
        restoreDefaultLayout();
      },
    },
    [EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS]: {
      execute: () => {
        collapseAdvancedPanels();
      },
    },
    [EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS]: {
      execute: () => {
        expandAllPanels();
      },
    },
    [EDITOR_MENU_COMMANDS.AI_GENERATE]: {
      execute: async () => {
        await runGeneration();
      },
      isEnabled: () => !busy && Boolean(selectedDocument) && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: {
      execute: async () => {
        revealPanel("provider_settings");
        await testSettings();
      },
      isEnabled: () => !settingsBusy && Boolean(settings),
    },
    [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: {
      execute: () => {
        revealPanel("provider_settings");
        onStatusChange("Opened AI provider settings.");
      },
    },
    [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF]: {
      execute: async () => {
        await createDraft("project_brief");
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD]: {
      execute: async () => {
        await createDraft("character_card");
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHAPTER_OUTLINE]: {
      execute: async () => {
        await createDraft("chapter_outline");
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_BRANCH_SHEET]: {
      execute: async () => {
        await createDraft("branch_sheet");
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
    [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_SCENE_DRAFT]: {
      execute: async () => {
        await createDraft("scene_draft");
      },
      isEnabled: () => !busy && hasActiveWorkspace,
    },
  });

  const actions = [
    {
      id: "ai-generate",
      label: "AI Generate",
      onClick: () => {
        void runGeneration();
      },
      disabled: busy || !selectedDocument || !hasActiveWorkspace,
    },
    {
      id: "save",
      label: "Save all",
      onClick: () => {
        void saveAll();
      },
      tone: "accent" as const,
      disabled: busy || dirtyCount === 0 || !hasActiveWorkspace,
    },
  ];

  const reviewBodyValue =
    reviewMode === "draft"
      ? response?.draftMarkdown ?? ""
      : reviewMode === "original"
        ? selectedDocument?.markdown ?? ""
        : narrativeDiffSummary(selectedDocument?.markdown ?? "", response, selectionText);

  const workbenchPanels = new Map<
    NarrativePanelId,
    {
      label: string;
      title: string;
      canHide: boolean;
      summary?: React.ReactNode;
      compact?: boolean;
      content: React.ReactNode;
    }
  >();

  workbenchPanels.set("document_overview", {
    label: "Document",
    title: selectedDocument?.meta.title ?? "Current narrative document",
    canHide: false,
    summary: (
      <div className="toolbar-summary">
        <Badge tone={selectedDocument?.dirty ? "warning" : "muted"}>
          {selectedDocument?.dirty ? "Unsaved" : "Saved"}
        </Badge>
        <Badge tone="muted">{selectedDocument ? docTypeLabel(selectedDocument.meta.docType) : "Idle"}</Badge>
      </div>
    ),
    content: selectedDocument ? (
      <>
        <div className="stats-grid narrative-stats-grid narrative-stats-grid-compact">
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
        <div className="toolbar-summary">
          <Badge tone={selectedDocument.validation.length ? "warning" : "success"}>
            validation: {selectedDocument.validation.length}
          </Badge>
          <Badge tone="muted">tags: {selectedDocument.meta.tags.length}</Badge>
          <Badge tone="muted">refs: {selectedDocument.meta.sourceRefs.length}</Badge>
        </div>
        <label className="field">
          <span className="field-label">Path</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={selectedDocument.relativePath}
          />
        </label>
      </>
    ) : (
      <div className="empty-state">
        <Badge tone="muted">Idle</Badge>
        <p>
          {hasActiveWorkspace
            ? "Select a narrative document or create one from the toolbar."
            : "Open or create a workspace to start writing."}
        </p>
      </div>
    ),
  });

  workbenchPanels.set("ai_task", {
    label: "AI",
    title: "Narrative operations",
    canHide: false,
    summary: (
      <div className="toolbar-summary">
        <Badge tone={hasSelection ? "accent" : "muted"}>
          {hasSelection ? "selection ready" : "full document"}
        </Badge>
        <Badge tone={selectedDocument ? "success" : "danger"}>
          {selectedDocument ? selectedDocument.meta.slug : "no target"}
        </Badge>
      </div>
    ),
    content: (
      <>
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
        <div className="toolbar-summary">
          <Badge tone={selectionRange ? "accent" : "muted"}>
            range: {selectionRange ? `${selectionRange.start}-${selectionRange.end}` : "none"}
          </Badge>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => setSelectionExpanded((current) => !current)}
            disabled={!selectionText}
          >
            {selectionExpanded ? "Hide selection" : "Show selection"}
          </button>
        </div>
        {selectionExpanded && selectionText ? (
          <label className="field">
            <span className="field-label">Selected text</span>
            <textarea
              className="field-input field-textarea ai-readonly narrative-readonly-compact"
              readOnly
              value={selectionText}
            />
          </label>
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
      </>
    ),
  });

  workbenchPanels.set("ai_review", {
    label: "Review",
    title: "AI draft review",
    canHide: false,
    summary: (
      <div className="toolbar-summary">
        <Badge tone={response?.riskLevel === "high" ? "danger" : "muted"}>
          risk: {response?.riskLevel ?? "n/a"}
        </Badge>
        <Badge tone="muted">scope: {response?.changeScope ?? "n/a"}</Badge>
        <Badge tone="muted">agents: {response?.agentRuns.length ?? 0}</Badge>
      </div>
    ),
    content: response ? (
      <>
        <label className="field">
          <span className="field-label">Summary</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={response.summary || response.providerError}
          />
        </label>
        <div className="toolbar-actions">
          {([
            ["diff", "Diff"],
            ["draft", "Draft"],
            ["original", "Original"],
          ] as Array<[ReviewMode, string]>).map(([mode, label]) => (
            <button
              key={mode}
              type="button"
              className={`toolbar-button ${reviewMode === mode ? "toolbar-accent" : ""}`}
              onClick={() => setReviewMode(mode)}
            >
              {label}
            </button>
          ))}
        </div>
        <label className="field">
          <span className="field-label">
            {reviewMode === "diff" ? "Diff preview" : reviewMode === "draft" ? "Draft markdown" : "Current markdown"}
          </span>
          <textarea
            className="field-input field-textarea field-code ai-readonly narrative-review-output"
            readOnly
            value={reviewBodyValue}
          />
        </label>
        <div className="toolbar-actions">
          {response.changeScope === "document" ? (
            <button type="button" className="toolbar-button toolbar-accent" onClick={() => void applyDraft("document")}>
              替换整篇
            </button>
          ) : null}
          {response.changeScope === "selection" ? (
            <button type="button" className="toolbar-button toolbar-accent" onClick={() => void applyDraft("selection")}>
              替换选区
            </button>
          ) : null}
          {response.changeScope === "insertion" ? (
            <button type="button" className="toolbar-button toolbar-accent" onClick={() => void applyDraft("insertion")}>
              插入到选区后
            </button>
          ) : null}
          {response.changeScope === "new_doc" ? (
            <button type="button" className="toolbar-button toolbar-accent" onClick={() => void applyDraft("new_doc")}>
              另存为新文稿
            </button>
          ) : null}
        </div>
        <div className="toolbar-actions">
          <button type="button" className="toolbar-button" onClick={() => setReviewDetailsExpanded((current) => !current)}>
            {reviewDetailsExpanded ? "Hide review notes" : "Show review notes"}
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => setAgentDetailsExpanded((current) => !current)}
            disabled={response.agentRuns.length === 0}
          >
            {agentDetailsExpanded ? "Hide agent runs" : "Show agent runs"}
          </button>
        </div>
        {reviewDetailsExpanded ? (
          <div className="field-grid">
            <label className="field">
              <span className="field-label">Review notes</span>
              <textarea
                className="field-input field-textarea ai-readonly narrative-readonly-compact"
                readOnly
                value={response.reviewNotes.join("\n")}
              />
            </label>
            <label className="field">
              <span className="field-label">Synthesis notes</span>
              <textarea
                className="field-input field-textarea ai-readonly narrative-readonly-compact"
                readOnly
                value={response.synthesisNotes.join("\n")}
              />
            </label>
          </div>
        ) : null}
        {agentDetailsExpanded ? (
          <div className="agent-run-list">
            {response.agentRuns.map((agentRun) => (
              <article key={agentRun.agentId} className="agent-run-card">
                <div className="agent-run-header">
                  <strong>{agentRun.label}</strong>
                  <div className="row-badges">
                    <Badge tone={agentRun.status === "completed" ? "success" : "danger"}>{agentRun.status}</Badge>
                    <Badge tone={agentRun.riskLevel === "high" ? "danger" : "muted"}>{agentRun.riskLevel}</Badge>
                  </div>
                </div>
                <p className="agent-run-focus">{agentRun.focus}</p>
                <label className="field">
                  <span className="field-label">Agent summary</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={agentRun.summary}
                  />
                </label>
                <label className="field">
                  <span className="field-label">Agent notes</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={agentRun.notes.join("\n")}
                  />
                </label>
              </article>
            ))}
          </div>
        ) : null}
      </>
    ) : (
      <div className="empty-state">
        <Badge tone="muted">Waiting</Badge>
        <p>Run an AI action to review the generated draft here.</p>
      </div>
    ),
  });

  workbenchPanels.set("manual_editor", {
    label: "Authoring",
    title: selectedDocument ? "Manual editor" : "Editor",
    canHide: true,
    summary: (
      <div className="toolbar-summary">
        <Badge tone={selectedDocument?.dirty ? "warning" : "muted"}>
          {selectedDocument?.dirty ? "dirty" : "clean"}
        </Badge>
        <Badge tone="muted">{selectedDocument?.markdown.length ?? 0} chars</Badge>
      </div>
    ),
    content: selectedDocument ? (
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
          <pre className="readonly-box narrative-preview">{selectedDocument.markdown || "(empty document)"}</pre>
        </div>
      </div>
    ) : (
      <div className="empty-state">
        <Badge tone="muted">No document</Badge>
        <p>Select a narrative document to edit its markdown and preview.</p>
      </div>
    ),
  });

  workbenchPanels.set("metadata", {
    label: "Metadata",
    title: "Document metadata",
    canHide: true,
    summary: (
      <div className="toolbar-summary">
        <Badge tone="muted">tags: {selectedDocument?.meta.tags.length ?? 0}</Badge>
        <Badge tone="muted">related: {selectedDocument?.meta.relatedDocs.length ?? 0}</Badge>
      </div>
    ),
    content: selectedDocument ? (
      <>
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
      </>
    ) : (
      <div className="empty-state">
        <Badge tone="muted">Idle</Badge>
        <p>Choose a narrative document before editing metadata.</p>
      </div>
    ),
  });

  workbenchPanels.set("workspace_context", {
    label: "Workspace",
    title: "Workspace / Project Context",
    canHide: true,
    summary: (
      <div className="toolbar-summary">
        <Badge tone={hasActiveWorkspace ? "accent" : "muted"}>
          workspace: {workspace.workspaceName || "none"}
        </Badge>
        <Badge tone={workspace.connectedProjectRoot ? "success" : "muted"}>
          project: {workspace.connectedProjectRoot ? "connected" : "none"}
        </Badge>
      </div>
    ),
    content: (
      <>
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
            onClick={() => void handleWorkspaceSubmit()}
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
            onClick={() => void handleProjectSubmit(projectInput)}
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
        <label className="field">
          <span className="field-label">Context status</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={workspace.projectContextStatus}
          />
        </label>
        <label className="field">
          <span className="field-label">Recent workspaces</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
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
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
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
      </>
    ),
  });

  workbenchPanels.set("sync_tools", {
    label: "Sync",
    title: "Cloud sync / mobile handoff",
    canHide: true,
    summary: (
      <div className="toolbar-summary">
        <Badge tone="accent">executor: desktop_local</Badge>
        <Badge tone={syncResult?.conflictCount ? "warning" : "muted"}>
          conflicts: {syncResult?.conflictCount ?? 0}
        </Badge>
      </div>
    ),
    content: (
      <>
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
          <button type="button" className="toolbar-button" onClick={() => void refreshCloudWorkspaces()} disabled={syncBusy || !canPersist}>
            刷新云工作区
          </button>
          <button type="button" className="toolbar-button toolbar-accent" onClick={() => void saveSyncSettings()} disabled={syncBusy || !canPersist}>
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
          <button type="button" className="toolbar-button" onClick={() => void createCloudWorkspace()} disabled={syncBusy || !cloudWorkspaceName.trim()}>
            创建云工作区
          </button>
          <button type="button" className="toolbar-button toolbar-accent" onClick={() => void syncWorkspaceNow()} disabled={syncBusy || !hasActiveWorkspace || !canPersist}>
            Sync now
          </button>
        </div>
        <div className="toolbar-actions">
          <button type="button" className="toolbar-button" onClick={() => void exportProjectSnapshot()} disabled={syncBusy || !hasActiveWorkspace || !canPersist}>
            导出项目快照
          </button>
          <button type="button" className="toolbar-button" onClick={() => void uploadProjectSnapshot()} disabled={syncBusy || !hasActiveWorkspace || !canPersist}>
            上传项目快照
          </button>
        </div>
        <label className="field">
          <span className="field-label">Sync status</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
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
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={cloudWorkspaces.map((entry) => `${entry.name} (${entry.workspaceId})`).join("\n")}
          />
        </label>
        <label className="field">
          <span className="field-label">Pending operations</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
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
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
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
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={snapshotUpload?.exportPath ?? snapshotExport?.exportPath ?? ""}
          />
        </label>
        <label className="field">
          <span className="field-label">Conflict notes</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={
              syncResult?.conflicts
                .map((conflict) => `${conflict.slug} -> ${conflict.conflictDocSlug}: ${conflict.message}`)
                .join("\n") ?? ""
            }
          />
        </label>
      </>
    ),
  });

  workbenchPanels.set("provider_settings", {
    label: "AI",
    title: "Provider settings",
    canHide: true,
    summary: settingsStatus ? <Badge tone="accent">{settingsStatus}</Badge> : undefined,
    content: (
      <>
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
          <button type="button" className="toolbar-button" onClick={() => void testSettings()} disabled={settingsBusy}>
            Test connection
          </button>
          <button type="button" className="toolbar-button toolbar-accent" onClick={() => void saveSettings()} disabled={settingsBusy}>
            Save settings
          </button>
        </div>
        {settingsStatus ? <p className="field-hint">{settingsStatus}</p> : null}
      </>
    ),
  });

  workbenchPanels.set("structuring_bundle", {
    label: "Stage 2",
    title: "Structuring bundle",
    canHide: true,
    summary: (
      <div className="toolbar-summary">
        <Badge tone="muted">selected: {bundleSelection.length || (selectedDocument ? 1 : 0)}</Badge>
        <Badge tone="muted">{bundleResult?.documentSlugs.length ?? 0} bundled</Badge>
      </div>
    ),
    content: (
      <>
        <div className="toolbar-actions">
          <button
            type="button"
            className="toolbar-button toolbar-accent"
            onClick={() => void prepareBundle()}
            disabled={(!selectedDocument && bundleSelection.length === 0) || !hasActiveWorkspace}
          >
            Prepare structuring bundle
          </button>
        </div>
        <label className="field">
          <span className="field-label">Bundle summary</span>
          <textarea className="field-input field-textarea ai-readonly narrative-readonly-compact" readOnly value={bundleResult?.summary ?? ""} />
        </label>
        <label className="field">
          <span className="field-label">Export path</span>
          <textarea className="field-input field-textarea ai-readonly narrative-readonly-compact" readOnly value={bundleResult?.exportPath ?? ""} />
        </label>
        <label className="field">
          <span className="field-label">Generated at</span>
          <textarea className="field-input field-textarea ai-readonly narrative-readonly-compact" readOnly value={bundleResult?.generatedAt ?? ""} />
        </label>
        <label className="field">
          <span className="field-label">Suggested targets</span>
          <textarea
            className="field-input field-textarea ai-readonly narrative-readonly-compact"
            readOnly
            value={bundleResult ? bundleResult.suggestedTargets.join("\n") : ""}
          />
        </label>
        <label className="field">
          <span className="field-label">Combined markdown</span>
          <textarea className="field-input field-textarea field-code ai-readonly" readOnly value={bundleResult?.combinedMarkdown ?? ""} />
        </label>
      </>
    ),
  });

  workbenchPanels.set("prompt_debug", {
    label: "Debug",
    title: "Prompt debug",
    canHide: true,
    compact: true,
    summary: response?.promptDebug ? <Badge tone="accent">available</Badge> : <Badge tone="muted">empty</Badge>,
    content: (
      <textarea
        className="field-input field-textarea field-code ai-readonly"
        readOnly
        value={JSON.stringify(response?.promptDebug ?? {}, null, 2)}
      />
    ),
  });

  return (
    <div className="workspace narrative-workspace">
      <Toolbar actions={actions}>
        <div className="toolbar-summary">
          <Badge tone={hasActiveWorkspace ? "accent" : "warning"}>
            {hasActiveWorkspace ? "workspace ready" : "workspace missing"}
          </Badge>
          <Badge tone="accent">{documents.length} docs</Badge>
          <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>{dirtyCount} dirty</Badge>
          <Badge tone={compactLayout ? "warning" : "success"}>{compactLayout ? "stacked mode" : "drag layout"}</Badge>
          <Badge tone={response?.providerError ? "danger" : response ? "success" : "muted"}>
            {response?.providerError ? "review blocked" : response ? "draft ready" : "no draft"}
          </Badge>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => {
              revealPanel("provider_settings");
              onStatusChange("Opened AI provider settings.");
            }}
          >
            AI settings
          </button>
        </div>
      </Toolbar>

      <div className="narrative-shell">
        <aside className="column narrative-index-column">
          <PanelSection
            label="Narrative Index"
            title={workspace.workspaceName ? `Narrative Lab · ${workspace.workspaceName}` : "Narrative Lab"}
            summary={
              <div className="toolbar-summary">
                <Badge tone={hasActiveWorkspace ? "accent" : "muted"}>{hasActiveWorkspace ? "workspace ready" : "workspace missing"}</Badge>
                <Badge tone="muted">{filteredDocuments.length} visible</Badge>
              </div>
            }
          >
            <TextField label="Search" value={searchText} onChange={setSearchText} placeholder="Filter by slug, title, or type" />
            <SelectField
              label="Doc type"
              value={filterDocType}
              onChange={setFilterDocType}
              options={workspace.docTypes}
              hint={hasActiveWorkspace ? undefined : "Open a workspace to browse narrative documents."}
            />
            <div className="item-list narrative-item-list">
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

        <section className="narrative-workbench-column">
          <ResponsiveGridLayout
            className="narrative-workbench"
            layouts={gridLayouts}
            breakpoints={{ lg: 1280, md: 0 }}
            cols={{ lg: 12, md: 12 }}
            rowHeight={28}
            margin={[16, 16]}
            containerPadding={[0, 0]}
            onBreakpointChange={(breakpoint) => {
              setCurrentBreakpoint((breakpoint === "lg" ? "lg" : "md") as NarrativeBreakpoint);
            }}
            isDraggable={!compactLayout}
            isResizable={!compactLayout}
            draggableHandle=".panel-drag-handle"
            draggableCancel="input, textarea, select, option, pre, label, .field-input, .readonly-box"
            onDragStop={(nextLayout) => updateLayoutFromGrid(nextLayout)}
            onResizeStop={(nextLayout) => updateLayoutFromGrid(nextLayout)}
            compactType="vertical"
            preventCollision={false}
            useCSSTransforms
          >
            {visibleLayoutItems.map((item) => {
              const panel = workbenchPanels.get(item.panelId);
              if (!panel) {
                return null;
              }
              return (
                <div key={item.panelId} className="narrative-grid-item">
                  <PanelSection
                    label={panel.label}
                    title={panel.title}
                    compact={panel.compact}
                    collapsible
                    collapsed={collapsedPanels.includes(item.panelId)}
                    onToggleCollapsed={() => togglePanelCollapsed(item.panelId)}
                    summary={panel.summary}
                    dragHandle={!compactLayout}
                    className="narrative-panel"
                    headerActions={
                      panel.canHide ? (
                        <button type="button" className="toolbar-button" onClick={() => setPanelHidden(item.panelId, true)}>
                          Hide
                        </button>
                      ) : undefined
                    }
                  >
                    {panel.content}
                  </PanelSection>
                </div>
              );
            })}
          </ResponsiveGridLayout>
        </section>
      </div>
    </div>
  );
}
