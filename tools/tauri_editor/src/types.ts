export type MigrationStage = {
  id: string;
  title: string;
  description: string;
};

export type EditorBootstrap = {
  appName: string;
  workspaceRoot: string;
  sharedRustPath: string;
  activeStage: string;
  stages: MigrationStage[];
  editorDomains: string[];
};

export type EditorMenuSelfTestScenario = "narrative-menu";

export type EditorRuntimeFlags = {
  menuSelfTestScenario?: EditorMenuSelfTestScenario | null;
};

export type EditorSettingsSection = "ai" | "narrative-sync" | "workspace";

export type ValidationIssue = {
  severity: "error" | "warning";
  field: string;
  message: string;
  scope?: "document" | "node" | "edge";
  nodeId?: string;
  edgeKey?: string;
  path?: string;
};

export type CatalogEntry = {
  value: string;
  label: string;
};

export type ItemReferencePreview = {
  id: string;
  name: string;
  value: number;
  weight: number;
  derivedTags: string[];
  keyFragments: string[];
};

export type EffectReferencePreview = {
  id: string;
  name: string;
  description: string;
  category: string;
  duration: number;
  stackMode: string;
  resourceDeltas: Record<string, number>;
};

export type ReferenceUsageEntry = {
  sourceItemId: number;
  sourceItemName: string;
  fragmentKind: string;
  path: string;
  note: string;
};

export type GraphPosition = {
  x: number;
  y: number;
};

export type ItemAmount = {
  item_id: number;
  count: number;
};

export type CraftingRecipe = {
  materials: ItemAmount[];
  time: number;
};

export type EconomyFragment = {
  kind: "economy";
  rarity: string;
};

export type StackingFragment = {
  kind: "stacking";
  stackable: boolean;
  max_stack: number;
};

export type EquipFragment = {
  kind: "equip";
  slots: string[];
  level_requirement: number;
  equip_effect_ids: string[];
  unequip_effect_ids: string[];
};

export type DurabilityFragment = {
  kind: "durability";
  durability: number;
  max_durability: number;
  repairable: boolean;
  repair_materials: ItemAmount[];
};

export type AttributeModifiersFragment = {
  kind: "attribute_modifiers";
  attributes: Record<string, number>;
};

export type WeaponFragment = {
  kind: "weapon";
  subtype: string;
  damage: number;
  attack_speed: number;
  range: number;
  stamina_cost: number;
  crit_chance: number;
  crit_multiplier: number;
  accuracy?: number | null;
  ammo_type?: number | null;
  max_ammo?: number | null;
  reload_time?: number | null;
  on_hit_effect_ids: string[];
};

export type UsableFragment = {
  kind: "usable";
  subtype: string;
  use_time: number;
  uses: number;
  consume_on_use: boolean;
  effect_ids: string[];
};

export type CraftingFragment = {
  kind: "crafting";
  crafting_recipe?: CraftingRecipe | null;
  deconstruct_yield: ItemAmount[];
};

export type PassiveEffectsFragment = {
  kind: "passive_effects";
  effect_ids: string[];
};

export type ItemFragment =
  | EconomyFragment
  | StackingFragment
  | EquipFragment
  | DurabilityFragment
  | AttributeModifiersFragment
  | WeaponFragment
  | UsableFragment
  | CraftingFragment
  | PassiveEffectsFragment;

export type ItemDefinition = {
  id: number;
  name: string;
  description: string;
  icon_path: string;
  value: number;
  weight: number;
  fragments: ItemFragment[];
  [key: string]: unknown;
};

export type ItemCatalogs = {
  fragmentKinds: string[];
  effectIds: string[];
  effectEntries: CatalogEntry[];
  effectPreviews?: EffectReferencePreview[];
  itemPreviews?: ItemReferencePreview[];
  effectUsedBy?: Record<string, ReferenceUsageEntry[]>;
  itemUsedBy?: Record<string, ReferenceUsageEntry[]>;
  equipmentSlots: string[];
  knownSubtypes: string[];
  itemIds: string[];
};

export type ItemDocumentPayload = {
  documentKey: string;
  originalId: number;
  fileName: string;
  relativePath: string;
  item: ItemDefinition;
  validation: ValidationIssue[];
};

export type ItemWorkspacePayload = {
  bootstrap: EditorBootstrap;
  dataDirectory: string;
  itemCount: number;
  catalogs: ItemCatalogs;
  documents: ItemDocumentPayload[];
};

export type SaveItemsResult = {
  savedIds: number[];
  deletedIds: number[];
};

export type DialogueOption = {
  text: string;
  next: string;
  [key: string]: unknown;
};

export type DialogueAction = {
  type: string;
  [key: string]: unknown;
};

export type DialogueNode = {
  id: string;
  type: string;
  title?: string;
  speaker?: string;
  text?: string;
  portrait?: string;
  is_start?: boolean;
  next?: string;
  options?: DialogueOption[];
  actions?: DialogueAction[];
  condition?: string;
  true_next?: string;
  false_next?: string;
  end_type?: string;
  position?: GraphPosition | null;
  [key: string]: unknown;
};

export type DialogueConnection = {
  from: string;
  from_port: number;
  to: string;
  to_port: number;
  [key: string]: unknown;
};

export type DialogueData = {
  dialog_id: string;
  nodes: DialogueNode[];
  connections: DialogueConnection[];
  [key: string]: unknown;
};

export type DialogueCatalogs = {
  nodeTypes: string[];
};

export type DialogueDocumentPayload = {
  documentKey: string;
  originalId: string;
  fileName: string;
  relativePath: string;
  dialog: DialogueData;
  validation: ValidationIssue[];
};

export type DialogueWorkspacePayload = {
  bootstrap: EditorBootstrap;
  dataDirectory: string;
  dialogCount: number;
  catalogs: DialogueCatalogs;
  documents: DialogueDocumentPayload[];
};

export type SaveDialoguesResult = {
  savedIds: string[];
  deletedIds: string[];
};

export type QuestChoiceOption = {
  text: string;
  next: string;
  [key: string]: unknown;
};

export type QuestRewardItem = {
  id: number;
  count: number;
  [key: string]: unknown;
};

export type QuestRewards = {
  items: QuestRewardItem[];
  experience: number;
  skill_points: number;
  unlock_location: string;
  unlock_recipes: string[];
  title: string;
  [key: string]: unknown;
};

export type QuestNode = {
  id: string;
  type: string;
  title?: string;
  description?: string;
  objective_type?: string;
  target?: string;
  item_id?: number | null;
  count?: number;
  dialog_id?: string;
  options?: QuestChoiceOption[];
  rewards?: QuestRewards;
  position?: GraphPosition | null;
  [key: string]: unknown;
};

export type QuestConnection = {
  from: string;
  from_port: number;
  to: string;
  to_port: number;
  [key: string]: unknown;
};

export type QuestFlow = {
  start_node_id: string;
  nodes: Record<string, QuestNode>;
  connections: QuestConnection[];
  [key: string]: unknown;
};

export type QuestEditorMeta = {
  relationship_position?: GraphPosition | null;
  [key: string]: unknown;
};

export type QuestData = {
  quest_id: string;
  title: string;
  description: string;
  prerequisites: string[];
  time_limit: number;
  flow: QuestFlow;
  _editor?: QuestEditorMeta | null;
  [key: string]: unknown;
};

export type QuestCatalogs = {
  nodeTypes: string[];
  objectiveTypes: string[];
  itemIds: string[];
  dialogIds: string[];
  questIds: string[];
  locationIds: string[];
  recipeIds: string[];
};

export type QuestDocumentPayload = {
  documentKey: string;
  originalId: string;
  fileName: string;
  relativePath: string;
  quest: QuestData;
  validation: ValidationIssue[];
};

export type QuestWorkspacePayload = {
  bootstrap: EditorBootstrap;
  dataDirectory: string;
  questCount: number;
  catalogs: QuestCatalogs;
  documents: QuestDocumentPayload[];
};

export type SaveQuestsResult = {
  savedIds: string[];
  deletedIds: string[];
};

export type AiSettings = {
  baseUrl: string;
  model: string;
  apiKey: string;
  timeoutSec: number;
  maxContextRecords: number;
};

export type AiConnectionTestResult = {
  ok: boolean;
  error: string;
};

export type AiGenerateRequest<TRecord = Record<string, unknown>> = {
  mode: "create" | "revise";
  targetId: string;
  userPrompt: string;
  adjustmentPrompt: string;
  currentRecord: TRecord;
  previousDraft?: TRecord | null;
  previousValidationErrors?: string[];
};

export type AiDraftPayload<TRecord = Record<string, unknown>> = {
  recordType: string;
  operation: "create" | "revise";
  targetId: string;
  summary: string;
  warnings: string[];
  record: TRecord;
};

export type AiDiffSummary = {
  summaryLines: string[];
  addedPaths: string[];
  changedPaths: string[];
  removedPaths: string[];
  riskLevel: string;
};

export type AiGenerationResponse<TRecord = Record<string, unknown>> = {
  draft: AiDraftPayload<TRecord> | null;
  validationErrors: string[];
  providerError: string;
  diffSummary: AiDiffSummary;
  reviewWarnings: string[];
  promptDebug: Record<string, unknown>;
  rawOutput: string;
};

export type NarrativeDocType =
  | "project_brief"
  | "world_bible"
  | "faction_note"
  | "character_card"
  | "arc_outline"
  | "chapter_outline"
  | "branch_sheet"
  | "scene_draft"
  | "dialogue_tone_sheet";

export type NarrativeDocumentMeta = {
  docType: NarrativeDocType;
  slug: string;
  title: string;
  status: string;
  tags: string[];
  relatedDocs: string[];
  sourceRefs: string[];
};

export type NarrativeDocumentPayload = {
  documentKey: string;
  originalSlug: string;
  fileName: string;
  relativePath: string;
  meta: NarrativeDocumentMeta;
  markdown: string;
  validation: ValidationIssue[];
};

export type NarrativeDocTypeEntry = {
  value: NarrativeDocType;
  label: string;
  directory: string;
};

export type NarrativePanelId =
  | "document_overview"
  | "ai_task"
  | "ai_review"
  | "manual_editor"
  | "metadata"
  | "workspace_context"
  | "sync_tools"
  | "provider_settings"
  | "structuring_bundle"
  | "prompt_debug";

export type NarrativePanelLayoutItem = {
  panelId: NarrativePanelId;
  x: number;
  y: number;
  w: number;
  h: number;
  minW?: number;
  minH?: number;
};

export type NarrativeWorkspaceLayout = {
  version: number;
  items: NarrativePanelLayoutItem[];
  collapsedPanels: NarrativePanelId[];
  hiddenPanels: NarrativePanelId[];
};

export type NarrativeAppSettings = {
  recentWorkspaces: string[];
  lastWorkspace?: string | null;
  connectedProjectRoot?: string | null;
  recentProjectRoots: string[];
  workspaceLayouts?: Record<string, NarrativeWorkspaceLayout>;
};

export type NarrativeExecutorMode = "desktop_local" | "cloud_mobile";

export type NarrativeSyncSettings = {
  serverUrl: string;
  authToken: string;
  workspaceId: string;
  deviceLabel: string;
  lastSyncAt?: string | null;
  lastSyncStatus: string;
};

export type CloudWorkspaceMeta = {
  workspaceId: string;
  name: string;
  documentCount: number;
  updatedAt: string;
};

export type PendingSyncOperation = {
  operationId: string;
  kind: string;
  docId: string;
  slug: string;
  baseRevision: number;
  queuedAt: string;
};

export type SyncConflictPayload = {
  slug: string;
  docId: string;
  localRevision: number;
  remoteRevision: number;
  conflictDocSlug: string;
  message: string;
};

export type ProjectContextSnapshot = {
  snapshotId: string;
  workspaceId: string;
  projectRootFingerprint: string;
  generatedAt: string;
  summary: string;
  sourceRefs: string[];
  runtimeIndexes: Record<string, unknown>;
  storyBackground: Record<string, unknown> | null;
};

export type ProjectContextSnapshotExportResult = {
  snapshot: ProjectContextSnapshot;
  exportPath: string;
};

export type ProjectContextSnapshotUploadResult = {
  snapshot: ProjectContextSnapshot;
  exportPath: string;
  serverStatus: string;
};

export type NarrativeWorkspaceSyncResult = {
  workspace: CloudWorkspaceMeta;
  headRevision: number;
  pushedCount: number;
  pulledCount: number;
  conflictCount: number;
  conflicts: SyncConflictPayload[];
  pendingOperations: PendingSyncOperation[];
  projectSnapshot?: ProjectContextSnapshot | null;
  executorMode: NarrativeExecutorMode;
  syncStatus: string;
};

export type NarrativeWorkspacePayload = {
  bootstrap: EditorBootstrap;
  dataDirectory: string;
  documentCount: number;
  docTypes: NarrativeDocTypeEntry[];
  documents: NarrativeDocumentPayload[];
  workspaceRoot: string;
  workspaceName: string;
  connectedProjectRoot?: string | null;
  projectContextStatus: string;
};

export type NarrativeAction =
  | "create"
  | "revise_document"
  | "rewrite_selection"
  | "expand_selection"
  | "insert_after_selection"
  | "derive_new_doc";

export type NarrativeSelectionRange = {
  start: number;
  end: number;
};

export type NarrativeGenerateRequest = {
  docType: NarrativeDocType;
  targetSlug: string;
  action: NarrativeAction;
  userPrompt: string;
  editorInstruction: string;
  currentMarkdown: string;
  selectedRange?: NarrativeSelectionRange | null;
  selectedText?: string;
  relatedDocSlugs: string[];
  derivedTargetDocType?: NarrativeDocType | null;
};

export type NarrativeAgentRun = {
  agentId: string;
  label: string;
  focus: string;
  status: "completed" | "failed";
  summary: string;
  notes: string[];
  riskLevel: string;
  draftMarkdown: string;
  rawOutput: string;
  providerError: string;
};

export type NarrativeGenerateResponse = {
  engineMode: "multi_agent";
  draftMarkdown: string;
  summary: string;
  reviewNotes: string[];
  riskLevel: string;
  changeScope: "document" | "selection" | "insertion" | "new_doc";
  promptDebug: Record<string, unknown>;
  rawOutput: string;
  usedContextRefs: string[];
  diffPreview: string;
  providerError: string;
  synthesisNotes: string[];
  agentRuns: NarrativeAgentRun[];
};

export type SaveNarrativeDocumentResult = {
  savedSlug: string;
  deletedSlug?: string | null;
};

export type NarrativeDocumentSummary = {
  slug: string;
  title: string;
  headingCount: number;
  headings: string[];
  excerpt: string;
};

export type StructuringBundlePayload = {
  documentSlugs: string[];
  combinedMarkdown: string;
  summary: string;
  suggestedTargets: string[];
  sourceRefs: string[];
  workspaceRoot: string;
  connectedProjectRoot?: string | null;
  generatedAt: string;
  exportPath?: string | null;
};

export type MapId = string;

export type MapSize = {
  width: number;
  height: number;
};

export type MapCellDefinition = {
  x: number;
  z: number;
  blocks_movement: boolean;
  blocks_sight: boolean;
  terrain: string;
  [key: string]: unknown;
};

export type MapLevelDefinition = {
  y: number;
  cells: MapCellDefinition[];
};

export type MapObjectKind = "building" | "pickup" | "interactive" | "ai_spawn";

export type MapRotation = "north" | "east" | "south" | "west";

export type MapObjectFootprint = {
  width: number;
  height: number;
};

export type MapBuildingProps = {
  prefab_id: string;
  [key: string]: unknown;
};

export type MapPickupProps = {
  item_id: string;
  min_count: number;
  max_count: number;
  [key: string]: unknown;
};

export type MapInteractiveProps = {
  interaction_kind: string;
  target_id?: string | null;
  [key: string]: unknown;
};

export type MapAiSpawnProps = {
  spawn_id: string;
  character_id: string;
  auto_spawn: boolean;
  respawn_enabled: boolean;
  respawn_delay: number;
  spawn_radius: number;
  [key: string]: unknown;
};

export type MapObjectProps = {
  building?: MapBuildingProps | null;
  pickup?: MapPickupProps | null;
  interactive?: MapInteractiveProps | null;
  ai_spawn?: MapAiSpawnProps | null;
  [key: string]: unknown;
};

export type MapObjectDefinition = {
  object_id: string;
  kind: MapObjectKind;
  anchor: {
    x: number;
    y: number;
    z: number;
  };
  footprint: MapObjectFootprint;
  rotation: MapRotation;
  blocks_movement: boolean;
  blocks_sight: boolean;
  props: MapObjectProps;
};

export type MapDefinition = {
  id: MapId;
  name: string;
  size: MapSize;
  default_level: number;
  levels: MapLevelDefinition[];
  objects: MapObjectDefinition[];
};

export type MapCatalogs = {
  itemIds: string[];
  characterIds: string[];
  buildingPrefabs: string[];
  interactiveKinds: string[];
};

export type MapDocumentPayload = {
  documentKey: string;
  originalId: string;
  fileName: string;
  relativePath: string;
  map: MapDefinition;
  validation: ValidationIssue[];
};

export type MapWorkspacePayload = {
  bootstrap: EditorBootstrap;
  dataDirectory: string;
  mapCount: number;
  catalogs: MapCatalogs;
  documents: MapDocumentPayload[];
};

export type SaveMapsResult = {
  savedIds: string[];
  deletedIds: string[];
};

export type MapEditorOpenDocumentPayload = {
  documentKey: string;
};

export type MapEditorStateChangedPayload = {
  documentKey: string;
  mapId: string;
  dirty: boolean;
  errorCount: number;
  warningCount: number;
  objectCount: number;
  level: number;
};

export type MapEditorSaveCompletePayload = {
  savedIds: string[];
  deletedIds: string[];
};

export type MapEditorSessionEndedPayload = {
  documentKey?: string;
};
