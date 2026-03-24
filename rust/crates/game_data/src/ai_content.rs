use std::fmt;

use crate::{
    CharacterDefinition, CharacterId, CharacterLibrary, NpcRole, SettlementDefinition,
    ScheduleDay, SettlementId, SettlementLibrary, SmartObjectKind,
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
) -> Vec<AiContentIssue> {
    let mut issues = Vec::new();

    for (settlement_id, settlement) in settlements.iter() {
        validate_settlement_routes(settlement_id, settlement, &mut issues);
    }

    for (character_id, definition) in characters.iter() {
        validate_character_life_profile(character_id, definition, settlements, &mut issues);
    }

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

    if !settlement.anchors.iter().any(|anchor| anchor.id == life.home_anchor) {
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

    if life.schedule.is_empty() && life.role != NpcRole::Resident {
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
}

fn required_smart_object_kinds(role: NpcRole) -> &'static [SmartObjectKind] {
    match role {
        NpcRole::Resident => &[SmartObjectKind::Bed],
        NpcRole::Guard => &[SmartObjectKind::GuardPost, SmartObjectKind::Bed],
        NpcRole::Cook => &[SmartObjectKind::CanteenSeat, SmartObjectKind::Bed],
        NpcRole::Doctor => &[SmartObjectKind::MedicalStation, SmartObjectKind::Bed],
    }
}

fn validate_guard_coverage(
    characters: &CharacterLibrary,
    settlements: &SettlementLibrary,
    issues: &mut Vec<AiContentIssue>,
) {
    for (settlement_id, settlement) in settlements.iter() {
        for day in [
            ScheduleDay::Monday,
            ScheduleDay::Tuesday,
            ScheduleDay::Wednesday,
            ScheduleDay::Thursday,
            ScheduleDay::Friday,
            ScheduleDay::Saturday,
            ScheduleDay::Sunday,
        ] {
            for minute in (0..24 * 60).step_by(60) {
                let scheduled_guards = characters
                    .iter()
                    .filter_map(|(_, definition)| definition.life.as_ref())
                    .filter(|life| {
                        life.settlement_id == settlement_id.as_str()
                            && life.role == NpcRole::Guard
                            && life.schedule.iter().any(|block| {
                                block.day == day
                                    && block.tags.iter().any(|tag| tag == "shift")
                                    && minute_in_window(minute as u16, block.start_minute, block.end_minute)
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

fn minute_in_window(minute: u16, start_minute: u16, end_minute: u16) -> bool {
    minute >= start_minute && minute < end_minute
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use crate::{
        validate_ai_content, CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate,
        CharacterCombatProfile, CharacterDefinition, CharacterDisposition, CharacterFaction,
        CharacterId, CharacterIdentity, CharacterLibrary, CharacterLifeProfile,
        CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
        CharacterResourcePool, NeedProfile, NpcRole, ScheduleBlock, ScheduleDay,
        ServiceRules, SettlementAnchorDefinition, SettlementDefinition, SettlementId,
        SettlementLibrary, SettlementRouteDefinition, SmartObjectDefinition, SmartObjectKind,
    };

    #[test]
    fn ai_content_validation_reports_missing_doctor_station_and_route() {
        let characters = CharacterLibrary::from(BTreeMap::from([(
            CharacterId("doctor".into()),
            sample_character(
                "doctor",
                Some(CharacterLifeProfile {
                    settlement_id: "safehouse".into(),
                    role: NpcRole::Doctor,
                    home_anchor: "home".into(),
                    duty_route_id: "missing_route".into(),
                    schedule: vec![ScheduleBlock {
                        day: ScheduleDay::Monday,
                        start_minute: 8 * 60,
                        end_minute: 16 * 60,
                        label: "clinic".into(),
                        tags: vec!["shift".into()],
                    }],
                    smart_object_access: vec![],
                    need_profile: NeedProfile::default(),
                }),
            ),
        )]));
        let settlements = SettlementLibrary::from(BTreeMap::from([(
            SettlementId("safehouse".into()),
            SettlementDefinition {
                id: SettlementId("safehouse".into()),
                map_id: crate::MapId("safehouse_grid".into()),
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

        let issues = validate_ai_content(&characters, &settlements);

        assert!(issues.iter().any(|issue| issue.code == "missing_duty_route"));
        assert!(issues.iter().any(|issue| issue.code == "missing_role_object"));
        assert!(issues.iter().any(|issue| issue.code == "route_not_meaningful"));
    }

    #[test]
    fn ai_content_validation_reports_guard_coverage_warnings() {
        let characters = CharacterLibrary::from(BTreeMap::from([(
            CharacterId("guard".into()),
            sample_character(
                "guard",
                Some(CharacterLifeProfile {
                    settlement_id: "safehouse".into(),
                    role: NpcRole::Guard,
                    home_anchor: "guard_home".into(),
                    duty_route_id: "guard_patrol".into(),
                    schedule: vec![ScheduleBlock {
                        day: ScheduleDay::Monday,
                        start_minute: 8 * 60,
                        end_minute: 10 * 60,
                        label: "guard".into(),
                        tags: vec!["shift".into()],
                    }],
                    smart_object_access: vec![],
                    need_profile: NeedProfile::default(),
                }),
            ),
        )]));
        let settlements = SettlementLibrary::from(BTreeMap::from([(
            SettlementId("safehouse".into()),
            SettlementDefinition {
                id: SettlementId("safehouse".into()),
                map_id: crate::MapId("safehouse_grid".into()),
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

        let issues = validate_ai_content(&characters, &settlements);
        assert!(issues
            .iter()
            .any(|issue| issue.code == "guard_coverage_insufficient"));
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
