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

