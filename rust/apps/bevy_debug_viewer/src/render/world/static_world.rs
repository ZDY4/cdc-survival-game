//! 共享静态世界适配层：把 `game_bevy::static_world` 的共享 scene spec
//! 映射到 debug viewer 的材质、拾取与 occlusion 语义。

use super::*;
use bevy::camera::visibility::NoFrustumCulling;
use game_bevy::static_world as shared_static_world;
use game_bevy::static_world::{
    build_static_world_from_simulation_snapshot, StaticWorldBuildConfig,
    StaticWorldMaterialRole as SharedRole, StaticWorldSceneSpec as SharedSceneSpec,
    StaticWorldSemantic as SharedSemantic,
};
use game_bevy::tile_world::TileRenderClass;
use game_bevy::world_render::{
    build_world_render_scene_from_simulation_snapshot, make_building_wall_material,
    prepare_tile_batch_scene, PreparedTileBatch, PreparedTileInstance,
    WorldRenderBuildingWallTileBatchSource, WorldRenderConfig as SharedWorldRenderConfig,
    WorldRenderStandardTileBatchMaterialState, WorldRenderStandardTileBatchSource,
    WorldRenderTileBatchRoot, WorldRenderTileBatchVisualState,
};

pub(super) fn rebuild_static_world(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    asset_server: &AssetServer,
    world_tiles: &game_bevy::WorldTileDefinitions,
    palette: &ViewerPalette,
    trigger_decal_assets: &TriggerDecalAssets,
    _runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    _hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
    static_world_state: &mut StaticWorldVisualState,
) {
    static_world_state.entities.clear();
    static_world_state.occluders.clear();
    static_world_state.occluder_by_tile_instance.clear();
    static_world_state.tile_instances.clear();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    let world_render_scene = build_world_render_scene_from_simulation_snapshot(
        snapshot,
        current_level,
        SharedWorldRenderConfig {
            camera_yaw_degrees: render_config.camera_yaw_degrees,
            camera_pitch_degrees: render_config.camera_pitch_degrees,
            camera_fov_degrees: render_config.camera_fov_degrees,
            floor_thickness_world: render_config.floor_thickness_world,
            ground_variation_strength: render_config.ground_variation_strength,
            object_style_seed: render_config.object_style_seed,
        },
        Some(shared_bounds(bounds)),
        &world_tiles.0,
    );
    let shared_scene = world_render_scene.static_scene.clone();
    let tile_scene = world_render_scene.resolve_tile_scene(&world_tiles.0);
    let prepared_tile_scene = prepare_tile_batch_scene(asset_server, &world_tiles.0, &tile_scene);

    static_world_state
        .entities
        .extend(spawn_shared_ground_sections(
            commands,
            meshes,
            ground_materials,
            render_config,
            palette,
            &shared_scene.ground,
        ));

    for spec in shared_scene
        .boxes
        .into_iter()
        .map(shared_box_spec_to_viewer_box_spec)
    {
        let occluder_cells = spec.occluder_cells.clone();
        let occluder_kind = spec.occluder_kind.clone();
        let spawned = spawn_box(commands, meshes, materials, building_wall_materials, spec);
        static_world_state.entities.push(spawned.entity);
        if occluder_kind.is_some() {
            static_world_state
                .occluders
                .push(occluder_visual_from_spawned_box(
                    spawned,
                    occluder_cells,
                    floor_top,
                    grid_size,
                    render_config,
                ));
        }
    }

    for spec in prepared_tile_scene
        .pick_proxies
        .into_iter()
        .map(shared_box_spec_to_viewer_box_spec)
    {
        let spawned = spawn_box(commands, meshes, materials, building_wall_materials, spec);
        static_world_state.entities.push(spawned.entity);
    }

    for batch in prepared_tile_scene.batches {
        let batch_root = commands
            .spawn((
                Transform::IDENTITY,
                GlobalTransform::IDENTITY,
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                WorldRenderTileBatchRoot { id: batch.id },
                WorldRenderTileBatchVisualState::default(),
            ))
            .id();
        let mut render_entities = Vec::new();
        for render_primitive in &batch.render_primitives {
            let mut render_entity = commands.spawn((
                Mesh3d(render_primitive.mesh.clone()),
                Transform::IDENTITY,
                GlobalTransform::IDENTITY,
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                NoFrustumCulling,
                WorldRenderTileBatchVisualState::default(),
            ));
            match batch.key.render_class {
                TileRenderClass::Standard => {
                    render_entity.insert((
                        WorldRenderStandardTileBatchSource {
                            logical_batch_entity: batch_root,
                            material: render_primitive.standard_material.clone().unwrap_or_else(
                                || {
                                    materials.add(StandardMaterial {
                                        base_color: Color::WHITE,
                                        ..default()
                                    })
                                },
                            ),
                            prototype_local_transform: render_primitive.local_transform,
                        },
                        WorldRenderStandardTileBatchMaterialState::default(),
                    ));
                }
                TileRenderClass::BuildingWallGrid(visual_kind) => {
                    render_entity.insert(WorldRenderBuildingWallTileBatchSource {
                        logical_batch_entity: batch_root,
                        visual_kind,
                        prototype_local_transform: render_primitive.local_transform,
                    });
                }
            }
            let render_entity = render_entity.id();
            commands.entity(batch_root).add_child(render_entity);
            static_world_state.entities.push(render_entity);
            render_entities.push(render_entity);
        }
        static_world_state.entities.push(batch_root);
        let standard_instance_material =
            if matches!(batch.key.render_class, TileRenderClass::Standard) {
                Some(
                    batch
                        .primary_render_primitive()
                        .and_then(|primitive| primitive.standard_material.clone())
                        .unwrap_or_else(|| {
                            materials.add(StandardMaterial {
                                base_color: Color::WHITE,
                                ..default()
                            })
                        }),
                )
            } else {
                None
            };
        let building_wall_instance_material = match batch.key.render_class {
            TileRenderClass::BuildingWallGrid(visual_kind) => Some(make_building_wall_material(
                building_wall_materials,
                game_bevy::world_render::building_wall_visual_profile(visual_kind),
            )),
            TileRenderClass::Standard => None,
        };
        for instance in &batch.instances {
            let Some((spawned, occluder_cells, occluder_kind)) = spawn_tile_instance(
                commands,
                meshes,
                materials,
                building_wall_materials,
                &batch,
                instance,
                standard_instance_material.clone(),
                building_wall_instance_material.clone(),
            ) else {
                continue;
            };
            commands.entity(batch_root).add_child(spawned.entity);
            static_world_state.entities.push(spawned.entity);
            if let Some(handle) = spawned.tile_instance_handle {
                static_world_state.tile_instances.insert(
                    handle,
                    StaticWorldTileInstanceVisual {
                        entity: spawned.entity,
                        material: spawned.material.clone(),
                        material_fade_enabled: false,
                        base_color: spawned.color,
                        base_alpha: spawned.color.to_srgba().alpha,
                        base_alpha_mode: AlphaMode::Opaque,
                        desired_faded: false,
                        applied_faded: false,
                    },
                );
            }
            if occluder_kind.is_some() {
                static_world_state
                    .occluders
                    .push(occluder_visual_from_spawned_mesh(
                        spawned,
                        occluder_cells,
                        floor_top,
                        grid_size,
                        render_config,
                    ));
            }
        }
    }

    for spec in shared_scene
        .decals
        .into_iter()
        .map(shared_decal_spec_to_viewer_decal_spec)
    {
        let entity = spawn_decal(
            commands,
            meshes,
            materials,
            &trigger_decal_assets.arrow_texture,
            spec,
        );
        static_world_state.entities.push(entity);
    }

    static_world_state.rebuild_occluder_index();
}

fn spawn_tile_instance(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    batch: &PreparedTileBatch,
    instance: &PreparedTileInstance,
    standard_instance_material: Option<Handle<StandardMaterial>>,
    building_wall_instance_material: Option<StaticWorldMaterialHandle>,
) -> Option<(
    SpawnedMeshVisual,
    Vec<GridCoord>,
    Option<StaticWorldOccluderKind>,
)> {
    let semantic = instance.semantic.clone();
    let pick_binding = semantic.as_ref().map(shared_semantic_to_binding);
    let outline_target = pick_binding
        .as_ref()
        .map(|binding| binding.semantic.clone());

    let spawned = match batch.key.render_class {
        TileRenderClass::BuildingWallGrid(_) => {
            let wall_cell = instance
                .occluder_cells
                .first()
                .copied()
                .expect("building wall tile should keep a single wall cell");
            let wall_pick_binding = match semantic.as_ref() {
                Some(shared_static_world::StaticWorldSemantic::MapObject(object_id)) => {
                    Some(ViewerPickBindingSpec::building_part(
                        object_id.clone(),
                        wall_cell.y,
                        crate::picking::BuildingPartKind::WallCell,
                        wall_cell,
                    ))
                }
                _ => pick_binding,
            };
            let outline_target = wall_pick_binding
                .as_ref()
                .map(|binding| binding.semantic.clone())
                .or(outline_target);
            let spawned_box = spawn_box(
                commands,
                meshes,
                materials,
                building_wall_materials,
                StaticWorldBoxSpec {
                    size: instance.world_aabb_half_extents * 2.0,
                    translation: instance.world_aabb_center,
                    color: Color::srgba(1.0, 1.0, 1.0, 0.0),
                    material_style: MaterialStyle::InvisiblePickProxy,
                    occluder_kind: None,
                    occluder_cells: Vec::new(),
                    pick_binding: wall_pick_binding,
                    outline_target,
                },
            );
            commands.entity(spawned_box.entity).insert((
                game_bevy::world_render::WorldRenderTileInstanceTag {
                    handle: instance.handle,
                },
                game_bevy::world_render::WorldRenderTileInstanceVisualState::default(),
            ));
            SpawnedMeshVisual {
                entity: spawned_box.entity,
                material: building_wall_instance_material
                    .expect("building wall tile metadata should carry wall material"),
                tile_instance_handle: Some(instance.handle),
                aabb_center: instance.world_aabb_center,
                aabb_half_extents: instance.world_aabb_half_extents,
                color: Color::WHITE,
            }
        }
        TileRenderClass::Standard => {
            let _ = pick_binding;
            let _ = outline_target;
            spawn_standard_tile_instance_metadata(
                commands,
                instance,
                standard_instance_material
                    .expect("standard tile batches should provide a material handle"),
            )
        }
    };

    Some((
        spawned,
        instance.occluder_cells.clone(),
        instance.occluder_kind.clone().map(|kind| match kind {
            shared_static_world::StaticWorldOccluderKind::MapObject(kind) => {
                StaticWorldOccluderKind::MapObject(kind)
            }
        }),
    ))
}

fn spawn_standard_tile_instance_metadata(
    commands: &mut Commands,
    instance: &PreparedTileInstance,
    material: Handle<StandardMaterial>,
) -> SpawnedMeshVisual {
    let entity = commands
        .spawn((
            instance.transform,
            GlobalTransform::from(instance.transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            game_bevy::world_render::WorldRenderTileInstanceTag {
                handle: instance.handle,
            },
            game_bevy::world_render::WorldRenderTileInstanceVisualState::default(),
        ))
        .id();

    SpawnedMeshVisual {
        entity,
        material: StaticWorldMaterialHandle::Standard(material),
        tile_instance_handle: Some(instance.handle),
        aabb_center: instance.world_aabb_center,
        aabb_half_extents: instance.world_aabb_half_extents,
        color: Color::WHITE,
    }
}

fn shared_bounds(bounds: GridBounds) -> shared_static_world::StaticWorldGridBounds {
    shared_static_world::StaticWorldGridBounds {
        min_x: bounds.min_x,
        max_x: bounds.max_x,
        min_z: bounds.min_z,
        max_z: bounds.max_z,
    }
}

fn shared_material_role_to_viewer_material_style(
    role: shared_static_world::StaticWorldMaterialRole,
) -> MaterialStyle {
    match role {
        shared_static_world::StaticWorldMaterialRole::Ground
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundRoad
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundPlain
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundForest
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundRiver
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundLake
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundMountain
        | shared_static_world::StaticWorldMaterialRole::OverworldGroundUrban
        | shared_static_world::StaticWorldMaterialRole::BuildingFloor => {
            MaterialStyle::StructureAccent
        }
        shared_static_world::StaticWorldMaterialRole::BuildingDoor => MaterialStyle::BuildingDoor,
        shared_static_world::StaticWorldMaterialRole::StairBase
        | shared_static_world::StaticWorldMaterialRole::PickupBase
        | shared_static_world::StaticWorldMaterialRole::InteractiveBase
        | shared_static_world::StaticWorldMaterialRole::OverworldCell
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationGeneric
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationHospital
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationSchool
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationStore
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationStreet
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationOutpost
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationFactory
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationForest
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationRuins
        | shared_static_world::StaticWorldMaterialRole::OverworldLocationSubway => {
            MaterialStyle::Utility
        }
        shared_static_world::StaticWorldMaterialRole::StairAccent
        | shared_static_world::StaticWorldMaterialRole::PickupAccent
        | shared_static_world::StaticWorldMaterialRole::InteractiveAccent
        | shared_static_world::StaticWorldMaterialRole::TriggerBase
        | shared_static_world::StaticWorldMaterialRole::TriggerAccent
        | shared_static_world::StaticWorldMaterialRole::OverworldBlockedCell
        | shared_static_world::StaticWorldMaterialRole::Warning => MaterialStyle::UtilityAccent,
        shared_static_world::StaticWorldMaterialRole::InvisiblePickProxy => {
            MaterialStyle::InvisiblePickProxy
        }
    }
}

fn shared_semantic_to_binding(
    semantic: &shared_static_world::StaticWorldSemantic,
) -> ViewerPickBindingSpec {
    match semantic {
        shared_static_world::StaticWorldSemantic::MapObject(object_id) => {
            ViewerPickBindingSpec::map_object(object_id.clone())
        }
        shared_static_world::StaticWorldSemantic::TriggerCell {
            object_id,
            story_level,
            cell,
        } => ViewerPickBindingSpec::trigger_cell(object_id.clone(), *story_level, *cell),
    }
}

fn shared_box_spec_to_viewer_box_spec(
    spec: shared_static_world::StaticWorldBoxSpec,
) -> StaticWorldBoxSpec {
    let pick_binding = spec.semantic.as_ref().map(shared_semantic_to_binding);
    let outline_target = pick_binding
        .as_ref()
        .map(|binding| binding.semantic.clone());
    StaticWorldBoxSpec {
        size: spec.size,
        translation: spec.translation,
        color: shared_static_world::default_color_for_role(spec.material_role),
        material_style: shared_material_role_to_viewer_material_style(spec.material_role),
        occluder_kind: spec.occluder_kind.map(|kind| match kind {
            shared_static_world::StaticWorldOccluderKind::MapObject(kind) => {
                StaticWorldOccluderKind::MapObject(kind)
            }
        }),
        occluder_cells: spec.occluder_cells,
        pick_binding,
        outline_target,
    }
}

fn shared_decal_spec_to_viewer_decal_spec(
    spec: shared_static_world::StaticWorldDecalSpec,
) -> StaticWorldDecalSpec {
    let outline_target = spec
        .semantic
        .as_ref()
        .map(shared_semantic_to_binding)
        .map(|binding| binding.semantic);
    StaticWorldDecalSpec {
        size: spec.size,
        translation: spec.translation,
        rotation: spec.rotation,
        color: shared_static_world::default_color_for_role(spec.material_role),
        outline_target,
    }
}

fn spawn_shared_ground_sections(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    ground_specs: &[shared_static_world::StaticWorldGroundSpec],
) -> Vec<Entity> {
    let mut material_cache =
        std::collections::HashMap::<SharedRole, Handle<GridGroundMaterial>>::new();

    ground_specs
        .iter()
        .map(|ground| {
            let material = material_cache
                .entry(ground.material_role)
                .or_insert_with(|| {
                    let (dark_color, light_color, edge_color) =
                        shared_ground_colors(ground.material_role, palette);
                    ground_materials.add(GridGroundMaterial {
                        base: StandardMaterial {
                            base_color: Color::WHITE,
                            perceptual_roughness: 0.97,
                            reflectance: 0.03,
                            metallic: 0.0,
                            opaque_render_method: OpaqueRendererMethod::Forward,
                            ..default()
                        },
                        extension: GridGroundMaterialExt {
                            world_origin: Vec2::ZERO,
                            grid_size: 1.0,
                            line_width: 0.035,
                            variation_strength: render_config.ground_variation_strength,
                            seed: render_config.object_style_seed,
                            _padding: Vec2::ZERO,
                            dark_color,
                            light_color,
                            edge_color,
                        },
                    })
                })
                .clone();
            commands
                .spawn((
                    Mesh3d(meshes.add(Cuboid::new(
                        ground.size.x.max(0.1),
                        ground.size.y.max(0.02),
                        ground.size.z.max(0.1),
                    ))),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(ground.translation),
                ))
                .id()
        })
        .collect()
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
    shared_scene(snapshot, current_level, render_config, bounds)
        .boxes
        .into_iter()
        .map(|spec| StaticWorldBoxSpec {
            size: spec.size,
            translation: spec.translation,
            color: shared_role_color(spec.material_role, palette),
            material_style: shared_role_material_style(spec.material_role),
            occluder_kind: spec.occluder_kind.map(|kind| match kind {
                game_bevy::static_world::StaticWorldOccluderKind::MapObject(kind) => {
                    StaticWorldOccluderKind::MapObject(kind)
                }
            }),
            occluder_cells: spec.occluder_cells,
            pick_binding: shared_semantic_pick_binding(spec.semantic.clone()),
            outline_target: (spec.material_role
                != game_bevy::static_world::StaticWorldMaterialRole::InvisiblePickProxy)
                .then(|| shared_semantic_outline_target(spec.semantic))
                .flatten(),
        })
        .collect()
}

pub(crate) fn collect_static_world_building_wall_tile_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
) -> Vec<shared_static_world::StaticWorldBuildingWallTileSpec> {
    shared_scene(snapshot, current_level, render_config, bounds).building_wall_tiles
}

pub(crate) fn collect_static_world_decal_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) -> Vec<StaticWorldDecalSpec> {
    shared_scene(
        snapshot,
        current_level,
        render_config,
        GridBounds {
            min_x: 0,
            max_x: snapshot.grid.map_width.unwrap_or(0) as i32,
            min_z: 0,
            max_z: snapshot.grid.map_height.unwrap_or(0) as i32,
        },
    )
    .decals
    .into_iter()
    .map(|spec| StaticWorldDecalSpec {
        size: spec.size,
        translation: spec.translation,
        rotation: spec.rotation,
        color: shared_role_color(spec.material_role, palette),
        outline_target: shared_semantic_outline_target(spec.semantic),
    })
    .collect()
}

pub(super) fn collect_ground_cells_to_render(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    bounds: GridBounds,
) -> Vec<GridCoord> {
    let shared = shared_scene(
        snapshot,
        current_level,
        ViewerRenderConfig::default(),
        bounds,
    );
    let mut cells = Vec::new();
    for ground in shared.ground {
        let min_x = (ground.translation.x - ground.size.x * 0.5).floor() as i32;
        let max_x = (ground.translation.x + ground.size.x * 0.5 - 0.001).floor() as i32;
        let min_z = (ground.translation.z - ground.size.z * 0.5).floor() as i32;
        let max_z = (ground.translation.z + ground.size.z * 0.5 - 0.001).floor() as i32;
        for z in min_z..=max_z {
            for x in min_x..=max_x {
                cells.push(GridCoord::new(x, current_level, z));
            }
        }
    }
    cells
}

fn shared_scene(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
) -> SharedSceneSpec {
    build_static_world_from_simulation_snapshot(
        snapshot,
        current_level,
        StaticWorldBuildConfig {
            floor_thickness_world: render_config.floor_thickness_world,
            object_style_seed: render_config.object_style_seed,
            include_generated_doors: false,
            bounds_override: Some(game_bevy::static_world::StaticWorldGridBounds {
                min_x: bounds.min_x,
                max_x: bounds.max_x,
                min_z: bounds.min_z,
                max_z: bounds.max_z,
            }),
        },
    )
}

fn shared_role_color(role: SharedRole, palette: &ViewerPalette) -> Color {
    match role {
        SharedRole::Ground => palette.ground_light,
        SharedRole::OverworldGroundRoad => Color::srgb(0.42, 0.40, 0.34),
        SharedRole::OverworldGroundPlain => Color::srgb(0.48, 0.56, 0.30),
        SharedRole::OverworldGroundForest => Color::srgb(0.20, 0.38, 0.19),
        SharedRole::OverworldGroundRiver => Color::srgb(0.17, 0.43, 0.67),
        SharedRole::OverworldGroundLake => Color::srgb(0.13, 0.34, 0.58),
        SharedRole::OverworldGroundMountain => Color::srgb(0.39, 0.39, 0.41),
        SharedRole::OverworldGroundUrban => Color::srgb(0.46, 0.45, 0.44),
        SharedRole::BuildingFloor => lerp_color(palette.building_top, palette.building_base, 0.38),
        SharedRole::BuildingDoor => building_door_color(),
        SharedRole::StairBase => darken_color(palette.interactive, 0.18),
        SharedRole::StairAccent => lighten_color(palette.current_turn, 0.12),
        SharedRole::PickupBase | SharedRole::PickupAccent => palette.pickup,
        SharedRole::InteractiveBase | SharedRole::InteractiveAccent => palette.interactive,
        SharedRole::TriggerBase | SharedRole::TriggerAccent => palette.trigger,
        SharedRole::InvisiblePickProxy => Color::srgba(1.0, 1.0, 1.0, 0.0),
        SharedRole::Warning => Color::srgb(0.95, 0.18, 0.18),
        SharedRole::OverworldCell => Color::srgb(0.18, 0.42, 0.28),
        SharedRole::OverworldBlockedCell => Color::srgb(0.52, 0.19, 0.14),
        SharedRole::OverworldLocationGeneric => Color::srgb(0.22, 0.58, 0.86),
        SharedRole::OverworldLocationHospital => Color::srgb(0.86, 0.34, 0.34),
        SharedRole::OverworldLocationSchool => Color::srgb(0.91, 0.73, 0.28),
        SharedRole::OverworldLocationStore => Color::srgb(0.89, 0.54, 0.22),
        SharedRole::OverworldLocationStreet => Color::srgb(0.66, 0.68, 0.72),
        SharedRole::OverworldLocationOutpost => Color::srgb(0.22, 0.72, 0.86),
        SharedRole::OverworldLocationFactory => Color::srgb(0.63, 0.39, 0.24),
        SharedRole::OverworldLocationForest => Color::srgb(0.27, 0.63, 0.31),
        SharedRole::OverworldLocationRuins => Color::srgb(0.63, 0.55, 0.43),
        SharedRole::OverworldLocationSubway => Color::srgb(0.26, 0.78, 0.74),
    }
}

fn shared_role_material_style(role: SharedRole) -> MaterialStyle {
    match role {
        SharedRole::BuildingDoor => MaterialStyle::BuildingDoor,
        SharedRole::PickupAccent
        | SharedRole::InteractiveAccent
        | SharedRole::TriggerAccent
        | SharedRole::StairAccent => MaterialStyle::Utility,
        SharedRole::InvisiblePickProxy => MaterialStyle::InvisiblePickProxy,
        _ => MaterialStyle::UtilityAccent,
    }
}

fn shared_ground_colors(role: SharedRole, palette: &ViewerPalette) -> (Color, Color, Color) {
    if role == SharedRole::Ground {
        return (
            palette.ground_dark,
            palette.ground_light,
            palette.ground_edge,
        );
    }

    let base = shared_role_color(role, palette);
    (
        darken_color(base, 0.18),
        lighten_color(base, 0.12),
        darken_color(base, 0.34),
    )
}

fn shared_semantic_pick_binding(semantic: Option<SharedSemantic>) -> Option<ViewerPickBindingSpec> {
    match semantic {
        Some(SharedSemantic::MapObject(object_id)) => {
            Some(ViewerPickBindingSpec::map_object(object_id))
        }
        Some(SharedSemantic::TriggerCell {
            object_id,
            story_level,
            cell,
        }) => Some(ViewerPickBindingSpec::trigger_cell(
            object_id,
            story_level,
            cell,
        )),
        None => None,
    }
}

fn shared_semantic_outline_target(semantic: Option<SharedSemantic>) -> Option<ViewerPickTarget> {
    match semantic {
        Some(SharedSemantic::MapObject(object_id)) => Some(ViewerPickTarget::MapObject(object_id)),
        Some(SharedSemantic::TriggerCell {
            object_id,
            story_level,
            cell,
        }) => Some(ViewerPickTarget::BuildingPart(
            crate::picking::BuildingPartPickTarget {
                building_object_id: object_id,
                story_level,
                kind: crate::picking::BuildingPartKind::TriggerCell,
                anchor_cell: cell,
            },
        )),
        None => None,
    }
}
