//! 静态世界构建：负责地面、建筑、楼梯、触发器与静态 occluder 规格收集和生成。

use super::*;

pub(super) fn rebuild_static_world(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    palette: &ViewerPalette,
    trigger_decal_assets: &TriggerDecalAssets,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
    static_world_state: &mut StaticWorldVisualState,
) {
    static_world_state.entities.clear();
    static_world_state.occluders.clear();

    let ground_entity = spawn_ground_plane(
        commands,
        meshes,
        ground_materials,
        snapshot,
        current_level,
        render_config,
        palette,
        bounds,
    );
    static_world_state.entities.push(ground_entity);

    for spec in collect_static_world_box_specs(
        snapshot,
        current_level,
        hide_building_roofs,
        render_config,
        palette,
        bounds,
        |grid| runtime_state.runtime.grid_to_world(grid),
    ) {
        let occluder_kind = spec.occluder_kind.clone();
        let spawned = spawn_box(commands, meshes, materials, building_wall_materials, spec);
        static_world_state.entities.push(spawned.entity);
        if occluder_kind.is_some() {
            static_world_state
                .occluders
                .push(occluder_visual_from_spawned_box(spawned));
        }
    }

    for spec in collect_static_world_mesh_specs(
        snapshot,
        current_level,
        hide_building_roofs,
        render_config,
        palette,
    ) {
        let occluder_kind = spec.occluder_kind.clone();
        let spawned = spawn_mesh_spec(commands, meshes, materials, building_wall_materials, spec);
        static_world_state.entities.push(spawned.entity);
        if occluder_kind.is_some() {
            static_world_state
                .occluders
                .push(occluder_visual_from_spawned_mesh(spawned));
        }
    }

    for spec in collect_static_world_decal_specs(snapshot, current_level, render_config, palette) {
        let entity = spawn_decal(
            commands,
            meshes,
            materials,
            &trigger_decal_assets.arrow_texture,
            spec,
        );
        static_world_state.entities.push(entity);
    }
}

pub(crate) fn collect_static_world_box_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    _hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    bounds: GridBounds,
    _grid_to_world: impl FnMut(GridCoord) -> game_data::WorldCoord,
) -> Vec<StaticWorldBoxSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;
    let generated_building_ids: HashSet<_> = snapshot
        .generated_buildings
        .iter()
        .map(|building| building.object_id.as_str())
        .collect();
    let mut rendered_cells = collect_rendered_map_cells(
        snapshot,
        current_level,
        &generated_building_ids,
    );

    for building in snapshot.generated_buildings.iter().filter(|building| {
        building
            .stories
            .iter()
            .any(|story| story.level == current_level)
    }) {
        push_generated_building_stair_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            palette,
        );
    }

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
    {
        if is_generated_door_object(object) {
            continue;
        }
        if object.kind == game_data::MapObjectKind::Building
            && generated_building_ids.contains(object.object_id.as_str())
        {
            continue;
        }
        if object.kind != game_data::MapObjectKind::Building && !object_has_viewer_function(object)
        {
            continue;
        }
        if object.kind != game_data::MapObjectKind::Building {
            rendered_cells.extend(object.occupied_cells.iter().copied());
        }
        let (center_x, center_z, footprint_width, footprint_depth) =
            occupied_cells_box(&object.occupied_cells, grid_size);
        let anchor_noise = cell_style_noise(
            render_config.object_style_seed.wrapping_add(409),
            object.anchor.x,
            object.anchor.z,
        );
        let base_color = map_object_color(object.kind, palette);
        let object_pick_binding = Some(ViewerPickBindingSpec::map_object(object.object_id.clone()));

        match object.kind {
            game_data::MapObjectKind::Building => {}
            game_data::MapObjectKind::Pickup => {
                let plinth_height = grid_size * 0.08;
                let core_height = grid_size * 0.22;
                let side = grid_size * 0.28;
                push_box_spec(
                    &mut specs,
                    Vec3::new(grid_size * 0.42, plinth_height, grid_size * 0.42),
                    Vec3::new(center_x, floor_top + plinth_height * 0.5, center_z),
                    darken_color(base_color, 0.18),
                    MaterialStyle::UtilityAccent,
                    None,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(side, core_height, side),
                    Vec3::new(
                        center_x,
                        floor_top + plinth_height + core_height * 0.5,
                        center_z,
                    ),
                    base_color,
                    MaterialStyle::Utility,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                    object_pick_binding,
                );
            }
            game_data::MapObjectKind::Interactive => {
                let pillar_height = grid_size * (0.72 + anchor_noise * 0.16);
                let width = footprint_width.min(grid_size * 0.46);
                push_box_spec(
                    &mut specs,
                    Vec3::new(grid_size * 0.52, grid_size * 0.08, grid_size * 0.52),
                    Vec3::new(center_x, floor_top + grid_size * 0.04, center_z),
                    darken_color(base_color, 0.16),
                    MaterialStyle::UtilityAccent,
                    None,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(
                        width.max(0.16),
                        pillar_height,
                        footprint_depth.min(grid_size * 0.42),
                    ),
                    Vec3::new(center_x, floor_top + pillar_height * 0.5, center_z),
                    base_color,
                    MaterialStyle::Utility,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                    object_pick_binding.clone(),
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(width.max(0.16) * 0.58, grid_size * 0.16, grid_size * 0.22),
                    Vec3::new(
                        center_x,
                        floor_top + pillar_height + grid_size * 0.08,
                        center_z,
                    ),
                    lighten_color(base_color, 0.12),
                    MaterialStyle::UtilityAccent,
                    None,
                    None,
                );
            }
            game_data::MapObjectKind::Trigger => {
                if is_scene_transition_trigger(object) {
                    for cell in &object.occupied_cells {
                        push_box_spec(
                            &mut specs,
                            Vec3::new(grid_size * 0.92, grid_size * 0.12, grid_size * 0.92),
                            Vec3::new(
                                (cell.x as f32 + 0.5) * grid_size,
                                floor_top + grid_size * 0.06,
                                (cell.z as f32 + 0.5) * grid_size,
                            ),
                            Color::srgba(1.0, 1.0, 1.0, 0.0),
                            MaterialStyle::InvisiblePickProxy,
                            None,
                            Some(ViewerPickBindingSpec::trigger_cell(
                                object.object_id.clone(),
                                current_level,
                                *cell,
                            )),
                        );
                    }
                    continue;
                }
                for cell in &object.occupied_cells {
                    push_trigger_cell_specs(
                        &mut specs,
                        *cell,
                        object.rotation,
                        floor_top,
                        grid_size,
                        base_color,
                        ViewerPickBindingSpec::trigger_cell(
                            object.object_id.clone(),
                            current_level,
                            *cell,
                        ),
                    );
                }
            }
            game_data::MapObjectKind::AiSpawn => {
                let beacon_height = grid_size * (0.34 + anchor_noise * 0.16);
                let side = grid_size * 0.28;
                push_box_spec(
                    &mut specs,
                    Vec3::new(grid_size * 0.52, grid_size * 0.06, grid_size * 0.52),
                    Vec3::new(center_x, floor_top + grid_size * 0.03, center_z),
                    darken_color(base_color, 0.2),
                    MaterialStyle::UtilityAccent,
                    None,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(side, beacon_height, side),
                    Vec3::new(center_x, floor_top + beacon_height * 0.5, center_z),
                    base_color,
                    MaterialStyle::Utility,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                    object_pick_binding.clone(),
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(side * 0.55, grid_size * 0.16, side * 0.55),
                    Vec3::new(
                        center_x,
                        floor_top + beacon_height + grid_size * 0.08,
                        center_z,
                    ),
                    lighten_color(base_color, 0.18),
                    MaterialStyle::UtilityAccent,
                    None,
                    None,
                );
            }
        }
    }

    push_unrendered_blocked_map_cell_wireframes(
        &mut specs,
        snapshot,
        current_level,
        floor_top,
        grid_size,
        bounds,
        &rendered_cells,
    );

    specs
}

fn collect_rendered_map_cells(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    generated_building_ids: &HashSet<&str>,
) -> HashSet<GridCoord> {
    let mut cells = HashSet::new();

    for building in snapshot.generated_buildings.iter().filter(|building| {
        generated_building_ids.contains(building.object_id.as_str())
            && building
                .stories
                .iter()
                .any(|story| story.level == current_level)
    }) {
        let Some(story) = building
            .stories
            .iter()
            .find(|story| story.level == current_level)
        else {
            continue;
        };
        cells.extend(story.wall_cells.iter().copied());
    }

    cells
}

fn push_unrendered_blocked_map_cell_wireframes(
    specs: &mut Vec<StaticWorldBoxSpec>,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    bounds: GridBounds,
    rendered_cells: &HashSet<GridCoord>,
) {
    for cell in snapshot
        .grid
        .map_cells
        .iter()
        .filter(|cell| cell.grid.y == current_level)
        .filter(|cell| cell.blocks_movement)
        .filter(|cell| cell.grid.x >= bounds.min_x && cell.grid.x <= bounds.max_x)
        .filter(|cell| cell.grid.z >= bounds.min_z && cell.grid.z <= bounds.max_z)
        .filter(|cell| !rendered_cells.contains(&cell.grid))
    {
        push_wireframe_cell_box_specs(specs, cell.grid, floor_top, grid_size);
    }
}

fn push_wireframe_cell_box_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    grid: GridCoord,
    floor_top: f32,
    grid_size: f32,
) {
    let box_width = grid_size * 0.92;
    let box_height = grid_size * 0.92;
    let line_thickness = (grid_size * 0.045).clamp(0.02, 0.08);
    let vertical_height = (box_height - line_thickness * 2.0).max(line_thickness);
    let horizontal_span = (box_width - line_thickness * 2.0).max(line_thickness);
    let center_x = (grid.x as f32 + 0.5) * grid_size;
    let center_z = (grid.z as f32 + 0.5) * grid_size;
    let center_y = floor_top + box_height * 0.5;
    let half_width = box_width * 0.5;
    let half_height = box_height * 0.5;
    let edge_offset = half_width - line_thickness * 0.5;
    let vertical_y = center_y;
    let top_y = center_y + half_height - line_thickness * 0.5;
    let bottom_y = center_y - half_height + line_thickness * 0.5;
    let color = Color::srgba(0.95, 0.18, 0.18, 1.0);

    for x_sign in [-1.0, 1.0] {
        for z_sign in [-1.0, 1.0] {
            push_box_spec(
                specs,
                Vec3::new(line_thickness, vertical_height, line_thickness),
                Vec3::new(
                    center_x + x_sign * edge_offset,
                    vertical_y,
                    center_z + z_sign * edge_offset,
                ),
                color,
                MaterialStyle::UtilityAccent,
                None,
                None,
            );
        }
    }

    for y in [bottom_y, top_y] {
        for z_sign in [-1.0, 1.0] {
            push_box_spec(
                specs,
                Vec3::new(horizontal_span, line_thickness, line_thickness),
                Vec3::new(center_x, y, center_z + z_sign * edge_offset),
                color,
                MaterialStyle::UtilityAccent,
                None,
                None,
            );
        }
        for x_sign in [-1.0, 1.0] {
            push_box_spec(
                specs,
                Vec3::new(line_thickness, line_thickness, horizontal_span),
                Vec3::new(center_x + x_sign * edge_offset, y, center_z),
                color,
                MaterialStyle::UtilityAccent,
                None,
                None,
            );
        }
    }
}

pub(crate) fn collect_static_world_mesh_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    _hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) -> Vec<StaticWorldMeshSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    for building in snapshot.generated_buildings.iter().filter(|building| {
        building
            .stories
            .iter()
            .any(|story| story.level == current_level)
    }) {
        push_generated_building_wall_mesh_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            palette,
        );
        push_generated_building_mesh_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            palette,
        );
    }

    specs
}

pub(crate) fn collect_static_world_decal_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) -> Vec<StaticWorldDecalSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter(|object| object.kind == game_data::MapObjectKind::Trigger)
        .filter(|object| is_scene_transition_trigger(object))
    {
        for cell in &object.occupied_cells {
            push_trigger_decal_spec(
                &mut specs,
                *cell,
                object.rotation,
                floor_top,
                grid_size,
                palette.trigger,
            );
        }
    }

    specs
}

pub(super) fn push_generated_building_stair_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    for stair in &building.stairs {
        push_generated_stair_specs(specs, stair, current_level, floor_top, grid_size, palette);
    }
}

pub(super) fn push_generated_building_wall_mesh_specs(
    specs: &mut Vec<StaticWorldMeshSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    let Some(story) = building
        .stories
        .iter()
        .find(|story| story.level == current_level)
    else {
        return;
    };

    let wall_height = grid_size * story.wall_height;
    let wall_thickness = (grid_size * story.wall_thickness).clamp(0.02, grid_size);
    let wall_color = darken_color(palette.building_base, 0.2);

    let wall_cells = story.wall_cells.iter().copied().collect::<HashSet<_>>();
    let occluder_kind = Some(StaticWorldOccluderKind::MapObject(
        game_data::MapObjectKind::Building,
    ));
    for wall in &story.wall_cells {
        push_generated_wall_tile_mesh_spec(
            specs,
            *wall,
            &wall_cells,
            floor_top,
            wall_height,
            wall_thickness,
            grid_size,
            wall_color,
            occluder_kind.clone(),
            Some(ViewerPickBindingSpec::building_part(
                building.object_id.clone(),
                current_level,
                BuildingPartKind::WallCell,
                *wall,
            )),
        );
    }
}

pub(super) fn push_generated_building_mesh_specs(
    specs: &mut Vec<StaticWorldMeshSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    let Some(story) = building
        .stories
        .iter()
        .find(|story| story.level == current_level)
    else {
        return;
    };

    let interior_floor_color = lerp_color(palette.building_top, palette.building_base, 0.38);

    for polygon in &story.walkable_polygons.polygons.polygons {
        push_polygon_prism_mesh_spec(
            specs,
            polygon,
            building.anchor,
            grid_size,
            floor_top + grid_size * 0.0405,
            floor_top + grid_size * 0.0755,
            interior_floor_color,
            MaterialStyle::StructureAccent,
            None,
            None,
        );
    }
}

pub(super) fn push_generated_stair_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    stair: &game_core::GeneratedStairConnection,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    let step_height = grid_size * 0.09;
    let landing_height = grid_size * 0.05;
    let direction = stair_run_direction(stair);

    if stair.from_level == current_level {
        for rect in merge_cells_into_rects(&stair.from_cells) {
            let center = rect_world_center(rect, grid_size);
            let base_size = rect_world_size(rect, grid_size, grid_size * 0.84);
            push_box_spec(
                specs,
                Vec3::new(base_size.x, landing_height, base_size.z),
                Vec3::new(center.x, floor_top + landing_height * 0.5, center.z),
                darken_color(palette.interactive, 0.18),
                MaterialStyle::UtilityAccent,
                None,
                None,
            );

            let run_span = if direction.x.abs() > direction.y.abs() {
                base_size.x
            } else {
                base_size.z
            };
            for step_index in 0..3 {
                let lift = (step_index + 1) as f32;
                let shift = (step_index as f32 - 0.8) * run_span * 0.12;
                let step_center = Vec3::new(
                    center.x + direction.x * shift,
                    floor_top + landing_height + step_height * (lift - 0.5),
                    center.z + direction.y * shift,
                );
                let scale = 1.0 - step_index as f32 * 0.16;
                let step_size = if direction.x.abs() > direction.y.abs() {
                    Vec3::new(base_size.x * scale, step_height, base_size.z * 0.86)
                } else {
                    Vec3::new(base_size.x * 0.86, step_height, base_size.z * scale)
                };
                push_box_spec(
                    specs,
                    step_size,
                    step_center,
                    lighten_color(palette.interactive, 0.08 + step_index as f32 * 0.05),
                    MaterialStyle::Utility,
                    None,
                    None,
                );
            }
        }
    }

    if stair.to_level == current_level {
        for rect in merge_cells_into_rects(&stair.to_cells) {
            let center = rect_world_center(rect, grid_size);
            let size = rect_world_size(rect, grid_size, grid_size * 0.7);
            push_box_spec(
                specs,
                Vec3::new(size.x, landing_height, size.z),
                Vec3::new(center.x, floor_top + landing_height * 0.5, center.z),
                lighten_color(palette.current_turn, 0.12),
                MaterialStyle::UtilityAccent,
                None,
                None,
            );
        }
    }
}

pub(super) fn stair_run_direction(stair: &game_core::GeneratedStairConnection) -> Vec2 {
    let count = stair.from_cells.len().max(1) as f32;
    let delta_x = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.x - from.x) as f32)
        .sum::<f32>()
        / count;
    let delta_z = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.z - from.z) as f32)
        .sum::<f32>()
        / count;

    if delta_x.abs() > delta_z.abs() && delta_x.abs() > f32::EPSILON {
        Vec2::new(delta_x.signum(), 0.0)
    } else if delta_z.abs() > f32::EPSILON {
        Vec2::new(0.0, delta_z.signum())
    } else {
        Vec2::new(0.0, 1.0)
    }
}

pub(super) fn spawn_ground_plane(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    bounds: GridBounds,
) -> Entity {
    let grid_size = snapshot.grid.grid_size;
    let width = (bounds.max_x - bounds.min_x + 1).max(1) as f32 * grid_size;
    let depth = (bounds.max_z - bounds.min_z + 1).max(1) as f32 * grid_size;
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    let floor_y =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world * 0.5;
    let material = ground_materials.add(GridGroundMaterial {
        base: StandardMaterial {
            base_color: Color::WHITE,
            perceptual_roughness: 0.97,
            reflectance: 0.03,
            metallic: 0.0,
            opaque_render_method: OpaqueRendererMethod::Forward,
            ..default()
        },
        extension: GridGroundMaterialExt {
            world_origin: Vec2::new(
                bounds.min_x as f32 * grid_size,
                bounds.min_z as f32 * grid_size,
            ),
            grid_size,
            line_width: 0.035,
            variation_strength: render_config.ground_variation_strength,
            seed: render_config.object_style_seed,
            dark_color: palette.ground_dark,
            light_color: palette.ground_light,
            edge_color: palette.ground_edge,
        },
    });

    commands
        .spawn((
            Mesh3d(meshes.add(Cuboid::new(
                width.max(grid_size),
                render_config.floor_thickness_world.max(0.02),
                depth.max(grid_size),
            ))),
            MeshMaterial3d(material),
            Transform::from_xyz(center_x, floor_y, center_z),
        ))
        .id()
}

pub(crate) fn push_box_spec(
    specs: &mut Vec<StaticWorldBoxSpec>,
    size: Vec3,
    translation: Vec3,
    color: Color,
    material_style: MaterialStyle,
    occluder_kind: Option<StaticWorldOccluderKind>,
    pick_binding: Option<ViewerPickBindingSpec>,
) {
    specs.push(StaticWorldBoxSpec {
        size,
        translation,
        color,
        material_style,
        occluder_kind,
        pick_binding,
    });
}
