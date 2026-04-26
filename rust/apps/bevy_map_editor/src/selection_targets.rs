use bevy::light::{NotShadowCaster, NotShadowReceiver};
use bevy::prelude::*;
use bevy_egui::input::EguiWantsInput;
use bevy_mesh_outline::MeshOutline;
use game_bevy::world_render::{build_generated_door_mesh_spec, WorldRenderScene};
use game_bevy::StaticWorldSemantic;
use game_data::WorldTileLibrary;

use crate::camera::ray_point_on_horizontal_plane;
use crate::state::{
    EditorCamera, EditorSelectionTarget, EditorState, EditorUiState, LibraryView, SceneEntity,
};

const SELECTED_OUTLINE_COLOR: Color = Color::srgba(0.98, 0.62, 0.22, 1.0);
const SELECTED_OUTLINE_FILL_COLOR: Color = Color::srgba(0.98, 0.62, 0.22, 0.035);
const SELECTED_OUTLINE_WIDTH_PX: f32 = 4.0;
const SELECTED_OUTLINE_INTENSITY: f32 = 1.0;
const SELECTED_OUTLINE_PRIORITY: f32 = 8.0;
const SELECTED_OUTLINE_LIFT_WORLD: f32 = 0.03;
const SELECTED_OUTLINE_PADDING_WORLD: f32 = 0.04;
const DECAL_PICK_THICKNESS_WORLD: f32 = 0.04;
const PICK_DISTANCE_EPSILON: f32 = 0.0001;

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct EditorSelectionIndex {
    visible_candidates: Vec<SelectionCandidate>,
    proxy_candidates: Vec<SelectionCandidate>,
}

impl EditorSelectionIndex {
    pub(crate) fn clear(&mut self) {
        self.visible_candidates.clear();
        self.proxy_candidates.clear();
    }

    fn resolve_pick(&self, ray: Ray3d) -> Option<EditorResolvedPick> {
        resolve_pick_from_candidates(ray, &self.visible_candidates)
            .or_else(|| resolve_pick_from_candidates(ray, &self.proxy_candidates))
    }

    fn outline_bounds_for(&self, semantic: &StaticWorldSemantic) -> Option<SelectionBounds> {
        outline_bounds_for_semantic(&self.visible_candidates, semantic)
            .or_else(|| outline_bounds_for_semantic(&self.proxy_candidates, semantic))
    }
}

#[derive(Debug, Clone, PartialEq)]
struct SelectionCandidate {
    semantic: StaticWorldSemantic,
    volume: SelectionVolume,
    outline_bounds: SelectionBounds,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct SelectionVolume {
    center: Vec3,
    rotation: Quat,
    half_extents: Vec3,
}

impl SelectionVolume {
    fn from_box(size: Vec3, translation: Vec3) -> Self {
        Self::from_center_half_extents(translation, Quat::IDENTITY, size * 0.5)
    }

    fn from_center_half_extents(center: Vec3, rotation: Quat, half_extents: Vec3) -> Self {
        Self {
            center,
            rotation,
            half_extents: Vec3::new(
                half_extents.x.max(0.01),
                half_extents.y.max(0.01),
                half_extents.z.max(0.01),
            ),
        }
    }

    fn outline_bounds(self) -> SelectionBounds {
        SelectionBounds::from_center_half_extents(
            self.center,
            rotated_half_extents(self.rotation, self.half_extents),
        )
    }

    fn ray_intersection_distance(self, ray: Ray3d) -> Option<f32> {
        let inverse_rotation = self.rotation.inverse();
        let local_origin = inverse_rotation * (ray.origin - self.center);
        let local_direction = inverse_rotation * *ray.direction;

        let (mut t_min, mut t_max) = axis_intersection(
            local_origin.x,
            local_direction.x,
            -self.half_extents.x,
            self.half_extents.x,
        )?;
        let (ty_min, ty_max) = axis_intersection(
            local_origin.y,
            local_direction.y,
            -self.half_extents.y,
            self.half_extents.y,
        )?;
        if t_min > ty_max || ty_min > t_max {
            return None;
        }
        t_min = t_min.max(ty_min);
        t_max = t_max.min(ty_max);

        let (tz_min, tz_max) = axis_intersection(
            local_origin.z,
            local_direction.z,
            -self.half_extents.z,
            self.half_extents.z,
        )?;
        if t_min > tz_max || tz_min > t_max {
            return None;
        }
        t_min = t_min.max(tz_min);
        t_max = t_max.min(tz_max);

        if t_max < 0.0 {
            None
        } else {
            Some(t_min.max(0.0))
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct SelectionBounds {
    center: Vec3,
    half_extents: Vec3,
}

impl SelectionBounds {
    fn from_center_half_extents(center: Vec3, half_extents: Vec3) -> Self {
        Self {
            center,
            half_extents: Vec3::new(
                half_extents.x.max(0.01),
                half_extents.y.max(0.01),
                half_extents.z.max(0.01),
            ),
        }
    }

    fn size(self) -> Vec3 {
        self.half_extents * 2.0
    }

    fn volume(self) -> f32 {
        let size = self.size();
        size.x * size.y * size.z
    }

    fn min(self) -> Vec3 {
        self.center - self.half_extents
    }

    fn max(self) -> Vec3 {
        self.center + self.half_extents
    }

    fn union(self, other: Self) -> Self {
        let min = self.min().min(other.min());
        let max = self.max().max(other.max());
        Self::from_center_half_extents((min + max) * 0.5, (max - min) * 0.5)
    }
}

#[derive(Debug, Clone, PartialEq)]
struct EditorResolvedPick {
    semantic: StaticWorldSemantic,
    distance: f32,
    bounds_volume: f32,
}

#[derive(Component, Debug, Clone, PartialEq)]
pub(crate) struct SelectedOutlineVisualState {
    target: EditorSelectionTarget,
    bounds: SelectionBounds,
}

pub(crate) fn build_selection_index_from_scene(
    scene: &WorldRenderScene,
    world_tiles: &WorldTileLibrary,
    floor_thickness_world: f32,
) -> EditorSelectionIndex {
    let mut index = EditorSelectionIndex::default();

    for placement in &scene.tile_placements {
        if let Some(semantic) = placement.semantic.as_ref() {
            if let Some(volume) = tile_placement_volume(placement, world_tiles) {
                index.visible_candidates.push(SelectionCandidate {
                    semantic: semantic.clone(),
                    outline_bounds: volume.outline_bounds(),
                    volume,
                });
            }
        }

        if let Some(proxy) = placement.pick_proxy.as_ref() {
            if let Some(semantic) = proxy.semantic.as_ref() {
                let volume = SelectionVolume::from_box(proxy.size, proxy.translation);
                index.proxy_candidates.push(SelectionCandidate {
                    semantic: semantic.clone(),
                    outline_bounds: volume.outline_bounds(),
                    volume,
                });
            }
        }
    }

    for spec in &scene.static_scene.boxes {
        if let Some(semantic) = spec.semantic.as_ref() {
            let volume = SelectionVolume::from_box(spec.size, spec.translation);
            index.visible_candidates.push(SelectionCandidate {
                semantic: semantic.clone(),
                outline_bounds: volume.outline_bounds(),
                volume,
            });
        }
    }

    for spec in &scene.static_scene.decals {
        if let Some(semantic) = spec.semantic.as_ref() {
            let volume = decal_volume(spec);
            index.visible_candidates.push(SelectionCandidate {
                semantic: semantic.clone(),
                outline_bounds: volume.outline_bounds(),
                volume,
            });
        }
    }

    for spec in &scene.static_scene.pick_proxies {
        if let Some(semantic) = spec.semantic.as_ref() {
            let volume = SelectionVolume::from_box(spec.size, spec.translation);
            index.proxy_candidates.push(SelectionCandidate {
                semantic: semantic.clone(),
                outline_bounds: volume.outline_bounds(),
                volume,
            });
        }
    }

    let floor_top =
        scene.current_level as f32 * scene.static_scene.grid_size + floor_thickness_world;
    for door in &scene.generated_doors {
        let Some(mesh_spec) =
            build_generated_door_mesh_spec(door, floor_top, scene.static_scene.grid_size)
        else {
            continue;
        };
        let rotation = Quat::from_rotation_y(if door.is_open {
            mesh_spec.open_yaw
        } else {
            0.0
        });
        let volume = SelectionVolume::from_center_half_extents(
            mesh_spec.pivot_translation + rotation * mesh_spec.local_aabb_center,
            rotation,
            mesh_spec.local_aabb_half_extents,
        );
        index.visible_candidates.push(SelectionCandidate {
            semantic: StaticWorldSemantic::MapObject(door.map_object_id.clone()),
            outline_bounds: volume.outline_bounds(),
            volume,
        });
    }

    index
}

pub(crate) fn handle_primary_selection_system(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<EditorCamera>>,
    buttons: Res<ButtonInput<MouseButton>>,
    egui_wants_input: Res<EguiWantsInput>,
    selection_index: Res<EditorSelectionIndex>,
    mut editor: ResMut<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
) {
    if !buttons.just_pressed(MouseButton::Left) || egui_wants_input.wants_any_pointer_input() {
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        return;
    };
    if ui_state
        .scene_viewport
        .is_some_and(|viewport| !viewport.contains(cursor_position))
    {
        return;
    }

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        return;
    };

    let next_selection = selection_index
        .resolve_pick(ray)
        .map(|pick| EditorSelectionTarget::SceneSemantic(pick.semantic))
        .or_else(|| fallback_grid_selection(&editor, ray));
    if next_selection == ui_state.selected_target {
        return;
    }

    ui_state.selected_target = next_selection.clone();
    editor.status = match next_selection {
        Some(EditorSelectionTarget::SceneSemantic(StaticWorldSemantic::MapObject(id))) => {
            format!("Selected object {id}.")
        }
        Some(EditorSelectionTarget::SceneSemantic(StaticWorldSemantic::TriggerCell {
            object_id,
            story_level,
            cell,
        })) => format!(
            "Selected trigger cell for {object_id} at ({}, {}, {}) on story level {story_level}.",
            cell.x, cell.y, cell.z
        ),
        Some(EditorSelectionTarget::GridCell(grid)) => {
            format!("Selected grid ({}, {}, {}).", grid.x, grid.y, grid.z)
        }
        None => "Selection cleared.".to_string(),
    };
}

pub(crate) fn sync_selected_outline_visual_system(
    mut commands: Commands,
    selection_index: Res<EditorSelectionIndex>,
    ui_state: Res<EditorUiState>,
    render_config: Res<game_bevy::world_render::WorldRenderConfig>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    current_visuals: Query<(Entity, &SelectedOutlineVisualState)>,
) {
    let desired_visual = ui_state
        .selected_target
        .as_ref()
        .and_then(|target| selected_outline_visual_state(target, &selection_index, &render_config));

    let mut needs_respawn = desired_visual.is_some();
    for (entity, current) in &current_visuals {
        if desired_visual.as_ref() == Some(current) {
            needs_respawn = false;
            continue;
        }
        commands.entity(entity).despawn();
    }

    let Some(desired_visual) = desired_visual else {
        return;
    };
    if !needs_respawn {
        return;
    }

    let size = desired_visual.bounds.size() + Vec3::splat(SELECTED_OUTLINE_PADDING_WORLD);
    let center = desired_visual.bounds.center + Vec3::Y * SELECTED_OUTLINE_LIFT_WORLD;
    let mesh = meshes.add(Cuboid::new(size.x, size.y, size.z));
    let material = materials.add(StandardMaterial {
        base_color: SELECTED_OUTLINE_FILL_COLOR,
        alpha_mode: AlphaMode::Blend,
        unlit: true,
        double_sided: true,
        ..default()
    });

    commands.spawn((
        SceneEntity,
        desired_visual,
        Mesh3d(mesh),
        MeshMaterial3d(material),
        Transform::from_translation(center),
        MeshOutline::new(SELECTED_OUTLINE_WIDTH_PX)
            .with_intensity(SELECTED_OUTLINE_INTENSITY)
            .with_priority(SELECTED_OUTLINE_PRIORITY)
            .with_color(SELECTED_OUTLINE_COLOR),
        NotShadowCaster,
        NotShadowReceiver,
    ));
}

fn selected_outline_visual_state(
    target: &EditorSelectionTarget,
    selection_index: &EditorSelectionIndex,
    render_config: &game_bevy::world_render::WorldRenderConfig,
) -> Option<SelectedOutlineVisualState> {
    let bounds = match target {
        EditorSelectionTarget::SceneSemantic(semantic) => {
            selection_index.outline_bounds_for(semantic)?
        }
        EditorSelectionTarget::GridCell(grid) => SelectionBounds::from_center_half_extents(
            Vec3::new(
                grid.x as f32 + 0.5,
                grid.y as f32 + render_config.floor_thickness_world * 0.5,
                grid.z as f32 + 0.5,
            ),
            Vec3::new(
                0.5,
                render_config.floor_thickness_world.max(0.04) * 0.5,
                0.5,
            ),
        ),
    };

    Some(SelectedOutlineVisualState {
        target: target.clone(),
        bounds,
    })
}

fn fallback_grid_selection(editor: &EditorState, ray: Ray3d) -> Option<EditorSelectionTarget> {
    let point = ray_point_on_horizontal_plane(ray, 0.0)?;
    let grid = match editor.selected_view {
        LibraryView::Maps => {
            let selected_map_id = editor.selected_map_id.as_ref()?;
            let document = editor.maps.get(selected_map_id)?;
            let grid = IVec2::new(point.x.floor() as i32, point.z.floor() as i32);
            if grid.x < 0
                || grid.y < 0
                || grid.x >= document.definition.size.width as i32
                || grid.y >= document.definition.size.height as i32
            {
                return None;
            }
            game_data::GridCoord::new(grid.x, editor.current_map_level, grid.y)
        }
        LibraryView::Overworlds => {
            let selected_overworld_id = editor.selected_overworld_id.as_ref()?;
            let definition = editor
                .overworld_library
                .get(&game_data::OverworldId(selected_overworld_id.clone()))?;
            let grid = IVec2::new(point.x.floor() as i32, point.z.floor() as i32);
            if grid.x < 0
                || grid.y < 0
                || grid.x >= definition.size.width as i32
                || grid.y >= definition.size.height as i32
            {
                return None;
            }
            game_data::GridCoord::new(grid.x, 0, grid.y)
        }
    };

    Some(EditorSelectionTarget::GridCell(grid))
}

fn tile_placement_volume(
    placement: &game_bevy::tile_world::TilePlacementSpec,
    world_tiles: &WorldTileLibrary,
) -> Option<SelectionVolume> {
    let prototype = world_tiles.prototype(&placement.prototype_id)?;
    let local_center = Vec3::new(
        prototype.bounds.center.x * placement.scale.x,
        prototype.bounds.center.y * placement.scale.y,
        prototype.bounds.center.z * placement.scale.z,
    );
    let local_half_extents = Vec3::new(
        prototype.bounds.size.x * 0.5 * placement.scale.x.abs().max(0.001),
        prototype.bounds.size.y * 0.5 * placement.scale.y.abs().max(0.001),
        prototype.bounds.size.z * 0.5 * placement.scale.z.abs().max(0.001),
    );
    Some(SelectionVolume::from_center_half_extents(
        placement.translation + placement.rotation * local_center,
        placement.rotation,
        local_half_extents,
    ))
}

fn decal_volume(spec: &game_bevy::StaticWorldDecalSpec) -> SelectionVolume {
    SelectionVolume::from_center_half_extents(
        spec.translation,
        spec.rotation,
        Vec3::new(
            spec.size.x * 0.5,
            DECAL_PICK_THICKNESS_WORLD * 0.5,
            spec.size.y * 0.5,
        ),
    )
}

fn rotated_half_extents(rotation: Quat, local_half_extents: Vec3) -> Vec3 {
    let right = rotation * Vec3::X;
    let up = rotation * Vec3::Y;
    let forward = rotation * Vec3::Z;

    Vec3::new(
        right.x.abs() * local_half_extents.x
            + up.x.abs() * local_half_extents.y
            + forward.x.abs() * local_half_extents.z,
        right.y.abs() * local_half_extents.x
            + up.y.abs() * local_half_extents.y
            + forward.y.abs() * local_half_extents.z,
        right.z.abs() * local_half_extents.x
            + up.z.abs() * local_half_extents.y
            + forward.z.abs() * local_half_extents.z,
    )
}

fn resolve_pick_from_candidates(
    ray: Ray3d,
    candidates: &[SelectionCandidate],
) -> Option<EditorResolvedPick> {
    let mut best = None;
    for candidate in candidates {
        let Some(distance) = candidate.volume.ray_intersection_distance(ray) else {
            continue;
        };
        let resolved = EditorResolvedPick {
            semantic: candidate.semantic.clone(),
            distance,
            bounds_volume: candidate.outline_bounds.volume(),
        };
        if should_replace_pick(best.as_ref(), &resolved) {
            best = Some(resolved);
        }
    }
    best
}

fn outline_bounds_for_semantic(
    candidates: &[SelectionCandidate],
    semantic: &StaticWorldSemantic,
) -> Option<SelectionBounds> {
    candidates
        .iter()
        .filter(|candidate| &candidate.semantic == semantic)
        .map(|candidate| candidate.outline_bounds)
        .reduce(|current, next| current.union(next))
}

fn should_replace_pick(
    current: Option<&EditorResolvedPick>,
    candidate: &EditorResolvedPick,
) -> bool {
    match current {
        None => true,
        Some(current) => {
            candidate.distance < current.distance - PICK_DISTANCE_EPSILON
                || ((candidate.distance - current.distance).abs() <= PICK_DISTANCE_EPSILON
                    && candidate.bounds_volume < current.bounds_volume)
        }
    }
}

fn axis_intersection(origin: f32, direction: f32, min: f32, max: f32) -> Option<(f32, f32)> {
    if direction.abs() <= f32::EPSILON {
        if origin < min || origin > max {
            return None;
        }
        return Some((f32::NEG_INFINITY, f32::INFINITY));
    }

    let inverse = 1.0 / direction;
    let mut t0 = (min - origin) * inverse;
    let mut t1 = (max - origin) * inverse;
    if t0 > t1 {
        std::mem::swap(&mut t0, &mut t1);
    }
    Some((t0, t1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn visible_candidates_beat_proxy_hits() {
        let index = EditorSelectionIndex {
            visible_candidates: vec![SelectionCandidate {
                semantic: StaticWorldSemantic::MapObject("visible".into()),
                volume: SelectionVolume::from_box(Vec3::splat(1.0), Vec3::new(0.0, 0.0, 5.0)),
                outline_bounds: SelectionBounds::from_center_half_extents(
                    Vec3::new(0.0, 0.0, 5.0),
                    Vec3::splat(0.5),
                ),
            }],
            proxy_candidates: vec![SelectionCandidate {
                semantic: StaticWorldSemantic::MapObject("proxy".into()),
                volume: SelectionVolume::from_box(Vec3::splat(2.0), Vec3::new(0.0, 0.0, 1.0)),
                outline_bounds: SelectionBounds::from_center_half_extents(
                    Vec3::new(0.0, 0.0, 1.0),
                    Vec3::splat(1.0),
                ),
            }],
        };

        let ray = Ray3d::new(Vec3::ZERO, Dir3::Z);
        let pick = index.resolve_pick(ray).expect("pick should resolve");

        assert_eq!(
            pick.semantic,
            StaticWorldSemantic::MapObject("visible".into())
        );
    }

    #[test]
    fn rotated_volume_is_precise_to_local_bounds() {
        let volume = SelectionVolume::from_center_half_extents(
            Vec3::new(0.0, 0.0, 3.0),
            Quat::from_rotation_y(std::f32::consts::FRAC_PI_4),
            Vec3::new(0.3, 0.3, 1.2),
        );

        let centered_ray = Ray3d::new(Vec3::new(0.0, 0.0, 0.0), Dir3::Z);
        let offset_ray = Ray3d::new(
            Vec3::new(1.1, 0.0, 0.0),
            Dir3::new(Vec3::new(0.0, 0.0, 1.0)).unwrap(),
        );

        assert!(volume.ray_intersection_distance(centered_ray).is_some());
        assert!(volume.ray_intersection_distance(offset_ray).is_none());
    }

    #[test]
    fn outline_bounds_prefer_visible_geometry() {
        let semantic = StaticWorldSemantic::MapObject("crate".into());
        let index = EditorSelectionIndex {
            visible_candidates: vec![SelectionCandidate {
                semantic: semantic.clone(),
                volume: SelectionVolume::from_box(Vec3::new(1.0, 2.0, 3.0), Vec3::ZERO),
                outline_bounds: SelectionBounds::from_center_half_extents(
                    Vec3::ZERO,
                    Vec3::new(0.5, 1.0, 1.5),
                ),
            }],
            proxy_candidates: vec![SelectionCandidate {
                semantic: semantic.clone(),
                volume: SelectionVolume::from_box(Vec3::splat(6.0), Vec3::ZERO),
                outline_bounds: SelectionBounds::from_center_half_extents(
                    Vec3::ZERO,
                    Vec3::splat(3.0),
                ),
            }],
        };

        let outline = index
            .outline_bounds_for(&semantic)
            .expect("outline bounds should resolve");

        assert_eq!(outline.size(), Vec3::new(1.0, 2.0, 3.0));
    }
}
