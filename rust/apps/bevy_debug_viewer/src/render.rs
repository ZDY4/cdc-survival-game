use std::collections::HashSet;

use bevy::prelude::*;
use bevy::sprite::{Anchor, Text2dShadow};
use game_data::ActorSide;

use crate::geometry::{
    actor_label, actor_label_translation, grid_bounds, render_cell_extent, rendered_path_preview,
    world_to_view_coord,
};
use crate::state::{
    ActorLabel, ActorLabelEntities, HudFooterText, HudText, InteractionMenuState,
    InteractionMenuText, ViewerCamera, ViewerRenderConfig, ViewerRuntimeState, ViewerState,
    ViewerUiFont, VIEWER_FONT_PATH,
};

const INTERACTION_MENU_WIDTH_PX: f32 = 288.0;
const INTERACTION_MENU_PADDING_PX: f32 = 12.0;
const INTERACTION_MENU_LINE_HEIGHT_PX: f32 = 17.0;
const INTERACTION_MENU_NON_OPTION_LINES: usize = 3;

#[derive(Debug, Clone, Copy)]
pub(crate) struct InteractionMenuLayout {
    pub left: f32,
    pub top: f32,
    pub width: f32,
    pub height: f32,
    pub option_top: f32,
}

impl InteractionMenuLayout {
    pub(crate) fn contains(self, cursor_position: Vec2) -> bool {
        cursor_position.x >= self.left
            && cursor_position.x <= self.left + self.width
            && cursor_position.y >= self.top
            && cursor_position.y <= self.top + self.height
    }
}

pub(crate) fn setup_viewer(mut commands: Commands, asset_server: Res<AssetServer>) {
    let ui_font = asset_server.load(VIEWER_FONT_PATH);
    commands.insert_resource(ViewerUiFont(ui_font.clone()));
    commands.spawn((Camera2d, ViewerCamera));
    commands
        .spawn((
            Text::new(""),
            TextFont::from_font_size(11.2).with_font(ui_font.clone()),
            Node {
                position_type: PositionType::Absolute,
                top: px(12),
                right: px(12),
                width: px(420),
                padding: UiRect::all(px(12)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.07, 0.09, 0.12, 0.92)),
            HudText,
        ))
        .with_child((
            TextSpan::new(""),
            TextFont::from_font_size(9.0).with_font(ui_font.clone()),
            TextColor(Color::srgba(0.79, 0.83, 0.88, 0.94)),
            HudFooterText,
        ));
    commands.spawn((
        Text::new(""),
        TextFont::from_font_size(11.0).with_font(ui_font),
        TextColor(Color::srgba(0.93, 0.95, 0.98, 0.96)),
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            width: px(INTERACTION_MENU_WIDTH_PX),
            padding: UiRect::all(px(INTERACTION_MENU_PADDING_PX)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.06, 0.07, 0.1, 0.96)),
        Visibility::Hidden,
        InteractionMenuText,
    ));
}

pub(crate) fn update_camera(
    mut camera_transform: Single<&mut Transform, With<ViewerCamera>>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let cell_extent = render_cell_extent(snapshot.grid.grid_size, *render_config);
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * cell_extent * 0.5;
    let center_y = (bounds.min_z + bounds.max_z + 1) as f32 * cell_extent * 0.5;

    camera_transform.translation.x = center_x + viewer_state.camera_pan_offset.x;
    camera_transform.translation.y = center_y + viewer_state.camera_pan_offset.y;
}

pub(crate) fn sync_actor_labels(
    mut commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    viewer_font: Res<ViewerUiFont>,
    mut label_entities: ResMut<ActorLabelEntities>,
    mut labels: Query<(&mut Text2d, &mut Transform, &mut TextColor, &ActorLabel)>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let mut seen_actor_ids = HashSet::new();

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let label = actor_label(actor);
        let color = actor_color(actor.side);
        let position = actor_label_translation(
            runtime_state.runtime.grid_to_world(actor.grid_position),
            snapshot.grid.grid_size,
            *render_config,
        );

        if let Some(entity) = label_entities.by_actor.get(&actor.actor_id).copied() {
            if let Ok((mut text, mut transform, mut text_color, actor_label)) =
                labels.get_mut(entity)
            {
                if actor_label.actor_id == actor.actor_id {
                    *text = Text2d::new(label);
                    *transform = Transform::from_translation(position);
                    *text_color = TextColor(color);
                    continue;
                }
            }
        }

        let entity = commands
            .spawn((
                Text2d::new(label),
                TextFont::from_font_size(13.5).with_font(viewer_font.0.clone()),
                TextLayout::new_with_justify(Justify::Center),
                TextColor(color),
                Text2dShadow::default(),
                Anchor::BOTTOM_CENTER,
                Transform::from_translation(position),
                ActorLabel {
                    actor_id: actor.actor_id,
                },
            ))
            .id();
        label_entities.by_actor.insert(actor.actor_id, entity);
    }

    let stale_actor_ids: Vec<_> = label_entities
        .by_actor
        .keys()
        .copied()
        .filter(|actor_id| !seen_actor_ids.contains(actor_id))
        .collect();
    for actor_id in stale_actor_ids {
        if let Some(entity) = label_entities.by_actor.remove(&actor_id) {
            commands.entity(entity).despawn();
        }
    }
}

pub(crate) fn update_interaction_menu(
    window: Single<&Window>,
    menu_text: Single<(&mut Text, &mut Node, &mut Visibility), With<InteractionMenuText>>,
    viewer_state: Res<ViewerState>,
) {
    let (mut text, mut node, mut visibility) = menu_text.into_inner();
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        *visibility = Visibility::Hidden;
        *text = Text::new("");
        return;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        *visibility = Visibility::Hidden;
        *text = Text::new("");
        return;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        *visibility = Visibility::Hidden;
        *text = Text::new("");
        return;
    }

    let layout = interaction_menu_layout(&window, menu_state, prompt);
    node.left = px(layout.left);
    node.top = px(layout.top);
    *text = Text::new(format_interaction_menu(prompt));
    *visibility = Visibility::Visible;
}

pub(crate) fn draw_world(
    mut gizmos: Gizmos,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    let cell_extent = render_cell_extent(grid_size, *render_config);

    for x in bounds.min_x..=bounds.max_x + 1 {
        let x_world = x as f32 * cell_extent;
        gizmos.line_2d(
            Vec2::new(x_world, bounds.min_z as f32 * cell_extent),
            Vec2::new(x_world, (bounds.max_z + 1) as f32 * cell_extent),
            Color::srgba(0.18, 0.22, 0.28, 0.9),
        );
    }

    for z in bounds.min_z..=bounds.max_z + 1 {
        let z_world = z as f32 * cell_extent;
        gizmos.line_2d(
            Vec2::new(bounds.min_x as f32 * cell_extent, z_world),
            Vec2::new((bounds.max_x + 1) as f32 * cell_extent, z_world),
            Color::srgba(0.18, 0.22, 0.28, 0.9),
        );
    }

    for cell in snapshot
        .grid
        .map_cells
        .iter()
        .filter(|cell| cell.grid.y == viewer_state.current_level)
    {
        let world = world_to_view_coord(
            runtime_state.runtime.grid_to_world(cell.grid),
            *render_config,
        );
        let color = if cell.blocks_movement {
            Color::srgba(0.52, 0.25, 0.22, 0.7)
        } else {
            Color::srgba(0.31, 0.41, 0.52, 0.45)
        };
        gizmos.rect_2d(world, Vec2::splat(cell_extent * 0.9), color);
    }

    for grid in snapshot
        .grid
        .static_obstacles
        .iter()
        .copied()
        .filter(|grid| grid.y == viewer_state.current_level)
    {
        let world = world_to_view_coord(runtime_state.runtime.grid_to_world(grid), *render_config);
        gizmos.rect_2d(
            world,
            Vec2::splat(cell_extent * 0.82),
            Color::srgb(0.67, 0.21, 0.21),
        );
    }

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == viewer_state.current_level)
    {
        let color = map_object_color(object.kind);
        for occupied_cell in &object.occupied_cells {
            let world = world_to_view_coord(
                runtime_state.runtime.grid_to_world(*occupied_cell),
                *render_config,
            );
            gizmos.rect_2d(
                world,
                Vec2::splat(cell_extent * 0.72),
                color.with_alpha(0.34),
            );
        }

        let anchor = world_to_view_coord(
            runtime_state.runtime.grid_to_world(object.anchor),
            *render_config,
        );
        gizmos.circle_2d(anchor, cell_extent * 0.14, color);
    }

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        let world = world_to_view_coord(
            runtime_state.runtime.grid_to_world(actor.grid_position),
            *render_config,
        );
        let color = actor_color(actor.side);
        gizmos.circle_2d(world, cell_extent * 0.22, color);

        if Some(actor.actor_id) == snapshot.combat.current_actor_id {
            gizmos.rect_2d(
                world,
                Vec2::splat(cell_extent * 0.7),
                Color::srgb(0.36, 0.86, 0.97),
            );
        }
    }

    let current_level_path: Vec<_> = rendered_path_preview(
        &runtime_state.runtime,
        &snapshot,
        runtime_state.runtime.pending_movement(),
    )
    .into_iter()
    .filter(|grid| grid.y == viewer_state.current_level)
    .collect();
    for path_segment in current_level_path.windows(2) {
        let start = world_to_view_coord(
            runtime_state.runtime.grid_to_world(path_segment[0]),
            *render_config,
        );
        let end = world_to_view_coord(
            runtime_state.runtime.grid_to_world(path_segment[1]),
            *render_config,
        );
        gizmos.line_2d(start, end, Color::srgba(0.96, 0.79, 0.24, 0.55));
    }

    if let Some(grid) = viewer_state.hovered_grid {
        let world = world_to_view_coord(runtime_state.runtime.grid_to_world(grid), *render_config);
        gizmos.rect_2d(
            world,
            Vec2::splat(cell_extent * 0.92),
            Color::srgb(0.35, 0.95, 0.64),
        );
    }
}

fn format_interaction_menu(prompt: &game_data::InteractionPrompt) -> String {
    let mut lines = vec![
        format!("Interaction · {}", prompt.target_name),
        "Left click target: execute primary interaction".to_string(),
        "Keyboard: E for primary, 1-9 for specific option".to_string(),
    ];

    lines.extend(prompt.options.iter().enumerate().map(|(index, option)| {
        let primary = if prompt.primary_option_id.as_ref() == Some(&option.id) {
            " [primary]"
        } else {
            ""
        };
        format!("{}. {}{}", index + 1, option.display_name, primary)
    }));

    lines.join("\n")
}

pub(crate) fn interaction_menu_layout(
    window: &Window,
    menu_state: &InteractionMenuState,
    prompt: &game_data::InteractionPrompt,
) -> InteractionMenuLayout {
    let option_count = prompt.options.len();
    let estimated_height = interaction_menu_height(option_count);
    let max_left = (window.width() - INTERACTION_MENU_WIDTH_PX - INTERACTION_MENU_PADDING_PX)
        .max(INTERACTION_MENU_PADDING_PX);
    let max_top = (window.height() - estimated_height - INTERACTION_MENU_PADDING_PX)
        .max(INTERACTION_MENU_PADDING_PX);
    let left = (menu_state.cursor_position.x + INTERACTION_MENU_PADDING_PX)
        .clamp(INTERACTION_MENU_PADDING_PX, max_left);
    let top = (menu_state.cursor_position.y + INTERACTION_MENU_PADDING_PX)
        .clamp(INTERACTION_MENU_PADDING_PX, max_top);

    InteractionMenuLayout {
        left,
        top,
        width: INTERACTION_MENU_WIDTH_PX,
        height: estimated_height,
        option_top: top
            + INTERACTION_MENU_PADDING_PX
            + INTERACTION_MENU_LINE_HEIGHT_PX * INTERACTION_MENU_NON_OPTION_LINES as f32,
    }
}

pub(crate) fn interaction_menu_option_at_cursor(
    layout: InteractionMenuLayout,
    cursor_position: Vec2,
    option_count: usize,
) -> Option<usize> {
    if !layout.contains(cursor_position) || cursor_position.y < layout.option_top {
        return None;
    }

    let option_index = ((cursor_position.y - layout.option_top) / INTERACTION_MENU_LINE_HEIGHT_PX)
        .floor() as usize;
    (option_index < option_count).then_some(option_index)
}

fn interaction_menu_height(option_count: usize) -> f32 {
    INTERACTION_MENU_PADDING_PX * 2.0
        + INTERACTION_MENU_LINE_HEIGHT_PX
            * (option_count + INTERACTION_MENU_NON_OPTION_LINES) as f32
}

#[cfg(test)]
mod tests {
    use super::{interaction_menu_layout, interaction_menu_option_at_cursor};
    use crate::state::InteractionMenuState;
    use bevy::prelude::*;
    use game_data::{
        ActorId, GridCoord, InteractionOptionId, InteractionPrompt, InteractionTargetId,
        ResolvedInteractionOption,
    };

    #[test]
    fn interaction_menu_layout_clamps_to_window_bounds() {
        let window = Window {
            resolution: (320, 180).into(),
            ..default()
        };
        let menu_state = InteractionMenuState {
            target_id: InteractionTargetId::MapObject("crate".into()),
            cursor_position: Vec2::new(310.0, 170.0),
        };
        let prompt = sample_prompt(2);

        let layout = interaction_menu_layout(&window, &menu_state, &prompt);

        assert!(layout.left >= 12.0);
        assert!(layout.top >= 12.0);
        assert!(layout.left + layout.width <= window.width() - 11.0);
        assert!(layout.top + layout.height <= window.height() - 11.0);
    }

    #[test]
    fn interaction_menu_hit_test_resolves_option_row() {
        let window = Window {
            resolution: (800, 600).into(),
            ..default()
        };
        let menu_state = InteractionMenuState {
            target_id: InteractionTargetId::MapObject("crate".into()),
            cursor_position: Vec2::new(120.0, 120.0),
        };
        let prompt = sample_prompt(3);
        let layout = interaction_menu_layout(&window, &menu_state, &prompt);
        let cursor = Vec2::new(layout.left + 24.0, layout.option_top + 17.0 * 1.4);

        assert_eq!(
            interaction_menu_option_at_cursor(layout, cursor, prompt.options.len()),
            Some(1)
        );
    }

    fn sample_prompt(option_count: usize) -> InteractionPrompt {
        InteractionPrompt {
            actor_id: ActorId(1),
            target_id: InteractionTargetId::MapObject("crate".into()),
            target_name: "Crate".into(),
            anchor_grid: GridCoord::new(1, 0, 1),
            primary_option_id: Some(InteractionOptionId("option_0".into())),
            options: (0..option_count)
                .map(|index| ResolvedInteractionOption {
                    id: InteractionOptionId(format!("option_{index}")),
                    display_name: format!("Option {index}"),
                    ..ResolvedInteractionOption::default()
                })
                .collect(),
        }
    }
}

fn actor_color(side: ActorSide) -> Color {
    match side {
        ActorSide::Player => Color::srgb(0.28, 0.72, 0.98),
        ActorSide::Friendly => Color::srgb(0.34, 0.88, 0.47),
        ActorSide::Hostile => Color::srgb(0.94, 0.36, 0.33),
        ActorSide::Neutral => Color::srgb(0.78, 0.78, 0.82),
    }
}

fn map_object_color(kind: game_data::MapObjectKind) -> Color {
    match kind {
        game_data::MapObjectKind::Building => Color::srgb(0.84, 0.58, 0.28),
        game_data::MapObjectKind::Pickup => Color::srgb(0.38, 0.85, 0.64),
        game_data::MapObjectKind::Interactive => Color::srgb(0.35, 0.66, 0.98),
        game_data::MapObjectKind::AiSpawn => Color::srgb(0.92, 0.38, 0.45),
    }
}
