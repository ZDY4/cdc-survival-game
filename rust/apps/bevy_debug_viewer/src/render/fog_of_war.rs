//! 战争迷雾后处理模块：负责战争迷雾 mask 纹理、后处理管线和可见区域快照构建。

use super::*;
use bevy::asset::RenderAssetUsages;
use bevy::core_pipeline::{
    core_3d::graph::{Core3d, Node3d},
    prepass::ViewPrepassTextures,
    FullscreenShader,
};
use bevy::ecs::query::QueryItem;
use bevy::image::ImageSampler;
use bevy::render::extract_component::{
    ComponentUniforms, DynamicUniformIndex, ExtractComponent, ExtractComponentPlugin,
    UniformComponentPlugin,
};
use bevy::render::render_asset::RenderAssets;
use bevy::render::render_graph::{
    NodeRunError, RenderGraphContext, RenderGraphExt, RenderLabel, ViewNode, ViewNodeRunner,
};
use bevy::render::render_resource::binding_types::{
    sampler, texture_2d, texture_depth_2d, uniform_buffer,
};
use bevy::render::render_resource::*;
use bevy::render::renderer::{RenderContext, RenderDevice};
use bevy::render::texture::GpuImage;
use bevy::render::view::ViewTarget;
use bevy::render::{RenderApp, RenderStartup};
use game_core::vision::ActorVisionSnapshot;

const FOG_OF_WAR_MASK_VISIBLE: u8 = 0;
const FOG_OF_WAR_MASK_EXPLORED: u8 = 128;
const FOG_OF_WAR_MASK_UNEXPLORED: u8 = 255;
const FOG_OF_WAR_POST_PROCESS_SHADER_PATH: &str = "shaders/fog_of_war_post_process.wgsl";

#[derive(Component, Clone, Copy, Default, ExtractComponent)]
pub(crate) struct FogOfWarOverlay;

#[derive(Component, Clone, ExtractComponent)]
pub(crate) struct FogOfWarPostProcessTextures {
    pub current_mask: Handle<Image>,
    pub previous_mask: Handle<Image>,
}

#[derive(Component, Clone, Copy, ExtractComponent, ShaderType)]
pub(crate) struct FogOfWarPostProcessSettings {
    effect_params: Vec4,
    edge_softness_and_padding: Vec4,
    fog_color: Vec4,
    map_min_world_xz: Vec2,
    map_size_world_xz: Vec2,
    mask_texel_size: Vec2,
    _padding: Vec2,
    world_from_clip: Mat4,
}

impl Default for FogOfWarPostProcessSettings {
    fn default() -> Self {
        Self {
            effect_params: Vec4::ZERO,
            edge_softness_and_padding: Vec4::ZERO,
            fog_color: Vec4::ZERO,
            map_min_world_xz: Vec2::ZERO,
            map_size_world_xz: Vec2::ZERO,
            mask_texel_size: Vec2::ONE,
            _padding: Vec2::ZERO,
            world_from_clip: Mat4::IDENTITY,
        }
    }
}

pub(crate) struct FogOfWarPostProcessPlugin;

impl Plugin for FogOfWarPostProcessPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((
            ExtractComponentPlugin::<FogOfWarOverlay>::default(),
            ExtractComponentPlugin::<FogOfWarPostProcessTextures>::default(),
            ExtractComponentPlugin::<FogOfWarPostProcessSettings>::default(),
            UniformComponentPlugin::<FogOfWarPostProcessSettings>::default(),
        ));

        let Some(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app.add_systems(RenderStartup, init_fog_of_war_post_process_pipeline);
        render_app
            .add_render_graph_node::<ViewNodeRunner<FogOfWarPostProcessNode>>(
                Core3d,
                FogOfWarPostProcessLabel,
            )
            .add_render_graph_edges(
                Core3d,
                (
                    Node3d::Tonemapping,
                    FogOfWarPostProcessLabel,
                    Node3d::EndMainPassPostProcessing,
                ),
            );
    }
}

#[derive(Debug, Hash, PartialEq, Eq, Clone, RenderLabel)]
struct FogOfWarPostProcessLabel;

#[derive(Default)]
struct FogOfWarPostProcessNode;

impl ViewNode for FogOfWarPostProcessNode {
    type ViewQuery = (
        &'static ViewTarget,
        &'static ViewPrepassTextures,
        &'static FogOfWarOverlay,
        &'static FogOfWarPostProcessTextures,
        &'static FogOfWarPostProcessSettings,
        &'static DynamicUniformIndex<FogOfWarPostProcessSettings>,
    );

    fn run(
        &self,
        _graph: &mut RenderGraphContext,
        render_context: &mut RenderContext,
        (
            view_target,
            prepass_textures,
            _overlay,
            texture_handles,
            _settings,
            settings_index,
        ): QueryItem<Self::ViewQuery>,
        world: &World,
    ) -> Result<(), NodeRunError> {
        let post_process_pipeline = world.resource::<FogOfWarPostProcessPipeline>();
        let pipeline_cache = world.resource::<PipelineCache>();
        let Some(pipeline) = pipeline_cache.get_render_pipeline(post_process_pipeline.pipeline_id)
        else {
            return Ok(());
        };

        let settings_uniforms = world.resource::<ComponentUniforms<FogOfWarPostProcessSettings>>();
        let Some(settings_binding) = settings_uniforms.uniforms().binding() else {
            return Ok(());
        };

        let Some(depth_view) = prepass_textures.depth_view() else {
            return Ok(());
        };

        let gpu_images = world.resource::<RenderAssets<GpuImage>>();
        let Some(current_mask) = gpu_images.get(texture_handles.current_mask.id()) else {
            return Ok(());
        };
        let Some(previous_mask) = gpu_images.get(texture_handles.previous_mask.id()) else {
            return Ok(());
        };

        let post_process = view_target.post_process_write();
        let bind_group = render_context.render_device().create_bind_group(
            "fog_of_war_post_process_bind_group",
            &pipeline_cache.get_bind_group_layout(&post_process_pipeline.layout),
            &BindGroupEntries::sequential((
                post_process.source,
                &post_process_pipeline.source_sampler,
                depth_view,
                &current_mask.texture_view,
                &previous_mask.texture_view,
                &post_process_pipeline.mask_sampler,
                settings_binding.clone(),
            )),
        );

        let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
            label: Some("fog_of_war_post_process_pass"),
            color_attachments: &[Some(RenderPassColorAttachment {
                view: post_process.destination,
                depth_slice: None,
                resolve_target: None,
                ops: Operations::default(),
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });

        render_pass.set_render_pipeline(pipeline);
        render_pass.set_bind_group(0, &bind_group, &[settings_index.index()]);
        render_pass.draw(0..3, 0..1);

        Ok(())
    }
}

#[derive(Resource)]
struct FogOfWarPostProcessPipeline {
    layout: BindGroupLayoutDescriptor,
    source_sampler: Sampler,
    mask_sampler: Sampler,
    pipeline_id: CachedRenderPipelineId,
}

fn init_fog_of_war_post_process_pipeline(
    mut commands: Commands,
    render_device: Res<RenderDevice>,
    asset_server: Res<AssetServer>,
    fullscreen_shader: Res<FullscreenShader>,
    pipeline_cache: Res<PipelineCache>,
) {
    let layout = BindGroupLayoutDescriptor::new(
        "fog_of_war_post_process_bind_group_layout",
        &BindGroupLayoutEntries::sequential(
            ShaderStages::FRAGMENT,
            (
                texture_2d(TextureSampleType::Float { filterable: true }),
                sampler(SamplerBindingType::Filtering),
                texture_depth_2d(),
                texture_2d(TextureSampleType::Float { filterable: true }),
                texture_2d(TextureSampleType::Float { filterable: true }),
                sampler(SamplerBindingType::Filtering),
                uniform_buffer::<FogOfWarPostProcessSettings>(true),
            ),
        ),
    );
    let source_sampler = render_device.create_sampler(&SamplerDescriptor::default());
    let mask_sampler = render_device.create_sampler(&SamplerDescriptor {
        label: Some("fog_of_war_mask_sampler"),
        address_mode_u: AddressMode::ClampToEdge,
        address_mode_v: AddressMode::ClampToEdge,
        address_mode_w: AddressMode::ClampToEdge,
        mag_filter: FilterMode::Linear,
        min_filter: FilterMode::Linear,
        mipmap_filter: FilterMode::Nearest,
        ..default()
    });
    let shader = asset_server.load(FOG_OF_WAR_POST_PROCESS_SHADER_PATH);
    let vertex_state = fullscreen_shader.to_vertex_state();
    let pipeline_id = pipeline_cache.queue_render_pipeline(RenderPipelineDescriptor {
        label: Some("fog_of_war_post_process_pipeline".into()),
        layout: vec![layout.clone()],
        vertex: vertex_state,
        fragment: Some(FragmentState {
            shader,
            entry_point: Some("fragment".into()),
            targets: vec![Some(ColorTargetState {
                format: TextureFormat::bevy_default(),
                blend: None,
                write_mask: ColorWrites::ALL,
            })],
            ..default()
        }),
        ..default()
    });

    commands.insert_resource(FogOfWarPostProcessPipeline {
        layout,
        source_sampler,
        mask_sampler,
        pipeline_id,
    });
}

#[derive(Debug, Clone, PartialEq)]
pub(super) struct FogOfWarMaskSnapshot {
    pub(super) key: Option<FogOfWarMaskKey>,
    pub(super) actor_id: Option<ActorId>,
    pub(super) map_id: Option<game_data::MapId>,
    pub(super) current_level: i32,
    pub(super) bounds: Option<GridBounds>,
    pub(super) map_min_world_xz: Vec2,
    pub(super) map_size_world_xz: Vec2,
    pub(super) mask_size: UVec2,
    pub(super) mask_texel_size: Vec2,
    pub(super) bytes: Vec<u8>,
}

pub(super) fn current_focus_actor_vision<'a>(
    snapshot: &'a game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
) -> Option<&'a ActorVisionSnapshot> {
    let actor_id = viewer_state.focus_actor_id(snapshot)?;
    snapshot.vision.actors.iter().find(|vision| {
        vision.actor_id == actor_id
            && vision.active_map_id.as_ref() == snapshot.grid.map_id.as_ref()
    })
}

pub(super) fn build_fog_of_war_mask_image(size: UVec2, bytes: &[u8]) -> Image {
    let mut image = Image::new_fill(
        Extent3d {
            width: size.x.max(1),
            height: size.y.max(1),
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        bytes,
        TextureFormat::R8Unorm,
        RenderAssetUsages::default(),
    );
    image.sampler = ImageSampler::linear();
    image
}

pub(super) fn update_fog_of_war_mask_image(
    images: &mut Assets<Image>,
    handle: &Handle<Image>,
    size: UVec2,
    bytes: &[u8],
) {
    let Some(image) = images.get_mut(handle) else {
        return;
    };
    image.data = Some(bytes.to_vec());
    image.texture_descriptor.size = Extent3d {
        width: size.x.max(1),
        height: size.y.max(1),
        depth_or_array_layers: 1,
    };
    image.texture_descriptor.dimension = TextureDimension::D2;
    image.texture_descriptor.format = TextureFormat::R8Unorm;
    image.texture_view_descriptor = None;
    image.sampler = ImageSampler::linear();
}

pub(crate) fn tick_fog_of_war_transition(
    time: Res<Time>,
    render_config: Res<ViewerRenderConfig>,
    mut fog_of_war_state: ResMut<FogOfWarMaskState>,
) {
    if fog_of_war_state.key.is_none() {
        return;
    }

    let duration = render_config.fow_transition_duration_sec.max(0.0);
    fog_of_war_state.transition_elapsed_sec =
        (fog_of_war_state.transition_elapsed_sec + time.delta_secs()).min(duration);
}

pub(crate) fn sync_fog_of_war_post_process_camera(
    scene_kind: Res<ViewerSceneKind>,
    render_config: Res<ViewerRenderConfig>,
    fog_of_war_state: Res<FogOfWarMaskState>,
    camera_query: Single<
        (
            &mut FogOfWarPostProcessSettings,
            &mut FogOfWarPostProcessTextures,
            &Projection,
            &Transform,
        ),
        (With<ViewerCamera>, With<FogOfWarOverlay>),
    >,
) {
    let (mut settings, mut textures, projection, transform) = camera_query.into_inner();
    textures.current_mask = fog_of_war_state.current_mask.clone();
    textures.previous_mask = fog_of_war_state.previous_mask.clone();

    let duration = render_config.fow_transition_duration_sec.max(0.0);
    let transition_progress = if duration <= f32::EPSILON {
        1.0
    } else {
        (fog_of_war_state.transition_elapsed_sec / duration).clamp(0.0, 1.0)
    };

    let clip_from_view = projection.get_clip_from_view();
    let world_from_view = transform.to_matrix();
    let world_from_clip = world_from_view * clip_from_view.inverse();
    let fog_of_war_enabled = !scene_kind.is_main_menu() && fog_of_war_state.key.is_some();

    *settings = FogOfWarPostProcessSettings {
        effect_params: Vec4::new(
            if fog_of_war_enabled { 1.0 } else { 0.0 },
            transition_progress,
            render_config.fow_explored_alpha.clamp(0.0, 1.0),
            render_config.fow_unexplored_alpha.clamp(0.0, 1.0),
        ),
        edge_softness_and_padding: Vec4::new(
            render_config.fow_edge_softness.max(0.0),
            0.0,
            0.0,
            0.0,
        ),
        fog_color: render_config.fow_fog_color.to_linear().to_vec4(),
        map_min_world_xz: fog_of_war_state.map_min_world_xz,
        map_size_world_xz: fog_of_war_state.map_size_world_xz,
        mask_texel_size: fog_of_war_state.mask_texel_size,
        _padding: Vec2::ZERO,
        world_from_clip,
    };
}

pub(super) fn build_fog_of_war_mask_snapshot(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    disabled: bool,
) -> FogOfWarMaskSnapshot {
    let current_level = viewer_state.current_level;
    if disabled {
        return FogOfWarMaskSnapshot::disabled(current_level);
    }

    let actor_id = viewer_state.focus_actor_id(snapshot);
    let Some(vision) = current_focus_actor_vision(snapshot, viewer_state) else {
        return FogOfWarMaskSnapshot::disabled(current_level);
    };
    let bounds = grid_bounds(snapshot, current_level);
    let map_id = snapshot.grid.map_id.clone();
    let mut visible_cells =
        collect_mask_cells(vision.visible_cells.iter().copied(), current_level, bounds);
    let mut explored_cells = collect_mask_cells(
        vision
            .explored_maps
            .iter()
            .find(|entry| Some(&entry.map_id) == map_id.as_ref())
            .into_iter()
            .flat_map(|entry| entry.explored_cells.iter().copied()),
        current_level,
        bounds,
    );

    visible_cells.sort_unstable_by_key(grid_sort_key);
    visible_cells.dedup();
    explored_cells.sort_unstable_by_key(grid_sort_key);
    explored_cells.dedup();

    let mask_size = UVec2::new(
        (bounds.max_x - bounds.min_x + 1).max(1) as u32,
        (bounds.max_z - bounds.min_z + 1).max(1) as u32,
    );
    let bytes = build_fog_of_war_mask_bytes(mask_size, bounds, &explored_cells, &visible_cells);
    let grid_size = snapshot.grid.grid_size.max(0.0001);

    FogOfWarMaskSnapshot {
        key: Some(FogOfWarMaskKey {
            map_id: map_id.clone(),
            current_level,
            topology_version: snapshot.grid.topology_version,
            actor_id,
            bounds,
            visible_cells,
            explored_cells,
        }),
        actor_id,
        map_id,
        current_level,
        bounds: Some(bounds),
        map_min_world_xz: Vec2::new(
            bounds.min_x as f32 * grid_size,
            bounds.min_z as f32 * grid_size,
        ),
        map_size_world_xz: Vec2::new(
            mask_size.x as f32 * grid_size,
            mask_size.y as f32 * grid_size,
        ),
        mask_size,
        mask_texel_size: Vec2::new(1.0 / mask_size.x as f32, 1.0 / mask_size.y as f32),
        bytes,
    }
}

fn collect_mask_cells(
    cells: impl IntoIterator<Item = GridCoord>,
    current_level: i32,
    bounds: GridBounds,
) -> Vec<GridCoord> {
    cells
        .into_iter()
        .filter(|grid| {
            grid.y == current_level
                && grid.x >= bounds.min_x
                && grid.x <= bounds.max_x
                && grid.z >= bounds.min_z
                && grid.z <= bounds.max_z
        })
        .collect()
}

fn build_fog_of_war_mask_bytes(
    mask_size: UVec2,
    bounds: GridBounds,
    explored_cells: &[GridCoord],
    visible_cells: &[GridCoord],
) -> Vec<u8> {
    let mut bytes = vec![FOG_OF_WAR_MASK_UNEXPLORED; (mask_size.x * mask_size.y) as usize];
    for grid in explored_cells {
        if let Some(index) = mask_index(mask_size, bounds, *grid) {
            bytes[index] = FOG_OF_WAR_MASK_EXPLORED;
        }
    }
    for grid in visible_cells {
        if let Some(index) = mask_index(mask_size, bounds, *grid) {
            bytes[index] = FOG_OF_WAR_MASK_VISIBLE;
        }
    }
    bytes
}

fn mask_index(mask_size: UVec2, bounds: GridBounds, grid: GridCoord) -> Option<usize> {
    if grid.x < bounds.min_x
        || grid.x > bounds.max_x
        || grid.z < bounds.min_z
        || grid.z > bounds.max_z
    {
        return None;
    }

    let local_x = (grid.x - bounds.min_x) as u32;
    let local_z = (grid.z - bounds.min_z) as u32;
    Some((local_z * mask_size.x + local_x) as usize)
}

fn grid_sort_key(grid: &GridCoord) -> (i32, i32, i32) {
    (grid.x, grid.y, grid.z)
}

impl FogOfWarMaskSnapshot {
    fn disabled(current_level: i32) -> Self {
        Self {
            key: None,
            actor_id: None,
            map_id: None,
            current_level,
            bounds: None,
            map_min_world_xz: Vec2::ZERO,
            map_size_world_xz: Vec2::ZERO,
            mask_size: UVec2::ONE,
            mask_texel_size: Vec2::ONE,
            bytes: vec![FOG_OF_WAR_MASK_UNEXPLORED],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use game_core::{
        vision::{ActorVisionMapSnapshot, ActorVisionSnapshot, VisionRuntimeSnapshot},
        ActorDebugState, CombatDebugState, GridDebugState, OverworldStateSnapshot,
        SimulationSnapshot,
    };
    use game_data::{
        ActorId, ActorKind, ActorSide, CharacterId, InteractionContextSnapshot, MapId, TurnState,
    };

    #[test]
    fn mask_encoding_visible_overrides_explored_and_leaves_unexplored_dark() {
        let bounds = GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        };
        let bytes = build_fog_of_war_mask_bytes(
            UVec2::new(2, 2),
            bounds,
            &[GridCoord::new(0, 0, 0), GridCoord::new(1, 0, 1)],
            &[GridCoord::new(0, 0, 0)],
        );

        assert_eq!(bytes, vec![0, 255, 255, 128]);
    }

    #[test]
    fn mask_snapshot_filters_current_map_and_level() {
        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: vec![sample_actor(ActorId(1))],
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: Some(MapId("map_a".into())),
                map_width: Some(3),
                map_height: Some(2),
                default_level: Some(0),
                levels: vec![0, 1],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 7,
                runtime_obstacle_version: 0,
            },
            vision: VisionRuntimeSnapshot {
                actors: vec![ActorVisionSnapshot {
                    actor_id: ActorId(1),
                    radius: 10,
                    active_map_id: Some(MapId("map_a".into())),
                    visible_cells: vec![
                        GridCoord::new(0, 0, 0),
                        GridCoord::new(1, 1, 0),
                        GridCoord::new(2, 0, 1),
                    ],
                    explored_maps: vec![
                        ActorVisionMapSnapshot {
                            map_id: MapId("map_a".into()),
                            explored_cells: vec![
                                GridCoord::new(0, 0, 0),
                                GridCoord::new(1, 0, 0),
                                GridCoord::new(1, 1, 0),
                            ],
                        },
                        ActorVisionMapSnapshot {
                            map_id: MapId("map_b".into()),
                            explored_cells: vec![GridCoord::new(2, 0, 0)],
                        },
                    ],
                }],
            },
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        };
        let viewer_state = ViewerState {
            selected_actor: Some(ActorId(1)),
            current_level: 0,
            ..ViewerState::default()
        };

        let mask = build_fog_of_war_mask_snapshot(&snapshot, &viewer_state, false);
        let key = mask.key.expect("mask should be enabled");

        assert_eq!(
            key.visible_cells,
            vec![GridCoord::new(0, 0, 0), GridCoord::new(2, 0, 1)]
        );
        assert_eq!(
            key.explored_cells,
            vec![GridCoord::new(0, 0, 0), GridCoord::new(1, 0, 0)]
        );
        assert_eq!(mask.bytes, vec![0, 128, 255, 255, 255, 0]);
    }

    #[test]
    fn unchanged_mask_input_keeps_same_snapshot_payload() {
        let snapshot = sample_snapshot(
            vec![GridCoord::new(0, 0, 0)],
            vec![GridCoord::new(1, 0, 0)],
            9,
        );
        let viewer_state = ViewerState {
            selected_actor: Some(ActorId(1)),
            current_level: 0,
            ..ViewerState::default()
        };

        let first = build_fog_of_war_mask_snapshot(&snapshot, &viewer_state, false);
        let second = build_fog_of_war_mask_snapshot(&snapshot, &viewer_state, false);

        assert_eq!(first, second);
    }

    #[test]
    fn changed_mask_input_preserves_previous_bytes_and_resets_transition() {
        let current_handle = Handle::<Image>::default();
        let previous_handle = Handle::<Image>::default();
        let mut state = FogOfWarMaskState::new(current_handle, previous_handle);
        let first = sample_snapshot(
            vec![GridCoord::new(0, 0, 0)],
            vec![GridCoord::new(1, 0, 0)],
            1,
        );
        let second = sample_snapshot(
            vec![GridCoord::new(1, 0, 0)],
            vec![GridCoord::new(0, 0, 0)],
            2,
        );
        let viewer_state = ViewerState {
            selected_actor: Some(ActorId(1)),
            current_level: 0,
            ..ViewerState::default()
        };

        let first_mask = build_fog_of_war_mask_snapshot(&first, &viewer_state, false);
        state.current_bytes = first_mask.bytes.clone();
        state.key = first_mask.key.clone();
        state.transition_elapsed_sec = 0.18;

        let next_fog_of_war_mask = build_fog_of_war_mask_snapshot(&second, &viewer_state, false);
        state.previous_bytes = state.current_bytes.clone();
        state.current_bytes = next_fog_of_war_mask.bytes.clone();
        state.key = next_fog_of_war_mask.key.clone();
        state.transition_elapsed_sec = 0.0;

        assert_eq!(state.previous_bytes, first_mask.bytes);
        assert_eq!(state.current_bytes, next_fog_of_war_mask.bytes);
        assert_eq!(state.transition_elapsed_sec, 0.0);
    }

    fn sample_snapshot(
        visible_cells: Vec<GridCoord>,
        explored_cells: Vec<GridCoord>,
        topology_version: u64,
    ) -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors: vec![sample_actor(ActorId(1))],
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: Some(MapId("map_a".into())),
                map_width: Some(2),
                map_height: Some(1),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version,
                runtime_obstacle_version: 0,
            },
            vision: VisionRuntimeSnapshot {
                actors: vec![ActorVisionSnapshot {
                    actor_id: ActorId(1),
                    radius: 10,
                    active_map_id: Some(MapId("map_a".into())),
                    visible_cells,
                    explored_maps: vec![ActorVisionMapSnapshot {
                        map_id: MapId("map_a".into()),
                        explored_cells,
                    }],
                }],
            },
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        }
    }

    fn sample_actor(actor_id: ActorId) -> ActorDebugState {
        ActorDebugState {
            actor_id,
            definition_id: Some(CharacterId("viewer_test_actor".into())),
            display_name: "viewer_test_actor".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Player,
            group_id: "player".into(),
            ap: 6.0,
            available_steps: 3,
            turn_open: false,
            in_combat: false,
            grid_position: GridCoord::new(0, 0, 0),
            level: 1,
            current_xp: 0,
            available_stat_points: 0,
            available_skill_points: 0,
            hp: 10.0,
            max_hp: 10.0,
        }
    }
}
