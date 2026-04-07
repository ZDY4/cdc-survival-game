use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::interaction::CharacterInteractionProfile;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct CharacterId(pub String);

impl CharacterId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for CharacterId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CharacterArchetype {
    Player,
    Npc,
    Enemy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CharacterDisposition {
    Player,
    Friendly,
    Hostile,
    Neutral,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum NpcRole {
    #[default]
    Resident,
    Guard,
    Cook,
    Doctor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ScheduleDay {
    #[default]
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,
}

impl ScheduleDay {
    pub const fn next(self) -> Self {
        match self {
            Self::Monday => Self::Tuesday,
            Self::Tuesday => Self::Wednesday,
            Self::Wednesday => Self::Thursday,
            Self::Thursday => Self::Friday,
            Self::Friday => Self::Saturday,
            Self::Saturday => Self::Sunday,
            Self::Sunday => Self::Monday,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScheduleBlock {
    #[serde(default)]
    pub day: Option<ScheduleDay>,
    #[serde(default)]
    pub days: Vec<ScheduleDay>,
    pub start_minute: u16,
    pub end_minute: u16,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub tags: Vec<String>,
}

impl ScheduleBlock {
    pub fn resolved_days(&self) -> Vec<ScheduleDay> {
        if !self.days.is_empty() {
            self.days.clone()
        } else {
            self.day.into_iter().collect()
        }
    }

    pub fn includes_day(&self, day: ScheduleDay) -> bool {
        self.resolved_days()
            .into_iter()
            .any(|candidate| candidate == day)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NeedProfile {
    #[serde(default = "default_hunger_decay_per_hour")]
    pub hunger_decay_per_hour: f32,
    #[serde(default = "default_energy_decay_per_hour")]
    pub energy_decay_per_hour: f32,
    #[serde(default = "default_morale_decay_per_hour")]
    pub morale_decay_per_hour: f32,
    #[serde(default = "default_safety_bias")]
    pub safety_bias: f32,
}

impl Default for NeedProfile {
    fn default() -> Self {
        Self {
            hunger_decay_per_hour: default_hunger_decay_per_hour(),
            energy_decay_per_hour: default_energy_decay_per_hour(),
            morale_decay_per_hour: default_morale_decay_per_hour(),
            safety_bias: default_safety_bias(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct PersonalityProfileOverride {
    #[serde(default)]
    pub safety_bias: Option<f32>,
    #[serde(default)]
    pub social_bias: Option<f32>,
    #[serde(default)]
    pub duty_bias: Option<f32>,
    #[serde(default)]
    pub comfort_bias: Option<f32>,
    #[serde(default)]
    pub alertness_bias: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterLifeProfile {
    pub settlement_id: String,
    pub role: NpcRole,
    pub ai_behavior_profile_id: String,
    pub schedule_profile_id: String,
    pub personality_profile_id: String,
    pub need_profile_id: String,
    pub smart_object_access_profile_id: String,
    pub home_anchor: String,
    #[serde(default)]
    pub duty_route_id: String,
    #[serde(default)]
    pub schedule: Vec<ScheduleBlock>,
    #[serde(default)]
    pub need_profile_override: Option<NeedProfile>,
    #[serde(default)]
    pub personality_override: PersonalityProfileOverride,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterDefinition {
    pub id: CharacterId,
    pub archetype: CharacterArchetype,
    pub identity: CharacterIdentity,
    pub faction: CharacterFaction,
    pub presentation: CharacterPresentation,
    pub progression: CharacterProgression,
    pub combat: CharacterCombatProfile,
    pub ai: CharacterAiProfile,
    pub attributes: CharacterAttributeTemplate,
    #[serde(default)]
    pub interaction: Option<CharacterInteractionProfile>,
    #[serde(default)]
    pub life: Option<CharacterLifeProfile>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterIdentity {
    pub display_name: String,
    #[serde(default)]
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterFaction {
    pub camp_id: String,
    pub disposition: CharacterDisposition,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterPresentation {
    #[serde(default)]
    pub portrait_path: String,
    #[serde(default)]
    pub avatar_path: String,
    #[serde(default)]
    pub model_path: String,
    pub placeholder_colors: CharacterPlaceholderColors,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterPlaceholderColors {
    pub head: String,
    pub body: String,
    pub legs: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CharacterProgression {
    pub level: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterCombatProfile {
    pub behavior: String,
    pub xp_reward: i32,
    #[serde(default)]
    pub loot: Vec<CharacterLootEntry>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterAiProfile {
    pub aggro_range: f32,
    pub attack_range: f32,
    pub wander_radius: f32,
    pub leash_distance: f32,
    pub decision_interval: f32,
    pub attack_cooldown: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterLootEntry {
    pub item_id: u32,
    pub chance: f32,
    pub min: i32,
    pub max: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterAttributeTemplate {
    #[serde(default)]
    pub sets: BTreeMap<String, BTreeMap<String, f32>>,
    #[serde(default)]
    pub resources: BTreeMap<String, CharacterResourcePool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterResourcePool {
    pub current: f32,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct CharacterLibrary {
    definitions: BTreeMap<CharacterId, CharacterDefinition>,
}

impl From<BTreeMap<CharacterId, CharacterDefinition>> for CharacterLibrary {
    fn from(definitions: BTreeMap<CharacterId, CharacterDefinition>) -> Self {
        Self { definitions }
    }
}

impl CharacterLibrary {
    pub fn get(&self, id: &CharacterId) -> Option<&CharacterDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&CharacterId, &CharacterDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }
}

#[derive(Debug, Error)]
pub enum CharacterLoadError {
    #[error("failed to read character definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read character definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse character definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("character definition file {path} is invalid: {source}")]
    InvalidDefinition {
        path: PathBuf,
        #[source]
        source: CharacterDefinitionValidationError,
    },
    #[error(
        "duplicate character id {id} found in {duplicate_path} (first declared in {first_path})"
    )]
    DuplicateId {
        id: CharacterId,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

#[derive(Debug, Clone, Error, PartialEq)]
pub enum CharacterDefinitionValidationError {
    #[error("character id must not be empty")]
    MissingId,
    #[error("faction camp_id must not be empty")]
    MissingCampId,
    #[error("progression level must be >= 1, got {level}")]
    InvalidLevel { level: u32 },
    #[error("combat xp_reward must be >= 0, got {xp_reward}")]
    InvalidXpReward { xp_reward: i32 },
    #[error("loot entry for item {item_id} has invalid chance {chance}")]
    InvalidLootChance { item_id: u32, chance: f32 },
    #[error("ai field {field} must be >= 0, got {value}")]
    InvalidAiValue { field: &'static str, value: f32 },
    #[error("player archetype must use player disposition, got {disposition:?}")]
    InvalidPlayerDisposition { disposition: CharacterDisposition },
    #[error("life settlement_id must not be empty")]
    MissingLifeSettlementId,
    #[error("life ai_behavior_profile_id must not be empty")]
    MissingLifeAiBehaviorProfileId,
    #[error("life schedule_profile_id must not be empty")]
    MissingLifeScheduleProfileId,
    #[error("life personality_profile_id must not be empty")]
    MissingLifePersonalityProfileId,
    #[error("life need_profile_id must not be empty")]
    MissingLifeNeedProfileId,
    #[error("life smart_object_access_profile_id must not be empty")]
    MissingLifeSmartObjectAccessProfileId,
    #[error("life home_anchor must not be empty")]
    MissingLifeHomeAnchor,
    #[error("life schedule block {index} must define day or days")]
    MissingScheduleDays { index: usize },
    #[error("life schedule block {index} has invalid window {start_minute}..{end_minute}")]
    InvalidScheduleWindow {
        index: usize,
        start_minute: u16,
        end_minute: u16,
    },
    #[error("life need_profile field {field} must be >= 0, got {value}")]
    InvalidNeedValue { field: &'static str, value: f32 },
}

pub fn validate_character_definition(
    definition: &CharacterDefinition,
) -> Result<(), CharacterDefinitionValidationError> {
    if definition.id.as_str().trim().is_empty() {
        return Err(CharacterDefinitionValidationError::MissingId);
    }
    if definition.faction.camp_id.trim().is_empty() {
        return Err(CharacterDefinitionValidationError::MissingCampId);
    }
    if definition.progression.level < 1 {
        return Err(CharacterDefinitionValidationError::InvalidLevel {
            level: definition.progression.level,
        });
    }
    if definition.combat.xp_reward < 0 {
        return Err(CharacterDefinitionValidationError::InvalidXpReward {
            xp_reward: definition.combat.xp_reward,
        });
    }
    for loot in &definition.combat.loot {
        if !(0.0..=1.0).contains(&loot.chance) {
            return Err(CharacterDefinitionValidationError::InvalidLootChance {
                item_id: loot.item_id,
                chance: loot.chance,
            });
        }
    }
    validate_ai_value("aggro_range", definition.ai.aggro_range)?;
    validate_ai_value("attack_range", definition.ai.attack_range)?;
    validate_ai_value("wander_radius", definition.ai.wander_radius)?;
    validate_ai_value("leash_distance", definition.ai.leash_distance)?;
    validate_ai_value("decision_interval", definition.ai.decision_interval)?;
    validate_ai_value("attack_cooldown", definition.ai.attack_cooldown)?;

    if definition.archetype == CharacterArchetype::Player
        && definition.faction.disposition != CharacterDisposition::Player
    {
        return Err(
            CharacterDefinitionValidationError::InvalidPlayerDisposition {
                disposition: definition.faction.disposition,
            },
        );
    }

    if let Some(life) = &definition.life {
        if life.settlement_id.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifeSettlementId);
        }
        if life.ai_behavior_profile_id.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifeAiBehaviorProfileId);
        }
        if life.schedule_profile_id.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifeScheduleProfileId);
        }
        if life.personality_profile_id.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifePersonalityProfileId);
        }
        if life.need_profile_id.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifeNeedProfileId);
        }
        if life.smart_object_access_profile_id.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifeSmartObjectAccessProfileId);
        }
        if life.home_anchor.trim().is_empty() {
            return Err(CharacterDefinitionValidationError::MissingLifeHomeAnchor);
        }
        if let Some(need_profile) = &life.need_profile_override {
            validate_non_negative_need(
                "hunger_decay_per_hour",
                need_profile.hunger_decay_per_hour,
            )?;
            validate_non_negative_need(
                "energy_decay_per_hour",
                need_profile.energy_decay_per_hour,
            )?;
            validate_non_negative_need(
                "morale_decay_per_hour",
                need_profile.morale_decay_per_hour,
            )?;
            validate_non_negative_need("safety_bias", need_profile.safety_bias)?;
        }
        validate_optional_non_negative_need("safety_bias", life.personality_override.safety_bias)?;
        validate_optional_non_negative_need("social_bias", life.personality_override.social_bias)?;
        validate_optional_non_negative_need("duty_bias", life.personality_override.duty_bias)?;
        validate_optional_non_negative_need(
            "comfort_bias",
            life.personality_override.comfort_bias,
        )?;
        validate_optional_non_negative_need(
            "alertness_bias",
            life.personality_override.alertness_bias,
        )?;

        for (index, block) in life.schedule.iter().enumerate() {
            if block.day.is_none() && block.days.is_empty() {
                return Err(CharacterDefinitionValidationError::MissingScheduleDays { index });
            }
            if block.start_minute >= block.end_minute || block.end_minute > 24 * 60 {
                return Err(CharacterDefinitionValidationError::InvalidScheduleWindow {
                    index,
                    start_minute: block.start_minute,
                    end_minute: block.end_minute,
                });
            }
        }
    }

    Ok(())
}

pub fn load_character_library(
    dir: impl AsRef<Path>,
) -> Result<CharacterLibrary, CharacterLoadError> {
    let dir = dir.as_ref();
    let mut file_paths = Vec::new();
    let entries = fs::read_dir(dir).map_err(|source| CharacterLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    for entry in entries {
        let entry = entry.map_err(|source| CharacterLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.is_file() && path.extension().is_some_and(|ext| ext == "json") {
            file_paths.push(path);
        }
    }
    file_paths.sort();

    let mut definitions = BTreeMap::new();
    let mut source_paths = BTreeMap::<CharacterId, PathBuf>::new();

    for path in file_paths {
        let json = fs::read_to_string(&path).map_err(|source| CharacterLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let definition: CharacterDefinition =
            serde_json::from_str(&json).map_err(|source| CharacterLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;

        validate_character_definition(&definition).map_err(|source| {
            CharacterLoadError::InvalidDefinition {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = source_paths.insert(definition.id.clone(), path.clone()) {
            return Err(CharacterLoadError::DuplicateId {
                id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }

        definitions.insert(definition.id.clone(), definition);
    }

    Ok(CharacterLibrary { definitions })
}

fn validate_ai_value(
    field: &'static str,
    value: f32,
) -> Result<(), CharacterDefinitionValidationError> {
    if value < 0.0 {
        Err(CharacterDefinitionValidationError::InvalidAiValue { field, value })
    } else {
        Ok(())
    }
}

fn validate_non_negative_need(
    field: &'static str,
    value: f32,
) -> Result<(), CharacterDefinitionValidationError> {
    if value < 0.0 {
        Err(CharacterDefinitionValidationError::InvalidNeedValue { field, value })
    } else {
        Ok(())
    }
}

fn validate_optional_non_negative_need(
    field: &'static str,
    value: Option<f32>,
) -> Result<(), CharacterDefinitionValidationError> {
    if let Some(value) = value {
        validate_non_negative_need(field, value)?;
    }
    Ok(())
}

const fn default_hunger_decay_per_hour() -> f32 {
    4.0
}

const fn default_energy_decay_per_hour() -> f32 {
    3.0
}

const fn default_morale_decay_per_hour() -> f32 {
    1.5
}

const fn default_safety_bias() -> f32 {
    0.5
}

#[cfg(test)]
mod tests {
    use super::{
        load_character_library, validate_character_definition, CharacterAiProfile,
        CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDefinitionValidationError, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLootEntry, CharacterPlaceholderColors, CharacterPresentation,
        CharacterProgression, CharacterResourcePool,
    };
    use crate::character::CharacterDisposition;
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn character_definition_deserializes_successfully() {
        let raw = r##"{
            "id": "doctor_chen",
            "archetype": "npc",
            "identity": { "display_name": "陈医生", "description": "..." },
            "faction": { "camp_id": "survivor", "disposition": "friendly" },
            "presentation": {
                "portrait_path": "res://assets/portraits/doctor.png",
                "avatar_path": "",
                "model_path": "",
                "placeholder_colors": {
                    "head": "#eecba0",
                    "body": "#6a9add",
                    "legs": "#3c5c90"
                }
            },
            "progression": { "level": 6 },
            "combat": { "behavior": "neutral", "xp_reward": 30, "loot": [] },
            "ai": {
                "aggro_range": 0.0,
                "attack_range": 1.2,
                "wander_radius": 3.0,
                "leash_distance": 5.0,
                "decision_interval": 1.2,
                "attack_cooldown": 999.0
            },
            "attributes": {
                "sets": { "base": { "strength": 5.0 } },
                "resources": { "hp": { "current": 60.0 } }
            }
        }"##;

        let definition: CharacterDefinition = serde_json::from_str(raw).expect("should parse");

        assert_eq!(definition.id.as_str(), "doctor_chen");
        assert_eq!(
            definition.faction.disposition,
            CharacterDisposition::Friendly
        );
        assert_eq!(definition.combat.xp_reward, 30);
    }

    #[test]
    fn duplicate_character_ids_are_rejected() {
        let temp_dir = create_temp_dir("duplicate_ids");
        let one = temp_dir.join("one.json");
        let two = temp_dir.join("two.json");
        fs::write(&one, sample_json("shared_id", "npc", "friendly")).expect("write first");
        fs::write(&two, sample_json("shared_id", "enemy", "hostile")).expect("write second");

        let error = load_character_library(&temp_dir).expect_err("duplicate ids should fail");
        let text = error.to_string();

        assert!(text.contains("duplicate character id shared_id"));
        cleanup_temp_dir(&temp_dir);
    }

    #[test]
    fn invalid_loot_chance_is_rejected() {
        let mut definition = sample_definition("zombie_walker");
        definition.combat.loot = vec![CharacterLootEntry {
            item_id: 1010,
            chance: 1.2,
            min: 1,
            max: 1,
        }];

        let error = validate_character_definition(&definition).expect_err("chance should fail");

        assert_eq!(
            error,
            CharacterDefinitionValidationError::InvalidLootChance {
                item_id: 1010,
                chance: 1.2
            }
        );
    }

    #[test]
    fn invalid_level_is_rejected() {
        let mut definition = sample_definition("zombie_walker");
        definition.progression.level = 0;

        let error = validate_character_definition(&definition).expect_err("level should fail");

        assert_eq!(
            error,
            CharacterDefinitionValidationError::InvalidLevel { level: 0 }
        );
    }

    #[test]
    fn player_archetype_requires_player_disposition() {
        let mut definition = sample_definition("player");
        definition.archetype = CharacterArchetype::Player;
        definition.faction.disposition = CharacterDisposition::Friendly;

        let error =
            validate_character_definition(&definition).expect_err("player disposition should fail");

        assert_eq!(
            error,
            CharacterDefinitionValidationError::InvalidPlayerDisposition {
                disposition: CharacterDisposition::Friendly
            }
        );
    }

    #[test]
    fn migrated_sample_library_loads_successfully() {
        let data_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("data/characters");
        let library = load_character_library(&data_dir).expect("samples should load");

        assert!(library.len() >= 2);
        assert!(library
            .get(&CharacterId("trader_lao_wang".to_string()))
            .is_some());
        assert!(library
            .get(&CharacterId("zombie_walker".to_string()))
            .is_some());
    }

    fn sample_definition(id: &str) -> CharacterDefinition {
        let mut sets = BTreeMap::new();
        sets.insert(
            "base".to_string(),
            BTreeMap::from([("strength".to_string(), 5.0)]),
        );
        let mut resources = BTreeMap::new();
        resources.insert("hp".to_string(), CharacterResourcePool { current: 50.0 });

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
                xp_reward: 5,
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
            attributes: CharacterAttributeTemplate { sets, resources },
            interaction: None,
            life: None,
        }
    }

    fn sample_json(id: &str, archetype: &str, disposition: &str) -> String {
        format!(
            r##"{{
                "id": "{id}",
                "archetype": "{archetype}",
                "identity": {{ "display_name": "{id}", "description": "" }},
                "faction": {{ "camp_id": "temp", "disposition": "{disposition}" }},
                "presentation": {{
                    "portrait_path": "",
                    "avatar_path": "",
                    "model_path": "",
                    "placeholder_colors": {{
                        "head": "#ffffff",
                        "body": "#cccccc",
                        "legs": "#999999"
                    }}
                }},
                "progression": {{ "level": 1 }},
                "combat": {{ "behavior": "neutral", "xp_reward": 1, "loot": [] }},
                "ai": {{
                    "aggro_range": 0.0,
                    "attack_range": 1.0,
                    "wander_radius": 1.0,
                    "leash_distance": 2.0,
                    "decision_interval": 0.5,
                    "attack_cooldown": 1.0
                }},
                "attributes": {{
                    "sets": {{ "base": {{ "strength": 1.0 }} }},
                    "resources": {{ "hp": {{ "current": 10.0 }} }}
                }}
            }}"##
        )
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should move forward")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cdc_survival_game_{label}_{nonce}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }

    fn cleanup_temp_dir(path: &Path) {
        if path.exists() {
            let _ = fs::remove_dir_all(path);
        }
    }
}
