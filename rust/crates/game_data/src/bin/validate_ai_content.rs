use std::path::PathBuf;

use game_data::{
    load_character_library, load_settlement_library, validate_ai_content, AiContentIssueSeverity,
};

fn main() {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let character_dir = repo_root.join("data/characters");
    let settlement_dir = repo_root.join("data/settlements");

    let characters = load_character_library(&character_dir).unwrap_or_else(|error| {
        panic!(
            "failed to load character library from {}: {error}",
            character_dir.display()
        )
    });
    let settlements = load_settlement_library(&settlement_dir).unwrap_or_else(|error| {
        panic!(
            "failed to load settlement library from {}: {error}",
            settlement_dir.display()
        )
    });

    let issues = validate_ai_content(&characters, &settlements);
    if issues.is_empty() {
        println!("ai_content_check: clean");
        return;
    }

    let mut error_count = 0usize;
    let mut warning_count = 0usize;
    for issue in &issues {
        match issue.severity {
            AiContentIssueSeverity::Error => error_count += 1,
            AiContentIssueSeverity::Warning => warning_count += 1,
        }
        println!(
            "[{}] {} settlement={:?} character={:?} {}",
            issue.severity,
            issue.code,
            issue.settlement_id,
            issue.character_id,
            issue.message,
        );
    }

    println!(
        "ai_content_check: {} errors, {} warnings",
        error_count, warning_count
    );

    if error_count > 0 {
        std::process::exit(1);
    }
}
