use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::PathBuf;

use game_data::{
    build_behavior_preview, build_character_ai_preview as build_default_character_ai_preview,
    build_character_ai_preview_at_time as build_shared_character_ai_preview_at_time,
    build_schedule_preview,
    load_ai_module_library, load_settlement_library, validate_ai_content,
    validate_character_definition, AiContentIssue, AiContentIssueSeverity, AiModuleLibrary,
    CharacterAiPreview, CharacterAiPreviewContext, CharacterDefinition,
    CharacterDefinitionValidationError, CharacterLibrary, NpcRole, SettlementDefinition,
    SettlementId, SettlementLibrary, SmartObjectAccessProfilePreview, SmartObjectAccessRulePreview,
    WeeklyScheduleEntryPreview,
};
use serde::{Deserialize, Serialize};

use crate::ValidationIssue;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CharacterWorkspaceCatalogs {
    pub settlement_ids: Vec<String>,
    pub roles: Vec<String>,
    pub behavior_profile_ids: Vec<String>,
    pub personality_profile_ids: Vec<String>,
    pub schedule_profile_ids: Vec<String>,
    pub need_profile_ids: Vec<String>,
    pub smart_object_access_profile_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettlementReferenceSummary {
    pub id: String,
    pub map_id: String,
    pub anchor_ids: Vec<String>,
    pub route_ids: Vec<String>,
    pub smart_objects: Vec<String>,
    pub min_guard_on_duty: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleProfileReferenceSummary {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub entries: Vec<WeeklyScheduleEntryPreview>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PersonalityProfileReferenceSummary {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub safety_bias: f32,
    pub social_bias: f32,
    pub duty_bias: f32,
    pub comfort_bias: f32,
    pub alertness_bias: f32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NeedProfileReferenceSummary {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub hunger_decay_per_hour: f32,
    pub energy_decay_per_hour: f32,
    pub morale_decay_per_hour: f32,
    pub safety_bias: f32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CharacterWorkspaceReferences {
    pub settlements: Vec<SettlementReferenceSummary>,
    pub behaviors: Vec<game_data::AiBehaviorPreview>,
    pub schedules: Vec<ScheduleProfileReferenceSummary>,
    pub personalities: Vec<PersonalityProfileReferenceSummary>,
    pub needs: Vec<NeedProfileReferenceSummary>,
    pub smart_object_access: Vec<SmartObjectAccessProfilePreview>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CharacterDocumentSummary {
    pub document_key: String,
    pub character_id: String,
    pub display_name: String,
    pub file_name: String,
    pub relative_path: String,
    pub settlement_id: String,
    pub role: String,
    pub behavior_profile_id: String,
    pub character: Option<CharacterDefinition>,
    pub validation: Vec<ValidationIssue>,
    pub preview_context: Option<CharacterAiPreviewContext>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CharacterWorkspacePayload {
    pub bootstrap: crate::EditorBootstrap,
    pub data_directory: String,
    pub character_count: usize,
    pub catalogs: CharacterWorkspaceCatalogs,
    pub references: CharacterWorkspaceReferences,
    pub documents: Vec<CharacterDocumentSummary>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CharacterAiPreviewRequest {
    pub character_id: String,
    pub context: CharacterAiPreviewContext,
}

#[derive(Debug, Clone)]
struct CharacterDocumentSource {
    file_name: String,
    relative_path: String,
    raw: String,
}

#[derive(Debug, Clone)]
struct ParsedCharacterDocument {
    document_key: String,
    character_id: String,
    display_name: String,
    settlement_id: String,
    role: String,
    behavior_profile_id: String,
    file_name: String,
    relative_path: String,
    character: Option<CharacterDefinition>,
    validation: Vec<ValidationIssue>,
    preview_context: Option<CharacterAiPreviewContext>,
}

#[tauri::command]
pub fn load_character_workspace() -> Result<CharacterWorkspacePayload, String> {
    let bootstrap = crate::editor_bootstrap()?;
    let sources = load_character_document_sources()?;
    let mut warnings = Vec::new();

    let ai_library = match load_ai_library() {
        Ok(library) => Some(library),
        Err(error) => {
            warnings.push(format!("AI library unavailable: {error}"));
            None
        }
    };
    let settlements = match load_settlements() {
        Ok(library) => Some(library),
        Err(error) => {
            warnings.push(format!("Settlement library unavailable: {error}"));
            None
        }
    };

    let mut documents = sources
        .iter()
        .map(parse_character_document)
        .collect::<Vec<_>>();
    let duplicate_ids = duplicate_character_ids(&documents);
    for document in &mut documents {
        if duplicate_ids.contains(&document.character_id) && !document.character_id.trim().is_empty() {
            document.validation.push(crate::document_error(
                "id",
                format!("duplicate character id {}", document.character_id),
            ));
        }
    }

    let ai_issue_map = if let (Some(ai_library), Some(settlements)) = (&ai_library, &settlements) {
        collect_ai_issue_map(&documents, settlements, ai_library)
    } else {
        BTreeMap::new()
    };

    for document in &mut documents {
        if let Some(issues) = ai_issue_map.get(&document.character_id) {
            document.validation.extend(issues.clone());
        }

        if document
            .validation
            .iter()
            .any(|issue| issue.severity == "error")
        {
            continue;
        }

        let Some(character) = &document.character else {
            continue;
        };
        let Some(ai_library) = &ai_library else {
            continue;
        };
        let settlement = settlement_for_character(character, settlements.as_ref());
        document.preview_context = build_default_character_ai_preview(character, settlement, ai_library)
            .map(|preview| preview.context)
            .ok();
    }

    let catalogs = collect_character_catalogs(&documents);
    let references = if let (Some(ai_library), Some(settlements)) = (&ai_library, &settlements) {
        collect_reference_payload(ai_library, settlements)
    } else {
        CharacterWorkspaceReferences {
            settlements: Vec::new(),
            behaviors: Vec::new(),
            schedules: Vec::new(),
            personalities: Vec::new(),
            needs: Vec::new(),
            smart_object_access: Vec::new(),
        }
    };
    documents.sort_by(|left, right| {
        left.display_name
            .cmp(&right.display_name)
            .then_with(|| left.character_id.cmp(&right.character_id))
            .then_with(|| left.file_name.cmp(&right.file_name))
    });

    Ok(CharacterWorkspacePayload {
        bootstrap,
        data_directory: crate::to_forward_slashes(crate::character_data_dir()?),
        character_count: documents.len(),
        catalogs,
        references,
        documents: documents
            .into_iter()
            .map(|document| CharacterDocumentSummary {
                document_key: document.document_key,
                character_id: document.character_id,
                display_name: document.display_name,
                file_name: document.file_name,
                relative_path: document.relative_path,
                settlement_id: document.settlement_id,
                role: document.role,
                behavior_profile_id: document.behavior_profile_id,
                character: document.character,
                validation: document.validation,
                preview_context: document.preview_context,
            })
            .collect(),
        warnings,
    })
}

fn collect_reference_payload(
    ai_library: &AiModuleLibrary,
    settlements: &SettlementLibrary,
) -> CharacterWorkspaceReferences {
    let mut settlement_refs = settlements
        .iter()
        .map(|(_, settlement)| SettlementReferenceSummary {
            id: settlement.id.as_str().to_string(),
            map_id: settlement.map_id.as_str().to_string(),
            anchor_ids: settlement.anchors.iter().map(|anchor| anchor.id.clone()).collect(),
            route_ids: settlement.routes.iter().map(|route| route.id.clone()).collect(),
            smart_objects: settlement
                .smart_objects
                .iter()
                .map(|object| format!("{} · {} @ {}", smart_object_kind_key(object.kind), object.id, object.anchor_id))
                .collect(),
            min_guard_on_duty: settlement.service_rules.min_guard_on_duty,
        })
        .collect::<Vec<_>>();
    settlement_refs.sort_by(|left, right| left.id.cmp(&right.id));

    let mut behavior_refs = ai_library
        .behaviors
        .keys()
        .filter_map(|id| build_behavior_preview(ai_library, id.as_str()).ok())
        .collect::<Vec<_>>();
    behavior_refs.sort_by(|left, right| left.display_name.cmp(&right.display_name).then_with(|| left.id.cmp(&right.id)));

    let mut schedule_refs = ai_library
        .schedule_templates
        .values()
        .map(|template| ScheduleProfileReferenceSummary {
            id: template.id.clone(),
            display_name: display_name(&template.meta.display_name, &template.id),
            description: template.meta.description.clone(),
            entries: build_schedule_preview(&game_data::ResolvedCharacterLifeProfile {
                settlement_id: String::new(),
                role: NpcRole::Resident,
                ai_behavior_profile_id: String::new(),
                schedule_profile_id: template.id.clone(),
                personality_profile_id: String::new(),
                need_profile_id: String::new(),
                smart_object_access_profile_id: String::new(),
                home_anchor: String::new(),
                duty_route_id: String::new(),
                schedule_blocks: template.blocks.clone(),
                need_profile: game_data::NeedProfile::default(),
                personality_profile: game_data::PersonalityProfileDefinition::default(),
                smart_object_access_profile: game_data::SmartObjectAccessProfileDefinition::default(),
            })
            .entries,
        })
        .collect::<Vec<_>>();
    schedule_refs.sort_by(|left, right| left.display_name.cmp(&right.display_name).then_with(|| left.id.cmp(&right.id)));

    let mut personality_refs = ai_library
        .personality_profiles
        .values()
        .map(|profile| PersonalityProfileReferenceSummary {
            id: profile.id.clone(),
            display_name: display_name(&profile.meta.display_name, &profile.id),
            description: profile.meta.description.clone(),
            safety_bias: profile.safety_bias,
            social_bias: profile.social_bias,
            duty_bias: profile.duty_bias,
            comfort_bias: profile.comfort_bias,
            alertness_bias: profile.alertness_bias,
        })
        .collect::<Vec<_>>();
    personality_refs.sort_by(|left, right| left.display_name.cmp(&right.display_name).then_with(|| left.id.cmp(&right.id)));

    let mut need_refs = ai_library
        .need_profiles
        .values()
        .map(|profile| NeedProfileReferenceSummary {
            id: profile.id.clone(),
            display_name: display_name(&profile.meta.display_name, &profile.id),
            description: profile.meta.description.clone(),
            hunger_decay_per_hour: profile.profile.hunger_decay_per_hour,
            energy_decay_per_hour: profile.profile.energy_decay_per_hour,
            morale_decay_per_hour: profile.profile.morale_decay_per_hour,
            safety_bias: profile.profile.safety_bias,
        })
        .collect::<Vec<_>>();
    need_refs.sort_by(|left, right| left.display_name.cmp(&right.display_name).then_with(|| left.id.cmp(&right.id)));

    let mut access_refs = ai_library
        .smart_object_access_profiles
        .values()
        .map(|profile| SmartObjectAccessProfilePreview {
            id: profile.id.clone(),
            display_name: display_name(&profile.meta.display_name, &profile.id),
            description: profile.meta.description.clone(),
            rules: profile
                .rules
                .iter()
                .map(|rule| SmartObjectAccessRulePreview {
                    kind: rule.kind,
                    preferred_tags: rule.preferred_tags.clone(),
                    fallback_to_any: rule.fallback_to_any,
                })
                .collect(),
        })
        .collect::<Vec<_>>();
    access_refs.sort_by(|left, right| left.display_name.cmp(&right.display_name).then_with(|| left.id.cmp(&right.id)));

    CharacterWorkspaceReferences {
        settlements: settlement_refs,
        behaviors: behavior_refs,
        schedules: schedule_refs,
        personalities: personality_refs,
        needs: need_refs,
        smart_object_access: access_refs,
    }
}

#[tauri::command]
pub fn build_character_ai_preview(
    request: CharacterAiPreviewRequest,
) -> Result<CharacterAiPreview, String> {
    let character = load_character_definition_by_id(&request.character_id)?
        .ok_or_else(|| format!("character {} not found", request.character_id))?;
    validate_character_definition(&character)
        .map_err(|error| format!("character {} is invalid: {error}", request.character_id))?;

    let ai_library = load_ai_library()?;
    let settlements = load_settlements()?;
    let settlement = settlement_for_character(&character, Some(&settlements));
    build_shared_character_ai_preview_at_time(&character, settlement, &ai_library, &request.context)
        .map_err(|error| format!("failed to build character AI preview: {error}"))
}

fn load_character_document_sources() -> Result<Vec<CharacterDocumentSource>, String> {
    let data_dir = crate::character_data_dir()?;
    if !data_dir.exists() {
        return Ok(Vec::new());
    }

    let mut entries = fs::read_dir(&data_dir)
        .map_err(|error| format!("failed to read {}: {error}", data_dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate character directory: {error}"))?;
    entries.sort_by_key(|entry| entry.file_name());

    let mut sources = Vec::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        sources.push(CharacterDocumentSource {
            file_name,
            relative_path: crate::relative_to_repo(&path)?,
            raw,
        });
    }
    Ok(sources)
}

fn parse_character_document(source: &CharacterDocumentSource) -> ParsedCharacterDocument {
    let file_stem = PathBuf::from(&source.file_name)
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string();

    let value = match serde_json::from_str::<serde_json::Value>(&source.raw) {
        Ok(value) => value,
        Err(error) => {
            return ParsedCharacterDocument {
                document_key: source.file_name.clone(),
                character_id: file_stem.clone(),
                display_name: file_stem,
                settlement_id: String::new(),
                role: String::new(),
                behavior_profile_id: String::new(),
                file_name: source.file_name.clone(),
                relative_path: source.relative_path.clone(),
                character: None,
                validation: vec![crate::document_error(
                    "file",
                    format!("failed to parse JSON: {error}"),
                )],
                preview_context: None,
            };
        }
    };

    let character_id = value
        .get("id")
        .and_then(|raw| raw.as_str())
        .unwrap_or(file_stem.as_str())
        .to_string();
    let display_name = value
        .get("identity")
        .and_then(|identity| identity.get("display_name"))
        .and_then(|raw| raw.as_str())
        .unwrap_or(character_id.as_str())
        .to_string();

    let character = match serde_json::from_value::<CharacterDefinition>(value) {
        Ok(character) => character,
        Err(error) => {
            return ParsedCharacterDocument {
                document_key: character_id.clone(),
                character_id: character_id.clone(),
                display_name,
                settlement_id: String::new(),
                role: String::new(),
                behavior_profile_id: String::new(),
                file_name: source.file_name.clone(),
                relative_path: source.relative_path.clone(),
                character: None,
                validation: vec![crate::document_error(
                    "file",
                    format!("failed to decode character schema: {error}"),
                )],
                preview_context: None,
            };
        }
    };

    let mut validation = Vec::new();
    if let Err(error) = validate_character_definition(&character) {
        validation.push(map_character_validation_error(error));
    }

    let (settlement_id, role, behavior_profile_id) = if let Some(life) = &character.life {
        (
            life.settlement_id.clone(),
            role_key(life.role).to_string(),
            life.ai_behavior_profile_id.clone(),
        )
    } else {
        (String::new(), String::new(), String::new())
    };

    ParsedCharacterDocument {
        document_key: character_id.clone(),
        character_id,
        display_name,
        settlement_id,
        role,
        behavior_profile_id,
        file_name: source.file_name.clone(),
        relative_path: source.relative_path.clone(),
        character: Some(character),
        validation,
        preview_context: None,
    }
}

fn duplicate_character_ids(documents: &[ParsedCharacterDocument]) -> BTreeSet<String> {
    let mut counts = BTreeMap::<String, usize>::new();
    for document in documents {
        if document.character_id.trim().is_empty() {
            continue;
        }
        *counts.entry(document.character_id.clone()).or_default() += 1;
    }
    counts
        .into_iter()
        .filter_map(|(id, count)| (count > 1).then_some(id))
        .collect()
}

fn collect_ai_issue_map(
    documents: &[ParsedCharacterDocument],
    settlements: &SettlementLibrary,
    ai_library: &AiModuleLibrary,
) -> BTreeMap<String, Vec<ValidationIssue>> {
    let character_library = CharacterLibrary::from(
        documents
            .iter()
            .filter(|document| {
                !document.character_id.trim().is_empty()
                    && !document.validation.iter().any(|issue| issue.severity == "error")
            })
            .filter_map(|document| {
                document
                    .character
                    .clone()
                    .map(|character| (character.id.clone(), character))
            })
            .collect::<BTreeMap<_, _>>(),
    );

    let mut issues_by_character = BTreeMap::<String, Vec<ValidationIssue>>::new();
    for issue in validate_ai_content(&character_library, settlements, ai_library) {
        if let Some(character_id) = issue.character_id.clone() {
            issues_by_character
                .entry(character_id)
                .or_default()
                .push(map_ai_content_issue(issue));
        }
    }
    issues_by_character
}

fn collect_character_catalogs(documents: &[ParsedCharacterDocument]) -> CharacterWorkspaceCatalogs {
    let mut settlement_ids = BTreeSet::new();
    let mut roles = BTreeSet::new();
    let mut behavior_profile_ids = BTreeSet::new();
    let mut personality_profile_ids = BTreeSet::new();
    let mut schedule_profile_ids = BTreeSet::new();
    let mut need_profile_ids = BTreeSet::new();
    let mut smart_object_access_profile_ids = BTreeSet::new();

    for document in documents {
        let Some(character) = &document.character else {
            continue;
        };
        let Some(life) = &character.life else {
            continue;
        };
        if !life.settlement_id.trim().is_empty() {
            settlement_ids.insert(life.settlement_id.clone());
        }
        roles.insert(role_key(life.role).to_string());
        if !life.ai_behavior_profile_id.trim().is_empty() {
            behavior_profile_ids.insert(life.ai_behavior_profile_id.clone());
        }
        if !life.personality_profile_id.trim().is_empty() {
            personality_profile_ids.insert(life.personality_profile_id.clone());
        }
        if !life.schedule_profile_id.trim().is_empty() {
            schedule_profile_ids.insert(life.schedule_profile_id.clone());
        }
        if !life.need_profile_id.trim().is_empty() {
            need_profile_ids.insert(life.need_profile_id.clone());
        }
        if !life.smart_object_access_profile_id.trim().is_empty() {
            smart_object_access_profile_ids.insert(life.smart_object_access_profile_id.clone());
        }
    }

    CharacterWorkspaceCatalogs {
        settlement_ids: settlement_ids.into_iter().collect(),
        roles: roles.into_iter().collect(),
        behavior_profile_ids: behavior_profile_ids.into_iter().collect(),
        personality_profile_ids: personality_profile_ids.into_iter().collect(),
        schedule_profile_ids: schedule_profile_ids.into_iter().collect(),
        need_profile_ids: need_profile_ids.into_iter().collect(),
        smart_object_access_profile_ids: smart_object_access_profile_ids.into_iter().collect(),
    }
}

fn load_character_definition_by_id(character_id: &str) -> Result<Option<CharacterDefinition>, String> {
    for source in load_character_document_sources()? {
        let parsed = parse_character_document(&source);
        if parsed.character_id == character_id {
            return Ok(parsed.character);
        }
    }
    Ok(None)
}

fn settlement_for_character<'a>(
    character: &CharacterDefinition,
    settlements: Option<&'a SettlementLibrary>,
) -> Option<&'a SettlementDefinition> {
    let life = character.life.as_ref()?;
    settlements?.get(&SettlementId(life.settlement_id.clone()))
}

fn load_ai_library() -> Result<AiModuleLibrary, String> {
    let data_dir = crate::repo_root()?.join("data").join("ai");
    load_ai_module_library(&data_dir)
        .map_err(|error| format!("failed to load AI library from {}: {error}", data_dir.display()))
}

fn load_settlements() -> Result<SettlementLibrary, String> {
    let data_dir = crate::repo_root()?.join("data").join("settlements");
    load_settlement_library(&data_dir).map_err(|error| {
        format!(
            "failed to load settlement library from {}: {error}",
            data_dir.display()
        )
    })
}

fn role_key(role: NpcRole) -> &'static str {
    match role {
        NpcRole::Resident => "resident",
        NpcRole::Guard => "guard",
        NpcRole::Cook => "cook",
        NpcRole::Doctor => "doctor",
    }
}

fn map_character_validation_error(error: CharacterDefinitionValidationError) -> ValidationIssue {
    match error {
        CharacterDefinitionValidationError::MissingId => {
            crate::document_error("id", "character id must not be empty")
        }
        CharacterDefinitionValidationError::MissingCampId => {
            crate::document_error("faction.camp_id", "faction camp_id must not be empty")
        }
        CharacterDefinitionValidationError::MissingLifeSettlementId => {
            crate::document_error("life.settlement_id", "life settlement_id must not be empty")
        }
        CharacterDefinitionValidationError::MissingLifeAiBehaviorProfileId => crate::document_error(
            "life.ai_behavior_profile_id",
            "life ai_behavior_profile_id must not be empty",
        ),
        CharacterDefinitionValidationError::MissingLifeScheduleProfileId => crate::document_error(
            "life.schedule_profile_id",
            "life schedule_profile_id must not be empty",
        ),
        CharacterDefinitionValidationError::MissingLifePersonalityProfileId => crate::document_error(
            "life.personality_profile_id",
            "life personality_profile_id must not be empty",
        ),
        CharacterDefinitionValidationError::MissingLifeNeedProfileId => crate::document_error(
            "life.need_profile_id",
            "life need_profile_id must not be empty",
        ),
        CharacterDefinitionValidationError::MissingLifeSmartObjectAccessProfileId => crate::document_error(
            "life.smart_object_access_profile_id",
            "life smart_object_access_profile_id must not be empty",
        ),
        CharacterDefinitionValidationError::MissingLifeHomeAnchor => {
            crate::document_error("life.home_anchor", "life home_anchor must not be empty")
        }
        CharacterDefinitionValidationError::MissingScheduleDays { index } => crate::document_error(
            "life.schedule",
            format!("life schedule block {index} must define day or days"),
        ),
        CharacterDefinitionValidationError::InvalidScheduleWindow {
            index,
            start_minute,
            end_minute,
        } => crate::document_error(
            "life.schedule",
            format!("life schedule block {index} has invalid window {start_minute}..{end_minute}"),
        ),
        other => crate::document_error("character", other.to_string()),
    }
}

fn map_ai_content_issue(issue: AiContentIssue) -> ValidationIssue {
    ValidationIssue {
        severity: match issue.severity {
            AiContentIssueSeverity::Error => "error".to_string(),
            AiContentIssueSeverity::Warning => "warning".to_string(),
        },
        field: issue.code.to_string(),
        message: issue.message,
        scope: Some("document".to_string()),
        node_id: None,
        edge_key: None,
        path: None,
    }
}

fn display_name(display_name: &str, fallback_id: &str) -> String {
    if display_name.trim().is_empty() {
        fallback_id.to_string()
    } else {
        display_name.to_string()
    }
}

fn smart_object_kind_key(kind: game_data::SmartObjectKind) -> &'static str {
    match kind {
        game_data::SmartObjectKind::GuardPost => "guard_post",
        game_data::SmartObjectKind::Bed => "bed",
        game_data::SmartObjectKind::CanteenSeat => "canteen_seat",
        game_data::SmartObjectKind::RecreationSpot => "recreation_spot",
        game_data::SmartObjectKind::MedicalStation => "medical_station",
        game_data::SmartObjectKind::AlarmPoint => "alarm_point",
    }
}
