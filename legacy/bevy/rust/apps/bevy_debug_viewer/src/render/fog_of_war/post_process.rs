//! 战争迷雾后处理：负责屏幕空间后处理节点、渲染管线以及相机同步。

use super::*;
use bevy::core_pipeline::{
    core_3d::graph::{Core3d, Node3d},
    prepass::ViewPrepassTextures,
    FullscreenShader,
};
use bevy::ecs::query::QueryItem;
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
