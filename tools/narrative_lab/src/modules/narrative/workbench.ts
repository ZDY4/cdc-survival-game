import type {
  NarrativePanelId,
  NarrativePanelLayoutItem,
  NarrativeWorkspaceLayout,
} from "../../types";

export const NARRATIVE_LAYOUT_VERSION = 1;
export const NARRATIVE_GRID_COLUMNS = 12;
export const NARRATIVE_CORE_PANELS = new Set<NarrativePanelId>([
  "document_overview",
  "ai_task",
  "ai_review",
]);

export const NARRATIVE_PANEL_ORDER: NarrativePanelId[] = [
  "document_overview",
  "ai_task",
  "ai_review",
  "manual_editor",
  "metadata",
  "workspace_context",
  "sync_tools",
  "provider_settings",
  "structuring_bundle",
  "prompt_debug",
];

const DEFAULT_ITEMS: NarrativePanelLayoutItem[] = [
  { panelId: "document_overview", x: 0, y: 0, w: 4, h: 5, minW: 3, minH: 4 },
  { panelId: "ai_task", x: 4, y: 0, w: 8, h: 7, minW: 5, minH: 6 },
  { panelId: "ai_review", x: 0, y: 5, w: 12, h: 8, minW: 6, minH: 6 },
  { panelId: "manual_editor", x: 0, y: 13, w: 8, h: 11, minW: 6, minH: 8 },
  { panelId: "metadata", x: 8, y: 13, w: 4, h: 9, minW: 4, minH: 6 },
  { panelId: "workspace_context", x: 0, y: 24, w: 4, h: 9, minW: 4, minH: 6 },
  { panelId: "sync_tools", x: 4, y: 24, w: 4, h: 10, minW: 4, minH: 7 },
  { panelId: "provider_settings", x: 8, y: 24, w: 4, h: 7, minW: 4, minH: 5 },
  { panelId: "structuring_bundle", x: 0, y: 34, w: 8, h: 8, minW: 5, minH: 6 },
  { panelId: "prompt_debug", x: 8, y: 34, w: 4, h: 7, minW: 4, minH: 5 },
];

const DEFAULT_COLLAPSED: NarrativePanelId[] = [
  "workspace_context",
  "sync_tools",
  "provider_settings",
  "structuring_bundle",
  "prompt_debug",
];

export function defaultNarrativeLayout(): NarrativeWorkspaceLayout {
  return {
    version: NARRATIVE_LAYOUT_VERSION,
    items: DEFAULT_ITEMS.map((item) => ({ ...item })),
    collapsedPanels: [...DEFAULT_COLLAPSED],
    hiddenPanels: [],
  };
}

export function normalizeNarrativeLayout(
  layout: NarrativeWorkspaceLayout | null | undefined,
): NarrativeWorkspaceLayout {
  const fallback = defaultNarrativeLayout();
  if (!layout) {
    return fallback;
  }

  const itemMap = new Map<NarrativePanelId, NarrativePanelLayoutItem>();
  for (const rawItem of layout.items ?? []) {
    if (!isNarrativePanelId(rawItem.panelId) || itemMap.has(rawItem.panelId)) {
      continue;
    }
    itemMap.set(rawItem.panelId, {
      panelId: rawItem.panelId,
      x: clampToGrid(rawItem.x),
      y: Math.max(0, rawItem.y),
      w: Math.max(rawItem.minW ?? 1, Math.min(NARRATIVE_GRID_COLUMNS, rawItem.w)),
      h: Math.max(rawItem.minH ?? 1, rawItem.h),
      minW: rawItem.minW,
      minH: rawItem.minH,
    });
  }

  const items = fallback.items.map((defaultItem) => {
    const saved = itemMap.get(defaultItem.panelId);
    if (!saved) {
      return { ...defaultItem };
    }
    return {
      ...defaultItem,
      ...saved,
      w: Math.max(defaultItem.minW ?? 1, Math.min(NARRATIVE_GRID_COLUMNS, saved.w)),
      h: Math.max(defaultItem.minH ?? 1, saved.h),
      minW: saved.minW ?? defaultItem.minW,
      minH: saved.minH ?? defaultItem.minH,
    };
  });

  return {
    version: layout.version || NARRATIVE_LAYOUT_VERSION,
    items,
    collapsedPanels: dedupePanels(layout.collapsedPanels),
    hiddenPanels: dedupePanels(layout.hiddenPanels).filter(
      (panelId) => !NARRATIVE_CORE_PANELS.has(panelId),
    ),
  };
}

export function sortLayoutItems(items: NarrativePanelLayoutItem[]): NarrativePanelLayoutItem[] {
  return [...items].sort((left, right) => {
    if (left.y !== right.y) {
      return left.y - right.y;
    }
    if (left.x !== right.x) {
      return left.x - right.x;
    }
    return NARRATIVE_PANEL_ORDER.indexOf(left.panelId) - NARRATIVE_PANEL_ORDER.indexOf(right.panelId);
  });
}

export function buildStackedLayout(
  items: NarrativePanelLayoutItem[],
  hiddenPanels: NarrativePanelId[],
): NarrativePanelLayoutItem[] {
  let nextY = 0;
  return sortLayoutItems(items)
    .filter((item) => !hiddenPanels.includes(item.panelId))
    .map((item) => {
      const stacked = {
        ...item,
        x: 0,
        y: nextY,
        w: NARRATIVE_GRID_COLUMNS,
      };
      nextY += item.h;
      return stacked;
    });
}

export function togglePanelValue(
  values: NarrativePanelId[],
  panelId: NarrativePanelId,
  enabled: boolean,
): NarrativePanelId[] {
  const next = new Set(values);
  if (enabled) {
    next.add(panelId);
  } else {
    next.delete(panelId);
  }
  return [...next];
}

export function isNarrativePanelId(value: string): value is NarrativePanelId {
  return NARRATIVE_PANEL_ORDER.includes(value as NarrativePanelId);
}

function dedupePanels(values: NarrativePanelId[] | string[] | undefined): NarrativePanelId[] {
  const result: NarrativePanelId[] = [];
  for (const value of values ?? []) {
    if (!isNarrativePanelId(value) || result.includes(value)) {
      continue;
    }
    result.push(value);
  }
  return result;
}

function clampToGrid(value: number) {
  return Math.max(0, Math.min(NARRATIVE_GRID_COLUMNS - 1, value));
}
