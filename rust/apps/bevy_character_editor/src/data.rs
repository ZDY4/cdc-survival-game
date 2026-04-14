//! 编辑器数据装载层。
//! 负责从仓库读取角色、AI、据点、外观等内容，并汇总校验结果供 UI 使用。

use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::log::{info, warn};
use game_data::{
    load_ai_module_library, load_character_appearance_library, load_character_library,
    load_effect_library, load_item_library, load_settlement_library, validate_ai_content,
    validate_character_appearance_content, CharacterAppearanceLibrary, CharacterLibrary,
    ItemLibrary, SettlementLibrary,
};

use crate::state::{npc_role_label, CharacterSummary, EditorAiIssue, EditorData, ItemChoice};

// 加载角色编辑器运行所需的全部只读数据。
pub(crate) fn load_editor_data() -> EditorData {
    let repo_root = repo_root();
    let character_dir = repo_root.join("data").join("characters");
    let effects_dir = repo_root.join("data").join("json").join("effects");
    let items_dir = repo_root.join("data").join("items");
    let ai_dir = repo_root.join("data").join("ai");
    let settlements_dir = repo_root.join("data").join("settlements");
    let appearance_dir = repo_root.join("data").join("appearance").join("characters");

    let mut warnings = Vec::new();
    let mut ai_issues = Vec::new();
    let characters = load_character_library(&character_dir).unwrap_or_else(|error| {
        warnings.push(format!("角色库加载失败: {error}"));
        CharacterLibrary::default()
    });
    let effects = load_effect_library(&effects_dir).ok();
    let items = load_item_library(&items_dir, effects.as_ref()).unwrap_or_else(|error| {
        warnings.push(format!("物品库加载失败: {error}"));
        ItemLibrary::default()
    });
    let settlements = load_settlement_library(&settlements_dir).unwrap_or_else(|error| {
        warnings.push(format!("据点库加载失败: {error}"));
        SettlementLibrary::default()
    });
    let ai_library = match load_ai_module_library(&ai_dir) {
        Ok(library) => Some(library),
        Err(error) => {
            warnings.push(format!("AI 模块库加载失败: {error}"));
            None
        }
    };
    let appearance_library = if appearance_dir.exists() {
        load_character_appearance_library(&appearance_dir).unwrap_or_else(|error| {
            warnings.push(format!("外观配置加载失败: {error}"));
            CharacterAppearanceLibrary::default()
        })
    } else {
        CharacterAppearanceLibrary::default()
    };

    if let Some(ai_library) = ai_library.as_ref() {
        for issue in validate_ai_content(&characters, &settlements, ai_library) {
            ai_issues.push(EditorAiIssue {
                severity: issue.severity.to_string(),
                code: issue.code.to_string(),
                settlement_id: issue.settlement_id.clone(),
                character_id: issue.character_id.clone(),
                message: issue.message.clone(),
            });
            warnings.push(format!("AI 校验 {}: {}", issue.severity, issue.message));
        }
    }
    for issue in validate_character_appearance_content(&characters, &items, &appearance_library) {
        warnings.push(format!("外观校验 {:?}: {}", issue.severity, issue.message));
    }

    let mut character_summaries = characters
        .iter()
        .map(|(id, definition)| CharacterSummary {
            id: id.as_str().to_string(),
            display_name: definition.identity.display_name.clone(),
            settlement_id: definition
                .life
                .as_ref()
                .map(|life| life.settlement_id.clone())
                .unwrap_or_default(),
            role: definition
                .life
                .as_ref()
                .map(|life| npc_role_label(life.role).to_string())
                .unwrap_or_default(),
            behavior_profile_id: definition
                .life
                .as_ref()
                .map(|life| life.ai_behavior_profile_id.clone())
                .unwrap_or_default(),
        })
        .collect::<Vec<_>>();
    character_summaries.sort_by(|left, right| {
        left.display_name
            .cmp(&right.display_name)
            .then_with(|| left.id.cmp(&right.id))
    });

    let mut item_catalog_by_slot = BTreeMap::<String, Vec<ItemChoice>>::new();
    for (_, item) in items.iter() {
        for slot in item.equip_slots() {
            item_catalog_by_slot
                .entry(slot)
                .or_default()
                .push(ItemChoice {
                    id: item.id,
                    name: item.name.clone(),
                });
        }
    }
    for entries in item_catalog_by_slot.values_mut() {
        entries.sort_by(|left, right| {
            left.name
                .cmp(&right.name)
                .then_with(|| left.id.cmp(&right.id))
        });
    }

    info!(
        "character editor data loaded: characters={}, items={}, settlements={}, ai_library_loaded={}, appearance_profiles={}, warnings={}",
        characters.len(),
        items.len(),
        settlements.len(),
        ai_library.is_some(),
        appearance_library.iter().count(),
        warnings.len(),
    );
    if !warnings.is_empty() {
        let summary = warnings
            .iter()
            .take(3)
            .cloned()
            .collect::<Vec<_>>()
            .join(" | ");
        warn!("character editor data warnings: {summary}");
    }

    EditorData {
        repo_root,
        characters,
        items,
        settlements,
        ai_library,
        appearance_library,
        character_summaries,
        item_catalog_by_slot,
        warnings,
        ai_issues,
    }
}

// 统一定位仓库根目录，供各类内容目录拼接复用。
fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
