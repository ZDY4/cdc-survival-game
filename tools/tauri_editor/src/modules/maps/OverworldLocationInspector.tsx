import {
  CheckboxField,
  NumberField,
  SelectField,
  TextField,
} from "../../components/fields";
import type {
  OverworldLocationDefinition,
  OverworldWorkspacePayload,
} from "../../types";

type OverworldLocationInspectorProps = {
  selectedLocation: OverworldLocationDefinition | null;
  workspace: OverworldWorkspacePayload;
  updateSelectedLocation: (
    transform: (location: OverworldLocationDefinition) => OverworldLocationDefinition,
  ) => void;
  deleteSelectedLocation: () => void;
};

export function OverworldLocationInspector({
  selectedLocation,
  workspace,
  updateSelectedLocation,
  deleteSelectedLocation,
}: OverworldLocationInspectorProps) {
  if (!selectedLocation) {
    return null;
  }

  const entryPointsForMap = workspace.catalogs.mapEntryPointsByMap[selectedLocation.map_id] ?? [];

  return (
    <>
      <div className="form-grid">
        <TextField
          label="Location ID"
          value={selectedLocation.id}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              id: value.trim(),
            }))
          }
        />
        <TextField
          label="Name"
          value={selectedLocation.name}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              name: value,
            }))
          }
        />
        <SelectField
          label="Kind"
          value={selectedLocation.kind}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              kind: value as OverworldLocationDefinition["kind"],
            }))
          }
          options={workspace.catalogs.locationKinds}
          allowBlank={false}
        />
        <NumberField
          label="Danger"
          value={selectedLocation.danger_level}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              danger_level: Math.floor(value),
            }))
          }
        />
        <TextField
          label="Map ID"
          value={selectedLocation.map_id}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              map_id: value.trim(),
            }))
          }
          hint={`Known maps: ${workspace.catalogs.mapIds.join(", ")}`}
        />
        <SelectField
          label="Entry point"
          value={selectedLocation.entry_point_id}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              entry_point_id: value,
            }))
          }
          options={entryPointsForMap}
        />
        <TextField
          label="Parent outdoor"
          value={selectedLocation.parent_outdoor_location_id ?? ""}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              parent_outdoor_location_id: value.trim() || null,
            }))
          }
        />
        <TextField
          label="Return entry point"
          value={selectedLocation.return_entry_point_id ?? ""}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              return_entry_point_id: value.trim() || null,
            }))
          }
        />
        <TextField
          label="Icon"
          value={selectedLocation.icon}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              icon: value,
            }))
          }
        />
      </div>

      <TextField
        label="Description"
        value={selectedLocation.description}
        onChange={(value) =>
          updateSelectedLocation((location) => ({
            ...location,
            description: value,
          }))
        }
      />

      <div className="toggle-grid">
        <CheckboxField
          label="Default unlocked"
          value={selectedLocation.default_unlocked}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              default_unlocked: value,
            }))
          }
        />
        <CheckboxField
          label="Visible"
          value={selectedLocation.visible}
          onChange={(value) =>
            updateSelectedLocation((location) => ({
              ...location,
              visible: value,
            }))
          }
        />
      </div>

      <button
        type="button"
        className="toolbar-button toolbar-danger"
        onClick={deleteSelectedLocation}
      >
        Delete selected location
      </button>
    </>
  );
}
