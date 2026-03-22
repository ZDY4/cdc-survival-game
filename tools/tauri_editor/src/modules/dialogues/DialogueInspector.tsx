import { Badge } from "../../components/Badge";
import {
  CheckboxField,
  TextField,
  TextareaField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import type { DialogueAction, DialogueData, DialogueNode, DialogueOption } from "../../types";
import {
  getDialogueEdgeTarget,
  getDialogueNode,
  renameDialogueNode,
  setDialogueNodeActions,
  setDialogueNodeOptions,
  setDialogueNodeStart,
  updateDialogueNode,
} from "./dialogueGraphAdapter";

type DialogueInspectorProps = {
  dialog: DialogueData;
  selectedNodeId: string | null;
  onDialogChange: (dialog: DialogueData) => void;
};

function CommonNodeFields({
  dialog,
  node,
  onDialogChange,
}: {
  dialog: DialogueData;
  node: DialogueNode;
  onDialogChange: (dialog: DialogueData) => void;
}) {
  return (
    <div className="form-grid">
      <TextField
        label="Node ID"
        value={node.id}
        onChange={(value) => onDialogChange(renameDialogueNode(dialog, node.id, value))}
      />
      <TextField
        label="Title"
        value={node.title ?? ""}
        onChange={(value) =>
          onDialogChange(updateDialogueNode(dialog, node.id, (current) => ({ ...current, title: value })))
        }
      />
      <div className="field">
        <span className="field-label">Node type</span>
        <div className="readonly-box">{node.type}</div>
      </div>
      <CheckboxField
        label="Start node"
        value={!!node.is_start}
        onChange={(value) => onDialogChange(setDialogueNodeStart(dialog, node.id, value))}
      />
    </div>
  );
}

function DialogNodeFields({
  dialog,
  node,
  onDialogChange,
}: {
  dialog: DialogueData;
  node: DialogueNode;
  onDialogChange: (dialog: DialogueData) => void;
}) {
  return (
    <div className="form-grid">
      <TextField
        label="Speaker"
        value={node.speaker ?? ""}
        onChange={(value) =>
          onDialogChange(updateDialogueNode(dialog, node.id, (current) => ({ ...current, speaker: value })))
        }
      />
      <TextField
        label="Portrait"
        value={node.portrait ?? ""}
        onChange={(value) =>
          onDialogChange(updateDialogueNode(dialog, node.id, (current) => ({ ...current, portrait: value })))
        }
      />
      <div className="field">
        <span className="field-label">Connected next</span>
        <div className="readonly-box">{getDialogueEdgeTarget(dialog, node.id, "next") || "None"}</div>
      </div>
      <div />
      <TextareaField
        label="Dialog text"
        value={node.text ?? ""}
        onChange={(value) =>
          onDialogChange(updateDialogueNode(dialog, node.id, (current) => ({ ...current, text: value })))
        }
      />
    </div>
  );
}

function ChoiceOptionEditor({
  option,
  index,
  target,
  onChange,
  onDelete,
}: {
  option: DialogueOption;
  index: number;
  target: string;
  onChange: (option: DialogueOption) => void;
  onDelete: () => void;
}) {
  return (
    <article className="summary-row">
      <div className="summary-row-main dialogue-option-main">
        <TextField
          label={`Option ${index + 1}`}
          value={option.text}
          onChange={(value) => onChange({ ...option, text: value })}
        />
        <div className="field">
          <span className="field-label">Connected target</span>
          <div className="readonly-box">{target || "Not connected"}</div>
        </div>
      </div>
      <button type="button" className="toolbar-button toolbar-danger" onClick={onDelete}>
        Remove
      </button>
    </article>
  );
}

function ChoiceNodeFields({
  dialog,
  node,
  onDialogChange,
}: {
  dialog: DialogueData;
  node: DialogueNode;
  onDialogChange: (dialog: DialogueData) => void;
}) {
  const options = node.options ?? [];
  return (
    <div className="list-summary">
      {options.map((option, index) => (
        <ChoiceOptionEditor
          key={`${node.id}-option-${index}`}
          option={option}
          index={index}
          target={getDialogueEdgeTarget(dialog, node.id, `option-${index}`)}
          onChange={(nextOption) => {
            const nextOptions = options.map((entry, optionIndex) =>
              optionIndex === index ? nextOption : entry,
            );
            onDialogChange(setDialogueNodeOptions(dialog, node.id, nextOptions));
          }}
          onDelete={() => {
            const nextOptions = options.filter((_, optionIndex) => optionIndex !== index);
            onDialogChange(setDialogueNodeOptions(dialog, node.id, nextOptions));
          }}
        />
      ))}
      <button
        type="button"
        className="toolbar-button toolbar-accent"
        onClick={() =>
          onDialogChange(
            setDialogueNodeOptions(dialog, node.id, [
              ...options,
              { text: `Option ${options.length + 1}`, next: "" },
            ]),
          )
        }
      >
        Add option
      </button>
    </div>
  );
}

function ConditionNodeFields({
  dialog,
  node,
  onDialogChange,
}: {
  dialog: DialogueData;
  node: DialogueNode;
  onDialogChange: (dialog: DialogueData) => void;
}) {
  return (
    <div className="form-grid">
      <TextareaField
        label="Condition"
        value={node.condition ?? ""}
        onChange={(value) =>
          onDialogChange(updateDialogueNode(dialog, node.id, (current) => ({ ...current, condition: value })))
        }
      />
      <div className="list-summary">
        <div className="field">
          <span className="field-label">True branch</span>
          <div className="readonly-box">{getDialogueEdgeTarget(dialog, node.id, "true") || "Not connected"}</div>
        </div>
        <div className="field">
          <span className="field-label">False branch</span>
          <div className="readonly-box">{getDialogueEdgeTarget(dialog, node.id, "false") || "Not connected"}</div>
        </div>
      </div>
    </div>
  );
}

type ActionDetailEntry = {
  key: string;
  value: string;
};

function listActionDetails(action: DialogueAction): ActionDetailEntry[] {
  return Object.entries(action)
    .filter(([key]) => key !== "type")
    .map(([key, value]) => ({
      key,
      value: typeof value === "string" ? value : JSON.stringify(value),
    }));
}

function parseActionDetailValue(value: string): unknown {
  const trimmed = value.trim();
  if (!trimmed) {
    return "";
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function buildActionFromEntries(
  actionType: string,
  entries: ActionDetailEntry[],
): DialogueAction {
  const nextAction: DialogueAction = {
    type: actionType,
  };

  for (const entry of entries) {
    const key = entry.key.trim();
    if (!key) {
      continue;
    }
    nextAction[key] = parseActionDetailValue(entry.value);
  }

  return nextAction;
}

function ActionDetailRow({
  entry,
  index,
  onChange,
  onDelete,
}: {
  entry: ActionDetailEntry;
  index: number;
  onChange: (entry: ActionDetailEntry) => void;
  onDelete: () => void;
}) {
  return (
    <div className="summary-row action-detail-row">
      <div className="summary-row-main dialogue-option-main action-detail-grid">
        <TextField
          label={`Field ${index + 1} key`}
          value={entry.key}
          onChange={(value) => onChange({ ...entry, key: value })}
        />
        <TextField
          label="Value"
          value={entry.value}
          onChange={(value) => onChange({ ...entry, value })}
        />
      </div>
      <button type="button" className="toolbar-button toolbar-danger" onClick={onDelete}>
        Remove
      </button>
    </div>
  );
}

function ActionRowEditor({
  action,
  index,
  onChange,
  onDelete,
}: {
  action: DialogueAction;
  index: number;
  onChange: (action: DialogueAction) => void;
  onDelete: () => void;
}) {
  const detailEntries = listActionDetails(action);

  return (
    <article className="summary-row">
      <div className="summary-row-main dialogue-option-main">
        <TextField
          label={`Action ${index + 1} type`}
          value={action.type}
          onChange={(value) => onChange({ ...action, type: value })}
        />
        <div className="list-summary">
          {detailEntries.length === 0 ? (
            <div className="readonly-box">No action fields yet. Add key/value rows below.</div>
          ) : null}
          {detailEntries.map((entry, detailIndex) => (
            <ActionDetailRow
              key={`${action.type}-${index}-detail-${detailIndex}`}
              entry={entry}
              index={detailIndex}
              onChange={(nextEntry) => {
                const nextEntries = detailEntries.map((currentEntry, currentIndex) =>
                  currentIndex === detailIndex ? nextEntry : currentEntry,
                );
                onChange(buildActionFromEntries(action.type, nextEntries));
              }}
              onDelete={() => {
                const nextEntries = detailEntries.filter((_, currentIndex) => currentIndex !== detailIndex);
                onChange(buildActionFromEntries(action.type, nextEntries));
              }}
            />
          ))}
          <button
            type="button"
            className="toolbar-button"
            onClick={() =>
              onChange(
                buildActionFromEntries(action.type, [
                  ...detailEntries,
                  { key: `field_${detailEntries.length + 1}`, value: "" },
                ]),
              )
            }
          >
            Add field
          </button>
        </div>
      </div>
      <button type="button" className="toolbar-button toolbar-danger" onClick={onDelete}>
        Remove
      </button>
    </article>
  );
}

function ActionNodeFields({
  dialog,
  node,
  onDialogChange,
}: {
  dialog: DialogueData;
  node: DialogueNode;
  onDialogChange: (dialog: DialogueData) => void;
}) {
  const actions = node.actions ?? [];
  return (
    <div className="list-summary">
      <div className="field">
        <span className="field-label">Connected next</span>
        <div className="readonly-box">{getDialogueEdgeTarget(dialog, node.id, "next") || "None"}</div>
      </div>
      {actions.map((action, index) => (
        <ActionRowEditor
          key={`${node.id}-action-${index}`}
          action={action}
          index={index}
          onChange={(nextAction) => {
            const nextActions = actions.map((entry, actionIndex) =>
              actionIndex === index ? nextAction : entry,
            );
            onDialogChange(setDialogueNodeActions(dialog, node.id, nextActions));
          }}
          onDelete={() => {
            const nextActions = actions.filter((_, actionIndex) => actionIndex !== index);
            onDialogChange(setDialogueNodeActions(dialog, node.id, nextActions));
          }}
        />
      ))}
      <button
        type="button"
        className="toolbar-button toolbar-accent"
        onClick={() =>
          onDialogChange(setDialogueNodeActions(dialog, node.id, [...actions, { type: "new_action" }]))
        }
      >
        Add action
      </button>
    </div>
  );
}

function EndNodeFields({
  dialog,
  node,
  onDialogChange,
}: {
  dialog: DialogueData;
  node: DialogueNode;
  onDialogChange: (dialog: DialogueData) => void;
}) {
  return (
    <div className="form-grid">
      <TextField
        label="End type"
        value={node.end_type ?? ""}
        onChange={(value) =>
          onDialogChange(updateDialogueNode(dialog, node.id, (current) => ({ ...current, end_type: value })))
        }
      />
      <div className="field">
        <span className="field-label">Outgoing edges</span>
        <div className="readonly-box">End nodes cannot connect forward.</div>
      </div>
    </div>
  );
}

export function DialogueInspector({
  dialog,
  selectedNodeId,
  onDialogChange,
}: DialogueInspectorProps) {
  const node = getDialogueNode(dialog, selectedNodeId);

  if (!node) {
    return (
      <PanelSection label="Inspector" title="No node selected">
        <div className="empty-state">
          <Badge tone="muted">Idle</Badge>
          <p>Select a node in the graph to edit its structure.</p>
        </div>
      </PanelSection>
    );
  }

  return (
    <PanelSection label="Inspector" title={node.title || node.id}>
      <CommonNodeFields dialog={dialog} node={node} onDialogChange={onDialogChange} />
      {node.type === "dialog" ? (
        <DialogNodeFields dialog={dialog} node={node} onDialogChange={onDialogChange} />
      ) : null}
      {node.type === "choice" ? (
        <ChoiceNodeFields dialog={dialog} node={node} onDialogChange={onDialogChange} />
      ) : null}
      {node.type === "condition" ? (
        <ConditionNodeFields dialog={dialog} node={node} onDialogChange={onDialogChange} />
      ) : null}
      {node.type === "action" ? (
        <ActionNodeFields dialog={dialog} node={node} onDialogChange={onDialogChange} />
      ) : null}
      {node.type === "end" ? (
        <EndNodeFields dialog={dialog} node={node} onDialogChange={onDialogChange} />
      ) : null}
    </PanelSection>
  );
}
