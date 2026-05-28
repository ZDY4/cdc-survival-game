mod app;
mod commands;
mod data;
mod graph;
mod handoff;
mod state;
mod ui;

fn main() {
    match parse_initial_dialogue_selection() {
        Ok(initial_dialogue_id) => {
            if let Err(error) = app::run(initial_dialogue_id) {
                eprintln!("{error}");
                std::process::exit(1);
            }
        }
        Err(error) => {
            eprintln!("bevy_dialogue_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_dialogue_selection() -> Result<Option<String>, String> {
    let mut args = std::env::args().skip(1);
    let mut initial_dialogue_id = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-dialogue" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-dialogue requires a dialogue id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-dialogue requires a non-empty dialogue id".to_string());
                }
                initial_dialogue_id = Some(raw_value);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(initial_dialogue_id)
}
