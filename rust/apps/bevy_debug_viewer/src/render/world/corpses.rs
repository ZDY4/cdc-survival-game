//! 尸体模型同步：尸体仍是地图容器对象，但表现上复用角色预览和装备外观。

use std::collections::BTreeMap;

use super::*;

const CORPSE_LYING_ROLL: f32 = std::f32::consts::FRAC_PI_2;

#[allow(clippy::too_many_arguments)]
pub(super) fn sync_corpse_visuals(
    commands: &mut Commands,
    asset_server: &AssetServer,
    materials: &mut Assets<StandardMaterial>,
    character_definitions: Option<&game_bevy::CharacterDefinitions>,
    item_definitions: Option<&game_bevy::ItemDefinitions>,
    character_appearance_definitions: Option<&game_bevy::CharacterAppearanceDefinitions>,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    corpse_visual_state: &mut CorpseVisualState,
) {
    let mut seen_object_ids = HashSet::new();
    let grid_size = snapshot.grid.grid_size;

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter(|object| map_object_is_corpse(object))
    {
        let Some(definition_id) = corpse_character_id(object) else {
            continue;
        };
        let equipped_slots = corpse_visible_equipped_slots(
            runtime_state.runtime.economy(),
            snapshot.grid.map_id.as_ref(),
            &object.object_id,
            parse_equipped_slots(object),
        );
        let appearance_key = game_bevy::RuntimeCharacterAppearanceKey {
            definition_id: Some(definition_id.clone()),
            equipped_slots: equipped_slots.clone(),
        };
        seen_object_ids.insert(object.object_id.clone());

        if let Some(existing) = corpse_visual_state.by_object.get(&object.object_id) {
            if existing.grid == object.anchor && existing.appearance_key == appearance_key {
                continue;
            }
            commands.entity(existing.root_entity).despawn();
            corpse_visual_state.by_object.remove(&object.object_id);
        }

        let Some(preview) = character_definitions
            .zip(item_definitions)
            .zip(character_appearance_definitions)
            .and_then(|((definitions, items), appearances)| {
                game_bevy::resolve_character_preview_for_loadout(
                    definitions,
                    items,
                    appearances,
                    Some(definition_id.as_str()),
                    &equipped_slots,
                )
            })
            .filter(game_bevy::character_preview_is_available)
        else {
            continue;
        };

        let translation = actor_body_translation(
            runtime_state.runtime.grid_to_world(object.anchor),
            grid_size,
            render_config,
        );
        let root_transform =
            Transform::from_translation(translation).with_scale(Vec3::splat(grid_size));
        let root_entity = commands
            .spawn((
                root_transform,
                GlobalTransform::from(root_transform),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                CorpseBodyVisual,
            ))
            .id();

        let model_ground_anchor_transform = actors::actor_model_ground_anchor_transform(
            render_config,
            grid_size,
            preview.base_model_asset.as_str(),
        );
        let model_ground_anchor_entity = commands
            .spawn((
                model_ground_anchor_transform,
                GlobalTransform::from(model_ground_anchor_transform),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                CorpseModelGroundAnchor,
            ))
            .id();
        commands
            .entity(root_entity)
            .add_child(model_ground_anchor_entity);

        let appearance_entity =
            game_bevy::spawn_character_preview_scene(commands, asset_server, materials, &preview);
        commands.entity(appearance_entity).insert(
            Transform::from_translation(Vec3::new(
                render_config.actor_body_length_world * 0.45,
                0.025,
                0.0,
            ))
            .with_rotation(Quat::from_rotation_z(CORPSE_LYING_ROLL)),
        );
        commands
            .entity(model_ground_anchor_entity)
            .add_child(appearance_entity);

        corpse_visual_state.by_object.insert(
            object.object_id.clone(),
            CorpseVisualEntry {
                root_entity,
                grid: object.anchor,
                appearance_key,
            },
        );
    }

    let stale_object_ids = corpse_visual_state
        .by_object
        .keys()
        .filter(|object_id| !seen_object_ids.contains(*object_id))
        .cloned()
        .collect::<Vec<_>>();
    for object_id in stale_object_ids {
        if let Some(entry) = corpse_visual_state.by_object.remove(&object_id) {
            commands.entity(entry.root_entity).despawn();
        }
    }
}

fn map_object_is_corpse(object: &game_core::MapObjectDebugState) -> bool {
    object
        .payload_summary
        .get("corpse")
        .is_some_and(|value| value == "true")
        || object
            .payload_summary
            .get("container_visual_id")
            .is_some_and(|value| value.trim() == "corpse")
}

fn corpse_character_id(object: &game_core::MapObjectDebugState) -> Option<String> {
    object
        .payload_summary
        .get("corpse_character_id")
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn parse_equipped_slots(object: &game_core::MapObjectDebugState) -> BTreeMap<String, u32> {
    object
        .payload_summary
        .get("corpse_equipped_slots")
        .map(|value| {
            value
                .split(',')
                .filter_map(|entry| {
                    let (slot, item_id) = entry.split_once(':')?;
                    let slot = slot.trim();
                    if slot.is_empty() {
                        return None;
                    }
                    item_id
                        .trim()
                        .parse::<u32>()
                        .ok()
                        .filter(|item_id| *item_id > 0)
                        .map(|item_id| (slot.to_string(), item_id))
                })
                .collect()
        })
        .unwrap_or_default()
}

fn corpse_visible_equipped_slots(
    economy: &game_core::HeadlessEconomyRuntime,
    map_id: Option<&game_data::MapId>,
    object_id: &str,
    equipped_slots: BTreeMap<String, u32>,
) -> BTreeMap<String, u32> {
    let Some(map_id) = map_id else {
        return equipped_slots;
    };
    let container_id = format!("{}::{}", map_id.as_str(), object_id);
    let Some(container) = economy.container(&container_id) else {
        return equipped_slots;
    };

    equipped_slots
        .into_iter()
        .filter(|(_, item_id)| container.inventory.get(item_id).copied().unwrap_or(0) > 0)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn corpse_visible_equipped_slots_hide_looted_equipment() {
        let mut economy = game_core::HeadlessEconomyRuntime::default();
        economy.ensure_container(
            "test_map::corpse_2",
            "test_map",
            "corpse_2",
            "尸体",
            [(1004, 0), (1009, 3)],
        );
        let slots = BTreeMap::from([
            ("main_hand".to_string(), 1004),
            ("ammo_pouch".to_string(), 1009),
        ]);

        let visible = corpse_visible_equipped_slots(
            &economy,
            Some(&game_data::MapId("test_map".into())),
            "corpse_2",
            slots,
        );

        assert!(!visible.contains_key("main_hand"));
        assert_eq!(visible.get("ammo_pouch"), Some(&1009));
    }
}
