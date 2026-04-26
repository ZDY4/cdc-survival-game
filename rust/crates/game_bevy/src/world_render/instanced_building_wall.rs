use bevy::asset::uuid_handle;
use bevy::core_pipeline::core_3d::{Opaque3d, Opaque3dBatchSetKey, Opaque3dBinKey, Transparent3d};
use bevy::ecs::change_detection::Tick;
use bevy::ecs::system::{lifetimeless::*, SystemParamItem};
use bevy::mesh::{MeshVertexBufferLayoutRef, VertexBufferLayout};
use bevy::pbr::{
    ErasedMaterialKey, ErasedMaterialPipelineKey, MaterialProperties, MeshPipeline,
    MeshPipelineKey, PrepassPipeline, PrepassPipelineSpecializer, PrepassVertexShader,
    RenderMeshInstances, SetMeshBindGroup, SetMeshViewBindGroup, SetMeshViewBindingArrayBindGroup,
    SetPrepassViewBindGroup, SetPrepassViewEmptyBindGroup, Shadow, ShadowBatchSetKey, ShadowBinKey,
    ShadowView, ViewKeyCache,
};
use bevy::prelude::*;
use bevy::render::batching::gpu_preprocessing::GpuPreprocessingSupport;
use bevy::render::extract_component::ExtractComponentPlugin;
use bevy::render::mesh::{allocator::MeshAllocator, RenderMesh, RenderMeshBufferInfo};
use bevy::render::render_asset::RenderAssets;
use bevy::render::render_phase::{
    AddRenderCommand, BinnedRenderPhaseType, DrawFunctions, PhaseItem, PhaseItemExtraIndex,
    RenderCommand, RenderCommandResult, SetItemPipeline, TrackedRenderPass, ViewBinnedRenderPhases,
    ViewSortedRenderPhases,
};
use bevy::render::render_resource::*;
use bevy::render::renderer::RenderDevice;
use bevy::render::sync_world::MainEntity;
use bevy::render::view::ExtractedView;
use bevy::render::{Render, RenderApp, RenderStartup, RenderSystems};
use bytemuck::{Pod, Zeroable};
use std::{any::TypeId, sync::Arc};

use super::{
    building_wall_visual_profile, WorldRenderBuildingWallTileBatchSource,
    WorldRenderTileBatchVisualState,
};

pub const BUILDING_WALL_TILE_INSTANCING_SHADER_HANDLE: Handle<Shader> =
    uuid_handle!("ad12dca1-7ae9-4f6f-a11f-07b21ad91573");

pub(super) struct WorldRenderBuildingWallTileInstancingPlugin;

impl Plugin for WorldRenderBuildingWallTileInstancingPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(ExtractComponentPlugin::<
            WorldRenderBuildingWallTileBatchSource,
        >::default());

        let Some(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app
            .add_render_command::<Opaque3d, DrawWorldRenderBuildingWallTileInstancedOpaque>()
            .add_render_command::<Transparent3d, DrawWorldRenderBuildingWallTileInstancedTransparent>()
            .add_render_command::<Shadow, DrawWorldRenderBuildingWallTileInstancedShadow>()
            .init_resource::<SpecializedMeshPipelines<WorldRenderBuildingWallTilePipeline>>()
            .add_systems(
                RenderStartup,
                (
                    init_world_render_building_wall_tile_pipeline,
                    init_world_render_building_wall_tile_shadow_pipeline
                        .after(bevy::pbr::init_prepass_pipeline),
                ),
            )
            .add_systems(
                Render,
                (
                    queue_world_render_building_wall_tile_opaque_batches
                        .in_set(RenderSystems::QueueMeshes),
                    queue_world_render_building_wall_tile_transparent_batches
                        .in_set(RenderSystems::QueueMeshes),
                    queue_world_render_building_wall_tile_shadow_batches
                        .in_set(RenderSystems::QueueMeshes),
                    prepare_world_render_building_wall_tile_instance_buffers
                        .in_set(RenderSystems::PrepareResources),
                ),
            );
    }
}

#[derive(Component)]
struct WorldRenderBuildingWallTileOpaqueInstanceBuffer {
    buffer: Buffer,
    length: usize,
}

#[derive(Component)]
struct WorldRenderBuildingWallTileTransparentInstanceBuffer {
    buffer: Buffer,
    length: usize,
    center: Vec3,
}

#[derive(Clone, Copy, Pod, Zeroable)]
#[repr(C)]
struct WorldRenderBuildingWallTileInstanceGpuData {
    world_from_local_0: [f32; 4],
    world_from_local_1: [f32; 4],
    world_from_local_2: [f32; 4],
    world_from_local_3: [f32; 4],
    face_color: [f32; 4],
    major_line_color: [f32; 4],
    minor_line_color: [f32; 4],
    cap_color: [f32; 4],
    params_0: [f32; 4],
    params_1: [f32; 4],
}

#[derive(Resource)]
struct WorldRenderBuildingWallTilePipeline {
    shader: Handle<Shader>,
    mesh_pipeline: MeshPipeline,
}

#[derive(Resource, Clone)]
struct WorldRenderBuildingWallTileShadowPipeline {
    pipeline: PrepassPipeline,
    properties: Arc<MaterialProperties>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum WorldRenderBuildingWallTilePass {
    Opaque,
    Transparent,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct WorldRenderBuildingWallTilePipelineKey {
    mesh_key: MeshPipelineKey,
    pass: WorldRenderBuildingWallTilePass,
}

fn init_world_render_building_wall_tile_pipeline(
    mut commands: Commands,
    mesh_pipeline: Res<MeshPipeline>,
) {
    commands.insert_resource(WorldRenderBuildingWallTilePipeline {
        shader: BUILDING_WALL_TILE_INSTANCING_SHADER_HANDLE.clone(),
        mesh_pipeline: mesh_pipeline.clone(),
    });
}

fn init_world_render_building_wall_tile_shadow_pipeline(
    mut commands: Commands,
    prepass_pipeline: Res<PrepassPipeline>,
) {
    let mut properties = MaterialProperties::default();
    properties.add_shader(
        PrepassVertexShader,
        BUILDING_WALL_TILE_INSTANCING_SHADER_HANDLE.clone(),
    );
    properties.specialize = Some(specialize_world_render_building_wall_tile_shadow_pipeline);
    properties.shadows_enabled = true;
    properties.prepass_enabled = true;
    properties.material_layout = Some(prepass_pipeline.empty_layout.clone());
    commands.insert_resource(WorldRenderBuildingWallTileShadowPipeline {
        pipeline: prepass_pipeline.clone(),
        properties: Arc::new(properties),
    });
}

fn building_wall_instance_buffer_layout() -> VertexBufferLayout {
    VertexBufferLayout {
        array_stride: std::mem::size_of::<WorldRenderBuildingWallTileInstanceGpuData>() as u64,
        step_mode: VertexStepMode::Instance,
        attributes: vec![
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: 0,
                shader_location: 8,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size(),
                shader_location: 9,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 2,
                shader_location: 10,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 3,
                shader_location: 11,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 4,
                shader_location: 12,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 5,
                shader_location: 13,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 6,
                shader_location: 14,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 7,
                shader_location: 15,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 8,
                shader_location: 16,
            },
            VertexAttribute {
                format: VertexFormat::Float32x4,
                offset: VertexFormat::Float32x4.size() * 9,
                shader_location: 17,
            },
        ],
    }
}

fn specialize_world_render_building_wall_tile_shadow_pipeline(
    _pipeline: &bevy::pbr::MaterialPipeline,
    descriptor: &mut RenderPipelineDescriptor,
    _layout: &MeshVertexBufferLayoutRef,
    _key: ErasedMaterialPipelineKey,
) -> Result<(), SpecializedMeshPipelineError> {
    descriptor.label = Some("world_render_building_wall_tile_instanced_shadow_pipeline".into());
    descriptor
        .vertex
        .buffers
        .push(building_wall_instance_buffer_layout());
    Ok(())
}

fn prepare_world_render_building_wall_tile_instance_buffers(
    mut commands: Commands,
    // Building-wall batches are extracted into the render world without `Mesh3d`,
    // so filtering on `Mesh3d` here would skip every wall batch and prevent buffer creation.
    batches: Query<(
        Entity,
        &WorldRenderTileBatchVisualState,
        &WorldRenderBuildingWallTileBatchSource,
    )>,
    render_device: Res<RenderDevice>,
) {
    for (entity, batch_visual_state, batch_source) in &batches {
        if batch_visual_state.instances.is_empty() {
            commands
                .entity(entity)
                .remove::<WorldRenderBuildingWallTileOpaqueInstanceBuffer>()
                .remove::<WorldRenderBuildingWallTileTransparentInstanceBuffer>();
            continue;
        }

        let profile = building_wall_visual_profile(batch_source.visual_kind);
        let face_color = profile.face_color.to_linear().to_vec4();
        let major_line_color = profile.major_line_color.to_linear().to_vec4();
        let minor_line_color = profile.minor_line_color.to_linear().to_vec4();
        let cap_color = profile.cap_color.to_linear().to_vec4();

        let mut opaque_instance_data = Vec::with_capacity(batch_visual_state.instances.len());
        let mut transparent_instance_data = Vec::new();
        let mut transparent_center_sum = Vec3::ZERO;

        for instance in &batch_visual_state.instances {
            let tint = instance.tint.to_linear().to_vec4();
            let fade_alpha = instance.fade_alpha.clamp(0.0, 1.0);
            let faded = fade_alpha < 0.999;
            let tint_rgb = Vec3::new(tint.x, tint.y, tint.z);
            let matrix = (instance.transform.to_matrix()
                * batch_source.prototype_local_transform.to_matrix())
            .to_cols_array_2d();

            let gpu_data = WorldRenderBuildingWallTileInstanceGpuData {
                world_from_local_0: matrix[0],
                world_from_local_1: matrix[1],
                world_from_local_2: matrix[2],
                world_from_local_3: matrix[3],
                face_color: [
                    face_color.x * tint_rgb.x,
                    face_color.y * tint_rgb.y,
                    face_color.z * tint_rgb.z,
                    face_color.w * fade_alpha,
                ],
                major_line_color: [
                    major_line_color.x * tint_rgb.x,
                    major_line_color.y * tint_rgb.y,
                    major_line_color.z * tint_rgb.z,
                    major_line_color.w * fade_alpha,
                ],
                minor_line_color: [
                    minor_line_color.x * tint_rgb.x,
                    minor_line_color.y * tint_rgb.y,
                    minor_line_color.z * tint_rgb.z,
                    minor_line_color.w * fade_alpha,
                ],
                cap_color: [
                    cap_color.x * tint_rgb.x,
                    cap_color.y * tint_rgb.y,
                    cap_color.z * tint_rgb.z,
                    cap_color.w * fade_alpha,
                ],
                params_0: [
                    profile.major_grid_size.max(0.001),
                    profile.minor_grid_size.max(0.001),
                    profile.major_line_width.max(0.0005),
                    profile.minor_line_width.max(0.0005),
                ],
                params_1: [
                    profile.face_tint_strength.clamp(0.0, 1.0),
                    if faded {
                        0.0
                    } else {
                        profile.grid_line_visibility.clamp(0.0, 1.0)
                    },
                    if faded {
                        0.0
                    } else {
                        profile.top_face_grid_visibility.clamp(0.0, 1.0)
                    },
                    if batch_source.receive_shadows {
                        1.0
                    } else {
                        0.0
                    },
                ],
            };

            let is_transparent = fade_alpha < 0.999
                || tint.w < 0.999
                || face_color.w < 0.999
                || major_line_color.w < 0.999
                || minor_line_color.w < 0.999
                || cap_color.w < 0.999;

            if is_transparent {
                transparent_center_sum += instance.transform.translation;
                transparent_instance_data.push(gpu_data);
            } else {
                opaque_instance_data.push(gpu_data);
            }
        }

        let mut entity_commands = commands.entity(entity);
        write_building_wall_opaque_buffer(
            &mut entity_commands,
            &render_device,
            opaque_instance_data.as_slice(),
        );
        write_building_wall_transparent_buffer(
            &mut entity_commands,
            &render_device,
            transparent_instance_data.as_slice(),
            transparent_center_sum,
        );
    }
}

fn write_building_wall_opaque_buffer(
    entity_commands: &mut EntityCommands,
    render_device: &RenderDevice,
    instance_data: &[WorldRenderBuildingWallTileInstanceGpuData],
) {
    if instance_data.is_empty() {
        entity_commands.remove::<WorldRenderBuildingWallTileOpaqueInstanceBuffer>();
        return;
    }

    let buffer = render_device.create_buffer_with_data(&BufferInitDescriptor {
        label: Some("world render building wall tile opaque instance buffer"),
        contents: bytemuck::cast_slice(instance_data),
        usage: BufferUsages::VERTEX | BufferUsages::COPY_DST,
    });

    entity_commands.insert(WorldRenderBuildingWallTileOpaqueInstanceBuffer {
        buffer,
        length: instance_data.len(),
    });
}

fn write_building_wall_transparent_buffer(
    entity_commands: &mut EntityCommands,
    render_device: &RenderDevice,
    instance_data: &[WorldRenderBuildingWallTileInstanceGpuData],
    center_sum: Vec3,
) {
    if instance_data.is_empty() {
        entity_commands.remove::<WorldRenderBuildingWallTileTransparentInstanceBuffer>();
        return;
    }

    let buffer = render_device.create_buffer_with_data(&BufferInitDescriptor {
        label: Some("world render building wall tile transparent instance buffer"),
        contents: bytemuck::cast_slice(instance_data),
        usage: BufferUsages::VERTEX | BufferUsages::COPY_DST,
    });

    entity_commands.insert(WorldRenderBuildingWallTileTransparentInstanceBuffer {
        buffer,
        length: instance_data.len(),
        center: center_sum / instance_data.len() as f32,
    });
}

fn queue_world_render_building_wall_tile_opaque_batches(
    opaque_draw_functions: Res<DrawFunctions<Opaque3d>>,
    custom_pipeline: Res<WorldRenderBuildingWallTilePipeline>,
    mut pipelines: ResMut<SpecializedMeshPipelines<WorldRenderBuildingWallTilePipeline>>,
    pipeline_cache: Res<PipelineCache>,
    meshes: Res<RenderAssets<RenderMesh>>,
    render_mesh_instances: Res<RenderMeshInstances>,
    view_key_cache: Res<ViewKeyCache>,
    mesh_allocator: Res<MeshAllocator>,
    gpu_preprocessing_support: Res<GpuPreprocessingSupport>,
    batches: Query<
        (
            Entity,
            &MainEntity,
            &WorldRenderBuildingWallTileOpaqueInstanceBuffer,
        ),
        With<WorldRenderBuildingWallTileBatchSource>,
    >,
    mut opaque_render_phases: ResMut<ViewBinnedRenderPhases<Opaque3d>>,
    views: Query<&ExtractedView>,
    mut change_tick: Local<Tick>,
) {
    let draw_function = opaque_draw_functions
        .read()
        .id::<DrawWorldRenderBuildingWallTileInstancedOpaque>();

    for view in &views {
        let Some(opaque_phase) = opaque_render_phases.get_mut(&view.retained_view_entity) else {
            continue;
        };
        let Some(view_key) = view_key_cache.get(&view.retained_view_entity).copied() else {
            continue;
        };

        for (entity, main_entity, instance_buffer) in &batches {
            if instance_buffer.length == 0 {
                continue;
            }

            let Some(mesh_instance) = render_mesh_instances.render_mesh_queue_data(*main_entity)
            else {
                continue;
            };
            let Some(mesh) = meshes.get(mesh_instance.mesh_asset_id) else {
                continue;
            };
            let (vertex_slab, index_slab) = mesh_allocator.mesh_slabs(&mesh_instance.mesh_asset_id);
            let mesh_key =
                view_key | MeshPipelineKey::from_primitive_topology(mesh.primitive_topology());
            let pipeline = match pipelines.specialize(
                &pipeline_cache,
                &custom_pipeline,
                WorldRenderBuildingWallTilePipelineKey {
                    mesh_key,
                    pass: WorldRenderBuildingWallTilePass::Opaque,
                },
                &mesh.layout,
            ) {
                Ok(pipeline) => pipeline,
                Err(_) => continue,
            };

            let next_change_tick = change_tick.get().wrapping_add(1);
            change_tick.set(next_change_tick);

            opaque_phase.add(
                Opaque3dBatchSetKey {
                    draw_function,
                    pipeline,
                    material_bind_group_index: None,
                    vertex_slab: vertex_slab.unwrap_or_default(),
                    index_slab,
                    lightmap_slab: None,
                },
                Opaque3dBinKey {
                    asset_id: mesh_instance.mesh_asset_id.into(),
                },
                (entity, *main_entity),
                mesh_instance.current_uniform_index,
                // The instance payload is stored per render entity, so cross-entity
                // batching would bind the wrong custom instance buffer.
                BinnedRenderPhaseType::mesh(false, &gpu_preprocessing_support),
                *change_tick,
            );
        }
    }
}

fn queue_world_render_building_wall_tile_transparent_batches(
    transparent_draw_functions: Res<DrawFunctions<Transparent3d>>,
    custom_pipeline: Res<WorldRenderBuildingWallTilePipeline>,
    mut pipelines: ResMut<SpecializedMeshPipelines<WorldRenderBuildingWallTilePipeline>>,
    pipeline_cache: Res<PipelineCache>,
    meshes: Res<RenderAssets<RenderMesh>>,
    render_mesh_instances: Res<RenderMeshInstances>,
    view_key_cache: Res<ViewKeyCache>,
    batches: Query<
        (
            Entity,
            &MainEntity,
            &WorldRenderBuildingWallTileTransparentInstanceBuffer,
        ),
        With<WorldRenderBuildingWallTileBatchSource>,
    >,
    mut transparent_render_phases: ResMut<ViewSortedRenderPhases<Transparent3d>>,
    views: Query<&ExtractedView>,
) {
    let draw_function = transparent_draw_functions
        .read()
        .id::<DrawWorldRenderBuildingWallTileInstancedTransparent>();

    for view in &views {
        let Some(transparent_phase) = transparent_render_phases.get_mut(&view.retained_view_entity)
        else {
            continue;
        };
        let Some(view_key) = view_key_cache.get(&view.retained_view_entity).copied() else {
            continue;
        };
        let rangefinder = view.rangefinder3d();

        for (entity, main_entity, instance_buffer) in &batches {
            if instance_buffer.length == 0 {
                continue;
            }

            let Some(mesh_instance) = render_mesh_instances.render_mesh_queue_data(*main_entity)
            else {
                continue;
            };
            let Some(mesh) = meshes.get(mesh_instance.mesh_asset_id) else {
                continue;
            };
            let mesh_key =
                view_key | MeshPipelineKey::from_primitive_topology(mesh.primitive_topology());
            let pipeline = match pipelines.specialize(
                &pipeline_cache,
                &custom_pipeline,
                WorldRenderBuildingWallTilePipelineKey {
                    mesh_key,
                    pass: WorldRenderBuildingWallTilePass::Transparent,
                },
                &mesh.layout,
            ) {
                Ok(pipeline) => pipeline,
                Err(_) => continue,
            };

            transparent_phase.add(Transparent3d {
                entity: (entity, *main_entity),
                pipeline,
                draw_function,
                distance: rangefinder.distance(&instance_buffer.center),
                batch_range: 0..1,
                extra_index: PhaseItemExtraIndex::None,
                indexed: matches!(mesh.buffer_info, RenderMeshBufferInfo::Indexed { .. }),
            });
        }
    }
}

fn queue_world_render_building_wall_tile_shadow_batches(
    shadow_draw_functions: Res<DrawFunctions<Shadow>>,
    custom_pipeline: Res<WorldRenderBuildingWallTileShadowPipeline>,
    mut pipelines: ResMut<SpecializedMeshPipelines<PrepassPipelineSpecializer>>,
    pipeline_cache: Res<PipelineCache>,
    meshes: Res<RenderAssets<RenderMesh>>,
    render_mesh_instances: Res<RenderMeshInstances>,
    mesh_allocator: Res<MeshAllocator>,
    gpu_preprocessing_support: Res<GpuPreprocessingSupport>,
    batches: Query<
        (
            Entity,
            &MainEntity,
            &WorldRenderBuildingWallTileOpaqueInstanceBuffer,
            &WorldRenderBuildingWallTileBatchSource,
        ),
        With<WorldRenderBuildingWallTileBatchSource>,
    >,
    mut shadow_render_phases: ResMut<ViewBinnedRenderPhases<Shadow>>,
    views: Query<&ExtractedView, With<ShadowView>>,
    mut change_tick: Local<Tick>,
) {
    let draw_function = shadow_draw_functions
        .read()
        .id::<DrawWorldRenderBuildingWallTileInstancedShadow>();

    for view in &views {
        let Some(shadow_phase) = shadow_render_phases.get_mut(&view.retained_view_entity) else {
            continue;
        };

        let mut view_key = MeshPipelineKey::DEPTH_PREPASS;
        view_key.set(
            MeshPipelineKey::UNCLIPPED_DEPTH_ORTHO,
            view.clip_from_view.w_axis.w.abs() > 0.5,
        );

        for (entity, main_entity, instance_buffer, batch_source) in &batches {
            if instance_buffer.length == 0 || !batch_source.cast_shadows {
                continue;
            }

            let Some(mesh_instance) = render_mesh_instances.render_mesh_queue_data(*main_entity)
            else {
                continue;
            };
            let Some(mesh) = meshes.get(mesh_instance.mesh_asset_id) else {
                continue;
            };
            let (vertex_slab, index_slab) = mesh_allocator.mesh_slabs(&mesh_instance.mesh_asset_id);
            let mesh_key =
                view_key | MeshPipelineKey::from_primitive_topology(mesh.primitive_topology());
            let pipeline = match pipelines.specialize(
                &pipeline_cache,
                &PrepassPipelineSpecializer {
                    pipeline: custom_pipeline.pipeline.clone(),
                    properties: custom_pipeline.properties.clone(),
                },
                ErasedMaterialPipelineKey {
                    mesh_key,
                    material_key: ErasedMaterialKey::default(),
                    type_id: TypeId::of::<WorldRenderBuildingWallTileShadowPipeline>(),
                },
                &mesh.layout,
            ) {
                Ok(pipeline) => pipeline,
                Err(_) => continue,
            };

            let next_change_tick = change_tick.get().wrapping_add(1);
            change_tick.set(next_change_tick);

            shadow_phase.add(
                ShadowBatchSetKey {
                    pipeline,
                    draw_function,
                    material_bind_group_index: None,
                    vertex_slab: vertex_slab.unwrap_or_default(),
                    index_slab,
                },
                ShadowBinKey {
                    asset_id: mesh_instance.mesh_asset_id.into(),
                },
                (entity, *main_entity),
                mesh_instance.current_uniform_index,
                BinnedRenderPhaseType::mesh(false, &gpu_preprocessing_support),
                *change_tick,
            );
        }
    }
}

impl SpecializedMeshPipeline for WorldRenderBuildingWallTilePipeline {
    type Key = WorldRenderBuildingWallTilePipelineKey;

    fn specialize(
        &self,
        key: Self::Key,
        layout: &MeshVertexBufferLayoutRef,
    ) -> Result<RenderPipelineDescriptor, SpecializedMeshPipelineError> {
        let mut descriptor = self.mesh_pipeline.specialize(key.mesh_key, layout)?;
        descriptor.label = Some("world_render_building_wall_tile_instanced_pipeline".into());
        descriptor.vertex.shader = self.shader.clone();
        descriptor
            .vertex
            .buffers
            .push(building_wall_instance_buffer_layout());
        if key.mesh_key.contains(MeshPipelineKey::DEPTH_PREPASS) {
            descriptor.fragment = None;
        } else if let Some(fragment) = descriptor.fragment.as_mut() {
            fragment.shader = self.shader.clone();
            if let Some(Some(target)) = fragment.targets.first_mut() {
                target.blend = match key.pass {
                    WorldRenderBuildingWallTilePass::Opaque => None,
                    WorldRenderBuildingWallTilePass::Transparent => {
                        Some(BlendState::ALPHA_BLENDING)
                    }
                };
            }
        }
        if let Some(depth_stencil) = descriptor.depth_stencil.as_mut() {
            depth_stencil.depth_write_enabled =
                matches!(key.pass, WorldRenderBuildingWallTilePass::Opaque);
        }
        Ok(descriptor)
    }
}

type DrawWorldRenderBuildingWallTileInstancedOpaque = (
    SetItemPipeline,
    SetMeshViewBindGroup<0>,
    SetMeshViewBindingArrayBindGroup<1>,
    SetMeshBindGroup<2>,
    DrawWorldRenderBuildingWallTileInstancedOpaqueMesh,
);

type DrawWorldRenderBuildingWallTileInstancedTransparent = (
    SetItemPipeline,
    SetMeshViewBindGroup<0>,
    SetMeshViewBindingArrayBindGroup<1>,
    SetMeshBindGroup<2>,
    DrawWorldRenderBuildingWallTileInstancedTransparentMesh,
);

type DrawWorldRenderBuildingWallTileInstancedShadow = (
    SetItemPipeline,
    SetPrepassViewBindGroup<0>,
    SetPrepassViewEmptyBindGroup<1>,
    SetMeshBindGroup<2>,
    SetPrepassViewEmptyBindGroup<3>,
    DrawWorldRenderBuildingWallTileInstancedOpaqueMesh,
);

struct DrawWorldRenderBuildingWallTileInstancedOpaqueMesh;

impl<P: PhaseItem> RenderCommand<P> for DrawWorldRenderBuildingWallTileInstancedOpaqueMesh {
    type Param = (
        SRes<RenderAssets<RenderMesh>>,
        SRes<RenderMeshInstances>,
        SRes<MeshAllocator>,
    );
    type ViewQuery = ();
    type ItemQuery = Read<WorldRenderBuildingWallTileOpaqueInstanceBuffer>;

    fn render<'w>(
        item: &P,
        _view: (),
        instance_buffer: Option<&'w WorldRenderBuildingWallTileOpaqueInstanceBuffer>,
        params: SystemParamItem<'w, '_, Self::Param>,
        pass: &mut TrackedRenderPass<'w>,
    ) -> RenderCommandResult {
        render_building_wall_tile_instanced_mesh(item, instance_buffer, params, pass)
    }
}

struct DrawWorldRenderBuildingWallTileInstancedTransparentMesh;

impl<P: PhaseItem> RenderCommand<P> for DrawWorldRenderBuildingWallTileInstancedTransparentMesh {
    type Param = (
        SRes<RenderAssets<RenderMesh>>,
        SRes<RenderMeshInstances>,
        SRes<MeshAllocator>,
    );
    type ViewQuery = ();
    type ItemQuery = Read<WorldRenderBuildingWallTileTransparentInstanceBuffer>;

    fn render<'w>(
        item: &P,
        _view: (),
        instance_buffer: Option<&'w WorldRenderBuildingWallTileTransparentInstanceBuffer>,
        params: SystemParamItem<'w, '_, Self::Param>,
        pass: &mut TrackedRenderPass<'w>,
    ) -> RenderCommandResult {
        render_building_wall_tile_instanced_mesh(item, instance_buffer, params, pass)
    }
}

trait WorldRenderBuildingWallTileInstanceBufferExt {
    fn buffer(&self) -> &Buffer;
    fn len(&self) -> usize;
}

impl WorldRenderBuildingWallTileInstanceBufferExt
    for WorldRenderBuildingWallTileOpaqueInstanceBuffer
{
    fn buffer(&self) -> &Buffer {
        &self.buffer
    }

    fn len(&self) -> usize {
        self.length
    }
}

impl WorldRenderBuildingWallTileInstanceBufferExt
    for WorldRenderBuildingWallTileTransparentInstanceBuffer
{
    fn buffer(&self) -> &Buffer {
        &self.buffer
    }

    fn len(&self) -> usize {
        self.length
    }
}

fn render_building_wall_tile_instanced_mesh<'w, P, B>(
    item: &P,
    instance_buffer: Option<&'w B>,
    (meshes, render_mesh_instances, mesh_allocator): SystemParamItem<
        'w,
        '_,
        (
            SRes<RenderAssets<RenderMesh>>,
            SRes<RenderMeshInstances>,
            SRes<MeshAllocator>,
        ),
    >,
    pass: &mut TrackedRenderPass<'w>,
) -> RenderCommandResult
where
    P: PhaseItem,
    B: WorldRenderBuildingWallTileInstanceBufferExt,
{
    let mesh_allocator = mesh_allocator.into_inner();

    let Some(mesh_instance) = render_mesh_instances.render_mesh_queue_data(item.main_entity())
    else {
        return RenderCommandResult::Skip;
    };
    let Some(gpu_mesh) = meshes.into_inner().get(mesh_instance.mesh_asset_id) else {
        return RenderCommandResult::Skip;
    };
    let Some(instance_buffer) = instance_buffer else {
        return RenderCommandResult::Skip;
    };
    let Some(vertex_buffer_slice) = mesh_allocator.mesh_vertex_slice(&mesh_instance.mesh_asset_id)
    else {
        return RenderCommandResult::Skip;
    };

    pass.set_vertex_buffer(0, vertex_buffer_slice.buffer.slice(..));
    pass.set_vertex_buffer(1, instance_buffer.buffer().slice(..));

    match &gpu_mesh.buffer_info {
        RenderMeshBufferInfo::Indexed {
            index_format,
            count,
        } => {
            let Some(index_buffer_slice) =
                mesh_allocator.mesh_index_slice(&mesh_instance.mesh_asset_id)
            else {
                return RenderCommandResult::Skip;
            };

            pass.set_index_buffer(index_buffer_slice.buffer.slice(..), *index_format);
            pass.draw_indexed(
                index_buffer_slice.range.start..(index_buffer_slice.range.start + count),
                vertex_buffer_slice.range.start as i32,
                0..instance_buffer.len() as u32,
            );
        }
        RenderMeshBufferInfo::NonIndexed => {
            pass.draw(vertex_buffer_slice.range, 0..instance_buffer.len() as u32);
        }
    }

    RenderCommandResult::Success
}
