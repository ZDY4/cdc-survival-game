//! UI 状态同步：负责场景切换后的默认值恢复、运行时快照同步和存档读写辅助。

use super::*;

pub(crate) fn setup_game_ui(mut commands: Commands, mut menu_state: ResMut<UiMenuState>) {
    menu_state.main_menu_open = false;
    menu_state.close_all_panels();
    let overlay_layer = || {
        (
            Node {
                position_type: PositionType::Absolute,
                left: px(0),
                top: px(0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                ..default()
            },
            Visibility::Hidden,
            viewer_ui_passthrough_bundle(),
        )
    };
    let root = commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(0),
                top: px(0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                ..default()
            },
            viewer_ui_passthrough_bundle(),
            GameUiRoot,
        ))
        .id();
    let main_menu = commands.spawn((overlay_layer(), MainMenuRoot)).id();
    let top_badges = commands.spawn((overlay_layer(), TopBadgeRoot)).id();
    let hotbar = commands.spawn((overlay_layer(), HotbarRoot)).id();
    let active_panel = commands.spawn((overlay_layer(), ActivePanelRoot)).id();
    let trade = commands.spawn((overlay_layer(), TradeRoot)).id();
    let container = commands.spawn((overlay_layer(), ContainerRoot)).id();
    let tooltip = commands.spawn((overlay_layer(), TooltipRoot)).id();
    let context_menu = commands
        .spawn((overlay_layer(), InventoryContextMenuLayerRoot))
        .id();
    let drag_preview = commands.spawn((overlay_layer(), DragPreviewRoot)).id();
    let discard_modal = commands.spawn((overlay_layer(), DiscardModalRoot)).id();
    let overworld_prompt = commands.spawn((overlay_layer(), OverworldPromptRoot)).id();

    commands.entity(root).add_children(&[
        main_menu,
        top_badges,
        hotbar,
        active_panel,
        trade,
        container,
        tooltip,
        context_menu,
        drag_preview,
        discard_modal,
        overworld_prompt,
    ]);
    commands.insert_resource(GameUiScaffold {
        root,
        main_menu,
        top_badges,
        hotbar,
        active_panel,
        trade,
        container,
        tooltip,
        context_menu,
        drag_preview,
        discard_modal,
        overworld_prompt,
    });
}

pub(crate) fn sync_game_ui_state(
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    mut viewer_state: ResMut<ViewerState>,
    mut menu_state: ResMut<UiMenuState>,
    mut modal_state: ResMut<UiModalState>,
    mut banner_state: ResMut<UiStatusBannerState>,
    mut input_block_state: ResMut<UiInputBlockState>,
    mut inventory_context_menu: ResMut<UiContextMenuState>,
    shops: Res<ShopDefinitions>,
) {
    let context = runtime_state.runtime.current_interaction_context();
    let banner = world_status_snapshot(&context);
    let prompt_text = interaction_prompt_text(viewer_state.current_prompt.as_ref());
    banner_state.visible = banner.visible;
    banner_state.title = banner.title;
    let targeting_prompt = viewer_state
        .targeting_state
        .as_ref()
        .map(|targeting| targeting.prompt_text.clone());
    banner_state.detail = [
        Some(banner.detail),
        (!prompt_text.is_empty()).then_some(prompt_text),
        targeting_prompt,
    ]
    .into_iter()
    .flatten()
    .chain(
        (!viewer_state.status_line.trim().is_empty()).then_some(viewer_state.status_line.clone()),
    )
    .collect::<Vec<_>>()
    .join(" | ");

    if let Some(target) = viewer_state.pending_open_trade_target.as_ref() {
        if modal_state.trade.is_none() {
            modal_state.trade = resolve_trade_session_for_target(&runtime_state, target, &shops.0);
        }
        if modal_state.trade.is_some() {
            menu_state.close_all_panels();
        }
    }
    if let Some(container_id) = viewer_state.pending_open_container_id.take() {
        if modal_state.container.is_none() {
            modal_state.container = Some(game_bevy::UiContainerSessionState { container_id });
        }
        if modal_state.container.is_some() {
            menu_state.close_all_panels();
        }
    }

    let in_main_menu_scene = should_render_main_menu(*scene_kind);
    input_block_state.blocked = in_main_menu_scene
        || menu_state.any_panel_open()
        || modal_state.item_quantity.is_some()
        || modal_state.trade.is_some()
        || modal_state.container.is_some()
        || viewer_state.active_dialogue.is_some()
        || viewer_state.interaction_menu.is_some();
    if (in_main_menu_scene
        || menu_state.any_panel_open()
        || modal_state.item_quantity.is_some()
        || modal_state.trade.is_some()
        || modal_state.container.is_some()
        || viewer_state.active_dialogue.is_some())
        && viewer_state.interaction_menu.is_some()
    {
        viewer_state.interaction_menu = None;
    }
    input_block_state.reason = if in_main_menu_scene {
        "main_menu_scene".to_string()
    } else if modal_state.item_quantity.is_some() {
        "item_quantity".to_string()
    } else if modal_state.trade.is_some() {
        "trade".to_string()
    } else if modal_state.container.is_some() {
        "container".to_string()
    } else if viewer_state.active_dialogue.is_some() {
        "dialogue".to_string()
    } else if menu_state.any_panel_open() {
        "menu_panel".to_string()
    } else if viewer_state.interaction_menu.is_some() {
        "interaction_menu".to_string()
    } else {
        String::new()
    };

    if input_block_state.blocked && viewer_state.targeting_state.is_some() {
        cancel_targeting(&mut viewer_state, "targeting: 已取消");
    }

    let allow_ui_context_menu = modal_state.trade.is_some()
        || menu_state.is_panel_open(UiMenuPanel::Inventory)
        || menu_state.is_panel_open(UiMenuPanel::Skills);
    if in_main_menu_scene || modal_state.item_quantity.is_some() || !allow_ui_context_menu {
        inventory_context_menu.clear();
    }
}

pub(super) fn load_runtime_snapshot(
    path: &ViewerRuntimeSavePath,
) -> Result<Option<RuntimeSnapshot>, String> {
    if !path.0.exists() {
        return Ok(None);
    }
    let raw = fs::read_to_string(&path.0).map_err(|error| error.to_string())?;
    serde_json::from_str(&raw)
        .map(Some)
        .map_err(|error| error.to_string())
}

pub(super) fn save_runtime_snapshot(
    path: &ViewerRuntimeSavePath,
    runtime: &game_core::SimulationRuntime,
) {
    if let Some(parent) = path.0.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string_pretty(&runtime.save_snapshot()) {
        let _ = fs::write(&path.0, raw);
    }
}

pub(super) fn transition_to_gameplay_scene(
    scene_kind: &mut ViewerSceneKind,
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    status_text: &str,
) {
    *scene_kind = ViewerSceneKind::Gameplay;
    runtime_state.runtime.clear_gameplay_entry_transients();
    reset_viewer_runtime_transients(viewer_state);
    sync_viewer_runtime_basics(runtime_state, viewer_state);
    viewer_state.status_line = status_text.to_string();
    menu_state.main_menu_open = false;
    menu_state.close_all_panels();
    menu_state.selected_inventory_item = None;
    menu_state.selected_equipment_slot = None;
    menu_state.selected_skill_tree_id = None;
    menu_state.selected_skill_id = None;
    menu_state.selected_recipe_id = None;
    menu_state.selected_map_location_id = None;
    menu_state.status_text = status_text.to_string();
    modal_state.item_quantity = None;
    modal_state.trade = None;
    modal_state.container = None;
}

pub(super) fn should_render_main_menu(scene_kind: ViewerSceneKind) -> bool {
    scene_kind.is_main_menu()
}

pub(super) fn configure_runtime_after_restore(
    runtime: &mut game_core::SimulationRuntime,
    items: &ItemDefinitions,
    skills: &SkillDefinitions,
    recipes: &RecipeDefinitions,
    quests: &QuestDefinitions,
    shops: &ShopDefinitions,
    overworld: &OverworldDefinitions,
) {
    apply_gameplay_libraries(runtime, items, skills, recipes, quests, shops, overworld);
}

pub(super) fn apply_new_game_defaults(
    runtime: &mut game_core::SimulationRuntime,
    items: &ItemDefinitions,
) -> Result<(), String> {
    let actor_id = player_actor_id(runtime).ok_or_else(|| "missing_player".to_string())?;
    runtime
        .economy_mut()
        .clear_actor_loadout(actor_id)
        .map_err(|error| error.to_string())?;
    runtime
        .economy_mut()
        .set_actor_attribute(actor_id, "strength", 5);
    runtime
        .economy_mut()
        .set_actor_attribute(actor_id, "agility", 5);
    runtime
        .economy_mut()
        .set_actor_attribute(actor_id, "constitution", 5);
    for (item_id, count) in [
        (1008, 2),
        (1007, 1),
        (1006, 3),
        (1002, 1),
        (1003, 1),
        (2004, 1),
        (2013, 1),
        (2015, 1),
    ] {
        runtime
            .economy_mut()
            .add_item(actor_id, item_id, count, &items.0)
            .map_err(|error| error.to_string())?;
    }
    runtime
        .economy_mut()
        .add_ammo(actor_id, 1009, 12, &items.0)
        .map_err(|error| error.to_string())?;
    runtime
        .economy_mut()
        .equip_item(actor_id, 1002, Some("main_hand"), &items.0)
        .map_err(|error| error.to_string())?;
    let _ = runtime
        .economy_mut()
        .equip_item(actor_id, 2004, Some("body"), &items.0);
    let _ = runtime
        .economy_mut()
        .equip_item(actor_id, 2013, Some("legs"), &items.0);
    let _ = runtime
        .economy_mut()
        .equip_item(actor_id, 2015, Some("feet"), &items.0);
    for location_id in [
        "survivor_outpost_01",
        "survivor_outpost_01_perimeter",
        "street_a",
        "street_b",
        "factory",
        "supermarket",
    ] {
        let _ = runtime.submit_command(game_core::SimulationCommand::UnlockLocation {
            location_id: location_id.to_string(),
        });
    }
    Ok(())
}

pub(super) fn rebuild_runtime_with_new_game_defaults(
    items: &ItemDefinitions,
    skills: &SkillDefinitions,
    recipes: &RecipeDefinitions,
    quests: &QuestDefinitions,
    shops: &ShopDefinitions,
    overworld: &OverworldDefinitions,
) -> Result<game_core::SimulationRuntime, String> {
    let mut bootstrap = load_viewer_gameplay_bootstrap().map_err(|error| error.to_string())?;
    configure_runtime_after_restore(
        &mut bootstrap.runtime,
        items,
        skills,
        recipes,
        quests,
        shops,
        overworld,
    );
    apply_new_game_defaults(&mut bootstrap.runtime, items)?;
    Ok(bootstrap.runtime)
}

pub(super) fn skills_snapshot_for_player(
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    trees: &SkillTreeDefinitions,
) -> Option<game_bevy::UiSkillsSnapshot> {
    let actor_id = player_actor_id(&runtime_state.runtime)?;
    Some(skills_snapshot(
        &runtime_state.runtime,
        actor_id,
        &skills.0,
        &trees.0,
    ))
}

pub(super) fn find_skill_tree_id<'a>(
    snapshot: &'a game_bevy::UiSkillsSnapshot,
    skill_id: &str,
) -> Option<&'a str> {
    snapshot.trees.iter().find_map(|tree| {
        tree.entries
            .iter()
            .any(|entry| entry.skill_id == skill_id)
            .then_some(tree.tree_id.as_str())
    })
}
