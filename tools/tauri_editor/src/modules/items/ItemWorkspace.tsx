import { useDeferredValue, useEffect, useState } from "react";
import { Badge } from "../../components/Badge";
import {
  CheckboxField,
  JsonField,
  NumberField,
  NumberMapField,
  SelectField,
  TextField,
  TextareaField,
  TokenListField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { ValidationPanel } from "../../components/ValidationPanel";
import { invokeCommand } from "../../lib/tauri";
import type {
  ArmorData,
  ConsumableData,
  ItemData,
  ItemDocumentPayload,
  ItemWorkspacePayload,
  SaveItemsResult,
  ValidationIssue,
  WeaponData,
} from "../../types";
import { createDefaultItem, KNOWN_ITEM_KEYS } from "./defaults";

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

function hydrateDocuments(documents: ItemDocumentPayload[]): EditableItemDocument[] {
  return documents.map((document) => ({
    ...document,
    savedSnapshot: JSON.stringify(document.item),
    dirty: false,
    isDraft: false,
  }));
}

function getDirtyState(item: ItemData, savedSnapshot: string): boolean {
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

function getExtraFields(item: ItemData): Record<string, unknown> {
  const extra: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(item)) {
    if (!KNOWN_ITEM_KEYS.has(key)) {
      extra[key] = value;
    }
  }
  return extra;
}

function mergeExtraFields(item: ItemData, extra: Record<string, unknown>): ItemData {
  const next: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(item)) {
    if (KNOWN_ITEM_KEYS.has(key)) {
      next[key] = value;
    }
  }
  for (const [key, value] of Object.entries(extra)) {
    next[key] = value;
  }
  return next as ItemData;
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

function ensureWeaponData(item: ItemData): WeaponData {
  return {
    damage: item.weapon_data?.damage ?? 0,
    attack_speed: item.weapon_data?.attack_speed ?? 1,
    range: item.weapon_data?.range ?? 1,
    stamina_cost: item.weapon_data?.stamina_cost ?? 0,
    crit_chance: item.weapon_data?.crit_chance ?? 0,
    crit_multiplier: item.weapon_data?.crit_multiplier ?? 1.5,
  };
}

function ensureArmorData(item: ItemData): ArmorData {
  return {
    defense: item.armor_data?.defense ?? 0,
    damage_reduction: item.armor_data?.damage_reduction ?? 0,
  };
}

function ensureConsumableData(item: ItemData): ConsumableData {
  return {
    health_restore: item.consumable_data?.health_restore ?? 0,
    stamina_restore: item.consumable_data?.stamina_restore ?? 0,
    duration: item.consumable_data?.duration ?? 0,
  };
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
  const [typeFilter, setTypeFilter] = useState("");
  const [busy, setBusy] = useState(false);
  const [extraJsonDraft, setExtraJsonDraft] = useState("{}");
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
  }, [workspace]);

  useEffect(() => {
    const selected = documents.find((document) => document.documentKey === selectedKey);
    setExtraJsonDraft(JSON.stringify(getExtraFields(selected?.item ?? ({} as ItemData)), null, 2));
  }, [documents, selectedKey]);

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
    if (typeFilter && document.item.type !== typeFilter) {
      return false;
    }
    if (!deferredSearch.trim()) {
      return true;
    }
    const haystack =
      `${document.item.id} ${document.item.name} ${document.item.type}`.toLowerCase();
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

  function updateSelectedItem(transform: (item: ItemData) => ItemData) {
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
                placeholder="Filter by id, name, or type"
              />
              <SelectField
                label="Type filter"
                value={typeFilter}
                onChange={setTypeFilter}
                options={workspace.catalogs.itemTypes}
              />
            </div>

            <div className="item-list">
              {filteredDocuments.map((document) => {
                const counts = getIssueCounts(document.validation);
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
                      #{document.item.id} · {document.item.type || "untyped"} ·{" "}
                      {document.item.rarity || "common"}
                    </p>
                    <div className="row-badges">
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
              </PanelSection>

              <PanelSection label="Basics" title="Core item fields">
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
                  <SelectField
                    label="Type"
                    value={selectedDocument.item.type}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, type: value }))}
                    options={workspace.catalogs.itemTypes}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Subtype"
                    value={selectedDocument.item.subtype}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, subtype: value }))
                    }
                    options={workspace.catalogs.subtypes}
                  />
                  <SelectField
                    label="Rarity"
                    value={selectedDocument.item.rarity}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, rarity: value }))
                    }
                    options={workspace.catalogs.rarities}
                    allowBlank={false}
                  />
                  <TextField
                    label="Icon path"
                    value={selectedDocument.item.icon_path}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, icon_path: value }))
                    }
                    placeholder="res://assets/..."
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

              <PanelSection label="Economy & inventory" title="Rules and persistence fields">
                <div className="form-grid">
                  <NumberField
                    label="Weight"
                    value={selectedDocument.item.weight}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, weight: value }))}
                    step={0.1}
                    min={0}
                  />
                  <NumberField
                    label="Value"
                    value={selectedDocument.item.value}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, value }))}
                  />
                  <NumberField
                    label="Max stack"
                    value={selectedDocument.item.max_stack}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, max_stack: value }))
                    }
                    min={1}
                  />
                  <NumberField
                    label="Level requirement"
                    value={selectedDocument.item.level_requirement}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, level_requirement: value }))
                    }
                    min={0}
                  />
                  <NumberField
                    label="Durability"
                    value={selectedDocument.item.durability}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, durability: value }))
                    }
                  />
                  <NumberField
                    label="Max durability"
                    value={selectedDocument.item.max_durability}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, max_durability: value }))
                    }
                  />
                </div>

                <div className="toggle-grid">
                  <CheckboxField
                    label="Stackable"
                    value={selectedDocument.item.stackable}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, stackable: value }))
                    }
                  />
                  <CheckboxField
                    label="Equippable"
                    value={selectedDocument.item.equippable}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, equippable: value }))
                    }
                  />
                  <CheckboxField
                    label="Usable"
                    value={selectedDocument.item.usable}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, usable: value }))
                    }
                  />
                  <CheckboxField
                    label="Repairable"
                    value={selectedDocument.item.repairable}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, repairable: value }))
                    }
                  />
                </div>
              </PanelSection>

              <PanelSection label="Equipment" title="Slot and type-specific payload">
                <div className="form-grid">
                  <SelectField
                    label="Slot"
                    value={selectedDocument.item.slot}
                    onChange={(value) => updateSelectedItem((item) => ({ ...item, slot: value }))}
                    options={workspace.catalogs.slots}
                  />
                </div>

                {selectedDocument.item.type === "weapon" ? (
                  <div className="form-grid">
                    <NumberField
                      label="Damage"
                      value={ensureWeaponData(selectedDocument.item).damage}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          weapon_data: { ...ensureWeaponData(item), damage: value },
                        }))
                      }
                    />
                    <NumberField
                      label="Attack speed"
                      value={ensureWeaponData(selectedDocument.item).attack_speed}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          weapon_data: { ...ensureWeaponData(item), attack_speed: value },
                        }))
                      }
                      step={0.1}
                    />
                    <NumberField
                      label="Range"
                      value={ensureWeaponData(selectedDocument.item).range}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          weapon_data: { ...ensureWeaponData(item), range: value },
                        }))
                      }
                    />
                    <NumberField
                      label="Stamina cost"
                      value={ensureWeaponData(selectedDocument.item).stamina_cost}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          weapon_data: { ...ensureWeaponData(item), stamina_cost: value },
                        }))
                      }
                    />
                    <NumberField
                      label="Crit chance"
                      value={ensureWeaponData(selectedDocument.item).crit_chance}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          weapon_data: { ...ensureWeaponData(item), crit_chance: value },
                        }))
                      }
                      step={0.01}
                    />
                    <NumberField
                      label="Crit multiplier"
                      value={ensureWeaponData(selectedDocument.item).crit_multiplier}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          weapon_data: { ...ensureWeaponData(item), crit_multiplier: value },
                        }))
                      }
                      step={0.1}
                    />
                  </div>
                ) : null}

                {selectedDocument.item.type === "armor" ? (
                  <div className="form-grid">
                    <NumberField
                      label="Defense"
                      value={ensureArmorData(selectedDocument.item).defense}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          armor_data: { ...ensureArmorData(item), defense: value },
                        }))
                      }
                    />
                    <NumberField
                      label="Damage reduction"
                      value={ensureArmorData(selectedDocument.item).damage_reduction}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          armor_data: { ...ensureArmorData(item), damage_reduction: value },
                        }))
                      }
                      step={0.01}
                    />
                  </div>
                ) : null}

                {selectedDocument.item.type === "consumable" ? (
                  <div className="form-grid">
                    <NumberField
                      label="Health restore"
                      value={ensureConsumableData(selectedDocument.item).health_restore}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          consumable_data: { ...ensureConsumableData(item), health_restore: value },
                        }))
                      }
                    />
                    <NumberField
                      label="Stamina restore"
                      value={ensureConsumableData(selectedDocument.item).stamina_restore}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          consumable_data: {
                            ...ensureConsumableData(item),
                            stamina_restore: value,
                          },
                        }))
                      }
                    />
                    <NumberField
                      label="Duration"
                      value={ensureConsumableData(selectedDocument.item).duration}
                      onChange={(value) =>
                        updateSelectedItem((item) => ({
                          ...item,
                          consumable_data: { ...ensureConsumableData(item), duration: value },
                        }))
                      }
                    />
                  </div>
                ) : null}
              </PanelSection>

              <PanelSection label="Effects" title="Bonuses and extensibility hooks">
                <div className="form-grid">
                  <TokenListField
                    label="Special effects"
                    values={selectedDocument.item.special_effects}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, special_effects: value }))
                    }
                    placeholder="One effect id per line"
                  />
                  <NumberMapField
                    label="Attribute bonuses"
                    value={selectedDocument.item.attributes_bonus}
                    onChange={(value) =>
                      updateSelectedItem((item) => ({ ...item, attributes_bonus: value }))
                    }
                  />
                </div>

                <JsonField
                  label="Extra JSON fields"
                  hint="Unknown fields stay editable here so migration work does not drop existing data."
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
