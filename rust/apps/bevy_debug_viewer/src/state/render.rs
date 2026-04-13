//! 渲染状态：定义相机、颜色主题、动作插值、战斗反馈和渲染相关标记组件。

use std::collections::HashMap;

use bevy::prelude::*;
use game_data::{ActorId, InteractionTargetId, WorldCoord};

use super::runtime::ViewerOverlayMode;

#[derive(Resource, Debug, Default)]
pub(crate) struct ActorLabelEntities {
    pub by_actor: HashMap<ActorId, Entity>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct ActorMotionTrack {
    pub from_world: WorldCoord,
    pub to_world: WorldCoord,
    pub current_world: WorldCoord,
    pub elapsed_sec: f32,
    pub duration_sec: f32,
    pub level: i32,
    pub active: bool,
}

impl ActorMotionTrack {
    pub(crate) fn new(
        from_world: WorldCoord,
        to_world: WorldCoord,
        level: i32,
        duration_sec: f32,
    ) -> Self {
        Self {
            from_world,
            to_world,
            current_world: from_world,
            elapsed_sec: 0.0,
            duration_sec,
            level,
            active: true,
        }
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        if !self.active {
            return;
        }

        self.elapsed_sec = (self.elapsed_sec + delta_sec).min(self.duration_sec.max(0.0));
        let progress = if self.duration_sec <= f32::EPSILON {
            1.0
        } else {
            (self.elapsed_sec / self.duration_sec).clamp(0.0, 1.0)
        };
        self.current_world = lerp_world_coord(self.from_world, self.to_world, progress);
        if progress >= 1.0 {
            self.current_world = self.to_world;
            self.active = false;
        }
    }

    pub(crate) fn snap_to(&mut self, world: WorldCoord, level: i32) {
        self.from_world = world;
        self.to_world = world;
        self.current_world = world;
        self.elapsed_sec = 0.0;
        self.level = level;
        self.active = false;
    }
}

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerActorMotionState {
    pub tracks: HashMap<ActorId, ActorMotionTrack>,
}

impl ViewerActorMotionState {
    pub(crate) fn current_world(&self, actor_id: ActorId) -> Option<WorldCoord> {
        self.tracks.get(&actor_id).map(|track| track.current_world)
    }

    pub(crate) fn track_movement(
        &mut self,
        actor_id: ActorId,
        from_world: WorldCoord,
        to_world: WorldCoord,
        level: i32,
        duration_sec: f32,
    ) {
        self.tracks.insert(
            actor_id,
            ActorMotionTrack::new(from_world, to_world, level, duration_sec),
        );
    }
}

const ATTACK_LUNGE_DISTANCE_RATIO: f32 = 0.35;
const ATTACK_LUNGE_MIN_DISTANCE: f32 = 0.35;
const ATTACK_LUNGE_MAX_DISTANCE: f32 = 0.75;
const ATTACK_LUNGE_FORWARD_DURATION_SEC: f32 = 0.08;
const ATTACK_LUNGE_RETURN_DURATION_SEC: f32 = 0.12;

const HIT_REACTION_SHAKE_OFFSETS: [Vec3; 4] = [
    Vec3::new(-0.10, 0.0, 0.06),
    Vec3::new(0.09, 0.0, -0.05),
    Vec3::new(-0.05, 0.0, -0.04),
    Vec3::new(0.04, 0.0, 0.03),
];
const HIT_REACTION_SHAKE_STEP_DURATION_SEC: f32 = 0.03;
const HIT_REACTION_RETURN_DURATION_SEC: f32 = 0.05;
const DAMAGE_NUMBER_DURATION_SEC: f32 = 0.6;
const DAMAGE_NUMBER_BASE_UPWARD_OFFSET: Vec3 = Vec3::new(0.0, 0.9, 0.0);
const DAMAGE_NUMBER_END_UPWARD_OFFSET: f32 = 0.65;
const CAMERA_SHAKE_DEFAULT_DURATION_SEC: f32 = 0.2;
const CAMERA_SHAKE_DEFAULT_AMPLITUDE: f32 = 0.1;
const CAMERA_SHAKE_DEFAULT_FREQUENCY: f32 = 1.2;

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct AttackLungeTrack {
    direction: Vec3,
    distance: f32,
    elapsed_sec: f32,
}

impl AttackLungeTrack {
    pub(crate) fn new(attacker_world: WorldCoord, target_world: WorldCoord) -> Option<Self> {
        let horizontal = Vec3::new(
            target_world.x - attacker_world.x,
            0.0,
            target_world.z - attacker_world.z,
        );
        let horizontal_distance = horizontal.length();
        if horizontal_distance <= 0.0001 {
            return None;
        }

        Some(Self {
            direction: horizontal / horizontal_distance,
            distance: (horizontal_distance * ATTACK_LUNGE_DISTANCE_RATIO)
                .clamp(ATTACK_LUNGE_MIN_DISTANCE, ATTACK_LUNGE_MAX_DISTANCE),
            elapsed_sec: 0.0,
        })
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        self.elapsed_sec = (self.elapsed_sec + delta_sec)
            .min(ATTACK_LUNGE_FORWARD_DURATION_SEC + ATTACK_LUNGE_RETURN_DURATION_SEC);
    }

    pub(crate) fn is_active(self) -> bool {
        self.elapsed_sec < ATTACK_LUNGE_FORWARD_DURATION_SEC + ATTACK_LUNGE_RETURN_DURATION_SEC
    }

    pub(crate) fn current_offset(self) -> Vec3 {
        if !self.is_active() {
            return Vec3::ZERO;
        }

        let peak_offset = self.direction * self.distance;
        if self.elapsed_sec <= ATTACK_LUNGE_FORWARD_DURATION_SEC {
            let progress = (self.elapsed_sec / ATTACK_LUNGE_FORWARD_DURATION_SEC.max(f32::EPSILON))
                .clamp(0.0, 1.0);
            return peak_offset * progress;
        }

        let return_elapsed = (self.elapsed_sec - ATTACK_LUNGE_FORWARD_DURATION_SEC).max(0.0);
        let progress = 1.0
            - (return_elapsed / ATTACK_LUNGE_RETURN_DURATION_SEC.max(f32::EPSILON)).clamp(0.0, 1.0);
        peak_offset * progress
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct HitReactionTrack {
    elapsed_sec: f32,
}

impl HitReactionTrack {
    pub(crate) fn new() -> Self {
        Self { elapsed_sec: 0.0 }
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        self.elapsed_sec = (self.elapsed_sec + delta_sec).min(self.total_duration_sec());
    }

    pub(crate) fn is_active(self) -> bool {
        self.elapsed_sec < self.total_duration_sec()
    }

    pub(crate) fn current_offset(self) -> Vec3 {
        let mut segment_start = 0.0;
        let mut from = Vec3::ZERO;
        for (index, to) in HIT_REACTION_SHAKE_OFFSETS
            .iter()
            .copied()
            .chain(std::iter::once(Vec3::ZERO))
            .enumerate()
        {
            let duration = if index < HIT_REACTION_SHAKE_OFFSETS.len() {
                HIT_REACTION_SHAKE_STEP_DURATION_SEC
            } else {
                HIT_REACTION_RETURN_DURATION_SEC
            };
            let segment_end = segment_start + duration;
            if self.elapsed_sec <= segment_end {
                let progress = ((self.elapsed_sec - segment_start) / duration.max(f32::EPSILON))
                    .clamp(0.0, 1.0);
                return from.lerp(to, progress);
            }
            segment_start = segment_end;
            from = to;
        }

        Vec3::ZERO
    }

    fn total_duration_sec(self) -> f32 {
        HIT_REACTION_SHAKE_OFFSETS.len() as f32 * HIT_REACTION_SHAKE_STEP_DURATION_SEC
            + HIT_REACTION_RETURN_DURATION_SEC
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub(crate) struct ActorCombatFeedbackTracks {
    pub attack_lunge: Option<AttackLungeTrack>,
    pub hit_reaction: Option<HitReactionTrack>,
}

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerActorFeedbackState {
    pub tracks: HashMap<ActorId, ActorCombatFeedbackTracks>,
}

impl ViewerActorFeedbackState {
    pub(crate) fn visual_offset(&self, actor_id: ActorId) -> Vec3 {
        self.tracks
            .get(&actor_id)
            .map(|tracks| {
                tracks
                    .attack_lunge
                    .map(|track| track.current_offset())
                    .unwrap_or(Vec3::ZERO)
                    + tracks
                        .hit_reaction
                        .map(|track| track.current_offset())
                        .unwrap_or(Vec3::ZERO)
            })
            .unwrap_or(Vec3::ZERO)
    }

    pub(crate) fn queue_attack_lunge(
        &mut self,
        actor_id: ActorId,
        attacker_world: WorldCoord,
        target_world: WorldCoord,
    ) {
        let Some(track) = AttackLungeTrack::new(attacker_world, target_world) else {
            return;
        };
        self.tracks.entry(actor_id).or_default().attack_lunge = Some(track);
    }

    pub(crate) fn queue_hit_reaction(&mut self, actor_id: ActorId) {
        self.tracks.entry(actor_id).or_default().hit_reaction = Some(HitReactionTrack::new());
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        let tracked_actor_ids: Vec<_> = self.tracks.keys().copied().collect();
        for actor_id in tracked_actor_ids {
            let Some(tracks) = self.tracks.get_mut(&actor_id) else {
                continue;
            };

            if let Some(track) = &mut tracks.attack_lunge {
                track.advance(delta_sec);
                if !track.is_active() {
                    tracks.attack_lunge = None;
                }
            }

            if let Some(track) = &mut tracks.hit_reaction {
                track.advance(delta_sec);
                if !track.is_active() {
                    tracks.hit_reaction = None;
                }
            }

            if tracks.attack_lunge.is_none() && tracks.hit_reaction.is_none() {
                self.tracks.remove(&actor_id);
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct DamageNumberTrack {
    pub world_origin: Vec3,
    pub world_drift: Vec3,
    pub amount: i32,
    pub is_critical: bool,
    pub elapsed_sec: f32,
    pub duration_sec: f32,
    pub start_font_size: f32,
    pub end_font_size: f32,
}

impl DamageNumberTrack {
    pub(crate) fn new(id: u64, world: WorldCoord, amount: i32, is_critical: bool) -> Self {
        let random_x = pseudo_random_range(id.wrapping_mul(17), -0.12, 0.12);
        let random_y = pseudo_random_range(id.wrapping_mul(29), -0.03, 0.06);
        let random_z = pseudo_random_range(id.wrapping_mul(41), -0.08, 0.08);
        let drift_x = pseudo_random_range(id.wrapping_mul(53), -0.08, 0.08);
        let drift_z = pseudo_random_range(id.wrapping_mul(67), -0.06, 0.06);
        Self {
            world_origin: Vec3::new(world.x, world.y, world.z)
                + DAMAGE_NUMBER_BASE_UPWARD_OFFSET
                + Vec3::new(random_x, random_y, random_z),
            world_drift: Vec3::new(drift_x, DAMAGE_NUMBER_END_UPWARD_OFFSET, drift_z),
            amount,
            is_critical,
            elapsed_sec: 0.0,
            duration_sec: DAMAGE_NUMBER_DURATION_SEC,
            start_font_size: if is_critical { 56.0 } else { 44.0 },
            end_font_size: if is_critical { 70.0 } else { 48.0 },
        }
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        self.elapsed_sec = (self.elapsed_sec + delta_sec).min(self.duration_sec);
    }

    pub(crate) fn is_active(self) -> bool {
        self.elapsed_sec < self.duration_sec
    }

    pub(crate) fn current_world_position(self) -> Vec3 {
        self.world_origin + self.world_drift * self.progress()
    }

    pub(crate) fn current_alpha(self) -> f32 {
        1.0 - self.progress()
    }

    pub(crate) fn current_font_size(self) -> f32 {
        self.start_font_size + (self.end_font_size - self.start_font_size) * self.progress()
    }

    pub(crate) fn text(self) -> String {
        if self.is_critical {
            format!("!{}", self.amount)
        } else {
            self.amount.to_string()
        }
    }

    pub(crate) fn color(self) -> Color {
        if self.is_critical {
            Color::srgba(1.0, 0.45, 0.2, self.current_alpha())
        } else {
            Color::srgba(1.0, 0.95, 0.65, self.current_alpha())
        }
    }

    fn progress(self) -> f32 {
        (self.elapsed_sec / self.duration_sec.max(f32::EPSILON)).clamp(0.0, 1.0)
    }
}

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerDamageNumberState {
    next_id: u64,
    pub entries: HashMap<u64, DamageNumberTrack>,
}

impl ViewerDamageNumberState {
    pub(crate) fn queue_damage_number(
        &mut self,
        world: WorldCoord,
        amount: i32,
        is_critical: bool,
    ) -> u64 {
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1);
        self.entries
            .insert(id, DamageNumberTrack::new(id, world, amount, is_critical));
        id
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        let ids: Vec<_> = self.entries.keys().copied().collect();
        for id in ids {
            let Some(entry) = self.entries.get_mut(&id) else {
                continue;
            };
            entry.advance(delta_sec);
            if !entry.is_active() {
                self.entries.remove(&id);
            }
        }
    }
}

#[derive(Resource, Debug, Clone, Copy, Default)]
pub(crate) struct ViewerCameraShakeState {
    pub time_remaining_sec: f32,
    pub duration_sec: f32,
    pub amplitude: f32,
    pub frequency: f32,
    pub elapsed_sec: f32,
}

impl ViewerCameraShakeState {
    pub(crate) fn trigger_default_damage_shake(&mut self) {
        self.trigger(
            CAMERA_SHAKE_DEFAULT_DURATION_SEC,
            CAMERA_SHAKE_DEFAULT_AMPLITUDE,
            CAMERA_SHAKE_DEFAULT_FREQUENCY,
        );
    }

    pub(crate) fn trigger(&mut self, duration_sec: f32, amplitude: f32, frequency: f32) {
        if duration_sec <= 0.0 || amplitude <= 0.0 {
            return;
        }
        self.time_remaining_sec = duration_sec;
        self.duration_sec = duration_sec;
        self.amplitude = self.amplitude.max(amplitude);
        self.frequency = self.frequency.max(frequency);
        self.elapsed_sec = 0.0;
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        if self.time_remaining_sec <= 0.0 {
            self.time_remaining_sec = 0.0;
            self.amplitude = 0.0;
            self.frequency = 1.0;
            return;
        }

        self.time_remaining_sec = (self.time_remaining_sec - delta_sec).max(0.0);
        self.elapsed_sec += delta_sec;
        if self.time_remaining_sec <= 0.0 {
            self.amplitude = 0.0;
            self.frequency = 1.0;
        }
    }

    pub(crate) fn current_offset(self) -> Vec3 {
        if self.time_remaining_sec <= 0.0 || self.amplitude <= 0.0 {
            return Vec3::ZERO;
        }

        let progress = if self.duration_sec > 0.0 {
            self.time_remaining_sec / self.duration_sec
        } else {
            1.0
        };
        let intensity = self.amplitude * progress;
        let t = self.elapsed_sec * self.frequency.max(0.01) * std::f32::consts::TAU;
        Vec3::new(
            (t * 2.7).sin() * intensity,
            (t * 3.9).cos() * intensity * 0.65,
            (t * 1.9).sin() * intensity * 0.35,
        )
    }
}

#[derive(Resource, Debug, Clone, Copy)]
pub(crate) struct ViewerCameraFollowState {
    pub smoothed_focus: Vec3,
    pub initialized: bool,
    pub last_actor_id: Option<ActorId>,
    pub last_level: i32,
}

impl Default for ViewerCameraFollowState {
    fn default() -> Self {
        Self {
            smoothed_focus: Vec3::ZERO,
            initialized: false,
            last_actor_id: None,
            last_level: 0,
        }
    }
}

impl ViewerCameraFollowState {
    pub(crate) fn reset(&mut self, focus: Vec3, actor_id: Option<ActorId>, level: i32) {
        self.smoothed_focus = focus;
        self.initialized = true;
        self.last_actor_id = actor_id;
        self.last_level = level;
    }
}

fn pseudo_random_range(seed: u64, min: f32, max: f32) -> f32 {
    let hashed = seed
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407);
    let normalized = ((hashed >> 40) as f32) / ((1_u64 << 24) as f32);
    min + (max - min) * normalized.clamp(0.0, 1.0)
}

fn lerp_world_coord(start: WorldCoord, end: WorldCoord, t: f32) -> WorldCoord {
    WorldCoord::new(
        start.x + (end.x - start.x) * t,
        start.y + (end.y - start.y) * t,
        start.z + (end.z - start.z) * t,
    )
}

#[derive(Resource, Debug, Clone, Copy)]
pub(crate) struct ViewerPalette {
    pub clear_color: Color,
    pub ambient_color: Color,
    pub key_light_color: Color,
    pub fill_light_color: Color,
    pub hud_text_secondary: Color,
    pub menu_background: Color,
    pub dialogue_background: Color,
    pub label_background: Color,
    pub ground_dark: Color,
    pub ground_light: Color,
    pub ground_edge: Color,
    pub building_base: Color,
    pub building_top: Color,
    pub pickup: Color,
    pub interactive: Color,
    pub trigger: Color,
    pub player: Color,
    pub friendly: Color,
    pub hostile: Color,
    pub neutral: Color,
    pub selection: Color,
    pub current_turn: Color,
    pub interaction_locked: Color,
    pub path: Color,
    pub hover_walkable: Color,
    pub hover_hostile: Color,
    pub ai_goal: Color,
    pub ai_anchor: Color,
    pub ai_reservation: Color,
}

impl Default for ViewerPalette {
    fn default() -> Self {
        Self {
            clear_color: Color::srgb(0.082, 0.09, 0.102),
            ambient_color: Color::srgb(0.72, 0.76, 0.82),
            key_light_color: Color::srgb(0.99, 0.94, 0.87),
            fill_light_color: Color::srgb(0.52, 0.62, 0.72),
            hud_text_secondary: Color::srgba(0.72, 0.71, 0.68, 0.94),
            menu_background: Color::srgba(0.055, 0.055, 0.052, 0.96),
            dialogue_background: Color::srgba(0.05, 0.05, 0.048, 0.95),
            label_background: Color::srgba(0.05, 0.05, 0.048, 0.8),
            ground_dark: Color::srgb(0.17, 0.18, 0.17),
            ground_light: Color::srgb(0.24, 0.235, 0.212),
            ground_edge: Color::srgb(0.115, 0.12, 0.118),
            building_base: Color::srgb(0.74, 0.755, 0.77),
            building_top: Color::srgb(0.84, 0.845, 0.85),
            pickup: Color::srgb(0.42, 0.82, 0.62),
            interactive: Color::srgb(0.35, 0.61, 0.9),
            trigger: Color::srgb(0.96, 0.72, 0.29),
            player: Color::srgb(0.25, 0.67, 0.96),
            friendly: Color::srgb(0.36, 0.79, 0.46),
            hostile: Color::srgb(0.9, 0.37, 0.32),
            neutral: Color::srgb(0.7, 0.72, 0.76),
            selection: Color::srgb(0.98, 0.94, 0.72),
            current_turn: Color::srgb(0.49, 0.89, 0.95),
            interaction_locked: Color::srgb(0.98, 0.83, 0.33),
            path: Color::srgb(0.95, 0.76, 0.28),
            hover_walkable: Color::srgb(0.96, 0.97, 0.99),
            hover_hostile: Color::srgb(0.94, 0.36, 0.33),
            ai_goal: Color::srgb(0.98, 0.71, 0.29),
            ai_anchor: Color::srgb(0.22, 0.84, 0.8),
            ai_reservation: Color::srgb(0.62, 0.48, 0.92),
        }
    }
}

#[derive(Resource, Debug, Clone, Copy)]
pub(crate) struct ViewerStyleProfile {
    pub ambient_brightness: f32,
    pub key_light_illuminance: f32,
    pub fill_light_illuminance: f32,
    pub selection_pulse_speed: f32,
    pub selection_pulse_amount: f32,
}

impl Default for ViewerStyleProfile {
    fn default() -> Self {
        Self {
            ambient_brightness: 42.0,
            key_light_illuminance: 12_500.0,
            fill_light_illuminance: 2_400.0,
            selection_pulse_speed: 3.4,
            selection_pulse_amount: 0.08,
        }
    }
}

#[derive(Resource, Debug, Clone, Copy)]
pub(crate) struct ViewerRenderConfig {
    pub zoom_factor: f32,
    pub viewport_padding_px: f32,
    pub hud_reserved_width_px: f32,
    pub camera_yaw_degrees: f32,
    pub camera_pitch_degrees: f32,
    pub camera_fov_degrees: f32,
    pub camera_distance_padding_world: f32,
    pub floor_thickness_world: f32,
    pub actor_radius_world: f32,
    pub actor_body_length_world: f32,
    pub actor_label_height_world: f32,
    pub label_screen_offset_px: Vec2,
    pub grid_line_opacity: f32,
    pub shadow_opacity_scale: f32,
    pub overlay_mode: ViewerOverlayMode,
    pub ground_variation_strength: f32,
    pub object_style_seed: u32,
    pub fow_fog_color: Color,
    pub fow_explored_alpha: f32,
    pub fow_unexplored_alpha: f32,
    pub fow_edge_softness: f32,
    pub fow_transition_duration_sec: f32,
}

impl Default for ViewerRenderConfig {
    fn default() -> Self {
        Self {
            zoom_factor: 1.0,
            viewport_padding_px: 72.0,
            hud_reserved_width_px: 620.0,
            camera_yaw_degrees: 0.0,
            camera_pitch_degrees: 36.0,
            camera_fov_degrees: 30.0,
            camera_distance_padding_world: 8.0,
            floor_thickness_world: 0.11,
            actor_radius_world: 0.22,
            actor_body_length_world: 0.52,
            actor_label_height_world: 1.3,
            label_screen_offset_px: Vec2::new(-26.0, -14.0),
            grid_line_opacity: 0.18,
            shadow_opacity_scale: 0.52,
            overlay_mode: ViewerOverlayMode::Gameplay,
            ground_variation_strength: 0.32,
            object_style_seed: 17,
            fow_fog_color: Color::srgba(0.05, 0.05, 0.05, 1.0),
            fow_explored_alpha: 0.55,
            fow_unexplored_alpha: 0.85,
            fow_edge_softness: 0.0075,
            fow_transition_duration_sec: 0.2,
        }
    }
}

impl ViewerRenderConfig {
    pub(crate) fn camera_yaw_radians(self) -> f32 {
        self.camera_yaw_degrees.to_radians()
    }

    pub(crate) fn camera_pitch_radians(self) -> f32 {
        self.camera_pitch_degrees.to_radians()
    }

    pub(crate) fn camera_fov_radians(self) -> f32 {
        self.camera_fov_degrees.to_radians()
    }

    pub(crate) fn vertical_projection_factor(self) -> f32 {
        self.camera_pitch_radians().sin().max(0.1)
    }
}

#[derive(Component)]
pub(crate) struct ViewerCamera;

#[derive(Component)]
pub(crate) struct InteractionMenuRoot;

#[derive(Component)]
pub(crate) struct DialoguePanelRoot;

#[derive(Component)]
pub(crate) struct InteractionMenuOptionsRoot;

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InteractionMenuOptionRow {
    pub index: usize,
}

#[derive(Component)]
pub(crate) struct DialoguePanelTitleLabel;

#[derive(Component)]
pub(crate) struct DialoguePanelSpeakerLabel;

#[derive(Component)]
pub(crate) struct DialoguePanelBodyLabel;

#[derive(Component)]
pub(crate) struct DialoguePanelChoicesRoot;

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DialogueChoiceRow {
    pub index: usize,
}

#[derive(Component)]
pub(crate) struct DialoguePanelHintLabel;

#[derive(Component, Debug, Clone)]
pub(crate) struct InteractionMenuButton {
    pub target_id: InteractionTargetId,
    pub option_id: game_data::InteractionOptionId,
    pub is_primary: bool,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DialogueChoiceButton {
    pub choice_index: usize,
}

#[derive(Component)]
pub(crate) struct InteractionLockedActorTag;

#[derive(Component)]
pub(crate) struct ActorLabel {
    pub actor_id: ActorId,
}
