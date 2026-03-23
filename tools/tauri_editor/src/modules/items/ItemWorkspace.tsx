import { useDeferredValue, useEffect, useState } from "react";
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
import { ValidationPanel } from "../../components/ValidationPanel";
import { invokeCommand } from "../../lib/tauri";
import type {
  CraftingFragment,
  CraftingRecipe,
  ItemAmount,
  ItemDefinition,
  ItemDocumentPayload,
  ItemFragment,
  ItemWorkspacePayload,
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
};

type ItemTag = "weapon" | "armor" | "accessory" | "usable" | "material_or_misc";

type FragmentOf<K extends ItemFragment["kind"]> = Extract<ItemFragment, { kind: K }>;

const ARMOR_SLOTS = new Set(["head", "body", "hands", "legs", "feet", "back"]);
const ACCESSORY_SLOTS = new Set(["accessory", "accessory_1", "accessory_2"]);

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

type SummaryBadge = {
  label: string;
  tone: "muted" | "accent" | "warning" | "success";
};

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
};

function ChipListEditor({
  label,
  hint,
  values,
  options,
  onChange,
  allowCustom = true,
  emptyMessage = "Nothing selected yet.",
}: ChipListEditorProps) {
  const availableOptions = options.filter((option) => !values.includes(option.value));
  const [selectedOption, setSelectedOption] = useState(availableOptions[0]?.value ?? "");
  const [customValue, setCustomValue] = useState("");

  useEffect(() => {
    if (!selectedOption || values.includes(selectedOption)) {
      setSelectedOption(availableOptions[0]?.value ?? "");
    }
  }, [availableOptions, selectedOption, values]);

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
          <select
            className="field-input"
            value={selectedOption}
            onChange={(event) => setSelectedOption(event.target.value)}
          >
            <option value="">Select option</option>
            {availableOptions.map((option) => (
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
};

function ItemAmountEditor({
  label,
  hint,
  values,
  itemOptions,
  onChange,
  emptyMessage = "No item amounts configured.",
}: ItemAmountEditorProps) {
  const [draftItemId, setDraftItemId] = useState(itemOptions[0]?.value ?? "");
  const [draftCount, setDraftCount] = useState("1");

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
        <div className="picker-controls picker-controls-wide">
          <select
            className="field-input"
            value={draftItemId}
            onChange={(event) => setDraftItemId(event.target.value)}
          >
            <option value="">Select item id</option>
            {itemOptions.map((option) => (
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
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
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
    const selected = documents.find((document) => document.documentKey === selectedKey);
    if (!selected || !canPersist) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void invokeCommand<ValidationIssue[]>("validate_item_document", {
        item: selected.item,
      })
        .then((issues) => {
          setDocuments((current) =>
            current.map((document) =>
              document.documentKey === selectedKey
                ? { ...document, validation: issues }
                : document,
            ),
          );
        })
        .catch(() => {});
    }, 180);

    return () => window.clearTimeout(timeoutId);
  }, [canPersist, documents, selectedKey]);

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

  const selectedDocument =
    documents.find((document) => document.documentKey === selectedKey) ?? null;
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
    const nextId =
      documents.reduce((maxId, document) => Math.max(maxId, document.item.id), 1000) + 1;
    const draft: EditableItemDocument = {
      documentKey: `draft-${Date.now()}`,
      originalId: nextId,
      fileName: `${nextId}.json`,
      relativePath: `data/items/${nextId}.json`,
      item: createDefaultItem(nextId),
      validation: [],
      savedSnapshot: "",
      dirty: true,
      isDraft: true,
    };

    setDocuments((current) => [draft, ...current]);
    setSelectedKey(draft.documentKey);
    onStatusChange(`Created draft item ${nextId}.`);
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
  const nextFragmentKinds = selectedDocument
    ? availableFragmentKinds(selectedDocument.item, workspace.catalogs.fragmentKinds)
    : [];
  const itemReferenceOptions = buildItemReferenceOptions(documents);
  const effectReferenceOptions = workspace.catalogs.effectEntries;
  const equipmentSlotOptions = buildStringOptions(workspace.catalogs.equipmentSlots);
  const itemLabelLookup = buildOptionLabelLookup(itemReferenceOptions);
  const effectLabelLookup = buildOptionLabelLookup(effectReferenceOptions);

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
                hint={`Known slots: ${workspace.catalogs.equipmentSlots.join(", ")}`}
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
                values={fragment.equip_effect_ids}
                onChange={(value) =>
                  updateSelectedFragment("equip", (current) => ({
                    ...current,
                    equip_effect_ids: dedupeStrings(value),
                  }))
                }
                options={effectReferenceOptions}
                emptyMessage="No equip effects configured."
              />
              <ChipListEditor
                label="Unequip effects"
                values={fragment.unequip_effect_ids}
                onChange={(value) =>
                  updateSelectedFragment("equip", (current) => ({
                    ...current,
                    unequip_effect_ids: dedupeStrings(value),
                  }))
                }
                options={effectReferenceOptions}
                emptyMessage="No unequip effects configured."
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
              hint="Use item_id=count per line."
              values={fragment.repair_materials}
              onChange={(value) =>
                updateSelectedFragment("durability", (current) => ({
                  ...current,
                  repair_materials: value,
                }))
              }
              itemOptions={itemReferenceOptions}
              emptyMessage="No repair materials configured."
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
                value={ammoTypeValue}
                onChange={(value) =>
                  updateSelectedFragment("weapon", (current) => ({
                    ...current,
                    ammo_type: value ? Number.parseInt(value, 10) : null,
                  }))
                }
                options={itemReferenceOptions}
              />
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
              values={fragment.on_hit_effect_ids}
              onChange={(value) =>
                updateSelectedFragment("weapon", (current) => ({
                  ...current,
                  on_hit_effect_ids: dedupeStrings(value),
                }))
              }
              options={effectReferenceOptions}
              emptyMessage="No on-hit effects configured."
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
              values={fragment.effect_ids}
              onChange={(value) =>
                updateSelectedFragment("usable", (current) => ({
                  ...current,
                  effect_ids: dedupeStrings(value),
                }))
              }
              options={effectReferenceOptions}
              emptyMessage="No use effects configured."
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
                hint="Pick item ids and quantities for crafting."
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
              />
              <ItemAmountEditor
                label="Deconstruct yield"
                hint="Pick item ids and quantities yielded by deconstruction."
                values={fragment.deconstruct_yield}
                onChange={(value) =>
                  updateSelectedFragment("crafting", (current) => ({
                    ...current,
                    deconstruct_yield: value,
                  }))
                }
                itemOptions={itemReferenceOptions}
                emptyMessage="No deconstruct yield configured."
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
          />
        );
      default:
        return null;
    }
  }

  return (
    <div className="workspace">
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

      <div className="workspace-grid">
        <aside className="column">
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
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>Select an item from the left panel or create a new draft.</p>
              </div>
            </PanelSection>
          )}
        </main>

        <aside className="column">
          <ValidationPanel issues={selectedIssues} />

          <PanelSection label="Catalogs" title="Fragment authoring context" compact>
            <div className="row-badges">
              <Badge tone="accent">{workspace.catalogs.fragmentKinds.length} fragment kinds</Badge>
              <Badge tone="muted">{workspace.catalogs.effectIds.length} effects</Badge>
              <Badge tone="muted">{workspace.catalogs.itemIds.length} item ids</Badge>
            </div>
            <ul className="domain-list">
              {workspace.catalogs.fragmentKinds.map((kind) => (
                <li key={kind}>{kind}</li>
              ))}
            </ul>
          </PanelSection>

          <PanelSection label="Domains" title="Why this shell exists" compact>
            <ul className="domain-list">
              {workspace.bootstrap.editorDomains.map((domain) => (
                <li key={domain}>{domain}</li>
              ))}
            </ul>
          </PanelSection>
        </aside>
      </div>
    </div>
  );
}
