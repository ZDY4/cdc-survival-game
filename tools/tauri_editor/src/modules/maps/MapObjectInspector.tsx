import {
  CheckboxField,
  NumberField,
  SelectField,
  TextField,
} from "../../components/fields";
import type {
  MapObjectDefinition,
  MapObjectKind,
  MapRotation,
  MapWorkspacePayload,
} from "../../types";

type MapObjectInspectorProps = {
  selectedObject: MapObjectDefinition | null;
  workspace: MapWorkspacePayload;
  updateSelectedObject: (transform: (object: MapObjectDefinition) => MapObjectDefinition) => void;
  changeSelectedObjectKind: (nextKind: MapObjectKind) => void;
  deleteSelectedObject: () => void;
};

export function MapObjectInspector({
  selectedObject,
  workspace,
  updateSelectedObject,
  changeSelectedObjectKind,
  deleteSelectedObject,
}: MapObjectInspectorProps) {
  if (!selectedObject) {
    return null;
  }

  return (
    <>
      <div className="form-grid">
        <TextField
          label="Object ID"
          value={selectedObject.object_id}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              object_id: value.trim(),
            }))
          }
        />
        <SelectField
          label="Kind"
          value={selectedObject.kind}
          onChange={(value) => changeSelectedObjectKind(value as MapObjectKind)}
          options={["building", "pickup", "interactive", "ai_spawn"]}
          allowBlank={false}
        />
        <NumberField
          label="Anchor X"
          value={selectedObject.anchor.x}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              anchor: { ...object.anchor, x: Math.floor(value) },
            }))
          }
        />
        <NumberField
          label="Anchor Y"
          value={selectedObject.anchor.y}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              anchor: { ...object.anchor, y: Math.floor(value) },
            }))
          }
        />
        <NumberField
          label="Anchor Z"
          value={selectedObject.anchor.z}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              anchor: { ...object.anchor, z: Math.floor(value) },
            }))
          }
        />
        <SelectField
          label="Rotation"
          value={selectedObject.rotation}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              rotation: value as MapRotation,
            }))
          }
          options={["north", "east", "south", "west"]}
          allowBlank={false}
        />
      </div>

      <div className="form-grid">
        <NumberField
          label="Footprint W"
          value={selectedObject.footprint.width}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              footprint: {
                ...object.footprint,
                width: Math.max(1, Math.floor(value)),
              },
            }))
          }
          min={1}
        />
        <NumberField
          label="Footprint H"
          value={selectedObject.footprint.height}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              footprint: {
                ...object.footprint,
                height: Math.max(1, Math.floor(value)),
              },
            }))
          }
          min={1}
        />
      </div>

      <div className="toggle-grid">
        <CheckboxField
          label="Blocks movement"
          value={selectedObject.blocks_movement}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              blocks_movement: value,
            }))
          }
        />
        <CheckboxField
          label="Blocks sight"
          value={selectedObject.blocks_sight}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              blocks_sight: value,
            }))
          }
        />
      </div>

      {selectedObject.kind === "building" ? (
        <TextField
          label="Prefab"
          value={selectedObject.props.building?.prefab_id ?? ""}
          onChange={(value) =>
            updateSelectedObject((object) => ({
              ...object,
              props: {
                ...object.props,
                building: {
                  ...(object.props.building ?? {}),
                  prefab_id: value,
                },
              },
            }))
          }
          hint={`Suggestions: ${workspace.catalogs.buildingPrefabs.join(", ")}`}
        />
      ) : null}

      {selectedObject.kind === "pickup" ? (
        <div className="form-grid">
          <SelectField
            label="Item"
            value={selectedObject.props.pickup?.item_id ?? ""}
            onChange={(value) =>
              updateSelectedObject((object) => ({
                ...object,
                props: {
                  ...object.props,
                  pickup: {
                    ...(object.props.pickup ?? {}),
                    item_id: value,
                    min_count: object.props.pickup?.min_count ?? 1,
                    max_count: object.props.pickup?.max_count ?? 1,
                  },
                },
              }))
            }
            options={workspace.catalogs.itemIds}
          />
          <NumberField
            label="Min count"
            value={selectedObject.props.pickup?.min_count ?? 1}
            onChange={(value) =>
              updateSelectedObject((object) => ({
                ...object,
                props: {
                  ...object.props,
                  pickup: {
                    ...(object.props.pickup ?? {}),
                    item_id: object.props.pickup?.item_id ?? "",
                    min_count: Math.max(1, Math.floor(value)),
                    max_count: object.props.pickup?.max_count ?? 1,
                  },
                },
              }))
            }
          />
          <NumberField
            label="Max count"
            value={selectedObject.props.pickup?.max_count ?? 1}
            onChange={(value) =>
              updateSelectedObject((object) => ({
                ...object,
                props: {
                  ...object.props,
                  pickup: {
                    ...(object.props.pickup ?? {}),
                    item_id: object.props.pickup?.item_id ?? "",
                    min_count: object.props.pickup?.min_count ?? 1,
                    max_count: Math.max(1, Math.floor(value)),
                  },
                },
              }))
            }
          />
        </div>
      ) : null}

      {selectedObject.kind === "interactive" ? (
        <div className="form-grid">
          <TextField
            label="Interaction"
            value={selectedObject.props.interactive?.interaction_kind ?? ""}
            onChange={(value) =>
              updateSelectedObject((object) => ({
                ...object,
                props: {
                  ...object.props,
                  interactive: {
                    ...(object.props.interactive ?? {}),
                    interaction_kind: value,
                  },
                },
              }))
            }
            hint={`Suggestions: ${workspace.catalogs.interactiveKinds.join(", ")}`}
          />
          <TextField
            label="Target ID"
            value={selectedObject.props.interactive?.target_id ?? ""}
            onChange={(value) =>
              updateSelectedObject((object) => ({
                ...object,
                props: {
                  ...object.props,
                  interactive: {
                    ...(object.props.interactive ?? {}),
                    interaction_kind: object.props.interactive?.interaction_kind ?? "",
                    target_id: value,
                  },
                },
              }))
            }
          />
        </div>
      ) : null}

      {selectedObject.kind === "ai_spawn" ? (
        <>
          <div className="form-grid">
            <TextField
              label="Spawn ID"
              value={selectedObject.props.ai_spawn?.spawn_id ?? ""}
              onChange={(value) =>
                updateSelectedObject((object) => ({
                  ...object,
                  props: {
                    ...object.props,
                    ai_spawn: {
                      ...(object.props.ai_spawn ?? {}),
                      spawn_id: value.trim(),
                      character_id: object.props.ai_spawn?.character_id ?? "",
                      auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                      respawn_enabled: object.props.ai_spawn?.respawn_enabled ?? false,
                      respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                      spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                    },
                  },
                }))
              }
            />
            <SelectField
              label="Character"
              value={selectedObject.props.ai_spawn?.character_id ?? ""}
              onChange={(value) =>
                updateSelectedObject((object) => ({
                  ...object,
                  props: {
                    ...object.props,
                    ai_spawn: {
                      ...(object.props.ai_spawn ?? {}),
                      spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                      character_id: value,
                      auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                      respawn_enabled: object.props.ai_spawn?.respawn_enabled ?? false,
                      respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                      spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                    },
                  },
                }))
              }
              options={workspace.catalogs.characterIds}
            />
            <NumberField
              label="Respawn delay"
              value={selectedObject.props.ai_spawn?.respawn_delay ?? 10}
              onChange={(value) =>
                updateSelectedObject((object) => ({
                  ...object,
                  props: {
                    ...object.props,
                    ai_spawn: {
                      ...(object.props.ai_spawn ?? {}),
                      spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                      character_id: object.props.ai_spawn?.character_id ?? "",
                      auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                      respawn_enabled: object.props.ai_spawn?.respawn_enabled ?? false,
                      respawn_delay: value,
                      spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                    },
                  },
                }))
              }
            />
            <NumberField
              label="Spawn radius"
              value={selectedObject.props.ai_spawn?.spawn_radius ?? 0}
              onChange={(value) =>
                updateSelectedObject((object) => ({
                  ...object,
                  props: {
                    ...object.props,
                    ai_spawn: {
                      ...(object.props.ai_spawn ?? {}),
                      spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                      character_id: object.props.ai_spawn?.character_id ?? "",
                      auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                      respawn_enabled: object.props.ai_spawn?.respawn_enabled ?? false,
                      respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                      spawn_radius: value,
                    },
                  },
                }))
              }
            />
          </div>
          <div className="toggle-grid">
            <CheckboxField
              label="Auto spawn"
              value={selectedObject.props.ai_spawn?.auto_spawn ?? true}
              onChange={(value) =>
                updateSelectedObject((object) => ({
                  ...object,
                  props: {
                    ...object.props,
                    ai_spawn: {
                      ...(object.props.ai_spawn ?? {}),
                      spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                      character_id: object.props.ai_spawn?.character_id ?? "",
                      auto_spawn: value,
                      respawn_enabled: object.props.ai_spawn?.respawn_enabled ?? false,
                      respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                      spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                    },
                  },
                }))
              }
            />
            <CheckboxField
              label="Respawn enabled"
              value={selectedObject.props.ai_spawn?.respawn_enabled ?? false}
              onChange={(value) =>
                updateSelectedObject((object) => ({
                  ...object,
                  props: {
                    ...object.props,
                    ai_spawn: {
                      ...(object.props.ai_spawn ?? {}),
                      spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                      character_id: object.props.ai_spawn?.character_id ?? "",
                      auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                      respawn_enabled: value,
                      respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                      spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                    },
                  },
                }))
              }
            />
          </div>
        </>
      ) : null}

      <button
        type="button"
        className="toolbar-button toolbar-danger"
        onClick={deleteSelectedObject}
      >
        Delete selected object
      </button>
    </>
  );
}
