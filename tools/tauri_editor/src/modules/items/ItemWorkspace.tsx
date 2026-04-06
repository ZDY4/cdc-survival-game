import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Badge } from "../../components/Badge";
import {
  CheckboxField,
  JsonField,
  NumberField,
  NumberMapField,
  SelectField,
  type SelectOption,
  TextField,
  TextareaField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { invokeCommand } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  CraftingFragment,
  CraftingRecipe,
  EffectReferencePreview,
  ItemAmount,
  ItemDefinition,
  ItemDocumentPayload,
  ItemFragment,
  ItemReferencePreview,
  ItemWorkspacePayload,
  ReferenceUsageEntry,
  SaveItemsResult,
  ValidationIssue,
} from "../../types";
import {
  createDefaultFragment,
  createDefaultItem,
  DEFAULT_RARITIES,
  KNOWN_ITEM_KEYS,
} from "./defaults";

type EditableItemDocument = ItemDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type ItemWorkspaceProps = {
  workspace: ItemWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  indexVisible?: boolean;
};

type ItemTag = "weapon" | "armor" | "accessory" | "usable" | "material_or_misc";

type FragmentOf<K extends ItemFragment["kind"]> = Extract<ItemFragment, { kind: K }>;

const ARMOR_SLOTS = new Set(["head", "body", "hands", "legs", "feet", "back"]);
const ACCESSORY_SLOTS = new Set(["accessory", "accessory_1", "accessory_2"]);
const COPY_SUFFIX = " (Copy)";

type ItemTemplateId =
  | "material_basic"
  | "consumable_stackable"
  | "weapon_melee"
  | "weapon_ranged"
  | "armor_basic"
  | "accessory_basic"
  | "crafting_material";

type ItemTemplateDefinition = {
  id: ItemTemplateId;
  label: string;
  build: (nextId: number) => ItemDefinition;
};

const ITEM_TEMPLATES: ItemTemplateDefinition[] = [
  {
    id: "material_basic",
    label: "Basic material",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Basic Material",
      fragments: [
        { kind: "economy", rarity: "common" },
        { kind: "stacking", stackable: true, max_stack: 99 },
      ],
    }),
  },
  {
    id: "consumable_stackable",
    label: "Stackable consumable",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Consumable Item",
      fragments: [
        { kind: "economy", rarity: "common" },
        { kind: "stacking", stackable: true, max_stack: 20 },
        {
          kind: "usable",
          subtype: "healing",
          use_time: 1,
          uses: 1,
          consume_on_use: true,
          effect_ids: [],
        },
      ],
    }),
  },
  {
    id: "weapon_melee",
    label: "Melee weapon",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Melee Weapon",
      fragments: [
        { kind: "economy", rarity: "common" },
        { kind: "stacking", stackable: false, max_stack: 1 },
        {
          kind: "equip",
          slots: ["main_hand"],
          level_requirement: 0,
          equip_effect_ids: [],
          unequip_effect_ids: [],
        },
        {
          kind: "weapon",
          subtype: "sword",
          damage: 12,
          attack_speed: 1,
          range: 1,
          stamina_cost: 4,
          crit_chance: 0.05,
          crit_multiplier: 1.5,
          accuracy: null,
          ammo_type: null,
          max_ammo: null,
          reload_time: null,
          on_hit_effect_ids: [],
        },
      ],
    }),
  },
  {
    id: "weapon_ranged",
    label: "Ranged weapon",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Ranged Weapon",
      fragments: [
        { kind: "economy", rarity: "uncommon" },
        { kind: "stacking", stackable: false, max_stack: 1 },
        {
          kind: "equip",
          slots: ["main_hand"],
          level_requirement: 1,
          equip_effect_ids: [],
          unequip_effect_ids: [],
        },
        {
          kind: "weapon",
          subtype: "rifle",
          damage: 20,
          attack_speed: 0.9,
          range: 6,
          stamina_cost: 5,
          crit_chance: 0.08,
          crit_multiplier: 1.7,
          accuracy: 85,
          ammo_type: null,
          max_ammo: 6,
          reload_time: 1.5,
          on_hit_effect_ids: [],
        },
      ],
    }),
  },
  {
    id: "armor_basic",
    label: "Armor piece",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Armor Piece",
      fragments: [
        { kind: "economy", rarity: "common" },
        { kind: "stacking", stackable: false, max_stack: 1 },
        {
          kind: "equip",
          slots: ["body"],
          level_requirement: 0,
          equip_effect_ids: [],
          unequip_effect_ids: [],
        },
        { kind: "attribute_modifiers", attributes: { defense: 5 } },
      ],
    }),
  },
  {
    id: "accessory_basic",
    label: "Accessory",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Accessory",
      fragments: [
        { kind: "economy", rarity: "uncommon" },
        { kind: "stacking", stackable: false, max_stack: 1 },
        {
          kind: "equip",
          slots: ["accessory"],
          level_requirement: 0,
          equip_effect_ids: [],
          unequip_effect_ids: [],
        },
      ],
    }),
  },
  {
    id: "crafting_material",
    label: "Crafting material",
    build: (nextId) => ({
      ...createDefaultItem(nextId),
      name: "Crafting Material",
      fragments: [
        { kind: "economy", rarity: "common" },
        { kind: "stacking", stackable: true, max_stack: 99 },
        {
          kind: "crafting",
          crafting_recipe: {
            materials: [],
            time: 0,
          },
          deconstruct_yield: [],
        },
      ],
    }),
  },
];

function hydrateDocuments(documents: ItemDocumentPayload[]): EditableItemDocument[] {
  return documents.map((document) => ({
    ...document,
    savedSnapshot: JSON.stringify(document.item),
    dirty: false,
    isDraft: false,
  }));
}

function getDirtyState(item: ItemDefinition, savedSnapshot: string): boolean {
  return JSON.stringify(item) !== savedSnapshot;
}

function getIssueCounts(issues: ValidationIssue[]) {
  let errorCount = 0;
  let warningCount = 0;
  for (const issue of issues) {
    if (issue.severity === "error") {
      errorCount += 1;
    } else {
      warningCount += 1;
    }
  }
  return { errorCount, warningCount };
}

function getExtraFields(item: ItemDefinition): Record<string, unknown> {
  const extra: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(item)) {
    if (!KNOWN_ITEM_KEYS.has(key)) {
      extra[key] = value;
    }
  }
  return extra;
}

function mergeExtraFields(item: ItemDefinition, extra: Record<string, unknown>): ItemDefinition {
  const next: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(item)) {
    if (KNOWN_ITEM_KEYS.has(key)) {
      next[key] = value;
    }
  }
  for (const [key, value] of Object.entries(extra)) {
    next[key] = value;
  }
  return next as ItemDefinition;
}

function parseExtraJson(raw: string): Record<string, unknown> | null {
  const trimmed = raw.trim();
  if (!trimmed) {
    return {};
  }
  const parsed = JSON.parse(trimmed);
  if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
    return null;
  }
  return parsed as Record<string, unknown>;
}

function getFragment<K extends ItemFragment["kind"]>(
  item: ItemDefinition,
  kind: K,
): FragmentOf<K> | null {
  const fragment = item.fragments.find(
    (candidate): candidate is FragmentOf<K> => candidate.kind === kind,
  );
  return fragment ?? null;
}

function replaceFragment(item: ItemDefinition, fragment: ItemFragment): ItemDefinition {
  const existingIndex = item.fragments.findIndex((candidate) => candidate.kind === fragment.kind);
  if (existingIndex === -1) {
    return {
      ...item,
      fragments: [...item.fragments, fragment],
    };
  }

  const fragments = [...item.fragments];
  fragments[existingIndex] = fragment;
  return {
    ...item,
    fragments,
  };
}

function removeFragment(item: ItemDefinition, kind: ItemFragment["kind"]): ItemDefinition {
  return {
    ...item,
    fragments: item.fragments.filter((fragment) => fragment.kind !== kind),
  };
}

function availableFragmentKinds(item: ItemDefinition, fragmentKinds: string[]) {
  const existing = new Set(item.fragments.map((fragment) => fragment.kind));
  return fragmentKinds.filter((kind) => !existing.has(kind as ItemFragment["kind"]));
}

function ensureCraftingRecipe(fragment: CraftingFragment): CraftingRecipe {
  return (
    fragment.crafting_recipe ?? {
      materials: [],
      time: 0,
    }
  );
}

function inferItemTags(item: ItemDefinition): ItemTag[] {
  const tags: ItemTag[] = [];
  const weapon = getFragment(item, "weapon");
  const equip = getFragment(item, "equip");
  const usable = getFragment(item, "usable");
  const crafting = getFragment(item, "crafting");
  const stacking = getFragment(item, "stacking");

  if (weapon) {
    tags.push("weapon");
  }
  if (equip && !weapon && equip.slots.some((slot) => ARMOR_SLOTS.has(slot))) {
    tags.push("armor");
  }
  if (equip && equip.slots.some((slot) => ACCESSORY_SLOTS.has(slot))) {
    tags.push("accessory");
  }
  if (usable) {
    tags.push("usable");
  }
  if (!equip && !weapon && !usable && (crafting || stacking)) {
    tags.push("material_or_misc");
  }
  if (tags.length === 0) {
    tags.push("material_or_misc");
  }

  return tags;
}

function getPrimaryTag(item: ItemDefinition): ItemTag {
  return inferItemTags(item)[0];
}

function getEconomyRarity(item: ItemDefinition): string {
  return getFragment(item, "economy")?.rarity ?? "common";
}

function getKnownSubtype(item: ItemDefinition): string {
  return getFragment(item, "weapon")?.subtype ?? getFragment(item, "usable")?.subtype ?? "";
}

function optionalNumberText(value: number | null | undefined): string {
  return value == null ? "" : String(value);
}

function parseOptionalInteger(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isNaN(parsed) ? null : parsed;
}

function parseOptionalFloat(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  const parsed = Number.parseFloat(trimmed);
  return Number.isNaN(parsed) ? null : parsed;
}

function formatTag(tag: ItemTag): string {
  switch (tag) {
    case "material_or_misc":
      return "material/misc";
    default:
      return tag;
  }
}

function dedupeStrings(values: string[]): string[] {
  return Array.from(new Set(values.map((value) => value.trim()).filter(Boolean)));
}

function cloneItemDefinition(item: ItemDefinition): ItemDefinition {
  return JSON.parse(JSON.stringify(item)) as ItemDefinition;
}

function findNextDraftId(documents: EditableItemDocument[]): number {
  return documents.reduce((maxId, document) => Math.max(maxId, document.item.id), 1000) + 1;
}

function buildDraftDocument(item: ItemDefinition, nextId: number): EditableItemDocument {
  return {
    documentKey: `draft-${Date.now()}-${nextId}`,
    originalId: nextId,
    fileName: `${nextId}.json`,
    relativePath: `data/items/${nextId}.json`,
    item,
    validation: [],
    savedSnapshot: "",
    dirty: true,
    isDraft: true,
  };
}

function buildCopyName(sourceName: string): string {
  const trimmed = sourceName.trim();
  if (!trimmed) {
    return "Copied Item";
  }
  return trimmed.endsWith(COPY_SUFFIX) ? trimmed : `${trimmed}${COPY_SUFFIX}`;
}

function buildItemReferenceOptions(documents: EditableItemDocument[]): SelectOption[] {
  return documents
    .slice()
    .sort((left, right) => left.item.id - right.item.id)
    .map((document) => ({
      value: String(document.item.id),
      label: `${document.item.id} · ${document.item.name || "Unnamed item"}`,
    }));
}

function buildStringOptions(values: string[]): SelectOption[] {
  return values.map((value) => ({
    value,
    label: value,
  }));
}

function buildOptionLabelLookup(options: SelectOption[]): Record<string, string> {
  return Object.fromEntries(options.map((option) => [option.value, option.label]));
}

function normalizeIssuePath(value: string | undefined): string {
  return value?.trim().toLowerCase() ?? "";
}

function issueMatchesAnyPath(issue: ValidationIssue, paths: string[]): boolean {
  const issuePath = normalizeIssuePath(issue.path || issue.field);
  if (!issuePath) {
    return false;
  }

  for (const rawPath of paths) {
    const path = normalizeIssuePath(rawPath);
    if (!path) {
      continue;
    }
    if (issuePath === path) {
      return true;
    }
    if (issuePath.startsWith(`${path}.`) || issuePath.startsWith(`${path}[`)) {
      return true;
    }
  }

  return false;
}

function collectIssuesByPaths(issues: ValidationIssue[], paths: string[]): ValidationIssue[] {
  return issues.filter((issue) => issueMatchesAnyPath(issue, paths));
}

function buildIssueHint(
  issues: ValidationIssue[],
  paths: string[],
  baseHint?: string,
): string | undefined {
  const matches = collectIssuesByPaths(issues, paths);
  if (matches.length === 0) {
    return baseHint;
  }

  const summary = matches
    .slice(0, 2)
    .map((issue) => issue.message)
    .join(" ");
  if (!baseHint) {
    return `Issue: ${summary}`;
  }
  return `${baseHint} | Issue: ${summary}`;
}

type SummaryBadge = {
  label: string;
  tone: "muted" | "accent" | "warning" | "success";
};

type ReferenceFocus =
  | {
      kind: "item";
      id: string;
    }
  | {
      kind: "effect";
      id: string;
    };

type ItemSidebarMode = "validation" | "reference" | "catalogs";

function shortenLabel(label: string, maxLength = 28): string {
  return label.length <= maxLength ? label : `${label.slice(0, maxLength - 1)}…`;
}

function summaryLabelFromLookup(
  value: string,
  lookup: Record<string, string>,
  maxLength?: number,
): string {
  const resolved = lookup[value] ?? value;
  return shortenLabel(resolved, maxLength);
}

function summarizeFragment(
  fragment: ItemFragment,
  itemLabelLookup: Record<string, string>,
  effectLabelLookup: Record<string, string>,
): SummaryBadge[] {
  switch (fragment.kind) {
    case "economy":
      return [{ label: fragment.rarity || "common", tone: "accent" }];
    case "stacking":
      return [
        {
          label: fragment.stackable ? `stack x${fragment.max_stack}` : "single item",
          tone: "muted",
        },
      ];
    case "equip": {
      const badges: SummaryBadge[] = [];
      badges.push(...fragment.slots.slice(0, 3).map((slot) => ({ label: slot, tone: "muted" as const })));
      if (fragment.slots.length > 3) {
        badges.push({ label: `+${fragment.slots.length - 3} slots`, tone: "muted" });
      }
      if (fragment.level_requirement > 0) {
        badges.push({ label: `lvl ${fragment.level_requirement}+`, tone: "accent" });
      }
      if (fragment.equip_effect_ids.length > 0) {
        badges.push({
          label: `equip ${summaryLabelFromLookup(fragment.equip_effect_ids[0] ?? "", effectLabelLookup)}`,
          tone: "success",
        });
        if (fragment.equip_effect_ids.length > 1) {
          badges.push({
            label: `+${fragment.equip_effect_ids.length - 1} equip fx`,
            tone: "success",
          });
        }
      }
      if (fragment.unequip_effect_ids.length > 0) {
        badges.push({
          label: `${fragment.unequip_effect_ids.length} unequip fx`,
          tone: "warning",
        });
      }
      return badges;
    }
    case "durability": {
      const badges: SummaryBadge[] = [
        {
          label:
            fragment.max_durability < 0
              ? "unbreakable"
              : `${fragment.durability}/${fragment.max_durability}`,
          tone: "muted",
        },
      ];
      if (fragment.repairable) {
        badges.push({ label: "repairable", tone: "accent" });
      }
      if (fragment.repair_materials.length > 0) {
        badges.push({
          label: `${fragment.repair_materials.length} repair mats`,
          tone: "success",
        });
      }
      return badges;
    }
    case "attribute_modifiers": {
      const entries = Object.entries(fragment.attributes);
      const badges = entries.slice(0, 3).map(([key, value]) => ({
        label: `${key} ${value >= 0 ? "+" : ""}${value}`,
        tone: "accent" as const,
      }));
      if (entries.length > 3) {
        badges.push({ label: `+${entries.length - 3} attrs`, tone: "accent" });
      }
      return badges;
    }
    case "weapon": {
      const badges: SummaryBadge[] = [];
      if (fragment.subtype) {
        badges.push({ label: fragment.subtype, tone: "accent" });
      }
      badges.push({ label: `dmg ${fragment.damage}`, tone: "muted" });
      badges.push({ label: `rng ${fragment.range}`, tone: "muted" });
      if (fragment.ammo_type != null) {
        badges.push({
          label: `ammo ${summaryLabelFromLookup(String(fragment.ammo_type), itemLabelLookup, 24)}`,
          tone: "warning",
        });
      }
      if (fragment.on_hit_effect_ids.length > 0) {
        badges.push({
          label: `hit ${summaryLabelFromLookup(fragment.on_hit_effect_ids[0] ?? "", effectLabelLookup)}`,
          tone: "success",
        });
        if (fragment.on_hit_effect_ids.length > 1) {
          badges.push({
            label: `+${fragment.on_hit_effect_ids.length - 1} hit fx`,
            tone: "success",
          });
        }
      }
      return badges;
    }
    case "usable": {
      const badges: SummaryBadge[] = [];
      if (fragment.subtype) {
        badges.push({ label: fragment.subtype, tone: "accent" });
      }
      badges.push({ label: `${fragment.uses} uses`, tone: "muted" });
      badges.push({ label: `${fragment.use_time}s`, tone: "muted" });
      badges.push({
        label: fragment.consume_on_use ? "consumes" : "keeps item",
        tone: fragment.consume_on_use ? "warning" : "success",
      });
      if (fragment.effect_ids.length > 0) {
        badges.push({
          label: summaryLabelFromLookup(fragment.effect_ids[0] ?? "", effectLabelLookup),
          tone: "success",
        });
        if (fragment.effect_ids.length > 1) {
          badges.push({ label: `+${fragment.effect_ids.length - 1} effects`, tone: "success" });
        }
      }
      return badges;
    }
    case "crafting": {
      const badges: SummaryBadge[] = [];
      if (fragment.crafting_recipe) {
        badges.push({
          label: `${fragment.crafting_recipe.materials.length} recipe mats`,
          tone: "accent",
        });
        badges.push({
          label: `${fragment.crafting_recipe.time}s`,
          tone: "muted",
        });
      }
      if (fragment.deconstruct_yield.length > 0) {
        badges.push({
          label: `${fragment.deconstruct_yield.length} yield items`,
          tone: "success",
        });
      }
      return badges;
    }
    case "passive_effects": {
      const badges: SummaryBadge[] = [];
      if (fragment.effect_ids.length > 0) {
        badges.push({
          label: summaryLabelFromLookup(fragment.effect_ids[0] ?? "", effectLabelLookup),
          tone: "success",
        });
        if (fragment.effect_ids.length > 1) {
          badges.push({ label: `+${fragment.effect_ids.length - 1} passive fx`, tone: "success" });
        }
      }
      return badges;
    }
    default:
      return [];
  }
}

type ChipListEditorProps = {
  label: string;
  hint?: string;
  values: string[];
  options: SelectOption[];
  onChange: (values: string[]) => void;
  allowCustom?: boolean;
  emptyMessage?: string;
  onInspectValue?: (value: string) => void;
};

function ChipListEditor({
  label,
  hint,
  values,
  options,
  onChange,
  allowCustom = true,
  emptyMessage = "Nothing selected yet.",
  onInspectValue,
}: ChipListEditorProps) {
  const availableOptions = options.filter((option) => !values.includes(option.value));
  const [filterText, setFilterText] = useState("");
  const [selectedOption, setSelectedOption] = useState(availableOptions[0]?.value ?? "");
  const [customValue, setCustomValue] = useState("");
  const filteredOptions = availableOptions.filter((option) => {
    const needle = filterText.trim().toLowerCase();
    if (!needle) {
      return true;
    }
    return (
      option.value.toLowerCase().includes(needle) || option.label.toLowerCase().includes(needle)
    );
  });

  useEffect(() => {
    if (!selectedOption || values.includes(selectedOption) || !availableOptions.some((option) => option.value === selectedOption)) {
      setSelectedOption(filteredOptions[0]?.value ?? availableOptions[0]?.value ?? "");
    }
  }, [availableOptions, filteredOptions, selectedOption, values]);

  function addSelectedOption() {
    if (!selectedOption) {
      return;
    }
    onChange([...values, selectedOption]);
  }

  function addCustomValue() {
    const trimmed = customValue.trim();
    if (!trimmed) {
      return;
    }
    onChange(dedupeStrings([...values, trimmed]));
    setCustomValue("");
  }

  function removeValue(target: string) {
    onChange(values.filter((value) => value !== target));
  }

  return (
    <label className="field">
      <span className="field-label">{label}</span>
      <div className="picker-stack">
        <div className="picker-controls">
          <input
            className="field-input"
            type="text"
            value={filterText}
            placeholder="Search references"
            onChange={(event) => setFilterText(event.target.value)}
          />
        </div>

        <div className="picker-controls">
          <select
            className="field-input"
            value={selectedOption}
            onChange={(event) => setSelectedOption(event.target.value)}
          >
            <option value="">Select option</option>
            {filteredOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <button
            type="button"
            className="toolbar-button"
            onClick={addSelectedOption}
            disabled={!selectedOption}
          >
            Add
          </button>
          {onInspectValue ? (
            <button
              type="button"
              className="toolbar-button"
              onClick={() => {
                if (selectedOption) {
                  onInspectValue(selectedOption);
                }
              }}
              disabled={!selectedOption}
            >
              Inspect
            </button>
          ) : null}
        </div>

        {allowCustom ? (
          <div className="picker-controls">
            <input
              className="field-input"
              type="text"
              value={customValue}
              placeholder="Add custom value"
              onChange={(event) => setCustomValue(event.target.value)}
            />
            <button
              type="button"
              className="toolbar-button"
              onClick={addCustomValue}
              disabled={!customValue.trim()}
            >
              Add custom
            </button>
          </div>
        ) : null}

        {values.length > 0 ? (
          <div className="picker-values">
            {values.map((value) => (
              <button
                key={value}
                type="button"
                className="picker-chip"
                onClick={() => removeValue(value)}
                title={`Remove ${value}`}
              >
                <span>{value}</span>
                <span>Remove</span>
              </button>
            ))}
          </div>
        ) : (
          <div className="empty-state picker-empty">
            <p>{emptyMessage}</p>
          </div>
        )}
      </div>
      {hint ? <span className="field-hint">{hint}</span> : null}
    </label>
  );
}

type ItemAmountEditorProps = {
  label: string;
  hint?: string;
  values: ItemAmount[];
  itemOptions: SelectOption[];
  onChange: (values: ItemAmount[]) => void;
  emptyMessage?: string;
  onInspectItem?: (itemId: string) => void;
};

function ItemAmountEditor({
  label,
  hint,
  values,
  itemOptions,
  onChange,
  emptyMessage = "No item amounts configured.",
  onInspectItem,
}: ItemAmountEditorProps) {
  const [filterText, setFilterText] = useState("");
  const [draftItemId, setDraftItemId] = useState(itemOptions[0]?.value ?? "");
  const [draftCount, setDraftCount] = useState("1");
  const filteredItemOptions = itemOptions.filter((option) => {
    const needle = filterText.trim().toLowerCase();
    if (!needle) {
      return true;
    }
    return (
      option.value.toLowerCase().includes(needle) || option.label.toLowerCase().includes(needle)
    );
  });

  useEffect(() => {
    if (!draftItemId && itemOptions.length > 0) {
      setDraftItemId(itemOptions[0]?.value ?? "");
    }
  }, [draftItemId, itemOptions]);

  function updateAmount(index: number, next: ItemAmount) {
    const updated = [...values];
    updated[index] = next;
    onChange(updated);
  }

  function removeAmount(index: number) {
    onChange(values.filter((_, currentIndex) => currentIndex !== index));
  }

  function addAmount() {
    const itemId = Number.parseInt(draftItemId, 10);
    const count = Number.parseInt(draftCount, 10);
    if (Number.isNaN(itemId) || Number.isNaN(count) || count <= 0) {
      return;
    }

    const existingIndex = values.findIndex((value) => value.item_id === itemId);
    if (existingIndex >= 0) {
      const updated = [...values];
      updated[existingIndex] = { item_id: itemId, count };
      onChange(updated);
    } else {
      onChange([...values, { item_id: itemId, count }]);
    }
    setDraftCount("1");
  }

  return (
    <label className="field">
      <span className="field-label">{label}</span>
      <div className="picker-stack">
        <div className="picker-controls">
          <input
            className="field-input"
            type="text"
            value={filterText}
            placeholder="Search item references"
            onChange={(event) => setFilterText(event.target.value)}
          />
        </div>

        <div className="picker-controls picker-controls-wide">
          <select
            className="field-input"
            value={draftItemId}
            onChange={(event) => setDraftItemId(event.target.value)}
          >
            <option value="">Select item id</option>
            {filteredItemOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <input
            className="field-input"
            type="number"
            min={1}
            value={draftCount}
            onChange={(event) => setDraftCount(event.target.value)}
          />
          <button
            type="button"
            className="toolbar-button"
            onClick={addAmount}
            disabled={!draftItemId}
          >
            Add
          </button>
          {onInspectItem ? (
            <button
              type="button"
              className="toolbar-button"
              onClick={() => {
                if (draftItemId) {
                  onInspectItem(draftItemId);
                }
              }}
              disabled={!draftItemId}
            >
              Inspect
            </button>
          ) : null}
        </div>

        {values.length > 0 ? (
          <div className="amount-list">
            {values.map((amount, index) => (
              <div className="amount-row" key={`${amount.item_id}-${index}`}>
                <select
                  className="field-input"
                  value={String(amount.item_id)}
                  onChange={(event) =>
                    updateAmount(index, {
                      ...amount,
                      item_id: Number.parseInt(event.target.value, 10),
                    })
                  }
                >
                  {itemOptions.map((option) => (
                    <option key={`${index}-${option.value}`} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
                <input
                  className="field-input"
                  type="number"
                  min={1}
                  value={amount.count}
                  onChange={(event) =>
                    updateAmount(index, {
                      ...amount,
                      count: Math.max(1, Number.parseInt(event.target.value, 10) || 1),
                    })
                  }
                />
                <button
                  type="button"
                  className="toolbar-button"
                  onClick={() => onInspectItem?.(String(amount.item_id))}
                >
                  Inspect
                </button>
                <button
                  type="button"
                  className="toolbar-button toolbar-danger"
                  onClick={() => removeAmount(index)}
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="empty-state picker-empty">
            <p>{emptyMessage}</p>
          </div>
        )}
      </div>
      {hint ? <span className="field-hint">{hint}</span> : null}
    </label>
  );
}

export function ItemWorkspace({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
  indexVisible = true,
}: ItemWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableItemDocument[]>(
    hydrateDocuments(workspace.documents),
  );
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [tagFilter, setTagFilter] = useState("");
  const [fragmentFilter, setFragmentFilter] = useState("");
  const [busy, setBusy] = useState(false);
  const [extraJsonDraft, setExtraJsonDraft] = useState("{}");
  const [addFragmentKind, setAddFragmentKind] = useState("");
  const [collapsedFragments, setCollapsedFragments] = useState<Record<string, boolean>>({});
  const [referenceFocus, setReferenceFocus] = useState<ReferenceFocus | null>(null);
  const [sidebarMode, setSidebarMode] = useState<ItemSidebarMode>("validation");
  const [newTemplateId, setNewTemplateId] = useState<ItemTemplateId>(ITEM_TEMPLATES[0].id);
  const [cloneSourceKey, setCloneSourceKey] = useState("");
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
    setReferenceFocus(null);
    setSidebarMode("validation");
  }, [workspace]);

  useEffect(() => {
    const selected = documents.find((document) => document.documentKey === selectedKey);
    setExtraJsonDraft(
      JSON.stringify(getExtraFields(selected?.item ?? createDefaultItem(0)), null, 2),
    );
    const firstAvailableKind =
      selected != null
        ? availableFragmentKinds(selected.item, workspace.catalogs.fragmentKinds)[0] ?? ""
        : "";
    setAddFragmentKind(firstAvailableKind);
  }, [documents, selectedKey, workspace.catalogs.fragmentKinds]);

  useEffect(() => {
    const candidate = documents.find((document) => document.documentKey !== selectedKey)?.documentKey;
    if (!candidate) {
      setCloneSourceKey("");
      return;
    }
    if (!cloneSourceKey || cloneSourceKey === selectedKey || !documents.some((document) => document.documentKey === cloneSourceKey)) {
      setCloneSourceKey(candidate);
    }
  }, [cloneSourceKey, documents, selectedKey]);

  const validationTarget =
    documents.find((document) => document.documentKey === selectedKey) ?? null;

  useEffect(() => {
    if (!validationTarget || !canPersist) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void invokeCommand<ValidationIssue[]>("validate_item_document", {
        item: validationTarget.item,
      })
        .then((issues) => {
          setDocuments((current) =>
            current.map((document) =>
              document.documentKey === validationTarget.documentKey
                ? { ...document, validation: issues }
                : document,
            ),
          );
        })
        .catch(() => {});
    }, 180);

    return () => window.clearTimeout(timeoutId);
  }, [canPersist, validationTarget?.documentKey, validationTarget?.item]);

  const filteredDocuments = documents.filter((document) => {
    const tags = inferItemTags(document.item);
    if (tagFilter && !tags.includes(tagFilter as ItemTag)) {
      return false;
    }
    if (
      fragmentFilter &&
      !document.item.fragments.some((fragment) => fragment.kind === fragmentFilter)
    ) {
      return false;
    }
    if (!deferredSearch.trim()) {
      return true;
    }

    const haystack = [
      document.item.id,
      document.item.name,
      document.item.description,
      getEconomyRarity(document.item),
      getKnownSubtype(document.item),
      ...tags,
      ...document.item.fragments.map((fragment) => fragment.kind),
    ]
      .join(" ")
      .toLowerCase();
    return haystack.includes(deferredSearch.trim().toLowerCase());
  });

  const selectedDocument = validationTarget;
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const totalIssues = documents.reduce(
    (totals, document) => {
      const counts = getIssueCounts(document.validation);
      return {
        errors: totals.errors + counts.errorCount,
        warnings: totals.warnings + counts.warningCount,
      };
    },
    { errors: 0, warnings: 0 },
  );

  function updateSelectedItem(transform: (item: ItemDefinition) => ItemDefinition) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const nextItem = transform(document.item);
        return {
          ...document,
          item: nextItem,
          dirty: getDirtyState(nextItem, document.savedSnapshot),
        };
      }),
    );
  }

  function updateSelectedFragment<K extends ItemFragment["kind"]>(
    kind: K,
    transform: (fragment: FragmentOf<K>) => FragmentOf<K>,
  ) {
    updateSelectedItem((item) => {
      const current = getFragment(item, kind);
      if (!current) {
        return item;
      }
      return replaceFragment(item, transform(current));
    });
  }

  function createDraft() {
    const nextId = findNextDraftId(documents);
    const draft = buildDraftDocument(createDefaultItem(nextId), nextId);

    setDocuments((current) => [draft, ...current]);
    setSelectedKey(draft.documentKey);
    onStatusChange(`Created draft item ${nextId}.`);
  }

  function createDraftFromTemplate() {
    const nextId = findNextDraftId(documents);
    const template = ITEM_TEMPLATES.find((entry) => entry.id === newTemplateId) ?? ITEM_TEMPLATES[0];
    const draftItem = template.build(nextId);
    const draft = buildDraftDocument(draftItem, nextId);

    setDocuments((current) => [draft, ...current]);
    setSelectedKey(draft.documentKey);
    onStatusChange(`Created template draft ${nextId} from ${template.label}.`);
  }

  function duplicateCurrentItem() {
    if (!selectedDocument) {
      onStatusChange("Select an item first.");
      return;
    }
    const nextId = findNextDraftId(documents);
    const copied = cloneItemDefinition(selectedDocument.item);
    const draftItem: ItemDefinition = {
      ...copied,
      id: nextId,
      name: buildCopyName(copied.name),
    };
    const draft = buildDraftDocument(draftItem, nextId);

    setDocuments((current) => [draft, ...current]);
    setSelectedKey(draft.documentKey);
    onStatusChange(`Duplicated item ${selectedDocument.item.id} into draft ${nextId}.`);
  }

  function cloneFragmentSetFromSource() {
    if (!selectedDocument) {
      onStatusChange("Select an item first.");
      return;
    }
    if (!cloneSourceKey) {
      onStatusChange("Choose a source item for fragment cloning.");
      return;
    }
    const sourceDocument = documents.find((document) => document.documentKey === cloneSourceKey);
    if (!sourceDocument) {
      onStatusChange("Source item is no longer available.");
      return;
    }
    if (sourceDocument.documentKey === selectedDocument.documentKey) {
      onStatusChange("Choose a different source item.");
      return;
    }

    const clonedFragments = cloneItemDefinition({
      ...sourceDocument.item,
      id: sourceDocument.item.id,
    }).fragments;

    updateSelectedItem((item) => ({
      ...item,
      fragments: clonedFragments,
    }));
    onStatusChange(
      `Cloned ${clonedFragments.length} fragments from item ${sourceDocument.item.id} to ${selectedDocument.item.id}.`,
    );
  }

  function addFragment() {
    if (!selectedDocument || !addFragmentKind) {
      return;
    }

    updateSelectedItem((item) => {
      const nextFragments = [...item.fragments];
      if (addFragmentKind === "weapon" && !getFragment(item, "equip")) {
        nextFragments.push(createDefaultFragment("equip"));
      }
      nextFragments.push(createDefaultFragment(addFragmentKind));
      return {
        ...item,
        fragments: nextFragments,
      };
    });

    setCollapsedFragments((current) => ({
      ...current,
      [`${selectedKey}:${addFragmentKind}`]: false,
    }));
    onStatusChange(`Added ${addFragmentKind} fragment.`);
  }

  function toggleFragment(kind: ItemFragment["kind"]) {
    setCollapsedFragments((current) => ({
      ...current,
      [`${selectedKey}:${kind}`]: !current[`${selectedKey}:${kind}`],
    }));
  }

  function deleteFragment(kind: ItemFragment["kind"]) {
    updateSelectedItem((item) => removeFragment(item, kind));
    onStatusChange(`Removed ${kind} fragment.`);
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved item changes.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot save in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      const result = await invokeCommand<SaveItemsResult>("save_item_documents", {
        documents: dirtyDocuments.map((document) => ({
          originalId: document.isDraft ? null : document.originalId,
          item: document.item,
        })),
      });
      await onReload();
      onStatusChange(
        `Saved ${result.savedIds.length} item documents. Removed ${result.deletedIds.length} renamed files.`,
      );
    } catch (error) {
      onStatusChange(`Save failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function validateCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select an item first.");
      return;
    }

    if (!canPersist) {
      const counts = getIssueCounts(selectedDocument.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current item looks clean in fallback mode."
          : `Current item has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return;
    }

    try {
      const issues = await invokeCommand<ValidationIssue[]>("validate_item_document", {
        item: selectedDocument.item,
      });
      setDocuments((current) =>
        current.map((document) =>
          document.documentKey === selectedDocument.documentKey
            ? { ...document, validation: issues }
            : document,
        ),
      );
      const counts = getIssueCounts(issues);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? `Item ${selectedDocument.item.id} passed validation.`
          : `Item ${selectedDocument.item.id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
    } catch (error) {
      onStatusChange(`Validation failed: ${String(error)}`);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select an item first.");
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      onStatusChange("Removed unsaved draft item.");
      return;
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_item_document", {
        itemId: selectedDocument.originalId,
      });
      await onReload();
      onStatusChange(`Deleted item ${selectedDocument.originalId}.`);
    } catch (error) {
      onStatusChange(`Delete failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  const actions = [
    { id: "new", label: "New item", onClick: createDraft, tone: "accent" as const, disabled: busy },
    {
      id: "save",
      label: "Save all",
      onClick: () => {
        void saveAll();
      },
      disabled: busy || dirtyCount === 0,
    },
    {
      id: "validate",
      label: "Validate current",
      onClick: () => {
        void validateCurrent();
      },
      disabled: busy || !selectedDocument,
    },
    {
      id: "reload",
      label: "Reload",
      onClick: () => {
        void onReload();
      },
      disabled: busy,
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

  const selectedIssues = selectedDocument?.validation ?? [];
  const selectedCounts = getIssueCounts(selectedIssues);
  const selectedTags = selectedDocument ? inferItemTags(selectedDocument.item) : [];
  const templateOptions: SelectOption[] = ITEM_TEMPLATES.map((template) => ({
    value: template.id,
    label: template.label,
  }));
  const cloneSourceOptions: SelectOption[] = documents
    .filter((document) => document.documentKey !== selectedKey)
    .sort((left, right) => left.item.id - right.item.id)
    .map((document) => ({
      value: document.documentKey,
      label: `${document.item.id} · ${document.item.name || "Unnamed item"}`,
    }));
  const nextFragmentKinds = selectedDocument
    ? availableFragmentKinds(selectedDocument.item, workspace.catalogs.fragmentKinds)
    : [];
  const itemReferenceOptions = buildItemReferenceOptions(documents);
  const effectReferenceOptions = workspace.catalogs.effectEntries;
  const equipmentSlotOptions = buildStringOptions(workspace.catalogs.equipmentSlots);
  const itemLabelLookup = buildOptionLabelLookup(itemReferenceOptions);
  const effectLabelLookup = buildOptionLabelLookup(effectReferenceOptions);
  const itemPreviews = workspace.catalogs.itemPreviews ?? [];
  const effectPreviews = workspace.catalogs.effectPreviews ?? [];
  const itemUsedByMap = workspace.catalogs.itemUsedBy ?? {};
  const effectUsedByMap = workspace.catalogs.effectUsedBy ?? {};
  const itemPreviewLookup: Record<string, ItemReferencePreview> = Object.fromEntries(
    itemPreviews.map((preview) => [preview.id, preview]),
  );
  const effectPreviewLookup: Record<string, EffectReferencePreview> = Object.fromEntries(
    effectPreviews.map((preview) => [preview.id, preview]),
  );
  const menuActionRef = useRef({
    createDraft,
    saveAll,
    deleteCurrent,
    validateCurrent,
    onReload,
  });

  useEffect(() => {
    menuActionRef.current = {
      createDraft,
      saveAll,
      deleteCurrent,
      validateCurrent,
      onReload,
    };
  }, [createDraft, deleteCurrent, onReload, saveAll, validateCurrent]);

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: () => {
          menuActionRef.current.createDraft();
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
        execute: async () => {
          await menuActionRef.current.saveAll();
        },
        isEnabled: () => !busy && dirtyCount > 0,
      },
      [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
        execute: async () => {
          await menuActionRef.current.onReload();
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
        execute: async () => {
          await menuActionRef.current.deleteCurrent();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
      [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: {
        execute: async () => {
          await menuActionRef.current.validateCurrent();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
    }),
    [busy, dirtyCount, selectedDocument],
  );

  useRegisterEditorMenuCommands(menuCommands);
  const documentKeyByItemId: Record<string, string> = Object.fromEntries(
    documents.map((document) => [String(document.item.id), document.documentKey]),
  );

  function focusItemReference(value: string | number | null | undefined) {
    if (value == null) {
      return;
    }
    const id = String(value).trim();
    if (!id || !itemPreviewLookup[id]) {
      return;
    }
    setReferenceFocus({ kind: "item", id });
    setSidebarMode("reference");
  }

  function focusEffectReference(value: string | null | undefined) {
    const id = value?.trim() ?? "";
    if (!id || !effectPreviewLookup[id]) {
      return;
    }
    setReferenceFocus({ kind: "effect", id });
    setSidebarMode("reference");
  }

  const focusedItemPreview =
    referenceFocus?.kind === "item" ? itemPreviewLookup[referenceFocus.id] : undefined;
  const focusedEffectPreview =
    referenceFocus?.kind === "effect" ? effectPreviewLookup[referenceFocus.id] : undefined;
  const focusedUsageEntries: ReferenceUsageEntry[] =
    referenceFocus?.kind === "item"
      ? itemUsedByMap[referenceFocus.id] ?? []
      : referenceFocus?.kind === "effect"
        ? effectUsedByMap[referenceFocus.id] ?? []
        : [];

  const issueHints = {
    equipSlots: buildIssueHint(selectedIssues, ["fragments.equip.slots", "equip.slots"]),
    equipEffects: buildIssueHint(selectedIssues, [
      "fragments.equip.equip_effect_ids",
      "equip.effect_ids",
    ]),
    unequipEffects: buildIssueHint(selectedIssues, [
      "fragments.equip.unequip_effect_ids",
      "equip.effect_ids",
    ]),
    weaponAmmoType: buildIssueHint(selectedIssues, [
      "fragments.weapon.ammo_type",
      "weapon.item_ids",
    ]),
    weaponOnHitEffects: buildIssueHint(selectedIssues, [
      "fragments.weapon.on_hit_effect_ids",
      "weapon.effect_ids",
    ]),
    usableEffects: buildIssueHint(selectedIssues, [
      "fragments.usable.effect_ids",
      "usable.effect_ids",
    ]),
    repairMaterials: buildIssueHint(selectedIssues, [
      "fragments.durability.repair_materials",
      "durability.amounts",
      "durability.item_ids",
    ]),
    craftingRecipeMaterials: buildIssueHint(selectedIssues, [
      "fragments.crafting.crafting_recipe.materials",
      "crafting.amounts",
      "crafting.item_ids",
    ]),
    deconstructYield: buildIssueHint(selectedIssues, [
      "fragments.crafting.deconstruct_yield",
      "crafting.amounts",
      "crafting.item_ids",
    ]),
  };

  function renderFragmentEditor(fragment: ItemFragment) {
    switch (fragment.kind) {
      case "economy":
        return (
          <div className="form-grid">
            <SelectField
              label="Rarity"
              value={fragment.rarity}
              onChange={(value) =>
                updateSelectedFragment("economy", (current) => ({ ...current, rarity: value }))
              }
              options={DEFAULT_RARITIES}
              allowBlank={false}
            />
          </div>
        );
      case "stacking":
        return (
          <>
            <div className="toggle-grid">
              <CheckboxField
                label="Stackable"
                value={fragment.stackable}
                onChange={(value) =>
                  updateSelectedFragment("stacking", (current) => ({
                    ...current,
                    stackable: value,
                    max_stack: value ? Math.max(current.max_stack, 1) : 1,
                  }))
                }
              />
            </div>
            <div className="form-grid">
              <NumberField
                label="Max stack"
                value={fragment.max_stack}
                onChange={(value) =>
                  updateSelectedFragment("stacking", (current) => ({
                    ...current,
                    max_stack: Math.max(1, value),
                  }))
                }
                min={1}
              />
            </div>
          </>
        );
      case "equip":
        return (
          <>
            <div className="form-grid">
              <NumberField
                label="Level requirement"
                value={fragment.level_requirement}
                onChange={(value) =>
                  updateSelectedFragment("equip", (current) => ({
                    ...current,
                    level_requirement: Math.max(0, value),
                  }))
                }
                min={0}
              />
            </div>
            <div className="form-grid">
              <ChipListEditor
                label="Slots"
                hint={buildIssueHint(
                  selectedIssues,
                  ["fragments.equip.slots", "equip.slots"],
                  `Known slots: ${workspace.catalogs.equipmentSlots.join(", ")}`,
                )}
                values={fragment.slots}
                onChange={(value) =>
                  updateSelectedFragment("equip", (current) => ({
                    ...current,
                    slots: dedupeStrings(value),
                  }))
                }
                options={equipmentSlotOptions}
                emptyMessage="No equip slots selected."
              />
              <ChipListEditor
                label="Equip effects"
                hint={issueHints.equipEffects}
                values={fragment.equip_effect_ids}
                onChange={(value) =>
                  updateSelectedFragment("equip", (current) => ({
                    ...current,
                    equip_effect_ids: dedupeStrings(value),
                  }))
                }
                options={effectReferenceOptions}
                emptyMessage="No equip effects configured."
                onInspectValue={focusEffectReference}
              />
              <ChipListEditor
                label="Unequip effects"
                hint={issueHints.unequipEffects}
                values={fragment.unequip_effect_ids}
                onChange={(value) =>
                  updateSelectedFragment("equip", (current) => ({
                    ...current,
                    unequip_effect_ids: dedupeStrings(value),
                  }))
                }
                options={effectReferenceOptions}
                emptyMessage="No unequip effects configured."
                onInspectValue={focusEffectReference}
              />
            </div>
          </>
        );
      case "durability":
        return (
          <>
            <div className="form-grid">
              <NumberField
                label="Durability"
                value={fragment.durability}
                onChange={(value) =>
                  updateSelectedFragment("durability", (current) => ({
                    ...current,
                    durability: value,
                  }))
                }
              />
              <NumberField
                label="Max durability"
                value={fragment.max_durability}
                onChange={(value) =>
                  updateSelectedFragment("durability", (current) => ({
                    ...current,
                    max_durability: value,
                  }))
                }
              />
            </div>
            <div className="toggle-grid">
              <CheckboxField
                label="Repairable"
                value={fragment.repairable}
                onChange={(value) =>
                  updateSelectedFragment("durability", (current) => ({
                    ...current,
                    repairable: value,
                  }))
                }
              />
            </div>
            <ItemAmountEditor
              label="Repair materials"
              hint={issueHints.repairMaterials ?? "Use item_id=count per line."}
              values={fragment.repair_materials}
              onChange={(value) =>
                updateSelectedFragment("durability", (current) => ({
                  ...current,
                  repair_materials: value,
                }))
              }
              itemOptions={itemReferenceOptions}
              emptyMessage="No repair materials configured."
              onInspectItem={focusItemReference}
            />
          </>
        );
      case "attribute_modifiers":
        return (
          <NumberMapField
            label="Attributes"
            value={fragment.attributes}
            onChange={(value) =>
              updateSelectedFragment("attribute_modifiers", (current) => ({
                ...current,
                attributes: value,
              }))
            }
          />
        );
      case "weapon": {
        const ammoTypeValue = fragment.ammo_type == null ? "" : String(fragment.ammo_type);
        return (
          <>
            <div className="form-grid">
              <SelectField
                label="Subtype"
                value={fragment.subtype}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({ ...current, subtype: value }))
                }
                options={workspace.catalogs.knownSubtypes}
              />
              <NumberField
                label="Damage"
                value={fragment.damage}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({ ...current, damage: value }))
                }
              />
              <NumberField
                label="Attack speed"
                value={fragment.attack_speed}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    attack_speed: value,
                  }))
                }
                step={0.1}
              />
              <NumberField
                label="Range"
                value={fragment.range}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({ ...current, range: value }))
                }
              />
              <NumberField
                label="Stamina cost"
                value={fragment.stamina_cost}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    stamina_cost: value,
                  }))
                }
              />
              <NumberField
                label="Crit chance"
                value={fragment.crit_chance}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    crit_chance: value,
                  }))
                }
                step={0.01}
              />
              <NumberField
                label="Crit multiplier"
                value={fragment.crit_multiplier}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    crit_multiplier: value,
                  }))
                }
                step={0.1}
              />
              <TextField
                label="Accuracy"
                value={optionalNumberText(fragment.accuracy)}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    accuracy: parseOptionalInteger(value),
                  }))
                }
                placeholder="Blank for none"
              />
              <SelectField
                label="Ammo type"
                hint={issueHints.weaponAmmoType}
                value={ammoTypeValue}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    ammo_type: value ? Number.parseInt(value, 10) : null,
                  }))
                }
                options={itemReferenceOptions}
              />
              <div>
                <button
                  type="button"
                  className="toolbar-button"
                  onClick={() => focusItemReference(ammoTypeValue)}
                  disabled={!ammoTypeValue}
                >
                  Inspect ammo reference
                </button>
              </div>
              <TextField
                label="Max ammo"
                value={optionalNumberText(fragment.max_ammo)}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    max_ammo: parseOptionalInteger(value),
                  }))
                }
                placeholder="Blank for none"
              />
              <TextField
                label="Reload time"
                value={optionalNumberText(fragment.reload_time)}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    reload_time: parseOptionalFloat(value),
                  }))
                }
                placeholder="Blank for none"
              />
            </div>
            <ChipListEditor
              label="On-hit effects"
              hint={issueHints.weaponOnHitEffects}
              values={fragment.on_hit_effect_ids}
              onChange={(value) =>
                updateSelectedFragment("weapon", (current) => ({
                  ...current,
                  on_hit_effect_ids: dedupeStrings(value),
                }))
              }
              options={effectReferenceOptions}
              emptyMessage="No on-hit effects configured."
              onInspectValue={focusEffectReference}
            />
          </>
        );
      }
      case "usable":
        return (
          <>
            <div className="form-grid">
              <SelectField
                label="Subtype"
                value={fragment.subtype}
                onChange={(value) =>
                  updateSelectedFragment("usable", (current) => ({ ...current, subtype: value }))
                }
                options={workspace.catalogs.knownSubtypes}
              />
              <NumberField
                label="Use time"
                value={fragment.use_time}
                onChange={(value) =>
                  updateSelectedFragment("usable", (current) => ({
                    ...current,
                    use_time: value,
                  }))
                }
                step={0.1}
              />
              <NumberField
                label="Uses"
                value={fragment.uses}
                onChange={(value) =>
                  updateSelectedFragment("usable", (current) => ({ ...current, uses: value }))
                }
                min={1}
              />
            </div>
            <div className="toggle-grid">
              <CheckboxField
                label="Consume on use"
                value={fragment.consume_on_use}
                onChange={(value) =>
                  updateSelectedFragment("usable", (current) => ({
                    ...current,
                    consume_on_use: value,
                  }))
                }
              />
            </div>
            <ChipListEditor
              label="Effect ids"
              hint={issueHints.usableEffects}
              values={fragment.effect_ids}
              onChange={(value) =>
                updateSelectedFragment("usable", (current) => ({
                  ...current,
                  effect_ids: dedupeStrings(value),
                }))
              }
              options={effectReferenceOptions}
              emptyMessage="No use effects configured."
              onInspectValue={focusEffectReference}
            />
          </>
        );
      case "crafting": {
        const recipe = ensureCraftingRecipe(fragment);
        return (
          <>
            <div className="form-grid">
              <NumberField
                label="Craft time"
                value={recipe.time}
                onChange={(value) =>
                  updateSelectedFragment("crafting", (current) => ({
                    ...current,
                    crafting_recipe: {
                      ...ensureCraftingRecipe(current),
                      time: value,
                    },
                  }))
                }
                min={0}
              />
            </div>
            <div className="form-grid">
              <ItemAmountEditor
                label="Recipe materials"
                hint={
                  issueHints.craftingRecipeMaterials ??
                  "Pick item ids and quantities for crafting."
                }
                values={recipe.materials}
                onChange={(value) =>
                  updateSelectedFragment("crafting", (current) => ({
                    ...current,
                    crafting_recipe: {
                      ...ensureCraftingRecipe(current),
                      materials: value,
                    },
                  }))
                }
                itemOptions={itemReferenceOptions}
                emptyMessage="No crafting materials configured."
                onInspectItem={focusItemReference}
              />
              <ItemAmountEditor
                label="Deconstruct yield"
                hint={
                  issueHints.deconstructYield ??
                  "Pick item ids and quantities yielded by deconstruction."
                }
                values={fragment.deconstruct_yield}
                onChange={(value) =>
                  updateSelectedFragment("crafting", (current) => ({
                    ...current,
                    deconstruct_yield: value,
                  }))
                }
                itemOptions={itemReferenceOptions}
                emptyMessage="No deconstruct yield configured."
                onInspectItem={focusItemReference}
              />
            </div>
          </>
        );
      }
      case "passive_effects":
        return (
          <ChipListEditor
            label="Effect ids"
            values={fragment.effect_ids}
            onChange={(value) =>
              updateSelectedFragment("passive_effects", (current) => ({
                ...current,
                effect_ids: dedupeStrings(value),
              }))
            }
            options={effectReferenceOptions}
            emptyMessage="No passive effects configured."
            onInspectValue={focusEffectReference}
          />
        );
      default:
        return null;
    }
  }

  function openUsageSource(entry: ReferenceUsageEntry) {
    const key = documentKeyByItemId[String(entry.sourceItemId)];
    if (!key) {
      onStatusChange(`Source item ${entry.sourceItemId} is not available in current workspace.`);
      return;
    }
    setSelectedKey(key);
    onStatusChange(`Opened source item ${entry.sourceItemId} from Used By.`);
  }

  function renderValidationInspector() {
    if (!selectedDocument) {
      return (
        <div className="workspace-empty settings-empty-inline">
          <p>Select an item to inspect its validation state.</p>
        </div>
      );
    }

    if (selectedIssues.length === 0) {
      return (
        <div className="workspace-empty settings-empty-inline">
          <Badge tone="success">Clean</Badge>
          <p>No validation issues for the current item.</p>
        </div>
      );
    }

    return (
      <div className="issue-list">
        {selectedIssues.map((issue, index) => (
          <article className={`issue issue-${issue.severity}`} key={`${issue.field}-${index}`}>
            <div className="issue-head">
              <Badge tone={issue.severity === "error" ? "danger" : "warning"}>
                {issue.severity}
              </Badge>
              <strong>{issue.field}</strong>
              {issue.scope ? <Badge tone="muted">{issue.scope}</Badge> : null}
              {issue.nodeId ? <Badge tone="accent">{issue.nodeId}</Badge> : null}
              {issue.edgeKey ? <Badge tone="muted">{issue.edgeKey}</Badge> : null}
            </div>
            <p>{issue.message}</p>
          </article>
        ))}
      </div>
    );
  }

  function renderReferenceInspector() {
    return (
      <>
        {focusedItemPreview ? (
          <div className="issue-list">
            <article className="issue">
              <div className="issue-head">
                <Badge tone="accent">item</Badge>
                <strong>
                  {focusedItemPreview.id} · {focusedItemPreview.name || "Unnamed item"}
                </strong>
              </div>
              <p>
                value {focusedItemPreview.value} · weight {focusedItemPreview.weight}
              </p>
              <div className="row-badges">
                {focusedItemPreview.derivedTags.map((tag) => (
                  <Badge key={`focus-item-tag-${tag}`} tone="muted">
                    {tag}
                  </Badge>
                ))}
                {focusedItemPreview.keyFragments.slice(0, 4).map((summary) => (
                  <Badge key={`focus-item-frag-${summary}`} tone="accent">
                    {summary}
                  </Badge>
                ))}
              </div>
            </article>
          </div>
        ) : null}

        {focusedEffectPreview ? (
          <div className="issue-list">
            <article className="issue">
              <div className="issue-head">
                <Badge tone="success">effect</Badge>
                <strong>
                  {focusedEffectPreview.id} · {focusedEffectPreview.name || "Unnamed effect"}
                </strong>
              </div>
              <p>
                {focusedEffectPreview.category} · duration {focusedEffectPreview.duration} · stack{" "}
                {focusedEffectPreview.stackMode}
              </p>
              {focusedEffectPreview.description ? <p>{focusedEffectPreview.description}</p> : null}
              {Object.keys(focusedEffectPreview.resourceDeltas).length > 0 ? (
                <div className="row-badges">
                  {Object.entries(focusedEffectPreview.resourceDeltas).map(([key, amount]) => (
                    <Badge key={`focus-effect-delta-${key}`} tone="accent">
                      {key} {amount >= 0 ? "+" : ""}
                      {amount}
                    </Badge>
                  ))}
                </div>
              ) : null}
            </article>
          </div>
        ) : null}

        {referenceFocus == null ? (
          <div className="workspace-empty settings-empty-inline">
            <p>Click Inspect in any reference field to view details and reverse usage.</p>
          </div>
        ) : focusedUsageEntries.length > 0 ? (
          <div className="issue-list">
            {focusedUsageEntries.map((entry, index) => (
              <article
                className="issue"
                key={`${entry.sourceItemId}-${entry.fragmentKind}-${entry.path}-${index}`}
              >
                <div className="issue-head">
                  <Badge tone="warning">{entry.fragmentKind}</Badge>
                  <strong>
                    #{entry.sourceItemId} · {entry.sourceItemName || "Unnamed item"}
                  </strong>
                </div>
                <p>
                  {entry.note} · {entry.path}
                </p>
                <button
                  type="button"
                  className="toolbar-button"
                  onClick={() => openUsageSource(entry)}
                >
                  Open source item
                </button>
              </article>
            ))}
          </div>
        ) : (
          <div className="workspace-empty settings-empty-inline">
            <Badge tone="success">No usage</Badge>
            <p>No reverse references found for this entry in the current workspace.</p>
          </div>
        )}
      </>
    );
  }

  function renderCatalogInspector() {
    return (
      <div className="settings-body">
        <div className="row-badges">
          <Badge tone="accent">{workspace.catalogs.fragmentKinds.length} fragment kinds</Badge>
          <Badge tone="muted">{workspace.catalogs.effectIds.length} effects</Badge>
          <Badge tone="muted">{workspace.catalogs.itemIds.length} item ids</Badge>
        </div>
        <div className="row-badges">
          {workspace.catalogs.fragmentKinds.slice(0, 8).map((kind) => (
            <Badge key={kind} tone="muted">
              {kind}
            </Badge>
          ))}
          {workspace.catalogs.fragmentKinds.length > 8 ? (
            <Badge tone="muted">+{workspace.catalogs.fragmentKinds.length - 8} more</Badge>
          ) : null}
        </div>
        <div className="row-badges">
          {workspace.bootstrap.editorDomains.map((domain) => (
            <Badge key={domain} tone="accent">
              {domain}
            </Badge>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="workspace workspace-items">
      <Toolbar actions={actions}>
        <div className="toolbar-summary">
          <Badge tone="accent">{workspace.itemCount} files</Badge>
          <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>{dirtyCount} dirty</Badge>
          <Badge tone={totalIssues.errors > 0 ? "danger" : "success"}>
            {totalIssues.errors} errors
          </Badge>
          <Badge tone={totalIssues.warnings > 0 ? "warning" : "muted"}>
            {totalIssues.warnings} warnings
          </Badge>
        </div>
      </Toolbar>

      <div
        className={`workspace-grid workspace-grid-items ${indexVisible ? "" : "workspace-grid-left-hidden"}`.trim()}
      >
        {indexVisible ? (
        <aside className="column workspace-index-column">
          <PanelSection label="Item index" title="Project items">
            <div className="filter-stack">
              <TextField
                label="Search"
                value={searchText}
                onChange={setSearchText}
                placeholder="Filter by id, name, tag, or fragment"
              />
              <SelectField
                label="Tag filter"
                value={tagFilter}
                onChange={setTagFilter}
                options={["weapon", "armor", "accessory", "usable", "material_or_misc"]}
              />
              <SelectField
                label="Fragment filter"
                value={fragmentFilter}
                onChange={setFragmentFilter}
                options={workspace.catalogs.fragmentKinds}
              />
            </div>

            <div className="item-list">
              {filteredDocuments.map((document) => {
                const counts = getIssueCounts(document.validation);
                const tags = inferItemTags(document.item);
                return (
                  <button
                    key={document.documentKey}
                    type="button"
                    className={`item-row ${
                      document.documentKey === selectedKey ? "item-row-active" : ""
                    }`}
                    onClick={() => setSelectedKey(document.documentKey)}
                  >
                    <div className="item-row-top">
                      <strong>{document.item.name || "Unnamed item"}</strong>
                      {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                    </div>
                    <p>
                      #{document.item.id} · {getPrimaryTag(document.item)} ·{" "}
                      {getEconomyRarity(document.item)}
                    </p>
                    <div className="row-badges">
                      {tags.map((tag) => (
                        <Badge key={`${document.documentKey}-${tag}`} tone="muted">
                          {formatTag(tag)}
                        </Badge>
                      ))}
                      {counts.errorCount > 0 ? (
                        <Badge tone="danger">{counts.errorCount} errors</Badge>
                      ) : null}
                      {counts.warningCount > 0 ? (
                        <Badge tone="warning">{counts.warningCount} warnings</Badge>
                      ) : null}
                    </div>
                  </button>
                );
              })}
            </div>
          </PanelSection>
        </aside>
        ) : null}

        <main className="column column-main">
          {selectedDocument ? (
            <>
              <PanelSection label="Selection" title={selectedDocument.item.name || "Unnamed item"}>
                <div className="stats-grid">
                  <article className="stat-card">
                    <span>ID</span>
                    <strong>{selectedDocument.item.id}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Source</span>
                    <strong>{selectedDocument.relativePath}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Status</span>
                    <strong>{selectedDocument.dirty ? "Unsaved" : "Synced"}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Validation</span>
                    <strong>
                      {selectedCounts.errorCount}E / {selectedCounts.warningCount}W
                    </strong>
                  </article>
                </div>
                <div className="row-badges">
                  {selectedTags.map((tag) => (
                    <Badge key={`selected-${tag}`} tone="accent">
                      {formatTag(tag)}
                    </Badge>
                  ))}
                  {selectedDocument.item.fragments.map((fragment) => (
                    <Badge key={`selected-kind-${fragment.kind}`} tone="muted">
                      {fragment.kind}
                    </Badge>
                  ))}
                </div>
              </PanelSection>

              <PanelSection label="Workflow" title="Templates and copy">
                <div className="form-grid">
                  <SelectField
                    label="New from template"
                    value={newTemplateId}
                    onChange={(value) => setNewTemplateId(value as ItemTemplateId)}
                    options={templateOptions}
                    allowBlank={false}
                  />
                  <div>
                    <button
                      type="button"
                      className="toolbar-button toolbar-accent"
                      onClick={createDraftFromTemplate}
                      disabled={busy}
                    >
                      New From Template
                    </button>
                  </div>
                  <div>
                    <button
                      type="button"
                      className="toolbar-button"
                      onClick={duplicateCurrentItem}
                      disabled={busy || !selectedDocument}
                    >
                      Duplicate Current Item
                    </button>
                  </div>
                </div>
                <div className="form-grid">
                  <SelectField
                    label="Clone fragment set from"
                    value={cloneSourceKey}
                    onChange={setCloneSourceKey}
                    options={cloneSourceOptions}
                    hint="Copies fragment list only. Keeps current id, name, and base fields."
                  />
                  <div>
                    <button
                      type="button"
                      className="toolbar-button"
                      onClick={cloneFragmentSetFromSource}
                      disabled={busy || !selectedDocument || !cloneSourceKey}
                    >
                      Clone Fragment Set
                    </button>
                  </div>
                </div>
              </PanelSection>

              <PanelSection label="Basics" title="Shared base properties">
                <div className="form-grid">
                  <NumberField
                    label="ID"
                    value={selectedDocument.item.id}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, id: Math.max(0, value) }))
                    }
                    min={1}
                  />
                  <TextField
                    label="Name"
                    value={selectedDocument.item.name}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, name: value }))}
                  />
                  <TextField
                    label="Icon path"
                    value={selectedDocument.item.icon_path}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, icon_path: value }))
                    }
                    placeholder="res://assets/..."
                  />
                  <NumberField
                    label="Value"
                    value={selectedDocument.item.value}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, value }))}
                    min={0}
                  />
                  <NumberField
                    label="Weight"
                    value={selectedDocument.item.weight}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, weight: value }))}
                    step={0.1}
                    min={0}
                  />
                </div>

                <TextareaField
                  label="Description"
                  value={selectedDocument.item.description}
                  onChange={(value) =>
                    updateSelectedItem((item) => ({ ...item, description: value }))
                  }
                />
              </PanelSection>

              <PanelSection label="Fragments" title="Composable item behavior">
                <div className="form-grid">
                  <SelectField
                    label="Add fragment"
                    value={addFragmentKind}
                    onChange={setAddFragmentKind}
                    options={nextFragmentKinds}
                  />
                </div>
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={addFragment}
                  disabled={!addFragmentKind}
                >
                  Add Fragment
                </button>

                <div className="item-list">
                  {selectedDocument.item.fragments.map((fragment) => {
                    const collapsed = Boolean(
                      collapsedFragments[`${selectedKey}:${fragment.kind}`],
                    );
                    const summaryBadges = summarizeFragment(
                      fragment,
                      itemLabelLookup,
                      effectLabelLookup,
                    );
                    return (
                      <article className="panel panel-compact" key={fragment.kind}>
                        <span className="section-label">Fragment</span>
                        <div className="panel-body">
                          <div className="item-row-top">
                            <div className="fragment-card-main">
                              <h3 className="panel-title">{fragment.kind}</h3>
                              {summaryBadges.length > 0 ? (
                                <div className="row-badges fragment-summary">
                                  {summaryBadges.map((badge, index) => (
                                    <Badge
                                      key={`${fragment.kind}-summary-${index}`}
                                      tone={badge.tone}
                                    >
                                      {badge.label}
                                    </Badge>
                                  ))}
                                </div>
                              ) : null}
                            </div>
                            <div className="row-badges">
                              <button
                                type="button"
                                className="toolbar-button"
                                onClick={() => toggleFragment(fragment.kind)}
                              >
                                {collapsed ? "Expand" : "Collapse"}
                              </button>
                              <button
                                type="button"
                                className="toolbar-button toolbar-danger"
                                onClick={() => deleteFragment(fragment.kind)}
                              >
                                Remove
                              </button>
                            </div>
                          </div>
                          {!collapsed ? renderFragmentEditor(fragment) : null}
                        </div>
                      </article>
                    );
                  })}
                </div>
              </PanelSection>

              <PanelSection label="Debug" title="Extra JSON">
                <JsonField
                  label="Top-level extra fields"
                  hint="Reserved for debugging. Known schema fields stay in the structured editor above."
                  value={extraJsonDraft}
                  onChange={(value) => {
                    setExtraJsonDraft(value);
                    try {
                      const parsed = parseExtraJson(value);
                      if (parsed == null) {
                        return;
                      }
                      updateSelectedItem((item) => mergeExtraFields(item, parsed));
                    } catch {
                      return;
                    }
                  }}
                />
              </PanelSection>
            </>
          ) : (
            <PanelSection label="Selection" title="No item selected">
              <div className="workspace-empty">
                <p>Select an item from the left panel or create a new draft.</p>
              </div>
            </PanelSection>
          )}
        </main>

        <aside className="column workspace-inspector-column">
          <PanelSection
            label="Inspector"
            title={
              sidebarMode === "validation"
                ? "Validation"
                : sidebarMode === "reference"
                  ? "Reference"
                  : "Catalogs"
            }
            compact
            summary={
              <div className="segmented-control">
                <button
                  type="button"
                  className={`segmented-control-item ${sidebarMode === "validation" ? "segmented-control-item-active" : ""}`}
                  onClick={() => setSidebarMode("validation")}
                >
                  Validation
                </button>
                <button
                  type="button"
                  className={`segmented-control-item ${sidebarMode === "reference" ? "segmented-control-item-active" : ""}`}
                  onClick={() => setSidebarMode("reference")}
                >
                  Reference
                </button>
                <button
                  type="button"
                  className={`segmented-control-item ${sidebarMode === "catalogs" ? "segmented-control-item-active" : ""}`}
                  onClick={() => setSidebarMode("catalogs")}
                >
                  Catalogs
                </button>
              </div>
            }
          >
            {sidebarMode === "validation"
              ? renderValidationInspector()
              : sidebarMode === "reference"
                ? renderReferenceInspector()
                : renderCatalogInspector()}
          </PanelSection>
        </aside>
      </div>
    </div>
  );
}
