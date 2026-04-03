#![allow(dead_code)]

use bevy::picking::hover::HoverMap;
use bevy::picking::mesh_picking::{MeshPickingPlugin, MeshPickingSettings};
use bevy::picking::pointer::PointerId;
use bevy::picking::prelude::Pickable;
use bevy::prelude::*;
use game_data::{ActorId, GridCoord, InteractionTargetId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ViewerPickTarget {
    Actor(ActorId),
    MapObject(String),
    BuildingPart(BuildingPartPickTarget),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BuildingPartPickTarget {
    pub building_object_id: String,
    pub story_level: i32,
    pub kind: BuildingPartKind,
    pub anchor_cell: GridCoord,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BuildingPartKind {
    WallCell,
    DoorFrame,
    TriggerCell,
    FloorCell,
    RoofCell,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum ViewerPickPriority {
    BuildingPart = 0,
    MapObject = 1,
    Trigger = 2,
    Actor = 3,
}

#[derive(Debug, Clone, PartialEq, Eq, Component)]
pub(crate) struct ViewerPickBinding {
    pub semantic: ViewerPickTarget,
    pub interaction: Option<InteractionTargetId>,
    pub priority: ViewerPickPriority,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ViewerPickBindingSpec {
    pub semantic: ViewerPickTarget,
    pub interaction: Option<InteractionTargetId>,
    pub priority: ViewerPickPriority,
}

impl ViewerPickBindingSpec {
    pub(crate) fn new(
        semantic: ViewerPickTarget,
        interaction: Option<InteractionTargetId>,
        priority: ViewerPickPriority,
    ) -> Self {
        Self {
            semantic,
            interaction,
            priority,
        }
    }

    pub(crate) fn actor(actor_id: ActorId) -> Self {
        Self::new(
            ViewerPickTarget::Actor(actor_id),
            Some(InteractionTargetId::Actor(actor_id)),
            ViewerPickPriority::Actor,
        )
    }

    pub(crate) fn map_object(object_id: impl Into<String>) -> Self {
        let object_id = object_id.into();
        Self::new(
            ViewerPickTarget::MapObject(object_id.clone()),
            Some(InteractionTargetId::MapObject(object_id)),
            ViewerPickPriority::MapObject,
        )
    }

    pub(crate) fn building_part(
        building_object_id: impl Into<String>,
        story_level: i32,
        kind: BuildingPartKind,
        anchor_cell: GridCoord,
    ) -> Self {
        let building_object_id = building_object_id.into();
        Self::new(
            ViewerPickTarget::BuildingPart(BuildingPartPickTarget {
                building_object_id: building_object_id.clone(),
                story_level,
                kind,
                anchor_cell,
            }),
            Some(InteractionTargetId::MapObject(building_object_id)),
            ViewerPickPriority::BuildingPart,
        )
    }

    pub(crate) fn trigger_cell(
        trigger_object_id: impl Into<String>,
        story_level: i32,
        anchor_cell: GridCoord,
    ) -> Self {
        let trigger_object_id = trigger_object_id.into();
        Self::new(
            ViewerPickTarget::BuildingPart(BuildingPartPickTarget {
                building_object_id: trigger_object_id.clone(),
                story_level,
                kind: BuildingPartKind::TriggerCell,
                anchor_cell,
            }),
            Some(InteractionTargetId::MapObject(trigger_object_id)),
            ViewerPickPriority::Trigger,
        )
    }
}

impl From<ViewerPickBindingSpec> for ViewerPickBinding {
    fn from(value: ViewerPickBindingSpec) -> Self {
        Self {
            semantic: value.semantic,
            interaction: value.interaction,
            priority: value.priority,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ViewerResolvedPick {
    pub entity: Entity,
    pub semantic: ViewerPickTarget,
    pub interaction: Option<InteractionTargetId>,
    pub priority: ViewerPickPriority,
    pub depth: f32,
    pub position: Option<Vec3>,
}

#[derive(Resource, Debug, Clone, Default, PartialEq)]
pub(crate) struct ViewerPickingState {
    pub hovered: Option<ViewerResolvedPick>,
    pub primary_click: Option<ViewerResolvedPick>,
    pub secondary_click: Option<ViewerResolvedPick>,
    pub cursor_position: Option<Vec2>,
}

impl ViewerPickingState {}

#[derive(Default)]
pub(crate) struct ViewerPickingPlugin;

impl Plugin for ViewerPickingPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(MeshPickingPlugin)
            .insert_resource(MeshPickingSettings {
                require_markers: true,
                ..default()
            })
            .init_resource::<ViewerPickingState>();
    }
}

pub(crate) fn sync_viewer_picking_state(
    window: Single<&Window>,
    buttons: Res<ButtonInput<MouseButton>>,
    hover_map: Res<HoverMap>,
    bindings: Query<&ViewerPickBinding>,
    mut picking_state: ResMut<ViewerPickingState>,
) {
    picking_state.cursor_position = window.cursor_position();
    picking_state.primary_click = None;
    picking_state.secondary_click = None;

    let hovered = resolve_hovered_pick(&hover_map, &bindings);
    picking_state.hovered = hovered.clone();

    if buttons.just_pressed(MouseButton::Left) {
        picking_state.primary_click = hovered.clone();
    }
    if buttons.just_pressed(MouseButton::Right) {
        picking_state.secondary_click = hovered;
    }
}

pub(crate) fn pickable_target(binding: ViewerPickBinding) -> (Pickable, ViewerPickBinding) {
    (Pickable::default(), binding)
}

fn resolve_hovered_pick(
    hover_map: &HoverMap,
    bindings: &Query<&ViewerPickBinding>,
) -> Option<ViewerResolvedPick> {
    let interaction = hover_map.get(&PointerId::Mouse)?;
    if interaction.is_empty() {
        return None;
    }

    let mut best: Option<ViewerResolvedPick> = None;
    for (entity, hit) in interaction.iter() {
        let Ok(binding) = bindings.get(*entity) else {
            continue;
        };
        let candidate = ViewerResolvedPick {
            entity: *entity,
            semantic: binding.semantic.clone(),
            interaction: binding.interaction.clone(),
            priority: binding.priority,
            depth: hit.depth,
            position: hit.position,
        };
        if should_replace_pick(best.as_ref(), &candidate) {
            best = Some(candidate);
        }
    }
    best
}

fn should_replace_pick(
    current: Option<&ViewerResolvedPick>,
    candidate: &ViewerResolvedPick,
) -> bool {
    match current {
        None => true,
        Some(current) => {
            candidate.priority > current.priority
                || (candidate.priority == current.priority && candidate.depth < current.depth)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_higher_priority_pick() {
        let current = ViewerResolvedPick {
            entity: Entity::from_bits(1),
            semantic: ViewerPickTarget::MapObject("crate".into()),
            interaction: Some(InteractionTargetId::MapObject("crate".into())),
            priority: ViewerPickPriority::MapObject,
            depth: 0.1,
            position: None,
        };
        let candidate = ViewerResolvedPick {
            entity: Entity::from_bits(2),
            semantic: ViewerPickTarget::Actor(ActorId(1)),
            interaction: Some(InteractionTargetId::Actor(ActorId(1))),
            priority: ViewerPickPriority::Actor,
            depth: 0.2,
            position: None,
        };

        assert!(should_replace_pick(Some(&current), &candidate));
    }

    #[test]
    fn prefers_nearer_pick_when_priorities_match() {
        let current = ViewerResolvedPick {
            entity: Entity::from_bits(1),
            semantic: ViewerPickTarget::MapObject("a".into()),
            interaction: Some(InteractionTargetId::MapObject("a".into())),
            priority: ViewerPickPriority::MapObject,
            depth: 0.3,
            position: None,
        };
        let candidate = ViewerResolvedPick {
            entity: Entity::from_bits(2),
            semantic: ViewerPickTarget::MapObject("b".into()),
            interaction: Some(InteractionTargetId::MapObject("b".into())),
            priority: ViewerPickPriority::MapObject,
            depth: 0.2,
            position: None,
        };

        assert!(should_replace_pick(Some(&current), &candidate));
    }

    #[test]
    fn actor_pick_binding_projects_to_actor_interaction() {
        let binding = ViewerPickBindingSpec::actor(ActorId(7));

        assert_eq!(binding.semantic, ViewerPickTarget::Actor(ActorId(7)));
        assert_eq!(
            binding.interaction,
            Some(InteractionTargetId::Actor(ActorId(7)))
        );
        assert_eq!(binding.priority, ViewerPickPriority::Actor);
    }

    #[test]
    fn building_wall_pick_binding_projects_to_parent_building_object() {
        let binding = ViewerPickBindingSpec::building_part(
            "house_01",
            2,
            BuildingPartKind::WallCell,
            GridCoord::new(4, 2, 9),
        );

        assert_eq!(
            binding.semantic,
            ViewerPickTarget::BuildingPart(BuildingPartPickTarget {
                building_object_id: "house_01".into(),
                story_level: 2,
                kind: BuildingPartKind::WallCell,
                anchor_cell: GridCoord::new(4, 2, 9),
            })
        );
        assert_eq!(
            binding.interaction,
            Some(InteractionTargetId::MapObject("house_01".into()))
        );
        assert_eq!(binding.priority, ViewerPickPriority::BuildingPart);
    }

    #[test]
    fn trigger_pick_binding_uses_trigger_priority_and_target() {
        let binding =
            ViewerPickBindingSpec::trigger_cell("edge_trigger", 0, GridCoord::new(1, 0, 0));

        assert_eq!(
            binding.interaction,
            Some(InteractionTargetId::MapObject("edge_trigger".into()))
        );
        assert_eq!(binding.priority, ViewerPickPriority::Trigger);
        assert_eq!(
            binding.semantic,
            ViewerPickTarget::BuildingPart(BuildingPartPickTarget {
                building_object_id: "edge_trigger".into(),
                story_level: 0,
                kind: BuildingPartKind::TriggerCell,
                anchor_cell: GridCoord::new(1, 0, 0),
            })
        );
    }
}
