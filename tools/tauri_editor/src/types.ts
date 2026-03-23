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
