mod app;
mod camera;
mod commands;
mod handoff;
mod scene;
mod state;
mod ui;

fn main() {
    match parse_initial_map_selection() {
        Ok(initial_map_id) => app::run(initial_map_id),
        Err(error) => {
            eprintln!("bevy_map_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_map_selection() -> Result<Option<String>, String> {
    let mut args = std::env::args().skip(1);
    let mut initial_map_id = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-map" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-map requires a map id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-map requires a non-empty map id".to_string());
                }
                initial_map_id = Some(raw_value);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(initial_map_id)
}
