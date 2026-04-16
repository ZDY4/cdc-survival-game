use bevy::asset::uuid_handle;
use bevy::core_pipeline::core_3d::Transparent3d;
use bevy::ecs::system::{lifetimeless::*, SystemParamItem};
use bevy::mesh::{MeshVertexBufferLayoutRef, VertexBufferLayout};
use bevy::pbr::{
    MeshPipeline, MeshPipelineKey, RenderMeshInstances, SetMeshBindGroup, SetMeshViewBindGroup,
    SetMeshViewBindingArrayBindGroup, ViewKeyCache,
};
use bevy::prelude::*;
use bevy::render::extract_component::ExtractComponentPlugin;
use bevy::render::mesh::{allocator::MeshAllocator, RenderMesh, RenderMeshBufferInfo};
use bevy::render::render_asset::RenderAssets;
use bevy::render::render_phase::{
    AddRenderCommand, DrawFunctions, PhaseItem, PhaseItemExtraIndex, RenderCommand,
    RenderCommandResult, SetItemPipeline, TrackedRenderPass, ViewSortedRenderPhases,
};
use bevy::render::render_resource::*;
use bevy::render::renderer::RenderDevice;
use bevy::render::sync_world::MainEntity;
use bevy::render::view::ExtractedView;
use bevy::render::{Render, RenderApp, RenderStartup, RenderSystems};
use bytemuck::{Pod, Zeroable};

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
            .add_render_command::<Transparent3d, DrawWorldRenderBuildingWallTileInstanced>()
            .init_resource::<SpecializedMeshPipelines<WorldRenderBuildingWallTilePipeline>>()
            .add_systems(RenderStartup, init_world_render_building_wall_tile_pipeline)
            .add_systems(
                Render,
                (
                    queue_world_render_building_wall_tile_batches
                        .in_set(RenderSystems::QueueMeshes),
                    prepare_world_render_building_wall_tile_instance_buffers
                        .in_set(RenderSystems::PrepareResources),
                ),
            );
    }
}

#[derive(Component)]
struct WorldRenderBuildingWallTileInstanceBuffer {
    buffer: Buffer,
    length: usize,
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct WorldRenderBuildingWallTilePipelineKey {
    mesh_key: MeshPipelineKey,
    blended: bool,
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
                .remove::<WorldRenderBuildingWallTileInstanceBuffer>();
            continue;
        }

        let profile = building_wall_visual_profile(batch_source.visual_kind);
        let instance_data = batch_visual_state
            .instances
            .iter()
            .map(|instance| {
                let tint = instance.tint.to_linear().to_vec4();
                let fade_alpha = instance.fade_alpha.clamp(0.0, 1.0);
                let faded = fade_alpha < 0.999;
                let tint_rgb = Vec3::new(tint.x, tint.y, tint.z);
                let face_color = profile.face_color.to_linear().to_vec4();
                let major_line_color = profile.major_line_color.to_linear().to_vec4();
                let minor_line_color = profile.minor_line_color.to_linear().to_vec4();
                let cap_color = profile.cap_color.to_linear().to_vec4();
                let matrix = (instance.transform.to_matrix()
                    * batch_source.prototype_local_transform.to_matrix())
                .to_cols_array_2d();

                WorldRenderBuildingWallTileInstanceGpuData {
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
                        0.0,
                    ],
                }
            })
            .collect::<Vec<_>>();

        let buffer = render_device.create_buffer_with_data(&BufferInitDescriptor {
            label: Some("world render building wall tile instance buffer"),
            contents: bytemuck::cast_slice(instance_data.as_slice()),
            usage: BufferUsages::VERTEX | BufferUsages::COPY_DST,
        });

        commands
            .entity(entity)
            .insert(WorldRenderBuildingWallTileInstanceBuffer {
                buffer,
                length: instance_data.len(),
            });
    }
}

fn queue_world_render_building_wall_tile_batches(
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
            &WorldRenderTileBatchVisualState,
            &WorldRenderBuildingWallTileInstanceBuffer,
        ),
        With<WorldRenderBuildingWallTileBatchSource>,
    >,
    mut transparent_render_phases: ResMut<ViewSortedRenderPhases<Transparent3d>>,
    views: Query<(&ExtractedView, &Msaa)>,
) {
    let draw_function = transparent_draw_functions
        .read()
        .id::<DrawWorldRenderBuildingWallTileInstanced>();

    for (view, _msaa) in &views {
        let Some(transparent_phase) = transparent_render_phases.get_mut(&view.retained_view_entity)
        else {
            continue;
        };

        let Some(view_key) = view_key_cache.get(&view.retained_view_entity).copied() else {
            continue;
        };
        let rangefinder = view.rangefinder3d();

        for (entity, main_entity, batch_visual_state, instance_buffer) in &batches {
            if instance_buffer.length == 0 || batch_visual_state.instances.is_empty() {
                continue;
            }

            let Some(mesh_instance) = render_mesh_instances.render_mesh_queue_data(*main_entity)
            else {
                continue;
            };
            let Some(mesh) = meshes.get(mesh_instance.mesh_asset_id) else {
                continue;
            };
            let batch_center = batch_center(batch_visual_state);
            let mesh_key =
                view_key | MeshPipelineKey::from_primitive_topology(mesh.primitive_topology());
            let blended = batch_visual_state
                .instances
                .iter()
                .any(|instance| instance.fade_alpha < 0.999 || instance.tint.to_linear().to_vec4().w < 0.999);
            let key = WorldRenderBuildingWallTilePipelineKey { mesh_key, blended };
            let pipeline =
                match pipelines.specialize(&pipeline_cache, &custom_pipeline, key, &mesh.layout) {
                    Ok(pipeline) => pipeline,
                    Err(_) => continue,
                };

            transparent_phase.add(Transparent3d {
                entity: (entity, *main_entity),
                pipeline,
                draw_function,
                distance: rangefinder.distance(&batch_center),
                batch_range: 0..1,
                extra_index: PhaseItemExtraIndex::None,
                indexed: matches!(mesh.buffer_info, RenderMeshBufferInfo::Indexed { .. }),
            });
        }
    }
}

fn batch_center(batch_visual_state: &WorldRenderTileBatchVisualState) -> Vec3 {
    let sum = batch_visual_state
        .instances
        .iter()
        .fold(Vec3::ZERO, |acc, instance| {
            acc + instance.transform.translation
        });
    sum / batch_visual_state.instances.len().max(1) as f32
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
        descriptor.vertex.buffers.push(VertexBufferLayout {
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
        });
        if let Some(fragment) = descriptor.fragment.as_mut() {
            fragment.shader = self.shader.clone();
            if let Some(Some(target)) = fragment.targets.first_mut() {
                target.blend = key.blended.then_some(BlendState::ALPHA_BLENDING);
            }
        }
        if let Some(depth_stencil) = descriptor.depth_stencil.as_mut() {
            depth_stencil.depth_write_enabled = !key.blended;
        }
        Ok(descriptor)
    }
}

type DrawWorldRenderBuildingWallTileInstanced = (
    SetItemPipeline,
    SetMeshViewBindGroup<0>,
    SetMeshViewBindingArrayBindGroup<1>,
    SetMeshBindGroup<2>,
    DrawWorldRenderBuildingWallTileInstancedMesh,
);

struct DrawWorldRenderBuildingWallTileInstancedMesh;

impl<P: PhaseItem> RenderCommand<P> for DrawWorldRenderBuildingWallTileInstancedMesh {
    type Param = (
        SRes<RenderAssets<RenderMesh>>,
        SRes<RenderMeshInstances>,
        SRes<MeshAllocator>,
    );
    type ViewQuery = ();
    type ItemQuery = Read<WorldRenderBuildingWallTileInstanceBuffer>;

    fn render<'w>(
        item: &P,
        _view: (),
        instance_buffer: Option<&'w WorldRenderBuildingWallTileInstanceBuffer>,
        (meshes, render_mesh_instances, mesh_allocator): SystemParamItem<'w, '_, Self::Param>,
        pass: &mut TrackedRenderPass<'w>,
    ) -> RenderCommandResult {
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
        let Some(vertex_buffer_slice) =
            mesh_allocator.mesh_vertex_slice(&mesh_instance.mesh_asset_id)
        else {
            return RenderCommandResult::Skip;
        };

        pass.set_vertex_buffer(0, vertex_buffer_slice.buffer.slice(..));
        pass.set_vertex_buffer(1, instance_buffer.buffer.slice(..));

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
                    0..instance_buffer.length as u32,
                );
            }
            RenderMeshBufferInfo::NonIndexed => {
                pass.draw(vertex_buffer_slice.range, 0..instance_buffer.length as u32);
            }
        }

        RenderCommandResult::Success
    }
}
