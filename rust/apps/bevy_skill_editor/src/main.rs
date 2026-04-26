use std::env;

mod app;
mod commands;
mod data;
mod handoff;
mod state;
mod ui;

fn main() {
    match parse_initial_selection() {
        Ok((initial_skill_id, initial_tree_id)) => app::run(initial_skill_id, initial_tree_id),
        Err(error) => {
            eprintln!("bevy_skill_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_selection() -> Result<(Option<String>, Option<String>), String> {
    let mut args = env::args().skip(1);
    let mut initial_skill_id = None;
    let mut initial_tree_id = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-skill" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-skill requires a skill id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-skill requires a non-empty skill id".to_string());
                }
                initial_skill_id = Some(raw_value);
            }
            "--select-skill-tree" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-skill-tree requires a tree id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-skill-tree requires a non-empty tree id".to_string());
                }
                initial_tree_id = Some(raw_value);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok((initial_skill_id, initial_tree_id))
}
