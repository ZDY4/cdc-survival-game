use bevy::asset::uuid_handle;
use bevy::core_pipeline::core_3d::{Opaque3d, Opaque3dBatchSetKey, Opaque3dBinKey, Transparent3d};
use bevy::ecs::change_detection::Tick;
use bevy::ecs::system::{lifetimeless::*, SystemParamItem};
use bevy::mesh::{MeshVertexBufferLayoutRef, VertexBufferLayout};
use bevy::pbr::{
    MeshPipeline, MeshPipelineKey, RenderMeshInstances, SetMeshBindGroup, SetMeshViewBindGroup,
    SetMeshViewBindingArrayBindGroup, ViewKeyCache,
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

use super::{
    WorldRenderStandardTileBatchMaterialState, WorldRenderStandardTileBatchSource,
    WorldRenderTileBatchVisualState,
};

pub const STANDARD_TILE_INSTANCING_SHADER_HANDLE: Handle<Shader> =
    uuid_handle!("f9dd33be-b22f-4ec0-beb5-f75b95de0cc5");

pub(super) struct WorldRenderStandardTileInstancingPlugin;

impl Plugin for WorldRenderStandardTileInstancingPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((
            ExtractComponentPlugin::<WorldRenderTileBatchVisualState>::default(),
            ExtractComponentPlugin::<WorldRenderStandardTileBatchSource>::default(),
            ExtractComponentPlugin::<WorldRenderStandardTileBatchMaterialState>::default(),
        ));

        let Some(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app
            .add_render_command::<Opaque3d, DrawWorldRenderStandardTileInstancedOpaque>()
            .add_render_command::<Transparent3d, DrawWorldRenderStandardTileInstancedTransparent>()
            .init_resource::<SpecializedMeshPipelines<WorldRenderStandardTilePipeline>>()
            .add_systems(RenderStartup, init_world_render_standard_tile_pipeline)
            .add_systems(
                Render,
                (
                    queue_world_render_standard_tile_opaque_batches
                        .in_set(RenderSystems::QueueMeshes),
                    queue_world_render_standard_tile_transparent_batches
                        .in_set(RenderSystems::QueueMeshes),
                    prepare_world_render_standard_tile_instance_buffers
                        .in_set(RenderSystems::PrepareResources),
                ),
            );
    }
}

#[derive(Component)]
struct WorldRenderStandardTileOpaqueInstanceBuffer {
    buffer: Buffer,
    length: usize,
}

#[derive(Component)]
struct WorldRenderStandardTileTransparentInstanceBuffer {
    buffer: Buffer,
    length: usize,
    center: Vec3,
}

#[derive(Clone, Copy, Pod, Zeroable)]
#[repr(C)]
struct WorldRenderStandardTileInstanceGpuData {
    world_from_local_0: [f32; 4],
    world_from_local_1: [f32; 4],
    world_from_local_2: [f32; 4],
    world_from_local_3: [f32; 4],
    color: [f32; 4],
}

#[derive(Resource)]
struct WorldRenderStandardTilePipeline {
    shader: Handle<Shader>,
    mesh_pipeline: MeshPipeline,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum WorldRenderStandardTilePass {
    Opaque,
    Transparent,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct WorldRenderStandardTilePipelineKey {
    mesh_key: MeshPipelineKey,
    pass: WorldRenderStandardTilePass,
}

fn init_world_render_standard_tile_pipeline(
    mut commands: Commands,
    mesh_pipeline: Res<MeshPipeline>,
) {
    commands.insert_resource(WorldRenderStandardTilePipeline {
        shader: STANDARD_TILE_INSTANCING_SHADER_HANDLE.clone(),
        mesh_pipeline: mesh_pipeline.clone(),
    });
}

fn prepare_world_render_standard_tile_instance_buffers(
    mut commands: Commands,
    // Standard tile batches are extracted into the render world without `Mesh3d`,
    // so filtering on `Mesh3d` here would skip ramps, floors, and other tile instances.
    batches: Query<(
        Entity,
        &WorldRenderTileBatchVisualState,
        &WorldRenderStandardTileBatchSource,
        &WorldRenderStandardTileBatchMaterialState,
    )>,
    render_device: Res<RenderDevice>,
) {
    for (entity, batch_visual_state, batch_source, batch_material_state) in &batches {
        if batch_visual_state.instances.is_empty() {
            commands
                .entity(entity)
                .remove::<WorldRenderStandardTileOpaqueInstanceBuffer>()
                .remove::<WorldRenderStandardTileTransparentInstanceBuffer>();
            continue;
        }

        let base_color = batch_material_state.base_color.to_linear().to_vec4();
        let mut opaque_instance_data = Vec::with_capacity(batch_visual_state.instances.len());
        let mut transparent_instance_data = Vec::new();
        let mut transparent_center_sum = Vec3::ZERO;

        for instance in &batch_visual_state.instances {
            let tint = instance.tint.to_linear().to_vec4();
            let alpha =
                (base_color.w * tint.w * instance.fade_alpha.clamp(0.0, 1.0)).clamp(0.0, 1.0);
            let matrix = (instance.transform.to_matrix()
                * batch_source.prototype_local_transform.to_matrix())
            .to_cols_array_2d();
            let gpu_data = WorldRenderStandardTileInstanceGpuData {
                world_from_local_0: matrix[0],
                world_from_local_1: matrix[1],
                world_from_local_2: matrix[2],
                world_from_local_3: matrix[3],
                color: [
                    base_color.x * tint.x,
                    base_color.y * tint.y,
                    base_color.z * tint.z,
                    alpha,
                ],
            };

            if alpha < 0.999 {
                transparent_center_sum += instance.transform.translation;
                transparent_instance_data.push(gpu_data);
            } else {
                opaque_instance_data.push(gpu_data);
            }
        }

        let mut entity_commands = commands.entity(entity);
        write_standard_tile_opaque_buffer(
            &mut entity_commands,
            &render_device,
            opaque_instance_data.as_slice(),
        );
        write_standard_tile_transparent_buffer(
            &mut entity_commands,
            &render_device,
            transparent_instance_data.as_slice(),
            transparent_center_sum,
        );
    }
}

fn write_standard_tile_opaque_buffer(
    entity_commands: &mut EntityCommands,
    render_device: &RenderDevice,
    instance_data: &[WorldRenderStandardTileInstanceGpuData],
) {
    if instance_data.is_empty() {
        entity_commands.remove::<WorldRenderStandardTileOpaqueInstanceBuffer>();
        return;
    }

    let buffer = render_device.create_buffer_with_data(&BufferInitDescriptor {
        label: Some("world render standard tile opaque instance buffer"),
        contents: bytemuck::cast_slice(instance_data),
        usage: BufferUsages::VERTEX | BufferUsages::COPY_DST,
    });

    entity_commands.insert(WorldRenderStandardTileOpaqueInstanceBuffer {
        buffer,
        length: instance_data.len(),
    });
}

fn write_standard_tile_transparent_buffer(
    entity_commands: &mut EntityCommands,
    render_device: &RenderDevice,
    instance_data: &[WorldRenderStandardTileInstanceGpuData],
    center_sum: Vec3,
) {
    if instance_data.is_empty() {
        entity_commands.remove::<WorldRenderStandardTileTransparentInstanceBuffer>();
        return;
    }

    let buffer = render_device.create_buffer_with_data(&BufferInitDescriptor {
        label: Some("world render standard tile transparent instance buffer"),
        contents: bytemuck::cast_slice(instance_data),
        usage: BufferUsages::VERTEX | BufferUsages::COPY_DST,
    });

    entity_commands.insert(WorldRenderStandardTileTransparentInstanceBuffer {
        buffer,
        length: instance_data.len(),
        center: center_sum / instance_data.len() as f32,
    });
}

fn queue_world_render_standard_tile_opaque_batches(
    opaque_draw_functions: Res<DrawFunctions<Opaque3d>>,
    custom_pipeline: Res<WorldRenderStandardTilePipeline>,
    mut pipelines: ResMut<SpecializedMeshPipelines<WorldRenderStandardTilePipeline>>,
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
            &WorldRenderStandardTileOpaqueInstanceBuffer,
        ),
        With<WorldRenderStandardTileBatchMaterialState>,
    >,
    mut opaque_render_phases: ResMut<ViewBinnedRenderPhases<Opaque3d>>,
    views: Query<&ExtractedView>,
    mut change_tick: Local<Tick>,
) {
    let draw_function = opaque_draw_functions
        .read()
        .id::<DrawWorldRenderStandardTileInstancedOpaque>();

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
                WorldRenderStandardTilePipelineKey {
                    mesh_key,
                    pass: WorldRenderStandardTilePass::Opaque,
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
                // Our per-entity instance payload lives in a custom GPU buffer, so
                // Bevy's cross-entity mesh batching would bind the wrong instance data.
                BinnedRenderPhaseType::mesh(false, &gpu_preprocessing_support),
                *change_tick,
            );
        }
    }
}

fn queue_world_render_standard_tile_transparent_batches(
    transparent_draw_functions: Res<DrawFunctions<Transparent3d>>,
    custom_pipeline: Res<WorldRenderStandardTilePipeline>,
    mut pipelines: ResMut<SpecializedMeshPipelines<WorldRenderStandardTilePipeline>>,
    pipeline_cache: Res<PipelineCache>,
    meshes: Res<RenderAssets<RenderMesh>>,
    render_mesh_instances: Res<RenderMeshInstances>,
    view_key_cache: Res<ViewKeyCache>,
    batches: Query<
        (
            Entity,
            &MainEntity,
            &WorldRenderStandardTileTransparentInstanceBuffer,
        ),
        With<WorldRenderStandardTileBatchMaterialState>,
    >,
    mut transparent_render_phases: ResMut<ViewSortedRenderPhases<Transparent3d>>,
    views: Query<&ExtractedView>,
) {
    let draw_function = transparent_draw_functions
        .read()
        .id::<DrawWorldRenderStandardTileInstancedTransparent>();

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
                WorldRenderStandardTilePipelineKey {
                    mesh_key,
                    pass: WorldRenderStandardTilePass::Transparent,
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

impl SpecializedMeshPipeline for WorldRenderStandardTilePipeline {
    type Key = WorldRenderStandardTilePipelineKey;

    fn specialize(
        &self,
        key: Self::Key,
        layout: &MeshVertexBufferLayoutRef,
    ) -> Result<RenderPipelineDescriptor, SpecializedMeshPipelineError> {
        let mut descriptor = self.mesh_pipeline.specialize(key.mesh_key, layout)?;
        descriptor.label = Some("world_render_standard_tile_instanced_pipeline".into());
        descriptor.vertex.shader = self.shader.clone();
        descriptor.vertex.buffers.push(VertexBufferLayout {
            array_stride: std::mem::size_of::<WorldRenderStandardTileInstanceGpuData>() as u64,
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
            ],
        });
        if let Some(fragment) = descriptor.fragment.as_mut() {
            fragment.shader = self.shader.clone();
            if let Some(Some(target)) = fragment.targets.first_mut() {
                target.blend = match key.pass {
                    WorldRenderStandardTilePass::Opaque => None,
                    WorldRenderStandardTilePass::Transparent => Some(BlendState::ALPHA_BLENDING),
                };
            }
        }
        if let Some(depth_stencil) = descriptor.depth_stencil.as_mut() {
            depth_stencil.depth_write_enabled =
                matches!(key.pass, WorldRenderStandardTilePass::Opaque);
        }
        Ok(descriptor)
    }
}

type DrawWorldRenderStandardTileInstancedOpaque = (
    SetItemPipeline,
    SetMeshViewBindGroup<0>,
    SetMeshViewBindingArrayBindGroup<1>,
    SetMeshBindGroup<2>,
    DrawWorldRenderStandardTileInstancedOpaqueMesh,
);

type DrawWorldRenderStandardTileInstancedTransparent = (
    SetItemPipeline,
    SetMeshViewBindGroup<0>,
    SetMeshViewBindingArrayBindGroup<1>,
    SetMeshBindGroup<2>,
    DrawWorldRenderStandardTileInstancedTransparentMesh,
);

struct DrawWorldRenderStandardTileInstancedOpaqueMesh;

impl<P: PhaseItem> RenderCommand<P> for DrawWorldRenderStandardTileInstancedOpaqueMesh {
    type Param = (
        SRes<RenderAssets<RenderMesh>>,
        SRes<RenderMeshInstances>,
        SRes<MeshAllocator>,
    );
    type ViewQuery = ();
    type ItemQuery = Read<WorldRenderStandardTileOpaqueInstanceBuffer>;

    fn render<'w>(
        item: &P,
        _view: (),
        instance_buffer: Option<&'w WorldRenderStandardTileOpaqueInstanceBuffer>,
        params: SystemParamItem<'w, '_, Self::Param>,
        pass: &mut TrackedRenderPass<'w>,
    ) -> RenderCommandResult {
        render_standard_tile_instanced_mesh(item, instance_buffer, params, pass)
    }
}

struct DrawWorldRenderStandardTileInstancedTransparentMesh;

impl<P: PhaseItem> RenderCommand<P> for DrawWorldRenderStandardTileInstancedTransparentMesh {
    type Param = (
        SRes<RenderAssets<RenderMesh>>,
        SRes<RenderMeshInstances>,
        SRes<MeshAllocator>,
    );
    type ViewQuery = ();
    type ItemQuery = Read<WorldRenderStandardTileTransparentInstanceBuffer>;

    fn render<'w>(
        item: &P,
        _view: (),
        instance_buffer: Option<&'w WorldRenderStandardTileTransparentInstanceBuffer>,
        params: SystemParamItem<'w, '_, Self::Param>,
        pass: &mut TrackedRenderPass<'w>,
    ) -> RenderCommandResult {
        render_standard_tile_instanced_mesh(item, instance_buffer, params, pass)
    }
}

trait WorldRenderStandardTileInstanceBufferExt {
    fn buffer(&self) -> &Buffer;
    fn len(&self) -> usize;
}

impl WorldRenderStandardTileInstanceBufferExt for WorldRenderStandardTileOpaqueInstanceBuffer {
    fn buffer(&self) -> &Buffer {
        &self.buffer
    }

    fn len(&self) -> usize {
        self.length
    }
}

impl WorldRenderStandardTileInstanceBufferExt for WorldRenderStandardTileTransparentInstanceBuffer {
    fn buffer(&self) -> &Buffer {
        &self.buffer
    }

    fn len(&self) -> usize {
        self.length
    }
}

fn render_standard_tile_instanced_mesh<'w, P, B>(
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
    B: WorldRenderStandardTileInstanceBufferExt,
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
