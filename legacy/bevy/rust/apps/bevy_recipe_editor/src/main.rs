use std::env;

mod actions;
mod app;
mod commands;
mod data;
mod navigation;
mod state;
mod ui;

fn main() {
    match parse_initial_recipe_selection() {
        Ok(initial_recipe_id) => app::run(initial_recipe_id),
        Err(error) => {
            eprintln!("bevy_recipe_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_recipe_selection() -> Result<Option<String>, String> {
    let mut args = env::args().skip(1);
    let mut initial_recipe_id = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-recipe" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-recipe requires a recipe id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-recipe requires a non-empty recipe id".to_string());
                }
                initial_recipe_id = Some(raw_value);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(initial_recipe_id)
}
