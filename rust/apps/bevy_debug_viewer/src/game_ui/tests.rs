//! 游戏 UI 测试：覆盖主菜单渲染、场景切换和新游戏默认值等关键回归场景。

use super::*;

use std::collections::BTreeMap;

use super::{apply_new_game_defaults, should_render_main_menu, transition_to_gameplay_scene};
use crate::state::{
    ActiveDialogueState, GameUiRoot, GameUiScaffold, InteractionMenuState, MainMenuRoot,
    ViewerRuntimeState, ViewerSceneKind, ViewerState,
};
use bevy::picking::prelude::Pickable;
use bevy::prelude::App;
use game_bevy::{ItemDefinitions, UiMenuPanel, UiMenuState, UiModalState};
use game_core::create_demo_runtime;
use game_data::{DialogueData, InteractionTargetId, ItemDefinition, ItemFragment};

fn sample_new_game_item_definitions() -> ItemDefinitions {
    let stackable = |id: u32, name: &str| ItemDefinition {
        id,
        name: name.to_string(),
        fragments: vec![ItemFragment::Stacking {
            stackable: true,
            max_stack: 99,
        }],
        ..ItemDefinition::default()
    };
    let equippable = |id: u32, name: &str, slot: &str| ItemDefinition {
        id,
        name: name.to_string(),
        fragments: vec![
            ItemFragment::Stacking {
                stackable: false,
                max_stack: 1,
            },
            ItemFragment::Equip {
                slots: vec![slot.to_string()],
                level_requirement: 1,
                equip_effect_ids: Vec::new(),
                unequip_effect_ids: Vec::new(),
            },
        ],
        ..ItemDefinition::default()
    };

    ItemDefinitions(game_data::ItemLibrary::from(BTreeMap::from([
        (1002, equippable(1002, "Knife", "main_hand")),
        (1003, stackable(1003, "Bandage")),
        (1006, stackable(1006, "Ration")),
        (1007, stackable(1007, "Water")),
        (1008, stackable(1008, "Scrap")),
        (1009, stackable(1009, "Pistol Ammo")),
        (2004, equippable(2004, "Jacket", "body")),
        (2013, equippable(2013, "Pants", "legs")),
        (2015, equippable(2015, "Boots", "feet")),
    ])))
}

#[test]
fn transition_to_gameplay_scene_resets_viewer_and_ui_state() {
    let mut scene_kind = ViewerSceneKind::MainMenu;
    let (runtime, _) = create_demo_runtime();
    let mut runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: Default::default(),
    };
    let mut viewer_state = ViewerState {
        focused_target: Some(InteractionTargetId::MapObject("door".into())),
        interaction_menu: Some(InteractionMenuState {
            target_id: InteractionTargetId::MapObject("door".into()),
            cursor_position: bevy::prelude::Vec2::new(32.0, 48.0),
        }),
        active_dialogue: Some(ActiveDialogueState {
            actor_id: game_data::ActorId(1),
            target_id: None,
            dialogue_key: "intro".into(),
            dialog_id: "intro".into(),
            data: DialogueData::default(),
            current_node_id: "start".into(),
            target_name: "door".into(),
        }),
        hovered_grid: Some(game_data::GridCoord::new(1, 0, 1)),
        pending_open_trade_target: Some(InteractionTargetId::MapObject("shop".into())),
        status_line: "menu".into(),
        ..ViewerState::default()
    };
    let mut menu_state = UiMenuState {
        selected_inventory_item: Some(42),
        selected_equipment_slot: Some("body".into()),
        selected_skill_tree_id: Some("tree_a".into()),
        selected_skill_id: Some("skill_a".into()),
        selected_recipe_id: Some("recipe_a".into()),
        selected_map_location_id: Some("street_a".into()),
        ..UiMenuState::default()
    };
    menu_state.open_panel(UiMenuPanel::Inventory);
    let mut modal_state = UiModalState {
        item_quantity: Some(game_bevy::UiItemQuantityModalState {
            item_id: 1006,
            source_count: 3,
            available_count: 3,
            selected_count: 2,
            intent: game_bevy::UiItemQuantityIntent::Discard,
        }),
        trade: Some(Default::default()),
        ..UiModalState::default()
    };

    transition_to_gameplay_scene(
        &mut scene_kind,
        &mut runtime_state,
        &mut viewer_state,
        &mut menu_state,
        &mut modal_state,
        "开始新游戏",
    );

    assert_eq!(scene_kind, ViewerSceneKind::Gameplay);
    assert!(viewer_state.focused_target.is_none());
    assert!(viewer_state.interaction_menu.is_none());
    assert!(viewer_state.active_dialogue.is_none());
    assert!(viewer_state.hovered_grid.is_none());
    assert_eq!(viewer_state.status_line, "开始新游戏");
    assert!(viewer_state.controlled_player_actor.is_some());
    assert_eq!(
        viewer_state.current_level,
        runtime_state
            .runtime
            .snapshot()
            .grid
            .default_level
            .unwrap_or(0)
    );
    assert!(!menu_state.any_panel_open());
    assert!(menu_state.selected_inventory_item.is_none());
    assert!(menu_state.selected_skill_tree_id.is_none());
    assert_eq!(menu_state.status_text, "开始新游戏");
    assert!(modal_state.item_quantity.is_none());
    assert!(modal_state.trade.is_none());
}

#[test]
fn transition_to_gameplay_scene_clears_runtime_movement_transients() {
    let mut scene_kind = ViewerSceneKind::MainMenu;
    let (mut runtime, handles) = create_demo_runtime();
    runtime
        .issue_actor_move(handles.player, game_data::GridCoord::new(0, 0, 2))
        .expect("path should be planned");
    let expected_position = runtime
        .get_actor_grid_position(handles.player)
        .expect("player should remain registered");
    let mut runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: Default::default(),
    };
    let mut viewer_state = ViewerState::default();
    let mut menu_state = UiMenuState::default();
    let mut modal_state = UiModalState::default();

    assert!(runtime_state.runtime.pending_movement().is_some());
    assert!(!runtime_state.runtime.snapshot().path_preview.is_empty());

    transition_to_gameplay_scene(
        &mut scene_kind,
        &mut runtime_state,
        &mut viewer_state,
        &mut menu_state,
        &mut modal_state,
        "已继续最近存档",
    );

    assert!(runtime_state.runtime.pending_movement().is_none());
    assert!(runtime_state.runtime.snapshot().path_preview.is_empty());

    for _ in 0..3 {
        let _ = runtime_state.runtime.advance_pending_progression();
    }

    assert_eq!(
        runtime_state
            .runtime
            .get_actor_grid_position(handles.player),
        Some(expected_position)
    );
}

#[test]
fn main_menu_ui_renders_only_in_main_menu_scene() {
    assert!(should_render_main_menu(ViewerSceneKind::MainMenu));
    assert!(!should_render_main_menu(ViewerSceneKind::Gameplay));
}

#[test]
fn apply_new_game_defaults_does_not_require_ap() {
    let (mut runtime, handles) = create_demo_runtime();
    let items = sample_new_game_item_definitions();
    runtime.economy_mut().set_actor_level(handles.player, 1);
    let _ = runtime.submit_command(game_core::SimulationCommand::SetActorAp {
        actor_id: handles.player,
        ap: 0.0,
    });

    apply_new_game_defaults(&mut runtime, &items).expect("new game setup should succeed");

    assert_eq!(runtime.get_actor_ap(handles.player), 0.0);
    assert_eq!(runtime.get_actor_inventory_count(handles.player, "1008"), 2);
    assert!(runtime
        .economy()
        .equipped_item(handles.player, "main_hand")
        .is_some());
    assert!(runtime
        .economy()
        .equipped_item(handles.player, "body")
        .is_some());
}

#[test]
fn setup_game_ui_spawns_non_pickable_root() {
    let mut app = App::new();
    app.init_resource::<UiMenuState>();
    app.add_systems(Startup, setup_game_ui);

    app.update();

    let scaffold = *app.world().resource::<GameUiScaffold>();
    for entity in [
        scaffold.root,
        scaffold.main_menu,
        scaffold.top_badges,
        scaffold.hotbar,
        scaffold.active_panel,
        scaffold.trade,
        scaffold.tooltip,
        scaffold.context_menu,
        scaffold.drag_preview,
        scaffold.discard_modal,
        scaffold.overworld_prompt,
    ] {
        assert_eq!(
            app.world().entity(entity).get::<Pickable>(),
            Some(&Pickable::IGNORE),
            "entity {entity:?} should opt out of world picking at spawn time"
        );
    }
}

#[test]
fn setup_game_ui_keeps_retained_roots_stable_across_updates() {
    let mut app = App::new();
    app.init_resource::<UiMenuState>();
    app.add_systems(Startup, setup_game_ui);

    app.update();
    let first = *app.world().resource::<GameUiScaffold>();
    app.update();
    let second = *app.world().resource::<GameUiScaffold>();

    assert_eq!(first.root, second.root);
    assert_eq!(first.main_menu, second.main_menu);
    assert_eq!(first.active_panel, second.active_panel);
    assert!(app.world().entity(first.root).contains::<GameUiRoot>());
    assert!(app
        .world()
        .entity(first.main_menu)
        .contains::<MainMenuRoot>());
}
