//! 角色编辑器入口。
//! 这里只负责声明模块并启动应用，避免业务逻辑继续堆积在 `main.rs`。

mod app;
mod camera_mode;
mod commands;
mod data;
mod handoff;
mod preview;
mod state;
mod ui;

fn main() {
    match parse_initial_character_selection() {
        Ok(initial_character_id) => app::run(initial_character_id),
        Err(error) => {
            eprintln!("bevy_character_editor argument error: {error}");
            std::process::exit(2);
        }
    }
}

fn parse_initial_character_selection() -> Result<Option<String>, String> {
    let mut args = std::env::args().skip(1);
    let mut initial_character_id = None;

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--select-character" => {
                let raw_value = args
                    .next()
                    .ok_or_else(|| "--select-character requires a character id".to_string())?;
                if raw_value.trim().is_empty() {
                    return Err("--select-character requires a non-empty character id".to_string());
                }
                initial_character_id = Some(raw_value);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(initial_character_id)
}
