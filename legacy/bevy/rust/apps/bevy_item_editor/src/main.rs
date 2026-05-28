use std::env;

mod actions;
mod app;
mod commands;
mod data;
mod preview;
mod state;
mod ui;

fn main() {
    match parse_initial_selection() {
        Ok(initial_selection) => app::run(initial_selection),
        Err(error) => {
            eprintln!("bevy_item_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_selection() -> Result<Option<u32>, String> {
    let mut args = env::args().skip(1);
    let mut initial_selection = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-item" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-item requires an item id".to_string())?;
                let item_id = raw_value
                    .parse::<u32>()
                    .map_err(|error| format!("invalid --select-item value {raw_value}: {error}"))?;
                initial_selection = Some(item_id);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(initial_selection)
}
