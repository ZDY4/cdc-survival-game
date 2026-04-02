// Viewer 运行时状态定义：集中声明 viewer 资源、交互状态、场景状态和共享数据结构。

use std::collections::{BTreeMap, BTreeSet, HashMap};

use bevy::prelude::*;
use game_bevy::{SettlementDebugSnapshot, UiInventoryFilter, UiMenuPanel};
use game_core::SimulationRuntime;
use game_core::SimulationSnapshot;
use game_data::{
    ActorId, ActorSide, DialogueData, GridCoord, InteractionPrompt, InteractionTargetId,
    SkillTargetRequest, WorldCoord,
};
use serde::{Deserialize, Serialize};

pub(crate) const VIEWER_FONT_PATH: &str = "fonts/NotoSansCJKsc-Regular.otf";

#[derive(Resource, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerSceneKind {
    #[default]
    MainMenu,
    Gameplay,
}

impl ViewerSceneKind {
    pub(crate) fn is_main_menu(self) -> bool {
        matches!(self, Self::MainMenu)
    }

    pub(crate) fn is_gameplay(self) -> bool {
        matches!(self, Self::Gameplay)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerOverlayMode {
    Minimal,
    #[default]
    Gameplay,
    AiDebug,
}

impl ViewerOverlayMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Minimal => "Minimal",
            Self::Gameplay => "Gameplay",
            Self::AiDebug => "AI Debug",
        }
    }

    pub(crate) fn next(self) -> Self {
        match self {
            Self::Minimal => Self::Gameplay,
            Self::Gameplay => Self::AiDebug,
            Self::AiDebug => Self::Minimal,
        }
    }
}

#[derive(Resource, Debug)]
pub(crate) struct ViewerRuntimeState {
    pub runtime: SimulationRuntime,
    pub recent_events: Vec<ViewerEventEntry>,
    pub ai_snapshot: SettlementDebugSnapshot,
}

#[derive(Resource, Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ViewerUiSettings {
    pub master_volume: f32,
    pub music_volume: f32,
    pub sfx_volume: f32,
    pub window_mode: String,
    pub vsync: bool,
    pub ui_scale: f32,
    pub action_bindings: BTreeMap<String, String>,
}

impl Default for ViewerUiSettings {
    fn default() -> Self {
        Self {
            master_volume: 1.0,
            music_volume: 1.0,
            sfx_volume: 1.0,
            window_mode: "windowed".to_string(),
            vsync: true,
            ui_scale: 1.0,
            action_bindings: BTreeMap::from([
                ("menu_inventory".to_string(), "KeyI".to_string()),
                ("menu_character".to_string(), "KeyC".to_string()),
                ("menu_map".to_string(), "KeyM".to_string()),
                ("menu_journal".to_string(), "KeyJ".to_string()),
                ("menu_skills".to_string(), "KeyK".to_string()),
                ("menu_crafting".to_string(), "KeyL".to_string()),
                ("menu_settings".to_string(), "Escape".to_string()),
            ]),
        }
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ViewerUiSettingsPath(pub std::path::PathBuf);

impl Default for ViewerUiSettingsPath {
    fn default() -> Self {
        Self(
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../../config/bevy_viewer_ui_settings.json"),
        )
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ViewerRuntimeSavePath(pub std::path::PathBuf);

impl Default for ViewerRuntimeSavePath {
    fn default() -> Self {
        Self(
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../../saves/bevy_viewer_latest.json"),
        )
    }
}

#[derive(Resource, Clone)]
pub(crate) struct ViewerUiFont(pub Handle<Font>);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerHudPage {
    #[default]
    Overview,
    Selection,
    SelectedActor,
    World,
    Interaction,
    TurnSys,
    Events,
    Ai,
    Performance,
}

impl ViewerHudPage {
    pub(crate) const ALL: [Self; 9] = [
        Self::Overview,
        Self::Selection,
        Self::SelectedActor,
        Self::World,
        Self::Interaction,
        Self::TurnSys,
        Self::Events,
        Self::Ai,
        Self::Performance,
    ];

    pub(crate) fn title(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::Selection => "Selection",
            Self::SelectedActor => "Selected Actor",
            Self::World => "World",
            Self::Interaction => "Interaction",
            Self::TurnSys => "Turn System",
            Self::Events => "Events",
            Self::Ai => "AI",
            Self::Performance => "Performance",
        }
    }

    pub(crate) fn tab_label(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::Selection => "Select",
            Self::SelectedActor => "Actor",
            Self::World => "World",
            Self::Interaction => "Interact",
            Self::TurnSys => "Turn",
            Self::Events => "Events",
            Self::Ai => "AI",
            Self::Performance => "Perf",
        }
    }

    pub(crate) fn console_name(self) -> &'static str {
        match self {
            Self::Overview => "overview",
            Self::Selection => "selection",
            Self::SelectedActor => "actor",
            Self::World => "world",
            Self::Interaction => "interaction",
            Self::TurnSys => "turn_sys",
            Self::Events => "events",
            Self::Ai => "ai",
            Self::Performance => "performance",
        }
    }

    pub(crate) fn from_console_name(name: &str) -> Option<Self> {
        match name {
            "overview" => Some(Self::Overview),
            "selection" => Some(Self::Selection),
            "actor" => Some(Self::SelectedActor),
            "world" => Some(Self::World),
            "interaction" => Some(Self::Interaction),
            "turn_sys" => Some(Self::TurnSys),
            "events" => Some(Self::Events),
            "ai" => Some(Self::Ai),
            "performance" => Some(Self::Performance),
            _ => None,
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct ViewerInfoPanelState {
    pub enabled_pages: Vec<ViewerHudPage>,
    pub active_page: Option<ViewerHudPage>,
}

impl ViewerInfoPanelState {
    pub(crate) fn is_empty(&self) -> bool {
        self.enabled_pages.is_empty() || self.active_page.is_none()
    }

    pub(crate) fn active_page(&self) -> Option<ViewerHudPage> {
        self.active_page
    }

    pub(crate) fn enabled_pages(&self) -> &[ViewerHudPage] {
        &self.enabled_pages
    }

    pub(crate) fn is_enabled(&self, page: ViewerHudPage) -> bool {
        self.enabled_pages.contains(&page)
    }

    pub(crate) fn set_active(&mut self, page: ViewerHudPage) -> bool {
        if self.is_enabled(page) {
            self.active_page = Some(page);
            true
        } else {
            false
        }
    }

    pub(crate) fn toggle(&mut self, page: ViewerHudPage) -> bool {
        if self.is_enabled(page) {
            self.disable(page);
            false
        } else {
            self.enable(page);
            true
        }
    }

    pub(crate) fn cycle_next(&mut self) -> Option<ViewerHudPage> {
        let active = self.active_page?;
        let current_index = self.enabled_pages.iter().position(|page| *page == active)?;
        let next_index = (current_index + 1) % self.enabled_pages.len();
        let next = self.enabled_pages[next_index];
        self.active_page = Some(next);
        Some(next)
    }

    pub(crate) fn cycle_previous(&mut self) -> Option<ViewerHudPage> {
        let active = self.active_page?;
        let current_index = self.enabled_pages.iter().position(|page| *page == active)?;
        let previous_index = if current_index == 0 {
            self.enabled_pages.len().saturating_sub(1)
        } else {
            current_index - 1
        };
        let previous = self.enabled_pages[previous_index];
        self.active_page = Some(previous);
        Some(previous)
    }

    fn enable(&mut self, page: ViewerHudPage) {
        self.enabled_pages.push(page);
        self.enabled_pages.sort_by_key(|enabled| {
            ViewerHudPage::ALL
                .iter()
                .position(|candidate| candidate == enabled)
                .unwrap_or(usize::MAX)
        });
        self.active_page = Some(page);
    }

    fn disable(&mut self, page: ViewerHudPage) {
        let removed_index = self
            .enabled_pages
            .iter()
            .position(|enabled| *enabled == page);
        self.enabled_pages.retain(|enabled| *enabled != page);

        if self.enabled_pages.is_empty() {
            self.active_page = None;
            return;
        }

        if self.active_page == Some(page) {
            let next_index = removed_index
                .map(|index| index.min(self.enabled_pages.len().saturating_sub(1)))
                .unwrap_or(0);
            self.active_page = self.enabled_pages.get(next_index).copied();
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerControlMode {
    #[default]
    PlayerControl,
    FreeObserve,
}

impl ViewerControlMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::PlayerControl => "Player Control",
            Self::FreeObserve => "Free Observe",
        }
    }

    pub(crate) fn toggle(self) -> Self {
        match self {
            Self::PlayerControl => Self::FreeObserve,
            Self::FreeObserve => Self::PlayerControl,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerCameraMode {
    #[default]
    FollowSelectedActor,
    ManualPan,
}

impl ViewerCameraMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::FollowSelectedActor => "Follow Selected Actor",
            Self::ManualPan => "Manual Pan",
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum HudEventFilter {
    #[default]
    All,
    Combat,
    Interaction,
    World,
}

#[allow(dead_code)]
impl HudEventFilter {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::All => "All",
            Self::Combat => "Combat",
            Self::Interaction => "Interaction",
            Self::World => "World",
        }
    }

    pub(crate) fn previous(self) -> Self {
        match self {
            Self::All => Self::World,
            Self::Combat => Self::All,
            Self::Interaction => Self::Combat,
            Self::World => Self::Interaction,
        }
    }

    pub(crate) fn next(self) -> Self {
        match self {
            Self::All => Self::Combat,
            Self::Combat => Self::Interaction,
            Self::Interaction => Self::World,
            Self::World => Self::All,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HudEventCategory {
    Combat,
    Interaction,
    World,
}

impl HudEventCategory {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Combat => "Combat",
            Self::Interaction => "Interaction",
            Self::World => "World",
        }
    }
}

#[derive(Debug, Clone)]
pub(crate) struct ViewerEventEntry {
    pub category: HudEventCategory,
    pub turn_index: u64,
    pub text: String,
}

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
    pub ai_spawn: Color,
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
            hud_text_secondary: Color::srgba(0.78, 0.81, 0.87, 0.94),
            menu_background: Color::srgba(0.055, 0.065, 0.08, 0.96),
            dialogue_background: Color::srgba(0.05, 0.058, 0.074, 0.95),
            label_background: Color::srgba(0.05, 0.06, 0.075, 0.8),
            ground_dark: Color::srgb(0.17, 0.18, 0.17),
            ground_light: Color::srgb(0.24, 0.235, 0.212),
            ground_edge: Color::srgb(0.115, 0.12, 0.118),
            building_base: Color::srgb(0.74, 0.755, 0.77),
            building_top: Color::srgb(0.84, 0.845, 0.85),
            pickup: Color::srgb(0.42, 0.82, 0.62),
            interactive: Color::srgb(0.35, 0.61, 0.9),
            trigger: Color::srgb(0.96, 0.72, 0.29),
            ai_spawn: Color::srgb(0.86, 0.35, 0.4),
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

#[derive(Resource, Debug)]
pub(crate) struct ViewerState {
    pub selected_actor: Option<ActorId>,
    pub controlled_player_actor: Option<ActorId>,
    pub focused_target: Option<InteractionTargetId>,
    pub current_prompt: Option<InteractionPrompt>,
    pub interaction_menu: Option<InteractionMenuState>,
    pub active_dialogue: Option<ActiveDialogueState>,
    pub control_mode: ViewerControlMode,
    pub camera_mode: ViewerCameraMode,
    pub event_filter: HudEventFilter,
    pub show_fps_overlay: bool,
    pub show_controls: bool,
    pub hovered_grid: Option<GridCoord>,
    pub targeting_state: Option<ViewerTargetingState>,
    pub current_level: i32,
    pub auto_tick: bool,
    pub end_turn_repeat_delay_sec: f32,
    pub end_turn_repeat_interval_sec: f32,
    pub end_turn_hold_sec: f32,
    pub end_turn_repeat_elapsed_sec: f32,
    pub auto_end_turn_after_stop: bool,
    pub min_progression_interval_sec: f32,
    pub progression_elapsed_sec: f32,
    pub camera_pan_offset: Vec2,
    pub camera_drag_cursor: Option<Vec2>,
    pub camera_drag_anchor_world: Option<Vec2>,
    pub pending_open_trade_target: Option<InteractionTargetId>,
    pub status_line: String,
}

impl Default for ViewerState {
    fn default() -> Self {
        Self {
            selected_actor: None,
            controlled_player_actor: None,
            focused_target: None,
            current_prompt: None,
            interaction_menu: None,
            active_dialogue: None,
            control_mode: ViewerControlMode::PlayerControl,
            camera_mode: ViewerCameraMode::FollowSelectedActor,
            event_filter: HudEventFilter::All,
            show_fps_overlay: false,
            show_controls: false,
            hovered_grid: None,
            targeting_state: None,
            current_level: 0,
            auto_tick: false,
            end_turn_repeat_delay_sec: 0.2,
            end_turn_repeat_interval_sec: 0.1,
            end_turn_hold_sec: 0.0,
            end_turn_repeat_elapsed_sec: 0.0,
            auto_end_turn_after_stop: false,
            min_progression_interval_sec: 0.1,
            progression_elapsed_sec: 0.0,
            camera_pan_offset: Vec2::ZERO,
            camera_drag_cursor: None,
            camera_drag_anchor_world: None,
            pending_open_trade_target: None,
            status_line: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ViewerTargetingAction {
    Attack,
    Skill {
        skill_id: String,
        skill_name: String,
    },
}

impl ViewerTargetingAction {
    pub(crate) fn label(&self) -> &str {
        match self {
            Self::Attack => "普通攻击",
            Self::Skill { skill_name, .. } => skill_name.as_str(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ViewerTargetingSource {
    AttackButton,
    HotbarSlot(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ViewerTargetingState {
    pub actor_id: ActorId,
    pub action: ViewerTargetingAction,
    pub source: ViewerTargetingSource,
    pub shape: String,
    pub radius: i32,
    pub valid_grids: BTreeSet<GridCoord>,
    pub valid_actor_ids: BTreeSet<ActorId>,
    pub hovered_grid: Option<GridCoord>,
    pub preview_target: Option<SkillTargetRequest>,
    pub preview_hit_grids: Vec<GridCoord>,
    pub preview_hit_actor_ids: Vec<ActorId>,
    pub prompt_text: String,
}

impl ViewerTargetingState {
    pub(crate) fn is_attack(&self) -> bool {
        matches!(self.action, ViewerTargetingAction::Attack)
    }
}

impl ViewerState {
    pub(crate) fn select_actor(&mut self, actor_id: ActorId, side: ActorSide) {
        if self.is_free_observe() {
            self.selected_actor = Some(actor_id);
            return;
        }

        self.selected_actor = None;
        if side == ActorSide::Player {
            self.controlled_player_actor = Some(actor_id);
        }
    }

    pub(crate) fn is_free_observe(self: &Self) -> bool {
        self.control_mode == ViewerControlMode::FreeObserve
    }

    pub(crate) fn can_issue_player_commands(self: &Self) -> bool {
        self.control_mode == ViewerControlMode::PlayerControl
    }

    pub(crate) fn is_player_control(self: &Self) -> bool {
        self.can_issue_player_commands()
    }

    pub(crate) fn is_camera_following_selected_actor(&self) -> bool {
        self.camera_mode == ViewerCameraMode::FollowSelectedActor
    }

    pub(crate) fn disable_camera_follow(&mut self) {
        self.camera_mode = ViewerCameraMode::ManualPan;
    }

    pub(crate) fn resume_camera_follow(&mut self) {
        self.camera_mode = ViewerCameraMode::FollowSelectedActor;
        self.camera_pan_offset = Vec2::ZERO;
        self.camera_drag_cursor = None;
        self.camera_drag_anchor_world = None;
    }

    pub(crate) fn command_actor_id(&self, snapshot: &SimulationSnapshot) -> Option<ActorId> {
        if !self.can_issue_player_commands() {
            return None;
        }

        self.selected_actor
            .filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id && actor.side == ActorSide::Player)
            })
            .or(self.controlled_player_actor.filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id && actor.side == ActorSide::Player)
            }))
            .or_else(|| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.side == ActorSide::Player)
                    .map(|actor| actor.actor_id)
            })
    }

    pub(crate) fn focus_actor_id(&self, snapshot: &SimulationSnapshot) -> Option<ActorId> {
        self.selected_actor
            .filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id)
            })
            .or(self.controlled_player_actor.filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id)
            }))
            .or_else(|| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.side == ActorSide::Player)
                    .map(|actor| actor.actor_id)
            })
            .or_else(|| snapshot.actors.first().map(|actor| actor.actor_id))
    }

    pub(crate) fn is_interaction_menu_open(&self) -> bool {
        self.interaction_menu.is_some()
    }

    pub(crate) fn interaction_locked_actor_id(
        &self,
        runtime_state: &ViewerRuntimeState,
    ) -> Option<ActorId> {
        self.active_dialogue
            .as_ref()
            .map(|dialogue| dialogue.actor_id)
            .or_else(|| {
                runtime_state
                    .runtime
                    .pending_interaction()
                    .map(|intent| intent.actor_id)
            })
    }

    pub(crate) fn is_actor_interaction_locked(
        &self,
        runtime_state: &ViewerRuntimeState,
        actor_id: ActorId,
    ) -> bool {
        self.interaction_locked_actor_id(runtime_state) == Some(actor_id)
    }
}

#[derive(Component)]
pub(crate) struct InfoPanelText;

#[derive(Component)]
pub(crate) struct InfoPanelFooterText;

#[derive(Component)]
pub(crate) struct InfoPanelTabBarRoot;

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InfoPanelTabButton {
    pub page: ViewerHudPage,
}

#[derive(Component)]
pub(crate) struct FpsOverlayText;

#[derive(Component)]
pub(crate) struct FreeObserveIndicatorRoot;

#[derive(Component)]
pub(crate) struct ViewerCamera;

#[derive(Component)]
pub(crate) struct InteractionMenuRoot;

#[derive(Component)]
pub(crate) struct DialoguePanelRoot;

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
pub(crate) struct GameUiRoot;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiHoverTooltipContent {
    InventoryItem { item_id: u32 },
    Skill { tree_id: String, skill_id: String },
    SceneTransition { target_name: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiInventoryContextMenuTarget {
    InventoryItem { item_id: u32 },
    EquipmentSlot { slot_id: String, item_id: u32 },
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct UiHoverTooltipState {
    pub visible: bool,
    pub cursor_position: Vec2,
    pub content: Option<UiHoverTooltipContent>,
}

impl Default for UiHoverTooltipState {
    fn default() -> Self {
        Self {
            visible: false,
            cursor_position: Vec2::ZERO,
            content: None,
        }
    }
}

impl UiHoverTooltipState {
    pub(crate) fn clear(&mut self) {
        self.visible = false;
        self.content = None;
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct UiInventoryContextMenuState {
    pub visible: bool,
    pub cursor_position: Vec2,
    pub target: Option<UiInventoryContextMenuTarget>,
}

impl Default for UiInventoryContextMenuState {
    fn default() -> Self {
        Self {
            visible: false,
            cursor_position: Vec2::ZERO,
            target: None,
        }
    }
}

impl UiInventoryContextMenuState {
    pub(crate) fn clear(&mut self) {
        self.visible = false;
        self.target = None;
    }
}

#[derive(Component)]
pub(crate) struct UiMouseBlocker;

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InventoryItemHoverTarget {
    pub item_id: u32,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) struct SkillHoverTarget {
    pub tree_id: String,
    pub skill_id: String,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InventoryItemClickTarget {
    pub item_id: u32,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) struct EquipmentSlotClickTarget {
    pub slot_id: String,
    pub item_id: Option<u32>,
}

#[derive(Component)]
pub(crate) struct InventoryContextMenuRoot;

#[derive(Component, Debug, Clone)]
pub(crate) enum GameUiButtonAction {
    MainMenuNewGame,
    MainMenuContinue,
    MainMenuExit,
    TogglePanel(UiMenuPanel),
    ClosePanels,
    CloseTrade,
    InventoryFilter(UiInventoryFilter),
    UseInventoryItem,
    EquipInventoryItem,
    DropInventoryItem,
    DecreaseDiscardQuantity,
    IncreaseDiscardQuantity,
    SetDiscardQuantityToMax,
    ConfirmDiscardQuantity,
    CancelDiscardQuantity,
    UnequipSlot(String),
    AllocateAttribute(String),
    SelectSkillTree(String),
    SelectSkill(String),
    AssignSkillToFirstEmptyHotbarSlot(String),
    AssignSkillToHotbar {
        skill_id: String,
        group: usize,
        slot: usize,
    },
    EnterAttackTargeting,
    ActivateHotbarSlot(usize),
    SelectHotbarGroup(usize),
    ClearHotbarSlot {
        group: usize,
        slot: usize,
    },
    CraftRecipe(String),
    SelectMapLocation(String),
    EnterOverworldLocation(String),
    BuyTradeItem {
        shop_id: String,
        item_id: u32,
    },
    SellTradeItem {
        shop_id: String,
        item_id: u32,
    },
    SettingsSetMaster(f32),
    SettingsSetMusic(f32),
    SettingsSetSfx(f32),
    SettingsSetWindowMode(String),
    SettingsSetVsync(bool),
    SettingsSetUiScale(f32),
    SettingsCycleBinding(String),
}

#[derive(Component)]
pub(crate) struct InteractionLockedActorTag;

#[derive(Component)]
pub(crate) struct ActorLabel {
    pub actor_id: ActorId,
}

#[derive(Debug, Clone)]
pub(crate) struct InteractionMenuState {
    pub target_id: InteractionTargetId,
    pub cursor_position: Vec2,
}

#[derive(Debug, Clone)]
pub(crate) struct ActiveDialogueState {
    pub actor_id: ActorId,
    pub target_id: Option<InteractionTargetId>,
    pub dialogue_key: String,
    pub dialog_id: String,
    pub data: DialogueData,
    pub current_node_id: String,
    pub target_name: String,
}

#[cfg(test)]
mod tests {
    use super::{
        ActorMotionTrack, AttackLungeTrack, HitReactionTrack, ViewerActorFeedbackState,
        ViewerCameraMode, ViewerCameraShakeState, ViewerControlMode, ViewerDamageNumberState,
        ViewerState,
    };
    use game_core::{
        ActorDebugState, CombatDebugState, GridDebugState, OverworldStateSnapshot,
        SimulationSnapshot,
    };
    use game_data::{
        ActorId, ActorKind, ActorSide, CharacterId, GridCoord, InteractionContextSnapshot,
        TurnState, WorldCoord,
    };

    #[test]
    fn command_actor_uses_controlled_player_in_player_control_mode() {
        let snapshot = snapshot_with_actors(vec![
            actor(ActorId(1), ActorSide::Player, "player"),
            actor(ActorId(2), ActorSide::Friendly, "guard"),
        ]);
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(ActorId(1), ActorSide::Player);

        assert_eq!(viewer_state.selected_actor, None);
        assert_eq!(viewer_state.controlled_player_actor, Some(ActorId(1)));
        assert_eq!(viewer_state.command_actor_id(&snapshot), Some(ActorId(1)));
    }

    #[test]
    fn select_actor_only_sets_selected_actor_in_free_observe_mode() {
        let mut viewer_state = ViewerState::default();
        viewer_state.control_mode = ViewerControlMode::FreeObserve;

        viewer_state.select_actor(ActorId(7), ActorSide::Friendly);

        assert_eq!(viewer_state.selected_actor, Some(ActorId(7)));
        assert_eq!(viewer_state.controlled_player_actor, None);
    }

    #[test]
    fn command_actor_is_disabled_in_free_observe_mode() {
        let snapshot = snapshot_with_actors(vec![actor(ActorId(1), ActorSide::Player, "player")]);
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(ActorId(1), ActorSide::Player);
        viewer_state.control_mode = ViewerControlMode::FreeObserve;

        assert_eq!(viewer_state.command_actor_id(&snapshot), None);
    }

    #[test]
    fn viewer_state_follows_selected_actor_by_default() {
        let viewer_state = ViewerState::default();

        assert_eq!(
            viewer_state.camera_mode,
            ViewerCameraMode::FollowSelectedActor
        );
        assert!(viewer_state.is_camera_following_selected_actor());
    }

    #[test]
    fn resume_camera_follow_resets_manual_pan_state() {
        let mut viewer_state = ViewerState {
            camera_mode: ViewerCameraMode::ManualPan,
            camera_pan_offset: bevy::prelude::Vec2::new(3.0, -2.0),
            camera_drag_cursor: Some(bevy::prelude::Vec2::new(120.0, 48.0)),
            camera_drag_anchor_world: Some(bevy::prelude::Vec2::new(6.5, 9.5)),
            ..ViewerState::default()
        };

        viewer_state.resume_camera_follow();

        assert_eq!(
            viewer_state.camera_mode,
            ViewerCameraMode::FollowSelectedActor
        );
        assert_eq!(viewer_state.camera_pan_offset, bevy::prelude::Vec2::ZERO);
        assert_eq!(viewer_state.camera_drag_cursor, None);
        assert_eq!(viewer_state.camera_drag_anchor_world, None);
    }

    #[test]
    fn actor_motion_track_interpolates_linearly() {
        let mut track = ActorMotionTrack::new(
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(1.5, 0.5, 0.5),
            0,
            0.1,
        );

        track.advance(0.05);

        assert_eq!(track.current_world, WorldCoord::new(1.0, 0.5, 0.5));
        assert!(track.active);

        track.advance(0.05);

        assert_eq!(track.current_world, WorldCoord::new(1.5, 0.5, 0.5));
        assert!(!track.active);
    }

    #[test]
    fn actor_motion_track_snaps_to_authoritative_world() {
        let mut track = ActorMotionTrack::new(
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(1.5, 0.5, 0.5),
            0,
            0.1,
        );

        track.advance(0.03);
        track.snap_to(WorldCoord::new(4.5, 1.5, 2.5), 1);

        assert_eq!(track.current_world, WorldCoord::new(4.5, 1.5, 2.5));
        assert_eq!(track.level, 1);
        assert_eq!(track.elapsed_sec, 0.0);
        assert!(!track.active);
    }

    #[test]
    fn attack_lunge_track_returns_to_origin() {
        let mut track = AttackLungeTrack::new(
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(3.5, 0.5, 0.5),
        )
        .expect("track should be created");

        track.advance(0.04);
        assert!(track.current_offset().x > 0.0);

        track.advance(0.16);
        assert_eq!(track.current_offset(), bevy::prelude::Vec3::ZERO);
        assert!(!track.is_active());
    }

    #[test]
    fn hit_reaction_track_returns_to_origin() {
        let mut track = HitReactionTrack::new();

        track.advance(0.03);
        assert!(track.current_offset().length() > 0.0);

        track.advance(0.20);
        assert_eq!(track.current_offset(), bevy::prelude::Vec3::ZERO);
        assert!(!track.is_active());
    }

    #[test]
    fn viewer_actor_feedback_state_sums_offsets() {
        let mut feedback_state = ViewerActorFeedbackState::default();
        feedback_state.queue_attack_lunge(
            ActorId(1),
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(3.5, 0.5, 0.5),
        );
        feedback_state.queue_hit_reaction(ActorId(1));
        feedback_state.advance(0.03);

        assert!(feedback_state.visual_offset(ActorId(1)).length() > 0.0);
    }

    #[test]
    fn damage_number_state_queues_and_expires_entries() {
        let mut damage_numbers = ViewerDamageNumberState::default();
        let id = damage_numbers.queue_damage_number(WorldCoord::new(1.5, 0.5, 2.5), 12, false);

        assert!(damage_numbers.entries.contains_key(&id));

        damage_numbers.advance(0.7);

        assert!(!damage_numbers.entries.contains_key(&id));
    }

    #[test]
    fn camera_shake_state_returns_to_rest_offset() {
        let mut shake_state = ViewerCameraShakeState::default();
        shake_state.trigger_default_damage_shake();
        shake_state.advance(0.05);
        assert!(shake_state.current_offset().length() > 0.0);

        shake_state.advance(0.4);
        assert_eq!(shake_state.current_offset(), bevy::prelude::Vec3::ZERO);
    }

    fn actor(actor_id: ActorId, side: ActorSide, definition_id: &str) -> ActorDebugState {
        ActorDebugState {
            actor_id,
            definition_id: Some(CharacterId(definition_id.into())),
            display_name: definition_id.into(),
            kind: ActorKind::Npc,
            side,
            group_id: "group".into(),
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

    fn snapshot_with_actors(actors: Vec<ActorDebugState>) -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors,
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(8),
                map_height: Some(8),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
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
}
