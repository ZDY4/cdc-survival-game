//! UI tooltip 逻辑：负责按当前悬停目标生成背包、技能和场景切换提示文本。

use super::pointer_input::{find_inventory_hover_target, find_skill_hover_target};
use super::*;
use crate::geometry::map_object_at_grid;
use game_core::{MapObjectDebugState, SimulationSnapshot};
use game_data::{GridCoord, MapObjectKind, OverworldDefinition, OverworldLocationKind};

pub(crate) fn update_hover_tooltip_state(
    window: Single<&Window>,
    scene_kind: Res<ViewerSceneKind>,
    menu_state: Res<UiMenuState>,
    modal_state: Res<UiModalState>,
    inventory_context_menu: Res<UiContextMenuState>,
    drag_state: Res<UiInventoryDragState>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    overworld: Res<OverworldDefinitions>,
    mut tooltip_state: ResMut<UiHoverTooltipState>,
    inventory_targets: Query<
        (
            &InventoryItemHoverTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
    skill_targets: Query<
        (
            &SkillHoverTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) {
    let Some(cursor_position) = window.cursor_position() else {
        tooltip_state.clear();
        return;
    };

    tooltip_state.cursor_position = cursor_position;

    if scene_kind.is_main_menu()
        || modal_state.item_quantity.is_some()
        || modal_state.trade.is_some()
        || inventory_context_menu.visible
        || drag_state.is_active()
    {
        tooltip_state.clear();
        return;
    }

    let hovered = find_inventory_hover_target(cursor_position, &inventory_targets)
        .filter(|_| menu_state.is_panel_open(UiMenuPanel::Inventory))
        .map(|item_id| UiHoverTooltipContent::InventoryItem { item_id })
        .or_else(|| {
            find_skill_hover_target(cursor_position, &skill_targets)
                .filter(|_| menu_state.is_panel_open(UiMenuPanel::Skills))
                .map(|(tree_id, skill_id)| UiHoverTooltipContent::Skill { tree_id, skill_id })
        })
        .or_else(|| {
            resolve_scene_transition_tooltip_content(
                &runtime_state.runtime.snapshot(),
                viewer_state.hovered_grid,
                &overworld,
            )
        });

    match hovered {
        Some(content) => {
            tooltip_state.visible = true;
            tooltip_state.content = Some(content);
        }
        None => tooltip_state.clear(),
    }
}

fn resolve_scene_transition_tooltip_content(
    snapshot: &SimulationSnapshot,
    hovered_grid: Option<GridCoord>,
    overworld: &OverworldDefinitions,
) -> Option<UiHoverTooltipContent> {
    let hovered_grid = hovered_grid?;
    let object = map_object_at_grid(snapshot, hovered_grid)?;
    let target_name = scene_transition_target_name(&object, &overworld.0)?;
    Some(UiHoverTooltipContent::SceneTransition { target_name })
}

fn scene_transition_target_name(
    object: &MapObjectDebugState,
    overworld: &game_data::OverworldLibrary,
) -> Option<String> {
    if object.kind != MapObjectKind::Trigger {
        return None;
    }
    let trigger_kind = object.payload_summary.get("trigger_kind")?;
    if !is_scene_transition_trigger_kind(trigger_kind) {
        return None;
    }

    let target_id = object.payload_summary.get("target_id")?;
    if target_id.trim().is_empty() {
        return None;
    }

    overworld
        .iter()
        .find_map(|(_, definition)| find_location_name(definition, target_id))
        .or_else(|| Some(target_id.clone()))
}

fn find_location_name(definition: &OverworldDefinition, target_id: &str) -> Option<String> {
    definition
        .locations
        .iter()
        .find(|location| {
            location.id.as_str() == target_id
                && matches!(
                    location.kind,
                    OverworldLocationKind::Outdoor
                        | OverworldLocationKind::Interior
                        | OverworldLocationKind::Dungeon
                )
        })
        .map(|location| {
            if location.name.trim().is_empty() {
                target_id.to_string()
            } else {
                location.name.clone()
            }
        })
}

fn is_scene_transition_trigger_kind(kind: &str) -> bool {
    matches!(
        kind,
        "enter_subscene" | "enter_overworld" | "exit_to_outdoor" | "enter_outdoor_location"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use game_data::{
        OverworldDefinition, OverworldId, OverworldLibrary, OverworldLocationDefinition,
        OverworldLocationId, OverworldLocationKind, OverworldTerrainKind, OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;

    #[test]
    fn scene_transition_target_name_prefers_location_name() {
        let object = MapObjectDebugState {
            object_id: "to_perimeter".into(),
            kind: MapObjectKind::Trigger,
            anchor: GridCoord::new(0, 0, 0),
            footprint: game_data::MapObjectFootprint {
                width: 1,
                height: 1,
            },
            rotation: game_data::MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            occupied_cells: vec![GridCoord::new(0, 0, 0)],
            payload_summary: BTreeMap::from([
                ("trigger_kind".into(), "enter_outdoor_location".into()),
                ("target_id".into(), "survivor_outpost_01_perimeter".into()),
            ]),
        };

        let target_name = scene_transition_target_name(&object, &sample_overworld_library())
            .expect("target name should resolve");

        assert_eq!(target_name, "据点外警戒区".to_string());
    }

    #[test]
    fn scene_transition_target_name_falls_back_to_target_id_when_location_is_missing() {
        let object = MapObjectDebugState {
            object_id: "to_unknown".into(),
            kind: MapObjectKind::Trigger,
            anchor: GridCoord::new(0, 0, 0),
            footprint: game_data::MapObjectFootprint {
                width: 1,
                height: 1,
            },
            rotation: game_data::MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            occupied_cells: vec![GridCoord::new(0, 0, 0)],
            payload_summary: BTreeMap::from([
                ("trigger_kind".into(), "enter_outdoor_location".into()),
                ("target_id".into(), "missing".into()),
            ]),
        };

        assert_eq!(
            scene_transition_target_name(&object, &sample_overworld_library()),
            Some("missing".to_string())
        );
    }

    fn sample_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main".into()),
            OverworldDefinition {
                id: OverworldId("main".into()),
                size: game_data::MapSize {
                    width: 2,
                    height: 1,
                },
                locations: vec![OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01_perimeter".into()),
                    name: "据点外警戒区".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: game_data::MapId("survivor_outpost_01_perimeter".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(1, 0, 0),
                    danger_level: 2,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                }],
                cells: vec![
                    game_data::OverworldCellDefinition {
                        grid: GridCoord::new(0, 0, 0),
                        terrain: OverworldTerrainKind::Plain,
                        blocked: false,
                        visual: None,
                        extra: BTreeMap::new(),
                    },
                    game_data::OverworldCellDefinition {
                        grid: GridCoord::new(1, 0, 0),
                        terrain: OverworldTerrainKind::Plain,
                        blocked: false,
                        visual: None,
                        extra: BTreeMap::new(),
                    },
                ],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }
}
