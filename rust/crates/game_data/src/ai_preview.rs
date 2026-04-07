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
    let facts = rebuild_preview_facts(&behavior, &blackboard, resolved_life.role);
    let fact_ids = facts
        .iter()
        .map(|fact| fact.id.as_str().to_string())
        .collect::<Vec<_>>();
    let fact_set = fact_ids.iter().cloned().collect::<BTreeSet<_>>();
    let goal_scores = score_preview_goals(&behavior, &fact_set, &blackboard, resolved_life.role);
    let available_actions = preview_action_availability(
        &behavior,
        &resolved_life,
        settlement,
        &fact_set,
        &blackboard,
        context,
    );
    let current_schedule_entry = active_schedule_block(
        &resolved_life.schedule_blocks,
        context.day,
        context.minute_of_day,
    )
    .map(schedule_entry_preview);

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
            current_schedule_entry,
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

fn score_preview_goals(
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
    role: NpcRole,
) -> Vec<AiGoalScorePreview> {
    behavior
        .goals
        .iter()
        .map(|goal| {
            let mut score = 0;
            let mut matched_rule_ids = Vec::new();
            for rule_id in &goal.score_rule_ids {
                let Some(rule) = behavior.score_rules.get(rule_id) else {
                    continue;
                };
                let matched = rule
                    .when
                    .as_ref()
                    .map(|condition| {
                        evaluate_condition(condition, behavior, facts, blackboard, role)
                    })
                    .unwrap_or(true);
                if matched {
                    let multiplier = rule
                        .score_multiplier_key
                        .as_deref()
                        .and_then(|key| blackboard.number(key))
                        .unwrap_or(1.0);
                    score += ((rule.score_delta as f32) * multiplier).round() as i32;
                    matched_rule_ids.push(rule.id.as_str().to_string());
                }
            }
            AiGoalScorePreview {
                goal_id: goal.id.as_str().to_string(),
                display_name: display_name(&goal.meta, goal.id.as_str()),
                score,
                matched_rule_ids,
            }
        })
        .collect()
}

fn preview_action_availability(
    behavior: &AiBehaviorProfile,
    resolved_life: &ResolvedCharacterLifeProfile,
    settlement: Option<&SettlementDefinition>,
    facts: &BTreeSet<String>,
    blackboard: &PreviewBlackboard,
    context: &CharacterAiPreviewContext,
) -> Vec<AiActionAvailabilityPreview> {
    let planner_state = derive_planner_state(facts, blackboard);
    behavior
        .actions
        .iter()
        .map(|action| {
            let mut blocked_by = Vec::new();
            for requirement in &action.preconditions {
                match planner_state.get(&requirement.key) {
                    Some(value) if *value == requirement.value => {}
                    Some(value) => blocked_by.push(format!(
                        "precondition {} expected {}, got {}",
                        requirement.key, requirement.value, value
                    )),
                    None => {
                        blocked_by.push(format!("precondition {} is unresolved", requirement.key))
                    }
                }
            }
            if let Some(anchor) = action.target_anchor.clone() {
                if resolve_anchor_binding(settlement, resolved_life, anchor.clone()).is_none() {
                    blocked_by.push(format!("missing target anchor {:?}", anchor));
                }
            }
            if let Some(reservation) = action.reservation_target.clone() {
                if !reservation_available(reservation.clone(), context) {
                    blocked_by.push(format!("reservation {:?} unavailable", reservation));
                }
            }
            AiActionAvailabilityPreview {
                action_id: action.id.as_str().to_string(),
                display_name: display_name(&action.meta, action.id.as_str()),
                available: blocked_by.is_empty(),
                blocked_by,
            }
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
