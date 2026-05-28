use std::collections::BTreeSet;
use std::fmt;

use crate::{
    resolve_ai_behavior_profile, resolve_character_life_profile, AiMetadata, AiModuleLibrary,
    CharacterDefinition, CharacterId, CharacterLibrary, NpcRole, ScheduleBlock, ScheduleDay,
    SettlementDefinition, SettlementId, SettlementLibrary, SmartObjectKind,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiContentIssueSeverity {
    Error,
    Warning,
}

impl fmt::Display for AiContentIssueSeverity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Error => f.write_str("error"),
            Self::Warning => f.write_str("warning"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AiContentIssue {
    pub severity: AiContentIssueSeverity,
    pub code: &'static str,
    pub settlement_id: Option<String>,
    pub character_id: Option<String>,
    pub message: String,
}

impl AiContentIssue {
    fn error(
        code: &'static str,
        settlement_id: Option<String>,
        character_id: Option<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            severity: AiContentIssueSeverity::Error,
            code,
            settlement_id,
            character_id,
            message: message.into(),
        }
    }

    fn warning(
        code: &'static str,
        settlement_id: Option<String>,
        character_id: Option<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            severity: AiContentIssueSeverity::Warning,
            code,
            settlement_id,
            character_id,
            message: message.into(),
        }
    }
}

pub fn validate_ai_content(
    characters: &CharacterLibrary,
    settlements: &SettlementLibrary,
    ai_library: &AiModuleLibrary,
) -> Vec<AiContentIssue> {
    let mut issues = Vec::new();

    validate_ai_metadata(ai_library, &mut issues);
    for (settlement_id, settlement) in settlements.iter() {
        validate_settlement_routes(settlement_id, settlement, &mut issues);
    }

    for (character_id, definition) in characters.iter() {
        validate_character_life_profile(
            character_id,
            definition,
            settlements,
            ai_library,
            &mut issues,
        );
    }

    validate_unused_ai_modules(ai_library, &mut issues);
    validate_behavior_reachability(ai_library, &mut issues);
    validate_guard_coverage(characters, settlements, &mut issues);
    issues
}

fn validate_settlement_routes(
    settlement_id: &SettlementId,
    settlement: &SettlementDefinition,
    issues: &mut Vec<AiContentIssue>,
) {
    for route in &settlement.routes {
        let unique_anchor_count = route
            .anchors
            .iter()
            .map(|anchor| anchor.as_str())
            .collect::<std::collections::BTreeSet<_>>()
            .len();
        if unique_anchor_count < 2 {
            issues.push(AiContentIssue::warning(
                "route_not_meaningful",
                Some(settlement_id.as_str().to_string()),
                None,
                format!(
                    "route {} does not form a meaningful traversal chain",
                    route.id
                ),
            ));
        }
    }
}

fn validate_character_life_profile(
    character_id: &CharacterId,
    definition: &CharacterDefinition,
    settlements: &SettlementLibrary,
    ai_library: &AiModuleLibrary,
    issues: &mut Vec<AiContentIssue>,
) {
    let Some(life) = &definition.life else {
        return;
    };

    let settlement_id = life.settlement_id.clone();
    let Some(settlement) = settlements.get(&SettlementId(settlement_id.clone())) else {
        issues.push(AiContentIssue::error(
            "missing_settlement",
            Some(settlement_id),
            Some(character_id.as_str().to_string()),
            format!(
                "character {} references missing settlement {}",
                character_id, life.settlement_id
            ),
        ));
        return;
    };

    let Ok(resolved_life) = resolve_character_life_profile(life, ai_library) else {
        issues.push(AiContentIssue::error(
            "invalid_life_profile_reference",
            Some(settlement.id.as_str().to_string()),
            Some(character_id.as_str().to_string()),
            format!(
                "character {} references invalid life profile ids: schedule={}, personality={}, need={}, access={}",
                character_id,
                life.schedule_profile_id,
                life.personality_profile_id,
                life.need_profile_id,
                life.smart_object_access_profile_id
            ),
        ));
        return;
    };

    if !settlement
        .anchors
        .iter()
        .any(|anchor| anchor.id == life.home_anchor)
    {
        issues.push(AiContentIssue::error(
            "missing_home_anchor",
            Some(settlement.id.as_str().to_string()),
            Some(character_id.as_str().to_string()),
            format!(
                "character {} home_anchor {} is not present in settlement {}",
                character_id, life.home_anchor, settlement.id
            ),
        ));
    }

    if !life.duty_route_id.trim().is_empty()
        && !settlement
            .routes
            .iter()
            .any(|route| route.id == life.duty_route_id)
    {
        issues.push(AiContentIssue::error(
            "missing_duty_route",
            Some(settlement.id.as_str().to_string()),
            Some(character_id.as_str().to_string()),
            format!(
                "character {} duty_route_id {} is not present in settlement {}",
                character_id, life.duty_route_id, settlement.id
            ),
        ));
    }

    if resolved_life.schedule_blocks.is_empty() && life.role != NpcRole::Resident {
        issues.push(AiContentIssue::warning(
            "empty_schedule",
            Some(settlement.id.as_str().to_string()),
            Some(character_id.as_str().to_string()),
            format!(
                "character {} has no life schedule for role {:?}",
                character_id, life.role
            ),
        ));
    }

    validate_schedule_blocks(
        character_id,
        settlement.id.as_str(),
        &resolved_life.schedule_blocks,
        issues,
    );

    for required_kind in required_smart_object_kinds(life.role) {
        if !settlement
            .smart_objects
            .iter()
            .any(|object| object.kind == *required_kind)
        {
            issues.push(AiContentIssue::warning(
                "missing_role_object",
                Some(settlement.id.as_str().to_string()),
                Some(character_id.as_str().to_string()),
                format!(
                    "character {} role {:?} has no {:?} available in settlement {}",
                    character_id, life.role, required_kind, settlement.id
                ),
            ));
        }
    }

    for rule in &resolved_life.smart_object_access_profile.rules {
        if !settlement
            .smart_objects
            .iter()
            .any(|object| object.kind == rule.kind)
        {
            issues.push(AiContentIssue::warning(
                "missing_access_profile_object",
                Some(settlement.id.as_str().to_string()),
                Some(character_id.as_str().to_string()),
                format!(
                    "character {} access profile {} expects {:?} but settlement {} has none",
                    character_id,
                    resolved_life.smart_object_access_profile.id,
                    rule.kind,
                    settlement.id
                ),
            ));
        }
    }

    if !settlement
        .smart_objects
        .iter()
        .any(|object| object.kind == SmartObjectKind::RecreationSpot)
    {
        issues.push(AiContentIssue::warning(
            "missing_recreation_spot",
            Some(settlement.id.as_str().to_string()),
            Some(character_id.as_str().to_string()),
            format!(
                "settlement {} has no recreation spot for morale recovery",
                settlement.id
            ),
        ));
    }

    if resolve_ai_behavior_profile(ai_library, &life.ai_behavior_profile_id.clone().into()).is_err()
    {
        issues.push(AiContentIssue::error(
            "missing_ai_behavior_profile",
            Some(settlement.id.as_str().to_string()),
            Some(character_id.as_str().to_string()),
            format!(
                "character {} ai_behavior_profile_id {} is not present in AI content",
                character_id, life.ai_behavior_profile_id
            ),
        ));
    }
}

fn required_smart_object_kinds(role: NpcRole) -> &'static [SmartObjectKind] {
    match role {
        NpcRole::Resident => &[SmartObjectKind::Bed],
        NpcRole::Guard => &[SmartObjectKind::GuardPost, SmartObjectKind::Bed],
        NpcRole::Cook => &[SmartObjectKind::CanteenSeat, SmartObjectKind::Bed],
        NpcRole::Doctor => &[SmartObjectKind::MedicalStation, SmartObjectKind::Bed],
    }
}

fn validate_schedule_blocks(
    character_id: &CharacterId,
    settlement_id: &str,
    blocks: &[ScheduleBlock],
    issues: &mut Vec<AiContentIssue>,
) {
    for day in all_schedule_days() {
        let mut day_blocks = blocks
            .iter()
            .filter(|block| block.includes_day(day))
            .collect::<Vec<_>>();
        day_blocks.sort_by_key(|block| (block.start_minute, block.end_minute));

        for pair in day_blocks.windows(2) {
            let current = pair[0];
            let next = pair[1];
            if current.end_minute > next.start_minute {
                issues.push(AiContentIssue::warning(
                    "schedule_overlap",
                    Some(settlement_id.to_string()),
                    Some(character_id.as_str().to_string()),
                    format!(
                        "character {} has overlapping schedule blocks on {:?}: {} and {}",
                        character_id, day, current.label, next.label
                    ),
                ));
            } else if current.end_minute == next.start_minute
                && current.label == next.label
                && current.tags == next.tags
            {
                issues.push(AiContentIssue::warning(
                    "schedule_redundant_split",
                    Some(settlement_id.to_string()),
                    Some(character_id.as_str().to_string()),
                    format!(
                        "character {} splits identical adjacent schedule blocks on {:?}: {}",
                        character_id, day, current.label
                    ),
                ));
            }
        }
    }
}

fn all_schedule_days() -> [ScheduleDay; 7] {
    [
        ScheduleDay::Monday,
        ScheduleDay::Tuesday,
        ScheduleDay::Wednesday,
        ScheduleDay::Thursday,
        ScheduleDay::Friday,
        ScheduleDay::Saturday,
        ScheduleDay::Sunday,
    ]
}

fn validate_guard_coverage(
    characters: &CharacterLibrary,
    settlements: &SettlementLibrary,
    issues: &mut Vec<AiContentIssue>,
) {
    for (settlement_id, settlement) in settlements.iter() {
        for day in all_schedule_days() {
            for minute in (0..24 * 60).step_by(60) {
                let scheduled_guards = characters
                    .iter()
                    .filter_map(|(_, definition)| definition.life.as_ref())
                    .filter(|life| {
                        life.settlement_id == settlement_id.as_str()
                            && life.role == NpcRole::Guard
                            && life.schedule.iter().any(|block| {
                                block.includes_day(day)
                                    && block.tags.iter().any(|tag| tag == "shift")
                                    && minute_in_window(
                                        minute as u16,
                                        block.start_minute,
                                        block.end_minute,
                                    )
                            })
                    })
                    .count() as u32;

                if scheduled_guards > 0
                    && scheduled_guards < settlement.service_rules.min_guard_on_duty
                {
                    issues.push(AiContentIssue::warning(
                        "guard_coverage_insufficient",
                        Some(settlement_id.as_str().to_string()),
                        None,
                        format!(
                            "settlement {} has only {} guards scheduled on {:?} at {:02}:00, below min_guard_on_duty={}",
                            settlement_id,
                            scheduled_guards,
                            day,
                            minute / 60,
                            settlement.service_rules.min_guard_on_duty
                        ),
                    ));
                }
            }
        }
    }
}

fn validate_ai_metadata(ai_library: &AiModuleLibrary, issues: &mut Vec<AiContentIssue>) {
    for behavior in ai_library.behaviors.values() {
        validate_metadata_presence("behavior", behavior.id.as_str(), &behavior.meta, issues);
    }
}

fn validate_metadata_presence(
    domain: &'static str,
    id: &str,
    meta: &AiMetadata,
    issues: &mut Vec<AiContentIssue>,
) {
    if meta.display_name.trim().is_empty() {
        issues.push(AiContentIssue::warning(
            "missing_metadata_display_name",
            None,
            None,
            format!("{domain} {id} is missing meta.display_name"),
        ));
    }
    if meta.category.trim().is_empty() {
        issues.push(AiContentIssue::warning(
            "missing_metadata_category",
            None,
            None,
            format!("{domain} {id} is missing meta.category"),
        ));
    }
}

fn validate_unused_ai_modules(ai_library: &AiModuleLibrary, issues: &mut Vec<AiContentIssue>) {
    let mut used_facts = BTreeSet::new();
    let mut used_goals = BTreeSet::new();
    let mut used_actions = BTreeSet::new();
    let mut used_score_rules = BTreeSet::new();
    let mut used_executors = BTreeSet::new();

    for behavior in ai_library.behaviors.values() {
        if let Ok(profile) = resolve_ai_behavior_profile(ai_library, &behavior.id) {
            for fact in &profile.facts {
                used_facts.insert(fact.id.as_str().to_string());
            }
            for goal in &profile.goals {
                used_goals.insert(goal.id.as_str().to_string());
                for rule_id in &goal.score_rule_ids {
                    used_score_rules.insert(rule_id.as_str().to_string());
                }
            }
            for action in &profile.actions {
                used_actions.insert(action.id.as_str().to_string());
                used_executors.insert(action.executor_binding_id.as_str().to_string());
            }
        }
    }

    for fact_id in ai_library.facts.keys() {
        if !used_facts.contains(fact_id.as_str()) {
            issues.push(AiContentIssue::warning(
                "unused_fact",
                None,
                None,
                format!(
                    "fact {} is not referenced by any resolved behavior",
                    fact_id
                ),
            ));
        }
    }
    for goal_id in ai_library.goals.keys() {
        if !used_goals.contains(goal_id.as_str()) {
            issues.push(AiContentIssue::warning(
                "unused_goal",
                None,
                None,
                format!(
                    "goal {} is not referenced by any resolved behavior",
                    goal_id
                ),
            ));
        }
    }
    for action_id in ai_library.actions.keys() {
        if !used_actions.contains(action_id.as_str()) {
            issues.push(AiContentIssue::warning(
                "unused_action",
                None,
                None,
                format!(
                    "action {} is not referenced by any resolved behavior",
                    action_id
                ),
            ));
        }
    }
    for rule_id in ai_library.score_rules.keys() {
        if !used_score_rules.contains(rule_id.as_str()) {
            issues.push(AiContentIssue::warning(
                "unused_score_rule",
                None,
                None,
                format!(
                    "score rule {} is not referenced by any resolved behavior",
                    rule_id
                ),
            ));
        }
    }
    for executor_id in ai_library.executors.keys() {
        if !used_executors.contains(executor_id.as_str()) {
            issues.push(AiContentIssue::warning(
                "unused_executor",
                None,
                None,
                format!(
                    "executor binding {} is not referenced by any resolved behavior",
                    executor_id
                ),
            ));
        }
    }
}

fn validate_behavior_reachability(ai_library: &AiModuleLibrary, issues: &mut Vec<AiContentIssue>) {
    for behavior in ai_library.behaviors.values() {
        let Ok(profile) = resolve_ai_behavior_profile(ai_library, &behavior.id) else {
            continue;
        };
        let produced = profile
            .actions
            .iter()
            .flat_map(|action| action.effects.iter())
            .map(|effect| (effect.key.clone(), effect.value))
            .collect::<BTreeSet<_>>();

        for goal in &profile.goals {
            let requirements = goal
                .planner_requirements
                .iter()
                .map(|requirement| (requirement.key.clone(), requirement.value))
                .collect::<BTreeSet<_>>();
            if !requirements.is_empty() && requirements.intersection(&produced).next().is_none() {
                issues.push(AiContentIssue::warning(
                    "goal_unreachable",
                    None,
                    None,
                    format!(
                        "behavior {} goal {} has planner requirements that are not produced by any action",
                        behavior.id, goal.id
                    ),
                ));
            }
        }

        let initially_known = profile
            .facts
            .iter()
            .map(|fact| fact.id.as_str().to_string())
            .collect::<BTreeSet<_>>();
        for action in &profile.actions {
            let impossible = action.preconditions.iter().all(|requirement| {
                !initially_known.contains(&requirement.key)
                    && !produced.contains(&(requirement.key.clone(), requirement.value))
            });
            if impossible && !action.preconditions.is_empty() {
                issues.push(AiContentIssue::warning(
                    "action_unreachable",
                    None,
                    None,
                    format!(
                        "behavior {} action {} has preconditions that are never seeded or produced",
                        behavior.id, action.id
                    ),
                ));
            }
        }
    }
}

fn minute_in_window(minute: u16, start_minute: u16, end_minute: u16) -> bool {
    minute >= start_minute && minute < end_minute
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use crate::{
        validate_ai_content, AiBehaviorDefinition, AiBehaviorProfileRef, AiMetadata,
        AiModuleLibrary, CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate,
        CharacterCombatProfile, CharacterDefinition, CharacterDisposition, CharacterFaction,
        CharacterId, CharacterIdentity, CharacterLibrary, CharacterLifeProfile,
        CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
        CharacterResourcePool, NeedProfile, NpcRole, PersonalityProfileOverride, ScheduleBlock,
        ScheduleDay, ScheduleTemplateDefinition, ServiceRules, SettlementAnchorDefinition,
        SettlementDefinition, SettlementId, SettlementLibrary, SettlementRouteDefinition,
        SmartObjectAccessProfileDefinition, SmartObjectDefinition, SmartObjectKind,
    };

    #[test]
    fn ai_content_validation_reports_missing_doctor_station_and_route() {
        let characters = CharacterLibrary::from(BTreeMap::from([(
            CharacterId("doctor".into()),
            sample_character(
                "doctor",
                Some(CharacterLifeProfile {
                    settlement_id: "survivor_outpost_01_settlement".into(),
                    role: NpcRole::Doctor,
                    ai_behavior_profile_id: "doctor_settlement".into(),
                    schedule_profile_id: "doctor_schedule".into(),
                    personality_profile_id: "doctor_personality".into(),
                    need_profile_id: "doctor_need".into(),
                    smart_object_access_profile_id: "doctor_access".into(),
                    home_anchor: "home".into(),
                    duty_route_id: "missing_route".into(),
                    schedule: vec![ScheduleBlock {
                        day: Some(ScheduleDay::Monday),
                        days: Vec::new(),
                        start_minute: 8 * 60,
                        end_minute: 16 * 60,
                        label: "clinic".into(),
                        tags: vec!["shift".into()],
                    }],
                    need_profile_override: None,
                    personality_override: PersonalityProfileOverride::default(),
                }),
            ),
        )]));
        let settlements = SettlementLibrary::from(BTreeMap::from([(
            SettlementId("survivor_outpost_01_settlement".into()),
            SettlementDefinition {
                id: SettlementId("survivor_outpost_01_settlement".into()),
                map_id: crate::MapId("survivor_outpost_01".into()),
                anchors: vec![SettlementAnchorDefinition {
                    id: "home".into(),
                    grid: crate::GridCoord::new(1, 0, 1),
                }],
                routes: vec![SettlementRouteDefinition {
                    id: "idle_loop".into(),
                    anchors: vec!["home".into()],
                }],
                smart_objects: vec![SmartObjectDefinition {
                    id: "doctor_bed".into(),
                    kind: SmartObjectKind::Bed,
                    anchor_id: "home".into(),
                    capacity: 1,
                    tags: vec!["doctor".into()],
                }],
                service_rules: ServiceRules::default(),
            },
        )]));

        let issues = validate_ai_content(&characters, &settlements, &sample_ai_library());

        assert!(issues
            .iter()
            .any(|issue| issue.code == "missing_duty_route"));
        assert!(issues
            .iter()
            .any(|issue| issue.code == "missing_role_object"));
        assert!(issues
            .iter()
            .any(|issue| issue.code == "route_not_meaningful"));
    }

    #[test]
    fn ai_content_validation_reports_guard_coverage_warnings() {
        let characters = CharacterLibrary::from(BTreeMap::from([(
            CharacterId("guard".into()),
            sample_character(
                "guard",
                Some(CharacterLifeProfile {
                    settlement_id: "survivor_outpost_01_settlement".into(),
                    role: NpcRole::Guard,
                    ai_behavior_profile_id: "guard_settlement".into(),
                    schedule_profile_id: "guard_schedule".into(),
                    personality_profile_id: "guard_personality".into(),
                    need_profile_id: "guard_need".into(),
                    smart_object_access_profile_id: "guard_access".into(),
                    home_anchor: "guard_home".into(),
                    duty_route_id: "guard_patrol".into(),
                    schedule: vec![ScheduleBlock {
                        day: Some(ScheduleDay::Monday),
                        days: Vec::new(),
                        start_minute: 8 * 60,
                        end_minute: 10 * 60,
                        label: "guard".into(),
                        tags: vec!["shift".into()],
                    }],
                    need_profile_override: None,
                    personality_override: PersonalityProfileOverride::default(),
                }),
            ),
        )]));
        let settlements = SettlementLibrary::from(BTreeMap::from([(
            SettlementId("survivor_outpost_01_settlement".into()),
            SettlementDefinition {
                id: SettlementId("survivor_outpost_01_settlement".into()),
                map_id: crate::MapId("survivor_outpost_01".into()),
                anchors: vec![
                    SettlementAnchorDefinition {
                        id: "guard_home".into(),
                        grid: crate::GridCoord::new(1, 0, 1),
                    },
                    SettlementAnchorDefinition {
                        id: "north_gate".into(),
                        grid: crate::GridCoord::new(5, 0, 1),
                    },
                ],
                routes: vec![SettlementRouteDefinition {
                    id: "guard_patrol".into(),
                    anchors: vec!["guard_home".into(), "north_gate".into()],
                }],
                smart_objects: vec![
                    SmartObjectDefinition {
                        id: "guard_bed".into(),
                        kind: SmartObjectKind::Bed,
                        anchor_id: "guard_home".into(),
                        capacity: 1,
                        tags: vec!["guard".into()],
                    },
                    SmartObjectDefinition {
                        id: "guard_post".into(),
                        kind: SmartObjectKind::GuardPost,
                        anchor_id: "north_gate".into(),
                        capacity: 1,
                        tags: vec!["guard".into()],
                    },
                    SmartObjectDefinition {
                        id: "bench".into(),
                        kind: SmartObjectKind::RecreationSpot,
                        anchor_id: "guard_home".into(),
                        capacity: 1,
                        tags: vec!["guard".into()],
                    },
                ],
                service_rules: ServiceRules {
                    min_guard_on_duty: 2,
                    ..ServiceRules::default()
                },
            },
        )]));

        let issues = validate_ai_content(&characters, &settlements, &sample_ai_library());
        assert!(issues
            .iter()
            .any(|issue| issue.code == "guard_coverage_insufficient"));
    }

    fn sample_ai_library() -> AiModuleLibrary {
        let mut library = AiModuleLibrary::default();
        library.behaviors.insert(
            AiBehaviorProfileRef::from("doctor_settlement"),
            AiBehaviorDefinition {
                id: AiBehaviorProfileRef::from("doctor_settlement"),
                meta: AiMetadata::default(),
                included_behavior_ids: Vec::new(),
                fact_group_ids: Vec::new(),
                fact_ids: Vec::new(),
                goal_group_ids: Vec::new(),
                goal_ids: Vec::new(),
                action_group_ids: Vec::new(),
                action_ids: Vec::new(),
                default_goal_id: None,
                alert_goal_id: None,
            },
        );
        library.behaviors.insert(
            AiBehaviorProfileRef::from("guard_settlement"),
            AiBehaviorDefinition {
                id: AiBehaviorProfileRef::from("guard_settlement"),
                meta: AiMetadata::default(),
                included_behavior_ids: Vec::new(),
                fact_group_ids: Vec::new(),
                fact_ids: Vec::new(),
                goal_group_ids: Vec::new(),
                goal_ids: Vec::new(),
                action_group_ids: Vec::new(),
                action_ids: Vec::new(),
                default_goal_id: None,
                alert_goal_id: None,
            },
        );
        library.schedule_templates.insert(
            "doctor_schedule".into(),
            ScheduleTemplateDefinition {
                id: "doctor_schedule".into(),
                meta: AiMetadata::default(),
                blocks: Vec::new(),
            },
        );
        library.schedule_templates.insert(
            "guard_schedule".into(),
            ScheduleTemplateDefinition {
                id: "guard_schedule".into(),
                meta: AiMetadata::default(),
                blocks: Vec::new(),
            },
        );
        library.need_profiles.insert(
            "doctor_need".into(),
            crate::NeedProfileDefinition {
                id: "doctor_need".into(),
                meta: AiMetadata::default(),
                profile: NeedProfile::default(),
            },
        );
        library.need_profiles.insert(
            "guard_need".into(),
            crate::NeedProfileDefinition {
                id: "guard_need".into(),
                meta: AiMetadata::default(),
                profile: NeedProfile::default(),
            },
        );
        library.personality_profiles.insert(
            "doctor_personality".into(),
            crate::PersonalityProfileDefinition {
                id: "doctor_personality".into(),
                meta: AiMetadata::default(),
                ..Default::default()
            },
        );
        library.personality_profiles.insert(
            "guard_personality".into(),
            crate::PersonalityProfileDefinition {
                id: "guard_personality".into(),
                meta: AiMetadata::default(),
                ..Default::default()
            },
        );
        library.smart_object_access_profiles.insert(
            "doctor_access".into(),
            SmartObjectAccessProfileDefinition {
                id: "doctor_access".into(),
                meta: AiMetadata::default(),
                rules: vec![crate::SmartObjectAccessRuleDefinition {
                    kind: SmartObjectKind::MedicalStation,
                    preferred_tags: vec!["doctor".into()],
                    fallback_to_any: true,
                }],
            },
        );
        library.smart_object_access_profiles.insert(
            "guard_access".into(),
            SmartObjectAccessProfileDefinition {
                id: "guard_access".into(),
                meta: AiMetadata::default(),
                rules: vec![crate::SmartObjectAccessRuleDefinition {
                    kind: SmartObjectKind::GuardPost,
                    preferred_tags: vec!["guard".into()],
                    fallback_to_any: true,
                }],
            },
        );
        library
    }

    fn sample_character(id: &str, life: Option<CharacterLifeProfile>) -> CharacterDefinition {
        CharacterDefinition {
            id: CharacterId(id.to_string()),
            archetype: CharacterArchetype::Npc,
            identity: CharacterIdentity {
                display_name: id.to_string(),
                description: String::new(),
            },
            faction: CharacterFaction {
                camp_id: "survivor".to_string(),
                disposition: CharacterDisposition::Friendly,
            },
            presentation: CharacterPresentation {
                portrait_path: String::new(),
                avatar_path: String::new(),
                model_path: String::new(),
                placeholder_colors: CharacterPlaceholderColors {
                    head: "#ffffff".to_string(),
                    body: "#cccccc".to_string(),
                    legs: "#999999".to_string(),
                },
            },
            appearance_profile_id: String::new(),
            progression: CharacterProgression { level: 1 },
            combat: CharacterCombatProfile {
                behavior: "neutral".to_string(),
                xp_reward: 1,
                loot: Vec::new(),
            },
            ai: CharacterAiProfile {
                aggro_range: 0.0,
                attack_range: 1.0,
                wander_radius: 1.0,
                leash_distance: 2.0,
                decision_interval: 0.5,
                attack_cooldown: 1.0,
            },
            attributes: CharacterAttributeTemplate {
                sets: BTreeMap::from([(
                    "base".to_string(),
                    BTreeMap::from([("strength".to_string(), 1.0)]),
                )]),
                resources: BTreeMap::from([(
                    "hp".to_string(),
                    CharacterResourcePool { current: 10.0 },
                )]),
            },
            interaction: None,
            life,
        }
    }
}
