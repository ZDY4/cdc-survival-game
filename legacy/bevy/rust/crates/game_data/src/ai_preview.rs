use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use crate::{
    resolve_ai_behavior_profile, AiAnchorBinding, AiBehaviorProfile, AiComparisonOperator,
    AiConditionDefinition, AiFactModuleDefinition, AiMetadata, AiModuleLibrary,
    AiReservationBinding, CharacterDefinition, CharacterLifeProfile, NeedProfile, NpcRole,
    ScheduleBlock, ScheduleDay, SettlementDefinition, SmartObjectKind,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolvedCharacterLifeProfile {
    pub settlement_id: String,
    pub role: NpcRole,
    pub ai_behavior_profile_id: String,
    pub schedule_profile_id: String,
    pub personality_profile_id: String,
    pub need_profile_id: String,
    pub smart_object_access_profile_id: String,
    pub home_anchor: String,
    pub duty_route_id: String,
    pub schedule_blocks: Vec<ScheduleBlock>,
    pub need_profile: NeedProfile,
    pub personality_profile: crate::PersonalityProfileDefinition,
    pub smart_object_access_profile: crate::SmartObjectAccessProfileDefinition,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WeeklyScheduleEntryPreview {
    pub label: String,
    pub tags: Vec<String>,
    pub days: Vec<ScheduleDay>,
    pub start_minute: u16,
    pub end_minute: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WeeklySchedulePreview {
    pub profile_id: String,
    pub entries: Vec<WeeklyScheduleEntryPreview>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiPreviewModuleRef {
    pub id: String,
    pub display_name: String,
    pub category: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiBehaviorPreview {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub default_goal_id: Option<String>,
    pub alert_goal_id: Option<String>,
    pub facts: Vec<AiPreviewModuleRef>,
    pub goals: Vec<AiPreviewModuleRef>,
    pub actions: Vec<AiPreviewModuleRef>,
    pub executors: Vec<AiPreviewModuleRef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PersonalityProfilePreview {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub safety_bias: f32,
    pub social_bias: f32,
    pub duty_bias: f32,
    pub comfort_bias: f32,
    pub alertness_bias: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NeedProfilePreview {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub hunger_decay_per_hour: f32,
    pub energy_decay_per_hour: f32,
    pub morale_decay_per_hour: f32,
    pub safety_bias: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SmartObjectAccessRulePreview {
    pub kind: SmartObjectKind,
    pub preferred_tags: Vec<String>,
    pub fallback_to_any: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SmartObjectAccessProfilePreview {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub rules: Vec<SmartObjectAccessRulePreview>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterLifeBindingPreview {
    pub settlement_id: String,
    pub role: NpcRole,
    pub home_anchor: String,
    pub duty_route_id: String,
    pub current_schedule_entry: Option<WeeklyScheduleEntryPreview>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiAvailabilityContext {
    pub guard_post_available: bool,
    pub meal_object_available: bool,
    pub leisure_object_available: bool,
    pub medical_station_available: bool,
    pub patrol_route_available: bool,
    pub bed_available: bool,
}

impl Default for AiAvailabilityContext {
    fn default() -> Self {
        Self {
            guard_post_available: true,
            meal_object_available: true,
            leisure_object_available: true,
            medical_station_available: true,
            patrol_route_available: true,
            bed_available: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterAiPreviewContext {
    pub day: ScheduleDay,
    pub minute_of_day: u16,
    pub hunger: f32,
    pub energy: f32,
    pub morale: f32,
    pub world_alert_active: bool,
    pub current_anchor: Option<String>,
    pub active_guards: u32,
    pub min_guard_on_duty: u32,
    pub availability: AiAvailabilityContext,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiGoalScorePreview {
    pub goal_id: String,
    pub display_name: String,
    pub score: i32,
    pub matched_rule_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiActionAvailabilityPreview {
    pub action_id: String,
    pub display_name: String,
    pub available: bool,
    pub blocked_by: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiBlackboardValueKind {
    Number,
    Bool,
    Text,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiBlackboardEntryPreview {
    pub key: String,
    pub value_kind: AiBlackboardValueKind,
    pub value_text: String,
    pub source: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiConditionTraceKind {
    ConditionRef,
    FactTrue,
    BoolEquals,
    NumberCompare,
    TextEquals,
    TextKeyEquals,
    RoleIs,
    AllOf,
    AnyOf,
    Not,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiConditionTracePreview {
    pub kind: AiConditionTraceKind,
    pub label: String,
    pub passed: bool,
    pub detail: String,
    pub children: Vec<AiConditionTracePreview>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiFactEvaluationPreview {
    pub fact_id: String,
    pub display_name: String,
    pub matched: bool,
    pub trace: AiConditionTracePreview,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiGoalRuleEvaluationPreview {
    pub rule_id: String,
    pub display_name: String,
    pub matched: bool,
    pub score_delta: i32,
    pub multiplier_key: Option<String>,
    pub multiplier_value: Option<f32>,
    pub contributed_score: i32,
    pub trace: Option<AiConditionTracePreview>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiGoalEvaluationPreview {
    pub goal_id: String,
    pub display_name: String,
    pub final_score: i32,
    pub rules: Vec<AiGoalRuleEvaluationPreview>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiActionBlockerKind {
    PreconditionMismatch,
    PreconditionUnresolved,
    MissingTargetAnchor,
    ReservationUnavailable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiActionBlockerPreview {
    pub kind: AiActionBlockerKind,
    pub message: String,
    pub subject: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiActionEvaluationPreview {
    pub action_id: String,
    pub display_name: String,
    pub available: bool,
    pub resolved_target_anchor: Option<String>,
    pub reservation_target: Option<String>,
    pub blockers: Vec<AiActionBlockerPreview>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterAiDiagnosticsPreview {
    pub active_schedule_entry: Option<WeeklyScheduleEntryPreview>,
    pub blackboard_entries: Vec<AiBlackboardEntryPreview>,
    pub fact_evaluations: Vec<AiFactEvaluationPreview>,
    pub goal_evaluations: Vec<AiGoalEvaluationPreview>,
    pub action_evaluations: Vec<AiActionEvaluationPreview>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterAiPreview {
    pub character_id: String,
    pub display_name: String,
    pub ai_behavior_profile_id: String,
    pub schedule_profile_id: String,
    pub personality_profile_id: String,
    pub need_profile_id: String,
    pub smart_object_access_profile_id: String,
    pub life: CharacterLifeBindingPreview,
    pub personality: PersonalityProfilePreview,
    pub need_profile: NeedProfilePreview,
    pub smart_object_access: SmartObjectAccessProfilePreview,
    pub behavior: AiBehaviorPreview,
    pub schedule: WeeklySchedulePreview,
    pub context: CharacterAiPreviewContext,
    pub fact_ids: Vec<String>,
    pub goal_scores: Vec<AiGoalScorePreview>,
    pub available_actions: Vec<AiActionAvailabilityPreview>,
    pub diagnostics: CharacterAiDiagnosticsPreview,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CharacterAiPreviewError {
    #[error("character {character_id} has no life profile")]
    MissingLifeProfile { character_id: String },
    #[error("AI behavior profile {profile_id} is invalid: {message}")]
    InvalidBehaviorProfile { profile_id: String, message: String },
    #[error("schedule profile {profile_id} is missing")]
    MissingScheduleProfile { profile_id: String },
    #[error("need profile {profile_id} is missing")]
    MissingNeedProfile { profile_id: String },
    #[error("personality profile {profile_id} is missing")]
    MissingPersonalityProfile { profile_id: String },
    #[error("smart object access profile {profile_id} is missing")]
    MissingSmartObjectAccessProfile { profile_id: String },
}

pub fn resolve_character_life_profile(
    life: &CharacterLifeProfile,
    ai_library: &AiModuleLibrary,
) -> Result<ResolvedCharacterLifeProfile, CharacterAiPreviewError> {
    let schedule_template = ai_library
        .schedule_templates
        .get(&life.schedule_profile_id)
        .ok_or_else(|| CharacterAiPreviewError::MissingScheduleProfile {
            profile_id: life.schedule_profile_id.clone(),
        })?;
    let need_profile = ai_library
        .need_profiles
        .get(&life.need_profile_id)
        .ok_or_else(|| CharacterAiPreviewError::MissingNeedProfile {
            profile_id: life.need_profile_id.clone(),
        })?;
    let personality_profile = ai_library
        .personality_profiles
        .get(&life.personality_profile_id)
        .ok_or_else(|| CharacterAiPreviewError::MissingPersonalityProfile {
            profile_id: life.personality_profile_id.clone(),
        })?;
    let access_profile = ai_library
        .smart_object_access_profiles
        .get(&life.smart_object_access_profile_id)
        .ok_or_else(
            || CharacterAiPreviewError::MissingSmartObjectAccessProfile {
                profile_id: life.smart_object_access_profile_id.clone(),
            },
        )?;

    let mut schedule_blocks = schedule_template.blocks.clone();
    schedule_blocks.extend(life.schedule.clone());

    let mut resolved_need_profile = need_profile.profile.clone();
    if let Some(override_profile) = &life.need_profile_override {
        resolved_need_profile = override_profile.clone();
    }

    let mut resolved_personality = personality_profile.clone();
    if let Some(value) = life.personality_override.safety_bias {
        resolved_personality.safety_bias = value;
    }
    if let Some(value) = life.personality_override.social_bias {
        resolved_personality.social_bias = value;
    }
    if let Some(value) = life.personality_override.duty_bias {
        resolved_personality.duty_bias = value;
    }
    if let Some(value) = life.personality_override.comfort_bias {
        resolved_personality.comfort_bias = value;
    }
    if let Some(value) = life.personality_override.alertness_bias {
        resolved_personality.alertness_bias = value;
    }

    Ok(ResolvedCharacterLifeProfile {
        settlement_id: life.settlement_id.clone(),
        role: life.role,
        ai_behavior_profile_id: life.ai_behavior_profile_id.clone(),
        schedule_profile_id: life.schedule_profile_id.clone(),
        personality_profile_id: life.personality_profile_id.clone(),
        need_profile_id: life.need_profile_id.clone(),
        smart_object_access_profile_id: life.smart_object_access_profile_id.clone(),
        home_anchor: life.home_anchor.clone(),
        duty_route_id: life.duty_route_id.clone(),
        schedule_blocks,
        need_profile: resolved_need_profile,
        personality_profile: resolved_personality,
        smart_object_access_profile: access_profile.clone(),
    })
}

pub fn build_schedule_preview(
    resolved_life: &ResolvedCharacterLifeProfile,
) -> WeeklySchedulePreview {
    WeeklySchedulePreview {
        profile_id: resolved_life.schedule_profile_id.clone(),
        entries: resolved_life
            .schedule_blocks
            .iter()
            .map(|block| WeeklyScheduleEntryPreview {
                label: block.label.clone(),
                tags: block.tags.clone(),
                days: block.resolved_days(),
                start_minute: block.start_minute,
                end_minute: block.end_minute,
            })
            .collect(),
    }
}

pub fn build_behavior_preview(
    ai_library: &AiModuleLibrary,
    behavior_profile_id: &str,
) -> Result<AiBehaviorPreview, CharacterAiPreviewError> {
    let behavior =
        resolve_ai_behavior_profile(ai_library, &behavior_profile_id.into()).map_err(|error| {
            CharacterAiPreviewError::InvalidBehaviorProfile {
                profile_id: behavior_profile_id.to_string(),
                message: error.to_string(),
            }
        })?;

    Ok(AiBehaviorPreview {
        id: behavior.id.as_str().to_string(),
        display_name: display_name(&behavior.meta, behavior.id.as_str()),
        description: behavior.meta.description.clone(),
        default_goal_id: behavior
            .default_goal_id
            .as_ref()
            .map(|id| id.as_str().to_string()),
        alert_goal_id: behavior
            .alert_goal_id
            .as_ref()
            .map(|id| id.as_str().to_string()),
        facts: behavior
            .facts
            .iter()
            .map(|fact| module_ref(fact.id.as_str(), &fact.meta))
            .collect(),
        goals: behavior
            .goals
            .iter()
            .map(|goal| module_ref(goal.id.as_str(), &goal.meta))
            .collect(),
        actions: behavior
            .actions
            .iter()
            .map(|action| module_ref(action.id.as_str(), &action.meta))
            .collect(),
        executors: behavior
            .executors
            .values()
            .map(|executor| module_ref(executor.id.as_str(), &executor.meta))
            .collect(),
    })
}

pub fn build_character_ai_preview(
    character: &CharacterDefinition,
    settlement: Option<&SettlementDefinition>,
    ai_library: &AiModuleLibrary,
) -> Result<CharacterAiPreview, CharacterAiPreviewError> {
    let resolved_life = resolve_character_life_profile(
        character
            .life
            .as_ref()
            .ok_or_else(|| CharacterAiPreviewError::MissingLifeProfile {
                character_id: character.id.as_str().to_string(),
            })?,
        ai_library,
    )?;
    let context = default_preview_context(&resolved_life, settlement);
    build_character_ai_preview_at_time(character, settlement, ai_library, &context)
}

pub fn build_character_ai_preview_at_time(
    character: &CharacterDefinition,
    settlement: Option<&SettlementDefinition>,
    ai_library: &AiModuleLibrary,
    context: &CharacterAiPreviewContext,
) -> Result<CharacterAiPreview, CharacterAiPreviewError> {
    let life =
        character
            .life
            .as_ref()
            .ok_or_else(|| CharacterAiPreviewError::MissingLifeProfile {
                character_id: character.id.as_str().to_string(),
            })?;
    let resolved_life = resolve_character_life_profile(life, ai_library)?;
    let behavior =
        resolve_ai_behavior_profile(ai_library, &life.ai_behavior_profile_id.clone().into())
            .map_err(|error| CharacterAiPreviewError::InvalidBehaviorProfile {
                profile_id: life.ai_behavior_profile_id.clone(),
                message: error.to_string(),
            })?;
    let schedule_preview = build_schedule_preview(&resolved_life);
    let behavior_preview = build_behavior_preview(ai_library, &life.ai_behavior_profile_id)?;
    let blackboard = build_preview_blackboard(&resolved_life, settlement, context);
    let fact_evaluations = evaluate_preview_facts(&behavior, &blackboard, resolved_life.role);
    let facts = rebuild_preview_facts(&behavior, &blackboard, resolved_life.role);
    let fact_ids = facts
        .iter()
        .map(|fact| fact.id.as_str().to_string())
        .collect::<Vec<_>>();
    let fact_set = fact_ids.iter().cloned().collect::<BTreeSet<_>>();
    let goal_evaluations =
        evaluate_preview_goals(&behavior, &fact_set, &blackboard, resolved_life.role);
    let goal_scores = summarize_goal_scores(&goal_evaluations);
    let action_evaluations = evaluate_preview_actions(
        &behavior,
        &resolved_life,
        settlement,
        &fact_set,
        &blackboard,
        context,
    );
    let available_actions = summarize_action_availability(&action_evaluations);
    let current_schedule_entry = active_schedule_block(
        &resolved_life.schedule_blocks,
        context.day,
        context.minute_of_day,
    )
    .map(schedule_entry_preview);
    let blackboard_entries = build_blackboard_entries(&blackboard);

    let need_meta = ai_library
        .need_profiles
        .get(resolved_life.need_profile_id.as_str())
        .map(|profile| profile.meta.clone())
        .unwrap_or_default();

    Ok(CharacterAiPreview {
        character_id: character.id.as_str().to_string(),
        display_name: character.identity.display_name.clone(),
        ai_behavior_profile_id: resolved_life.ai_behavior_profile_id.clone(),
        schedule_profile_id: resolved_life.schedule_profile_id.clone(),
        personality_profile_id: resolved_life.personality_profile_id.clone(),
        need_profile_id: resolved_life.need_profile_id.clone(),
        smart_object_access_profile_id: resolved_life.smart_object_access_profile_id.clone(),
        life: CharacterLifeBindingPreview {
            settlement_id: resolved_life.settlement_id.clone(),
            role: resolved_life.role,
            home_anchor: resolved_life.home_anchor.clone(),
            duty_route_id: resolved_life.duty_route_id.clone(),
            current_schedule_entry: current_schedule_entry.clone(),
        },
        personality: PersonalityProfilePreview {
            id: resolved_life.personality_profile_id.clone(),
            display_name: display_name(
                &resolved_life.personality_profile.meta,
                &resolved_life.personality_profile_id,
            ),
            description: resolved_life.personality_profile.meta.description.clone(),
            safety_bias: resolved_life.personality_profile.safety_bias,
            social_bias: resolved_life.personality_profile.social_bias,
            duty_bias: resolved_life.personality_profile.duty_bias,
            comfort_bias: resolved_life.personality_profile.comfort_bias,
            alertness_bias: resolved_life.personality_profile.alertness_bias,
        },
        need_profile: NeedProfilePreview {
            id: resolved_life.need_profile_id.clone(),
            display_name: display_name(&need_meta, &resolved_life.need_profile_id),
            description: need_meta.description.clone(),
            hunger_decay_per_hour: resolved_life.need_profile.hunger_decay_per_hour,
            energy_decay_per_hour: resolved_life.need_profile.energy_decay_per_hour,
            morale_decay_per_hour: resolved_life.need_profile.morale_decay_per_hour,
            safety_bias: resolved_life.need_profile.safety_bias,
        },
        smart_object_access: SmartObjectAccessProfilePreview {
            id: resolved_life.smart_object_access_profile_id.clone(),
            display_name: display_name(
                &resolved_life.smart_object_access_profile.meta,
                &resolved_life.smart_object_access_profile_id,
            ),
            description: resolved_life
                .smart_object_access_profile
                .meta
                .description
                .clone(),
            rules: resolved_life
                .smart_object_access_profile
                .rules
                .iter()
                .map(|rule| SmartObjectAccessRulePreview {
                    kind: rule.kind,
                    preferred_tags: rule.preferred_tags.clone(),
                    fallback_to_any: rule.fallback_to_any,
                })
                .collect(),
        },
        behavior: behavior_preview,
        schedule: schedule_preview,
        context: context.clone(),
        fact_ids,
        goal_scores,
        available_actions,
        diagnostics: CharacterAiDiagnosticsPreview {
            active_schedule_entry: current_schedule_entry.clone(),
            blackboard_entries,
            fact_evaluations,
            goal_evaluations,
            action_evaluations,
        },
    })
}

fn default_preview_context(
    resolved_life: &ResolvedCharacterLifeProfile,
    settlement: Option<&SettlementDefinition>,
) -> CharacterAiPreviewContext {
    CharacterAiPreviewContext {
        day: ScheduleDay::Monday,
        minute_of_day: 7 * 60,
        hunger: 60.0,
        energy: 85.0,
        morale: 50.0,
        world_alert_active: false,
        current_anchor: Some(resolved_life.home_anchor.clone()),
        active_guards: 0,
        min_guard_on_duty: settlement
            .map(|settlement| settlement.service_rules.min_guard_on_duty)
            .unwrap_or(0),
        availability: AiAvailabilityContext {
            patrol_route_available: !resolved_life.duty_route_id.trim().is_empty(),
            ..AiAvailabilityContext::default()
        },
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
struct PreviewBlackboard {
    numbers: std::collections::BTreeMap<String, f32>,
    booleans: std::collections::BTreeMap<String, bool>,
    texts: std::collections::BTreeMap<String, String>,
}

impl PreviewBlackboard {
    fn set_number(&mut self, key: impl Into<String>, value: f32) {
        self.numbers.insert(key.into(), value);
    }

    fn set_bool(&mut self, key: impl Into<String>, value: bool) {
        self.booleans.insert(key.into(), value);
    }

    fn set_text(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.texts.insert(key.into(), value.into());
    }

    fn number(&self, key: &str) -> Option<f32> {
        self.numbers.get(key).copied()
    }

    fn boolean(&self, key: &str) -> Option<bool> {
        self.booleans.get(key).copied()
    }

    fn text(&self, key: &str) -> Option<&str> {
        self.texts.get(key).map(String::as_str)
    }
}

fn build_preview_blackboard(
    resolved_life: &ResolvedCharacterLifeProfile,
    settlement: Option<&SettlementDefinition>,
    context: &CharacterAiPreviewContext,
) -> PreviewBlackboard {
    let mut blackboard = PreviewBlackboard::default();
    blackboard.set_number("need.hunger", context.hunger);
    blackboard.set_number("need.energy", context.energy);
    blackboard.set_number("need.morale", context.morale);
    blackboard.set_number(
        "personality.safety_bias",
        resolved_life.personality_profile.safety_bias,
    );
    blackboard.set_number(
        "personality.social_bias",
        resolved_life.personality_profile.social_bias,
    );
    blackboard.set_number(
        "personality.duty_bias",
        resolved_life.personality_profile.duty_bias,
    );
    blackboard.set_number(
        "personality.comfort_bias",
        resolved_life.personality_profile.comfort_bias,
    );
    blackboard.set_number(
        "personality.alertness_bias",
        resolved_life.personality_profile.alertness_bias,
    );
    blackboard.set_bool(
        "schedule.on_shift",
        active_schedule_block(
            &resolved_life.schedule_blocks,
            context.day,
            context.minute_of_day,
        )
        .map(|block| block.tags.iter().any(|tag| tag == "shift"))
        .unwrap_or(false),
    );
    blackboard.set_bool(
        "schedule.shift_starting_soon",
        resolved_life.schedule_blocks.iter().any(|block| {
            block.includes_day(context.day)
                && block.start_minute >= context.minute_of_day
                && block.start_minute.saturating_sub(context.minute_of_day) <= 30
        }),
    );
    blackboard.set_bool(
        "schedule.meal_window_open",
        settlement
            .map(|settlement| {
                settlement.service_rules.meal_windows.iter().any(|window| {
                    context.minute_of_day >= window.start_minute
                        && context.minute_of_day < window.end_minute
                })
            })
            .unwrap_or(false),
    );
    blackboard.set_bool(
        "schedule.quiet_hours",
        settlement
            .and_then(|settlement| settlement.service_rules.quiet_hours.as_ref())
            .map(|window| {
                context.minute_of_day >= window.start_minute
                    && context.minute_of_day < window.end_minute
            })
            .unwrap_or(false),
    );
    blackboard.set_bool("world.alert_active", context.world_alert_active);
    blackboard.set_bool(
        "settlement.guard_coverage_insufficient",
        resolved_life.role == NpcRole::Guard
            && blackboard.boolean("schedule.on_shift").unwrap_or(false)
            && context.active_guards < context.min_guard_on_duty,
    );
    blackboard.set_bool(
        "availability.guard_post",
        context.availability.guard_post_available,
    );
    blackboard.set_bool(
        "availability.meal_object",
        context.availability.meal_object_available,
    );
    blackboard.set_bool(
        "availability.leisure_object",
        context.availability.leisure_object_available,
    );
    blackboard.set_bool(
        "availability.medical_station",
        context.availability.medical_station_available,
    );
    blackboard.set_bool(
        "availability.patrol_route",
        context.availability.patrol_route_available,
    );
    blackboard.set_bool("availability.bed", context.availability.bed_available);
    blackboard.set_bool("reservation.bed.active", context.availability.bed_available);
    blackboard.set_bool(
        "reservation.meal_object.active",
        context.availability.meal_object_available,
    );
    if let Some(anchor) = &context.current_anchor {
        blackboard.set_text("anchor.current", anchor.clone());
    }
    blackboard.set_text("anchor.home", resolved_life.home_anchor.clone());
    if let Some(anchor) = resolve_first_anchor(
        settlement,
        &resolved_life.smart_object_access_profile,
        SmartObjectKind::GuardPost,
    ) {
        blackboard.set_text("anchor.duty", anchor);
    }
    if let Some(anchor) = resolve_first_anchor(
        settlement,
        &resolved_life.smart_object_access_profile,
        SmartObjectKind::CanteenSeat,
    ) {
        blackboard.set_text("anchor.canteen", anchor);
    }
    if let Some(anchor) = resolve_first_anchor(
        settlement,
        &resolved_life.smart_object_access_profile,
        SmartObjectKind::RecreationSpot,
    ) {
        blackboard.set_text("anchor.leisure", anchor);
    }
    if let Some(anchor) = settlement
        .and_then(|settlement| {
            settlement
                .smart_objects
                .iter()
                .find(|object| object.kind == SmartObjectKind::AlarmPoint)
        })
        .map(|object| object.anchor_id.clone())
    {
        blackboard.set_text("anchor.alarm", anchor);
    }
    blackboard
}

fn rebuild_preview_facts(
    behavior: &AiBehaviorProfile,
    blackboard: &PreviewBlackboard,
    role: NpcRole,
) -> Vec<AiFactModuleDefinition> {
    let mut resolved = Vec::new();
    let mut fact_ids = BTreeSet::new();
    for fact in &behavior.facts {
        if evaluate_condition(&fact.condition, behavior, &fact_ids, blackboard, role) {
            fact_ids.insert(fact.id.as_str().to_string());
            resolved.push(fact.clone());
        }
    }
    resolved
}

fn evaluate_preview_facts(
    behavior: &AiBehaviorProfile,
    blackboard: &PreviewBlackboard,
    role: NpcRole,
) -> Vec<AiFactEvaluationPreview> {
    let mut fact_ids = BTreeSet::new();
    let mut evaluations = Vec::new();
    for fact in &behavior.facts {
        let trace =
            evaluate_condition_trace(&fact.condition, behavior, &fact_ids, blackboard, role);
        let matched = evaluate_condition(&fact.condition, behavior, &fact_ids, blackboard, role);
        if matched {
            fact_ids.insert(fact.id.as_str().to_string());
        }
        evaluations.push(AiFactEvaluationPreview {
            fact_id: fact.id.as_str().to_string(),
            display_name: display_name(&fact.meta, fact.id.as_str()),
            matched,
            trace,
        });
    }
    evaluations
}

fn evaluate_preview_goals(
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
    role: NpcRole,
) -> Vec<AiGoalEvaluationPreview> {
    behavior
        .goals
        .iter()
        .map(|goal| {
            let mut final_score = 0;
            let mut rules = Vec::new();
            for rule_id in &goal.score_rule_ids {
                let Some(rule) = behavior.score_rules.get(rule_id) else {
                    continue;
                };
                let trace = rule.when.as_ref().map(|condition| {
                    evaluate_condition_trace(condition, behavior, facts, blackboard, role)
                });
                let matched = trace.as_ref().map(|trace| trace.passed).unwrap_or(true);
                let multiplier_value = rule
                    .score_multiplier_key
                    .as_deref()
                    .and_then(|key| blackboard.number(key));
                let contributed_score = if matched {
                    let multiplier = multiplier_value.unwrap_or(1.0);
                    ((rule.score_delta as f32) * multiplier).round() as i32
                } else {
                    0
                };
                if matched {
                    final_score += contributed_score;
                }
                rules.push(AiGoalRuleEvaluationPreview {
                    rule_id: rule.id.as_str().to_string(),
                    display_name: display_name(&rule.meta, rule.id.as_str()),
                    matched,
                    score_delta: rule.score_delta,
                    multiplier_key: rule.score_multiplier_key.clone(),
                    multiplier_value,
                    contributed_score,
                    trace,
                });
            }
            AiGoalEvaluationPreview {
                goal_id: goal.id.as_str().to_string(),
                display_name: display_name(&goal.meta, goal.id.as_str()),
                final_score,
                rules,
            }
        })
        .collect()
}

fn summarize_goal_scores(goal_evaluations: &[AiGoalEvaluationPreview]) -> Vec<AiGoalScorePreview> {
    goal_evaluations
        .iter()
        .map(|goal| AiGoalScorePreview {
            goal_id: goal.goal_id.clone(),
            display_name: goal.display_name.clone(),
            score: goal.final_score,
            matched_rule_ids: goal
                .rules
                .iter()
                .filter(|rule| rule.matched)
                .map(|rule| rule.rule_id.clone())
                .collect(),
        })
        .collect()
}

fn evaluate_preview_actions(
    behavior: &AiBehaviorProfile,
    resolved_life: &ResolvedCharacterLifeProfile,
    settlement: Option<&SettlementDefinition>,
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
    context: &CharacterAiPreviewContext,
) -> Vec<AiActionEvaluationPreview> {
    let planner_state = derive_planner_state(facts, blackboard);
    behavior
        .actions
        .iter()
        .map(|action| {
            let mut blockers = Vec::new();
            for requirement in &action.preconditions {
                match planner_state.get(&requirement.key) {
                    Some(value) if *value == requirement.value => {}
                    Some(value) => blockers.push(AiActionBlockerPreview {
                        kind: AiActionBlockerKind::PreconditionMismatch,
                        message: format!(
                            "precondition {} expected {}, got {}",
                            requirement.key, requirement.value, value
                        ),
                        subject: requirement.key.clone(),
                    }),
                    None => blockers.push(AiActionBlockerPreview {
                        kind: AiActionBlockerKind::PreconditionUnresolved,
                        message: format!("precondition {} is unresolved", requirement.key),
                        subject: requirement.key.clone(),
                    }),
                }
            }
            let resolved_target_anchor = action
                .target_anchor
                .clone()
                .and_then(|anchor| resolve_anchor_binding(settlement, resolved_life, anchor));
            if let Some(anchor) = action.target_anchor.clone() {
                if resolved_target_anchor.is_none() {
                    blockers.push(AiActionBlockerPreview {
                        kind: AiActionBlockerKind::MissingTargetAnchor,
                        message: format!("missing target anchor {:?}", anchor),
                        subject: format!("{anchor:?}"),
                    });
                }
            }
            if let Some(reservation) = action.reservation_target.clone() {
                if !reservation_available(reservation.clone(), context) {
                    blockers.push(AiActionBlockerPreview {
                        kind: AiActionBlockerKind::ReservationUnavailable,
                        message: format!("reservation {:?} unavailable", reservation),
                        subject: format!("{reservation:?}"),
                    });
                }
            }
            AiActionEvaluationPreview {
                action_id: action.id.as_str().to_string(),
                display_name: display_name(&action.meta, action.id.as_str()),
                available: blockers.is_empty(),
                resolved_target_anchor,
                reservation_target: action
                    .reservation_target
                    .as_ref()
                    .map(|reservation| format!("{reservation:?}")),
                blockers,
            }
        })
        .collect()
}

fn summarize_action_availability(
    action_evaluations: &[AiActionEvaluationPreview],
) -> Vec<AiActionAvailabilityPreview> {
    action_evaluations
        .iter()
        .map(|action| AiActionAvailabilityPreview {
            action_id: action.action_id.clone(),
            display_name: action.display_name.clone(),
            available: action.available,
            blocked_by: action
                .blockers
                .iter()
                .map(|blocker| blocker.message.clone())
                .collect(),
        })
        .collect()
}

fn derive_planner_state(
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
) -> std::collections::BTreeMap<String, bool> {
    let mut state = std::collections::BTreeMap::new();
    state.insert(
        "on_shift".to_string(),
        blackboard.boolean("schedule.on_shift").unwrap_or(false),
    );
    state.insert(
        "threat_detected".to_string(),
        blackboard.boolean("world.alert_active").unwrap_or(false),
    );
    state.insert(
        "at_home".to_string(),
        blackboard
            .text("anchor.current")
            .zip(blackboard.text("anchor.home"))
            .map(|(left, right)| left == right)
            .unwrap_or(false),
    );
    state.insert(
        "at_duty_area".to_string(),
        blackboard
            .text("anchor.current")
            .zip(blackboard.text("anchor.duty"))
            .map(|(left, right)| left == right)
            .unwrap_or(false),
    );
    state.insert(
        "at_canteen".to_string(),
        blackboard
            .text("anchor.current")
            .zip(blackboard.text("anchor.canteen"))
            .map(|(left, right)| left == right)
            .unwrap_or(false),
    );
    state.insert(
        "at_leisure".to_string(),
        blackboard
            .text("anchor.current")
            .zip(blackboard.text("anchor.leisure"))
            .map(|(left, right)| left == right)
            .unwrap_or(false),
    );
    state.insert(
        "has_reserved_bed".to_string(),
        blackboard
            .boolean("reservation.bed.active")
            .unwrap_or(false),
    );
    state.insert(
        "has_reserved_meal_seat".to_string(),
        blackboard
            .boolean("reservation.meal_object.active")
            .unwrap_or(false),
    );
    for fact in facts {
        state.insert(fact.clone(), true);
    }
    state
}

fn build_blackboard_entries(blackboard: &PreviewBlackboard) -> Vec<AiBlackboardEntryPreview> {
    let mut entries = Vec::new();
    for (key, value) in &blackboard.numbers {
        entries.push(AiBlackboardEntryPreview {
            key: key.clone(),
            value_kind: AiBlackboardValueKind::Number,
            value_text: format!("{value:.2}"),
            source: blackboard_source(key).to_string(),
        });
    }
    for (key, value) in &blackboard.booleans {
        entries.push(AiBlackboardEntryPreview {
            key: key.clone(),
            value_kind: AiBlackboardValueKind::Bool,
            value_text: value.to_string(),
            source: blackboard_source(key).to_string(),
        });
    }
    for (key, value) in &blackboard.texts {
        entries.push(AiBlackboardEntryPreview {
            key: key.clone(),
            value_kind: AiBlackboardValueKind::Text,
            value_text: value.clone(),
            source: blackboard_source(key).to_string(),
        });
    }
    entries.sort_by(|left, right| {
        blackboard_group_rank(&left.key)
            .cmp(&blackboard_group_rank(&right.key))
            .then_with(|| left.key.cmp(&right.key))
    });
    entries
}

fn blackboard_group_rank(key: &str) -> usize {
    match key.split('.').next().unwrap_or_default() {
        "need" => 0,
        "personality" => 1,
        "schedule" => 2,
        "world" => 3,
        "settlement" => 4,
        "availability" => 5,
        "reservation" => 6,
        "anchor" => 7,
        _ => 8,
    }
}

fn blackboard_source(key: &str) -> &'static str {
    match key {
        "need.hunger" | "need.energy" | "need.morale" => "preview context",
        "personality.safety_bias"
        | "personality.social_bias"
        | "personality.duty_bias"
        | "personality.comfort_bias"
        | "personality.alertness_bias" => "resolved personality profile",
        "schedule.on_shift" | "schedule.shift_starting_soon" => "schedule + preview time",
        "schedule.meal_window_open" | "schedule.quiet_hours" => "settlement service rules",
        "world.alert_active" => "preview context",
        "settlement.guard_coverage_insufficient" => "role + guard coverage",
        "availability.guard_post"
        | "availability.meal_object"
        | "availability.leisure_object"
        | "availability.medical_station"
        | "availability.patrol_route"
        | "availability.bed" => "preview availability",
        "reservation.bed.active" | "reservation.meal_object.active" => "preview availability",
        "anchor.current" => "preview context",
        "anchor.home" => "life profile",
        "anchor.duty" | "anchor.canteen" | "anchor.leisure" | "anchor.alarm" => {
            "settlement smart objects"
        }
        _ => "derived",
    }
}

fn evaluate_condition_trace(
    condition: &AiConditionDefinition,
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
    role: NpcRole,
) -> AiConditionTracePreview {
    match condition {
        AiConditionDefinition::ConditionRef { condition_id } => {
            let trace = behavior.conditions.get(condition_id).map(|definition| {
                evaluate_condition_trace(&definition.condition, behavior, facts, blackboard, role)
            });
            let passed = trace.as_ref().map(|trace| trace.passed).unwrap_or(false);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::ConditionRef,
                label: format!("condition_ref {}", condition_id.as_str()),
                passed,
                detail: if trace.is_some() {
                    format!("resolved condition {}", condition_id.as_str())
                } else {
                    format!("missing condition {}", condition_id.as_str())
                },
                children: trace.into_iter().collect(),
            }
        }
        AiConditionDefinition::FactTrue { fact_id } => {
            let passed = facts.contains(fact_id.as_str());
            AiConditionTracePreview {
                kind: AiConditionTraceKind::FactTrue,
                label: format!("fact {}", fact_id.as_str()),
                passed,
                detail: if passed {
                    "fact is present".to_string()
                } else {
                    "fact is absent".to_string()
                },
                children: Vec::new(),
            }
        }
        AiConditionDefinition::BoolEquals { key, value } => {
            let actual = blackboard.boolean(key);
            let passed = actual == Some(*value);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::BoolEquals,
                label: format!("bool {key}"),
                passed,
                detail: format!(
                    "expected {value}, got {}",
                    actual
                        .map(|value| value.to_string())
                        .unwrap_or_else(|| "unresolved".to_string())
                ),
                children: Vec::new(),
            }
        }
        AiConditionDefinition::NumberCompare { key, op, value } => {
            let actual = blackboard.number(key);
            let passed = actual
                .map(|number| compare_number(number, *op, *value))
                .unwrap_or(false);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::NumberCompare,
                label: format!("number {key}"),
                passed,
                detail: format!(
                    "expected {:?} {value}, got {}",
                    op,
                    actual
                        .map(|value| format!("{value:.2}"))
                        .unwrap_or_else(|| "unresolved".to_string())
                ),
                children: Vec::new(),
            }
        }
        AiConditionDefinition::TextEquals { key, value } => {
            let actual = blackboard.text(key);
            let passed = actual.is_some_and(|current| current == value);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::TextEquals,
                label: format!("text {key}"),
                passed,
                detail: format!("expected {value}, got {}", actual.unwrap_or("unresolved")),
                children: Vec::new(),
            }
        }
        AiConditionDefinition::TextKeyEquals {
            left_key,
            right_key,
        } => {
            let left = blackboard.text(left_key);
            let right = blackboard.text(right_key);
            let passed = left
                .zip(right)
                .map(|(left, right)| left == right)
                .unwrap_or(false);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::TextKeyEquals,
                label: format!("text_key {left_key} == {right_key}"),
                passed,
                detail: format!(
                    "left={}, right={}",
                    left.unwrap_or("unresolved"),
                    right.unwrap_or("unresolved")
                ),
                children: Vec::new(),
            }
        }
        AiConditionDefinition::RoleIs {
            role: expected_role,
        } => {
            let passed = *expected_role == role;
            AiConditionTracePreview {
                kind: AiConditionTraceKind::RoleIs,
                label: "role".to_string(),
                passed,
                detail: format!("expected {:?}, got {:?}", expected_role, role),
                children: Vec::new(),
            }
        }
        AiConditionDefinition::AllOf { conditions } => {
            let children = conditions
                .iter()
                .map(|condition| {
                    evaluate_condition_trace(condition, behavior, facts, blackboard, role)
                })
                .collect::<Vec<_>>();
            let passed = children.iter().all(|trace| trace.passed);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::AllOf,
                label: "all_of".to_string(),
                passed,
                detail: format!("{} child conditions", children.len()),
                children,
            }
        }
        AiConditionDefinition::AnyOf { conditions } => {
            let children = conditions
                .iter()
                .map(|condition| {
                    evaluate_condition_trace(condition, behavior, facts, blackboard, role)
                })
                .collect::<Vec<_>>();
            let passed = children.iter().any(|trace| trace.passed);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::AnyOf,
                label: "any_of".to_string(),
                passed,
                detail: format!("{} child conditions", children.len()),
                children,
            }
        }
        AiConditionDefinition::Not { condition } => {
            let child = evaluate_condition_trace(condition, behavior, facts, blackboard, role);
            AiConditionTracePreview {
                kind: AiConditionTraceKind::Not,
                label: "not".to_string(),
                passed: !child.passed,
                detail: "negated child condition".to_string(),
                children: vec![child],
            }
        }
    }
}

fn evaluate_condition(
    condition: &AiConditionDefinition,
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
    role: NpcRole,
) -> bool {
    match condition {
        AiConditionDefinition::ConditionRef { condition_id } => behavior
            .conditions
            .get(condition_id)
            .map(|definition| {
                evaluate_condition(&definition.condition, behavior, facts, blackboard, role)
            })
            .unwrap_or(false),
        AiConditionDefinition::FactTrue { fact_id } => facts.contains(fact_id.as_str()),
        AiConditionDefinition::BoolEquals { key, value } => {
            blackboard.boolean(key).unwrap_or(false) == *value
        }
        AiConditionDefinition::NumberCompare { key, op, value } => blackboard
            .number(key)
            .map(|number| compare_number(number, *op, *value))
            .unwrap_or(false),
        AiConditionDefinition::TextEquals { key, value } => {
            blackboard.text(key).is_some_and(|current| current == value)
        }
        AiConditionDefinition::TextKeyEquals {
            left_key,
            right_key,
        } => blackboard
            .text(left_key)
            .zip(blackboard.text(right_key))
            .map(|(left, right)| left == right)
            .unwrap_or(false),
        AiConditionDefinition::RoleIs {
            role: expected_role,
        } => *expected_role == role,
        AiConditionDefinition::AllOf { conditions } => conditions
            .iter()
            .all(|condition| evaluate_condition(condition, behavior, facts, blackboard, role)),
        AiConditionDefinition::AnyOf { conditions } => conditions
            .iter()
            .any(|condition| evaluate_condition(condition, behavior, facts, blackboard, role)),
        AiConditionDefinition::Not { condition } => {
            !evaluate_condition(condition, behavior, facts, blackboard, role)
        }
    }
}

fn compare_number(left: f32, op: AiComparisonOperator, right: f32) -> bool {
    match op {
        AiComparisonOperator::LessThan => left < right,
        AiComparisonOperator::LessThanOrEqual => left <= right,
        AiComparisonOperator::Equal => (left - right).abs() <= f32::EPSILON,
        AiComparisonOperator::GreaterThanOrEqual => left >= right,
        AiComparisonOperator::GreaterThan => left > right,
    }
}

fn display_name(meta: &AiMetadata, fallback_id: &str) -> String {
    if meta.display_name.trim().is_empty() {
        fallback_id.to_string()
    } else {
        meta.display_name.clone()
    }
}

fn schedule_entry_preview(block: &ScheduleBlock) -> WeeklyScheduleEntryPreview {
    WeeklyScheduleEntryPreview {
        label: block.label.clone(),
        tags: block.tags.clone(),
        days: block.resolved_days(),
        start_minute: block.start_minute,
        end_minute: block.end_minute,
    }
}

fn module_ref(id: &str, meta: &AiMetadata) -> AiPreviewModuleRef {
    AiPreviewModuleRef {
        id: id.to_string(),
        display_name: display_name(meta, id),
        category: meta.category.clone(),
        description: meta.description.clone(),
    }
}

fn active_schedule_block(
    schedule: &[ScheduleBlock],
    day: ScheduleDay,
    minute_of_day: u16,
) -> Option<&ScheduleBlock> {
    schedule.iter().find(|block| {
        block.includes_day(day)
            && minute_of_day >= block.start_minute
            && minute_of_day < block.end_minute
    })
}

fn resolve_first_anchor(
    settlement: Option<&SettlementDefinition>,
    access_profile: &crate::SmartObjectAccessProfileDefinition,
    kind: SmartObjectKind,
) -> Option<String> {
    let settlement = settlement?;
    let rule = access_profile.rules.iter().find(|rule| rule.kind == kind);
    if let Some(rule) = rule {
        if let Some(object) = settlement.smart_objects.iter().find(|object| {
            object.kind == kind
                && rule
                    .preferred_tags
                    .iter()
                    .any(|tag| object.tags.iter().any(|object_tag| object_tag == tag))
        }) {
            return Some(object.anchor_id.clone());
        }
    }
    settlement
        .smart_objects
        .iter()
        .find(|object| object.kind == kind)
        .map(|object| object.anchor_id.clone())
}

fn resolve_anchor_binding(
    settlement: Option<&SettlementDefinition>,
    resolved_life: &ResolvedCharacterLifeProfile,
    binding: AiAnchorBinding,
) -> Option<String> {
    match binding {
        AiAnchorBinding::Home => Some(resolved_life.home_anchor.clone()),
        AiAnchorBinding::Duty => resolve_first_anchor(
            settlement,
            &resolved_life.smart_object_access_profile,
            match resolved_life.role {
                NpcRole::Guard => SmartObjectKind::GuardPost,
                NpcRole::Doctor => SmartObjectKind::MedicalStation,
                NpcRole::Cook => SmartObjectKind::CanteenSeat,
                NpcRole::Resident => SmartObjectKind::Bed,
            },
        ),
        AiAnchorBinding::Canteen => resolve_first_anchor(
            settlement,
            &resolved_life.smart_object_access_profile,
            SmartObjectKind::CanteenSeat,
        ),
        AiAnchorBinding::Leisure => resolve_first_anchor(
            settlement,
            &resolved_life.smart_object_access_profile,
            SmartObjectKind::RecreationSpot,
        ),
        AiAnchorBinding::Alarm => settlement
            .and_then(|settlement| {
                settlement
                    .smart_objects
                    .iter()
                    .find(|object| object.kind == SmartObjectKind::AlarmPoint)
            })
            .map(|object| object.anchor_id.clone()),
    }
}

fn reservation_available(
    reservation: AiReservationBinding,
    context: &CharacterAiPreviewContext,
) -> bool {
    match reservation {
        AiReservationBinding::GuardPost => context.availability.guard_post_available,
        AiReservationBinding::Bed => context.availability.bed_available,
        AiReservationBinding::MealObject => context.availability.meal_object_available,
        AiReservationBinding::LeisureObject => context.availability.leisure_object_available,
        AiReservationBinding::MedicalStation => context.availability.medical_station_available,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    use crate::{
        AiActionDefinition, AiAnchorBinding, AiBehaviorProfileRef, AiConditionId,
        AiConditionModuleDefinition, AiExecutorBindingDefinition, AiExecutorBindingId, AiFactId,
        AiFactModuleDefinition, AiGoalDefinition, AiGoalId, AiMetadata, AiPlannerDatumAssignment,
        AiReservationBinding, AiScoreRuleDefinition, BuiltinAiExecutorKind, GridCoord, MapId,
        PersonalityProfileDefinition, SettlementAnchorDefinition, SettlementDefinition,
        SettlementId, SmartObjectAccessProfileDefinition, SmartObjectAccessRuleDefinition,
        SmartObjectDefinition,
    };

    #[test]
    fn condition_trace_preserves_recursive_structure() {
        let behavior = sample_behavior_profile();
        let mut facts = BTreeSet::new();
        facts.insert("hungry".to_string());
        let blackboard = sample_blackboard();

        let trace = evaluate_condition_trace(
            &AiConditionDefinition::AllOf {
                conditions: vec![
                    AiConditionDefinition::ConditionRef {
                        condition_id: AiConditionId::from("guard_shift"),
                    },
                    AiConditionDefinition::AnyOf {
                        conditions: vec![
                            AiConditionDefinition::FactTrue {
                                fact_id: AiFactId::from("hungry"),
                            },
                            AiConditionDefinition::Not {
                                condition: Box::new(AiConditionDefinition::BoolEquals {
                                    key: "world.alert_active".to_string(),
                                    value: true,
                                }),
                            },
                        ],
                    },
                ],
            },
            &behavior,
            &facts,
            &blackboard,
            NpcRole::Guard,
        );

        assert!(trace.passed);
        assert_eq!(trace.kind, AiConditionTraceKind::AllOf);
        assert_eq!(trace.children.len(), 2);
        assert_eq!(trace.children[0].kind, AiConditionTraceKind::ConditionRef);
        assert_eq!(
            trace.children[0].children[0].kind,
            AiConditionTraceKind::AllOf
        );
        assert_eq!(
            trace.children[0].children[0].children[0].kind,
            AiConditionTraceKind::RoleIs
        );
        assert_eq!(trace.children[1].kind, AiConditionTraceKind::AnyOf);
        assert_eq!(
            trace.children[1].children[0].kind,
            AiConditionTraceKind::FactTrue
        );
        assert_eq!(
            trace.children[1].children[1].kind,
            AiConditionTraceKind::Not
        );
    }

    #[test]
    fn goal_evaluation_uses_multiplier_and_trace() {
        let behavior = sample_behavior_profile();
        let blackboard = sample_blackboard();
        let facts = BTreeSet::from(["hungry".to_string()]);

        let evaluations = evaluate_preview_goals(&behavior, &facts, &blackboard, NpcRole::Guard);
        let goal = evaluations
            .iter()
            .find(|goal| goal.goal_id == "eat_meal")
            .expect("goal evaluation should exist");
        let rule = goal
            .rules
            .iter()
            .find(|rule| rule.rule_id == "rule_hunger")
            .expect("goal rule should exist");

        assert!(rule.matched);
        assert_eq!(rule.multiplier_value, Some(1.5));
        assert_eq!(rule.contributed_score, 6);
        assert!(rule.trace.as_ref().is_some_and(|trace| trace.passed));
        assert_eq!(goal.final_score, 6);
    }

    #[test]
    fn action_evaluation_reports_all_blocker_kinds() {
        let behavior = sample_behavior_profile();
        let resolved_life = sample_resolved_life();
        let settlement = sample_settlement();
        let mut blackboard = sample_blackboard();
        blackboard.set_bool("schedule.on_shift", false);
        let facts = BTreeSet::new();
        let mut context = sample_context();
        context.availability.guard_post_available = false;

        let evaluations = evaluate_preview_actions(
            &behavior,
            &resolved_life,
            Some(&settlement),
            &facts,
            &blackboard,
            &context,
        );
        let action = evaluations
            .iter()
            .find(|action| action.action_id == "guard_action")
            .expect("guard action should exist");

        assert!(!action.available);
        let kinds = action
            .blockers
            .iter()
            .map(|blocker| blocker.kind)
            .collect::<Vec<_>>();
        assert!(kinds.contains(&AiActionBlockerKind::PreconditionMismatch));
        assert!(kinds.contains(&AiActionBlockerKind::PreconditionUnresolved));
        assert!(kinds.contains(&AiActionBlockerKind::MissingTargetAnchor));
        assert!(kinds.contains(&AiActionBlockerKind::ReservationUnavailable));
    }

    #[test]
    fn blackboard_entries_include_expected_diagnostic_keys() {
        let blackboard = build_preview_blackboard(
            &sample_resolved_life(),
            Some(&sample_settlement()),
            &sample_context(),
        );
        let entries = build_blackboard_entries(&blackboard);
        let keys = entries
            .iter()
            .map(|entry| entry.key.as_str())
            .collect::<Vec<_>>();

        assert!(keys.contains(&"schedule.on_shift"));
        assert!(keys.contains(&"schedule.meal_window_open"));
        assert!(keys.contains(&"world.alert_active"));
        assert!(keys.contains(&"settlement.guard_coverage_insufficient"));
        assert!(keys.contains(&"availability.guard_post"));
        assert!(keys.contains(&"availability.bed"));
        assert!(keys.contains(&"anchor.home"));
    }

    fn sample_behavior_profile() -> AiBehaviorProfile {
        let mut conditions = BTreeMap::new();
        conditions.insert(
            AiConditionId::from("guard_shift"),
            AiConditionModuleDefinition {
                id: AiConditionId::from("guard_shift"),
                meta: AiMetadata::default(),
                condition: AiConditionDefinition::AllOf {
                    conditions: vec![
                        AiConditionDefinition::RoleIs {
                            role: NpcRole::Guard,
                        },
                        AiConditionDefinition::BoolEquals {
                            key: "schedule.on_shift".to_string(),
                            value: true,
                        },
                    ],
                },
            },
        );
        AiBehaviorProfile {
            id: AiBehaviorProfileRef::from("test_behavior"),
            meta: AiMetadata::default(),
            facts: vec![AiFactModuleDefinition {
                id: AiFactId::from("hungry"),
                meta: AiMetadata::default(),
                condition: AiConditionDefinition::NumberCompare {
                    key: "need.hunger".to_string(),
                    op: AiComparisonOperator::GreaterThanOrEqual,
                    value: 50.0,
                },
            }],
            goals: vec![AiGoalDefinition {
                id: AiGoalId::from("eat_meal"),
                meta: AiMetadata::default(),
                summary: String::new(),
                preview_examples: Vec::new(),
                failure_hints: Vec::new(),
                score_rule_ids: vec!["rule_hunger".into()],
                planner_requirements: Vec::new(),
                conditional_requirements: Vec::new(),
            }],
            actions: vec![AiActionDefinition {
                id: "guard_action".into(),
                meta: AiMetadata::default(),
                summary: String::new(),
                preview_examples: Vec::new(),
                failure_hints: Vec::new(),
                preconditions: vec![
                    AiPlannerDatumAssignment {
                        key: "on_shift".to_string(),
                        value: true,
                    },
                    AiPlannerDatumAssignment {
                        key: "missing_state".to_string(),
                        value: true,
                    },
                ],
                effects: Vec::new(),
                planner_cost: 1,
                target_anchor: Some(AiAnchorBinding::Leisure),
                reservation_target: Some(AiReservationBinding::GuardPost),
                executor_binding_id: AiExecutorBindingId::from("walk"),
                default_travel_minutes: 5,
                perform_minutes: 10,
                expected_fact_ids: Vec::new(),
                need_effects: Default::default(),
                world_state_effects: Default::default(),
            }],
            score_rules: BTreeMap::from([(
                "rule_hunger".into(),
                AiScoreRuleDefinition {
                    id: "rule_hunger".into(),
                    meta: AiMetadata::default(),
                    when: Some(AiConditionDefinition::FactTrue {
                        fact_id: AiFactId::from("hungry"),
                    }),
                    score_delta: 4,
                    score_multiplier_key: Some("personality.duty_bias".to_string()),
                },
            )]),
            executors: BTreeMap::from([(
                AiExecutorBindingId::from("walk"),
                AiExecutorBindingDefinition {
                    id: AiExecutorBindingId::from("walk"),
                    meta: AiMetadata::default(),
                    kind: BuiltinAiExecutorKind::TravelToAnchor,
                },
            )]),
            conditions,
            default_goal_id: Some(AiGoalId::from("eat_meal")),
            alert_goal_id: None,
        }
    }

    fn sample_blackboard() -> PreviewBlackboard {
        let mut blackboard = PreviewBlackboard::default();
        blackboard.set_number("need.hunger", 60.0);
        blackboard.set_number("personality.duty_bias", 1.5);
        blackboard.set_bool("schedule.on_shift", true);
        blackboard.set_bool("world.alert_active", false);
        blackboard.set_text("anchor.current", "home");
        blackboard.set_text("anchor.home", "home");
        blackboard
    }

    fn sample_resolved_life() -> ResolvedCharacterLifeProfile {
        ResolvedCharacterLifeProfile {
            settlement_id: "settlement_a".to_string(),
            role: NpcRole::Guard,
            ai_behavior_profile_id: "test_behavior".to_string(),
            schedule_profile_id: "schedule_guard".to_string(),
            personality_profile_id: "personality_guard".to_string(),
            need_profile_id: "needs_guard".to_string(),
            smart_object_access_profile_id: "access_guard".to_string(),
            home_anchor: "home_anchor".to_string(),
            duty_route_id: "missing_route".to_string(),
            schedule_blocks: vec![ScheduleBlock {
                day: Some(ScheduleDay::Monday),
                days: Vec::new(),
                start_minute: 8 * 60,
                end_minute: 10 * 60,
                label: "Morning Shift".to_string(),
                tags: vec!["shift".to_string()],
            }],
            need_profile: Default::default(),
            personality_profile: PersonalityProfileDefinition {
                id: "personality_guard".to_string(),
                meta: AiMetadata::default(),
                safety_bias: 1.0,
                social_bias: 1.0,
                duty_bias: 1.5,
                comfort_bias: 1.0,
                alertness_bias: 1.0,
            },
            smart_object_access_profile: SmartObjectAccessProfileDefinition {
                id: "access_guard".to_string(),
                meta: AiMetadata::default(),
                rules: vec![SmartObjectAccessRuleDefinition {
                    kind: crate::SmartObjectKind::GuardPost,
                    preferred_tags: vec!["outer".to_string()],
                    fallback_to_any: true,
                }],
            },
        }
    }

    fn sample_settlement() -> SettlementDefinition {
        SettlementDefinition {
            id: SettlementId("settlement_a".to_string()),
            map_id: MapId("map_a".to_string()),
            anchors: vec![SettlementAnchorDefinition {
                id: "home_anchor".to_string(),
                grid: GridCoord::new(0, 0, 0),
            }],
            routes: Vec::new(),
            smart_objects: vec![
                SmartObjectDefinition {
                    id: "guard_post_1".to_string(),
                    kind: crate::SmartObjectKind::GuardPost,
                    anchor_id: "guard_anchor".to_string(),
                    capacity: 1,
                    tags: vec!["outer".to_string()],
                },
                SmartObjectDefinition {
                    id: "alarm_1".to_string(),
                    kind: crate::SmartObjectKind::AlarmPoint,
                    anchor_id: "alarm_anchor".to_string(),
                    capacity: 1,
                    tags: Vec::new(),
                },
            ],
            service_rules: Default::default(),
        }
    }

    fn sample_context() -> CharacterAiPreviewContext {
        CharacterAiPreviewContext {
            day: ScheduleDay::Monday,
            minute_of_day: 8 * 60 + 15,
            hunger: 70.0,
            energy: 80.0,
            morale: 55.0,
            world_alert_active: false,
            current_anchor: Some("home_anchor".to_string()),
            active_guards: 0,
            min_guard_on_duty: 1,
            availability: AiAvailabilityContext {
                guard_post_available: true,
                meal_object_available: true,
                leisure_object_available: true,
                medical_station_available: true,
                patrol_route_available: false,
                bed_available: true,
            },
        }
    }
}
