//! Hover mesh outline：负责把当前 hovered 语义目标映射到可见 mesh 描边成员。

use super::*;
use crate::geometry::actor_at_grid;
use crate::picking::{BuildingPartKind, BuildingPartPickTarget, ViewerPickTarget};
use bevy_mesh_outline::MeshOutline;
use game_data::InteractionTargetId;

const STABLE_INTERACTION_HOVER_HOLD_SEC: f32 = 0.18;
const STABLE_INTERACTION_HOVER_CURSOR_EPSILON_PX: f32 = 0.5;

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) struct HoverOutlineMember {
    pub target: ViewerPickTarget,
}

impl HoverOutlineMember {
    pub(crate) fn new(target: ViewerPickTarget) -> Self {
        Self { target }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ActiveInteractionHover {
    pub semantic: ViewerPickTarget,
    pub display_grid: GridCoord,
    pub outline_kind: HoveredGridOutlineKind,
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct StableInteractionHoverState {
    pub active: Option<ActiveInteractionHover>,
    last_cursor_position: Option<Vec2>,
    remaining_hold_sec: f32,
}

pub(crate) fn sync_stable_interaction_hover(
    time: Res<Time>,
    runtime_state: Res<ViewerRuntimeState>,
    picking_state: Res<crate::picking::ViewerPickingState>,
    viewer_state: Res<ViewerState>,
    mut stable_hover: ResMut<StableInteractionHoverState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let raw_hover =
        resolve_active_interaction_hover(&runtime_state, &snapshot, &viewer_state, &picking_state);
    let cursor_position = picking_state.cursor_position;

    if let Some(active) = raw_hover {
        stable_hover.active = Some(active);
        stable_hover.last_cursor_position = cursor_position;
        stable_hover.remaining_hold_sec = STABLE_INTERACTION_HOVER_HOLD_SEC;
        return;
    }

    let cursor_unchanged = cursor_position.is_some()
        && stable_hover.last_cursor_position.is_some_and(|previous| {
            previous.distance(cursor_position.expect("cursor should exist"))
                <= STABLE_INTERACTION_HOVER_CURSOR_EPSILON_PX
        });
    stable_hover.last_cursor_position = cursor_position;

    if !cursor_unchanged || viewer_state.command_actor_id(&snapshot).is_none() {
        stable_hover.active = None;
        stable_hover.remaining_hold_sec = 0.0;
        return;
    }

    stable_hover.remaining_hold_sec =
        (stable_hover.remaining_hold_sec - time.delta_secs()).max(0.0);
    if stable_hover.remaining_hold_sec <= 0.0 {
        stable_hover.active = None;
        return;
    }

    stable_hover.active = stable_hover
        .active
        .as_ref()
        .and_then(|previous| refresh_preserved_hover(&snapshot, &viewer_state, previous));
    if stable_hover.active.is_none() {
        stable_hover.remaining_hold_sec = 0.0;
    }
}

pub(crate) fn sync_hover_mesh_outlines(
    mut commands: Commands,
    palette: Res<ViewerPalette>,
    stable_hover: Res<StableInteractionHoverState>,
    members: Query<(Entity, &HoverOutlineMember, Option<&MeshOutline>)>,
) {
    let active_hover = stable_hover.active.as_ref();
    let active_target = active_hover.as_ref().map(|hovered| &hovered.semantic);
    let active_outline = active_hover
        .as_ref()
        .map(|hovered| hover_mesh_outline(hover_outline_color(hovered, &palette)));

    for (entity, member, current_outline) in &members {
        let should_outline = active_target == Some(&member.target);
        match (should_outline, current_outline, active_outline.as_ref()) {
            (true, Some(current), Some(desired)) if outline_matches(current, desired) => {}
            (true, _, Some(desired)) => {
                commands.entity(entity).insert(desired.clone());
            }
            (false, Some(_), _) => {
                commands.entity(entity).remove::<MeshOutline>();
            }
            _ => {}
        }
    }
}

pub(super) fn resolve_active_interaction_hover(
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    picking_state: &crate::picking::ViewerPickingState,
) -> Option<ActiveInteractionHover> {
    let actor_id = viewer_state.command_actor_id(snapshot)?;

    if let Some(hovered) = picking_state.hovered.as_ref().and_then(|hovered| {
        resolve_hover_candidate(
            runtime_state,
            snapshot,
            viewer_state,
            actor_id,
            hovered.interaction.as_ref(),
            &hovered.semantic,
            picking_state
                .cursor_position
                .is_some()
                .then_some(viewer_state.hovered_grid)
                .flatten(),
        )
    }) {
        return Some(hovered);
    }

    let hovered_grid = viewer_state.hovered_grid?;
    resolve_hover_candidate_from_grid(
        runtime_state,
        snapshot,
        viewer_state,
        actor_id,
        hovered_grid,
    )
}

fn hover_mesh_outline(color: Color) -> MeshOutline {
    MeshOutline::new(HOVER_MESH_OUTLINE_WIDTH_PX)
        .with_intensity(HOVER_MESH_OUTLINE_INTENSITY)
        .with_priority(HOVER_MESH_OUTLINE_PRIORITY)
        .with_color(color)
}

fn outline_matches(current: &MeshOutline, desired: &MeshOutline) -> bool {
    current.width == desired.width
        && current.intensity == desired.intensity
        && current.priority == desired.priority
        && current.color.to_srgba() == desired.color.to_srgba()
}

fn resolve_hover_candidate(
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    actor_id: ActorId,
    interaction: Option<&InteractionTargetId>,
    semantic: &ViewerPickTarget,
    hovered_grid: Option<GridCoord>,
) -> Option<ActiveInteractionHover> {
    let target_id = interaction?;
    if !target_has_real_prompt(runtime_state, actor_id, target_id) {
        return None;
    }

    let display_grid =
        semantic_display_grid(snapshot, viewer_state.current_level, semantic, hovered_grid)?;
    Some(ActiveInteractionHover {
        semantic: semantic.clone(),
        display_grid,
        outline_kind: outline_kind_for_target(snapshot, semantic),
    })
}

fn resolve_hover_candidate_from_grid(
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    actor_id: ActorId,
    hovered_grid: GridCoord,
) -> Option<ActiveInteractionHover> {
    if let Some(actor) = actor_at_grid(snapshot, hovered_grid) {
        let semantic = ViewerPickTarget::Actor(actor.actor_id);
        let target_id = InteractionTargetId::Actor(actor.actor_id);
        if let Some(active) = resolve_hover_candidate(
            runtime_state,
            snapshot,
            viewer_state,
            actor_id,
            Some(&target_id),
            &semantic,
            Some(hovered_grid),
        ) {
            return Some(active);
        }
    }

    let mut candidates = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.occupied_cells.contains(&hovered_grid))
        .collect::<Vec<_>>();
    candidates.sort_by_key(|object| object_hover_priority(object));
    candidates.reverse();

    for object in candidates {
        let semantic = grid_hover_semantic_target(object, viewer_state.current_level, hovered_grid);
        let target_id = InteractionTargetId::MapObject(object.object_id.clone());
        if let Some(active) = resolve_hover_candidate(
            runtime_state,
            snapshot,
            viewer_state,
            actor_id,
            Some(&target_id),
            &semantic,
            Some(hovered_grid),
        ) {
            return Some(active);
        }
    }

    None
}

fn target_has_real_prompt(
    runtime_state: &ViewerRuntimeState,
    actor_id: ActorId,
    target_id: &InteractionTargetId,
) -> bool {
    runtime_state
        .runtime
        .peek_interaction_prompt(actor_id, target_id)
        .is_some_and(|prompt| !prompt.options.is_empty())
}

fn semantic_display_grid(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    semantic: &ViewerPickTarget,
    hovered_grid: Option<GridCoord>,
) -> Option<GridCoord> {
    match semantic {
        ViewerPickTarget::Actor(actor_id) => snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == *actor_id)
            .map(|actor| actor.grid_position),
        ViewerPickTarget::MapObject(object_id) => {
            let object = snapshot
                .grid
                .map_objects
                .iter()
                .find(|object| object.object_id == *object_id)?;
            hovered_grid
                .filter(|grid| object.occupied_cells.contains(grid))
                .or_else(|| {
                    object
                        .occupied_cells
                        .iter()
                        .copied()
                        .find(|grid| grid.y == current_level)
                })
                .or(Some(object.anchor))
        }
        ViewerPickTarget::BuildingPart(part) => Some(part.anchor_cell),
    }
}

fn grid_hover_semantic_target(
    object: &game_core::MapObjectDebugState,
    current_level: i32,
    hovered_grid: GridCoord,
) -> ViewerPickTarget {
    if object.kind == game_data::MapObjectKind::Trigger {
        return ViewerPickTarget::BuildingPart(BuildingPartPickTarget {
            building_object_id: object.object_id.clone(),
            story_level: current_level,
            kind: BuildingPartKind::TriggerCell,
            anchor_cell: hovered_grid,
        });
    }

    ViewerPickTarget::MapObject(object.object_id.clone())
}

fn object_hover_priority(object: &game_core::MapObjectDebugState) -> (usize, usize) {
    (
        usize::from(
            object
                .payload_summary
                .get("generated_door")
                .is_some_and(|value| value == "true"),
        ),
        usize::from(object.kind != game_data::MapObjectKind::Building),
    )
}

fn outline_kind_for_target(
    snapshot: &game_core::SimulationSnapshot,
    semantic: &ViewerPickTarget,
) -> HoveredGridOutlineKind {
    match semantic {
        ViewerPickTarget::Actor(actor_id) => snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == *actor_id)
            .filter(|actor| actor.side == ActorSide::Hostile)
            .map(|_| HoveredGridOutlineKind::Hostile)
            .unwrap_or(HoveredGridOutlineKind::Neutral),
        ViewerPickTarget::MapObject(object_id) => snapshot
            .grid
            .map_objects
            .iter()
            .find(|object| object.object_id == *object_id)
            .filter(|object| object.kind == game_data::MapObjectKind::AiSpawn)
            .map(|_| HoveredGridOutlineKind::Hostile)
            .unwrap_or(HoveredGridOutlineKind::Neutral),
        ViewerPickTarget::BuildingPart(part) => snapshot
            .grid
            .map_objects
            .iter()
            .find(|object| object.object_id == part.building_object_id)
            .filter(|object| object.kind == game_data::MapObjectKind::AiSpawn)
            .map(|_| HoveredGridOutlineKind::Hostile)
            .unwrap_or(HoveredGridOutlineKind::Neutral),
    }
}

fn hover_outline_color(hovered: &ActiveInteractionHover, palette: &ViewerPalette) -> Color {
    let base = match hovered.outline_kind {
        HoveredGridOutlineKind::Neutral => palette.hover_walkable,
        HoveredGridOutlineKind::Hostile => palette.hover_hostile,
    };
    with_alpha(base, 0.98)
}

fn refresh_preserved_hover(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    previous: &ActiveInteractionHover,
) -> Option<ActiveInteractionHover> {
    let display_grid = semantic_display_grid(
        snapshot,
        viewer_state.current_level,
        &previous.semantic,
        Some(previous.display_grid),
    )?;
    Some(ActiveInteractionHover {
        semantic: previous.semantic.clone(),
        display_grid,
        outline_kind: outline_kind_for_target(snapshot, &previous.semantic),
    })
}
