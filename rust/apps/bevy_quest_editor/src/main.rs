mod app;
mod commands;
mod data;
mod graph;
mod handoff;
mod navigation;
mod state;
mod ui;

fn main() {
    match parse_initial_quest_selection() {
        Ok(initial_quest_id) => {
            if let Err(error) = app::run(initial_quest_id) {
                eprintln!("{error}");
                std::process::exit(1);
            }
        }
        Err(error) => {
            eprintln!("bevy_quest_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_quest_selection() -> Result<Option<String>, String> {
    let mut args = std::env::args().skip(1);
    let mut initial_quest_id = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-quest" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-quest requires a quest id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-quest requires a non-empty quest id".to_string());
                }
                initial_quest_id = Some(raw_value);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(initial_quest_id)
}
