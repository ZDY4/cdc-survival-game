use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;

use game_data::{
    GridCoord, MapCellDefinition, MapEditCommand, MapEditDiagnosticSeverity, MapEditResult,
    MapEditTarget, MapEditorService, MapEntryPointDefinition, MapId, MapObjectDefinition, MapSize,
};

fn main() {
    let raw_args = env::args().collect::<Vec<_>>();
    let wants_help = raw_args.len() == 1
        || raw_args
            .iter()
            .skip(1)
            .any(|arg| matches!(arg.as_str(), "help" | "--help" | "-h"));
    if let Err(message) = run() {
        if wants_help {
            println!("{message}");
        } else {
            eprintln!("{message}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1).collect::<Vec<_>>();
    if args.is_empty() {
        return Err(usage());
    }

    let json_output = take_flag(&mut args, "--json");
    let maps_dir = take_option(&mut args, "--maps-dir")
        .map(PathBuf::from)
        .unwrap_or_else(default_maps_dir);
    let service = MapEditorService::new(maps_dir);

    let Some(command) = args.first().cloned() else {
        return Err(usage());
    };
    args.remove(0);

    match command.as_str() {
        "validate" => run_validate(&service, args, json_output),
        "format" => run_format(&service, args, json_output),
        "create" => run_create(&service, args, json_output),
        "entry-point" => run_entry_point(&service, args, json_output),
        "object" => run_object(&service, args, json_output),
        "level" => run_level(&service, args, json_output),
        "cells" => run_cells(&service, args, json_output),
        "help" | "--help" | "-h" => Err(usage()),
        other => Err(format!("unknown command `{other}`\n\n{}", usage())),
    }
}

fn run_validate(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    if take_flag(&mut args, "--all") {
        let results = service
            .validate_all_maps()
            .map_err(|error| error.to_string())?;
        print_results(&results, json_output)?;
        if has_error_diagnostics(&results) {
            std::process::exit(1);
        }
        return Ok(());
    }

    let target = parse_target(&mut args)?;
    ensure_no_args(&args)?;
    let result = service
        .execute(MapEditCommand::ValidateMap { target })
        .map_err(|error| error.to_string())?;
    print_results(&[result.clone()], json_output)?;
    if has_error_diagnostics(&[result]) {
        std::process::exit(1);
    }
    Ok(())
}

fn run_format(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    if take_flag(&mut args, "--all") {
        let results = service
            .format_all_maps()
            .map_err(|error| error.to_string())?;
        print_results(&results, json_output)?;
        return Ok(());
    }

    let target = parse_target(&mut args)?;
    ensure_no_args(&args)?;
    let result = service
        .execute(MapEditCommand::FormatMap { target })
        .map_err(|error| error.to_string())?;
    print_results(&[result], json_output)
}

fn run_create(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    let map_id = required_option(&mut args, "--map-id")?;
    let width = required_option(&mut args, "--width")?
        .parse::<u32>()
        .map_err(|error| format!("invalid --width: {error}"))?;
    let height = required_option(&mut args, "--height")?
        .parse::<u32>()
        .map_err(|error| format!("invalid --height: {error}"))?;
    let name = take_option(&mut args, "--name");
    let default_level = take_option(&mut args, "--default-level")
        .map(|value| {
            value
                .parse::<i32>()
                .map_err(|error| format!("invalid --default-level: {error}"))
        })
        .transpose()?
        .unwrap_or(0);
    let overwrite = take_flag(&mut args, "--overwrite");
    ensure_no_args(&args)?;

    let result = service
        .execute(MapEditCommand::CreateMap {
            map_id: MapId(map_id),
            name,
            size: MapSize { width, height },
            default_level,
            overwrite,
        })
        .map_err(|error| error.to_string())?;
    print_results(&[result], json_output)
}

fn run_entry_point(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    let Some(action) = args.first().cloned() else {
        return Err("missing entry-point action".to_string());
    };
    args.remove(0);

    match action.as_str() {
        "upsert" => {
            let target = parse_target(&mut args)?;
            let json_file = required_option(&mut args, "--json-file")?;
            ensure_no_args(&args)?;
            let entry_point = read_json_file::<MapEntryPointDefinition>(&json_file)?;
            let result = service
                .execute(MapEditCommand::UpsertEntryPoint {
                    target,
                    entry_point,
                })
                .map_err(|error| error.to_string())?;
            print_results(&[result], json_output)
        }
        "remove" => {
            let target = parse_target(&mut args)?;
            let entry_point_id = required_option(&mut args, "--entry-point-id")?;
            ensure_no_args(&args)?;
            let result = service
                .execute(MapEditCommand::RemoveEntryPoint {
                    target,
                    entry_point_id,
                })
                .map_err(|error| error.to_string())?;
            print_results(&[result], json_output)
        }
        other => Err(format!("unknown entry-point action `{other}`")),
    }
}

fn run_object(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    let Some(action) = args.first().cloned() else {
        return Err("missing object action".to_string());
    };
    args.remove(0);

    match action.as_str() {
        "upsert" => {
            let target = parse_target(&mut args)?;
            let json_file = required_option(&mut args, "--json-file")?;
            ensure_no_args(&args)?;
            let object = read_json_file::<MapObjectDefinition>(&json_file)?;
            let result = service
                .execute(MapEditCommand::UpsertObject { target, object })
                .map_err(|error| error.to_string())?;
            print_results(&[result], json_output)
        }
        "remove" => {
            let target = parse_target(&mut args)?;
            let object_id = required_option(&mut args, "--object-id")?;
            ensure_no_args(&args)?;
            let result = service
                .execute(MapEditCommand::RemoveObject { target, object_id })
                .map_err(|error| error.to_string())?;
            print_results(&[result], json_output)
        }
        other => Err(format!("unknown object action `{other}`")),
    }
}

fn run_level(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    let Some(action) = args.first().cloned() else {
        return Err("missing level action".to_string());
    };
    args.remove(0);

    let target = parse_target(&mut args)?;
    let level = required_option(&mut args, "--level")?
        .parse::<i32>()
        .map_err(|error| format!("invalid --level: {error}"))?;
    ensure_no_args(&args)?;

    let command = match action.as_str() {
        "add" => MapEditCommand::AddLevel { target, level },
        "remove" => MapEditCommand::RemoveLevel { target, level },
        other => return Err(format!("unknown level action `{other}`")),
    };

    let result = service
        .execute(command)
        .map_err(|error| error.to_string())?;
    print_results(&[result], json_output)
}

fn run_cells(
    service: &MapEditorService,
    mut args: Vec<String>,
    json_output: bool,
) -> Result<(), String> {
    let Some(action) = args.first().cloned() else {
        return Err("missing cells action".to_string());
    };
    args.remove(0);

    match action.as_str() {
        "paint" => {
            let target = parse_target(&mut args)?;
            let level = required_option(&mut args, "--level")?
                .parse::<i32>()
                .map_err(|error| format!("invalid --level: {error}"))?;
            let json_file = required_option(&mut args, "--json-file")?;
            ensure_no_args(&args)?;
            let cells = read_json_file::<Vec<MapCellDefinition>>(&json_file)?;
            let result = service
                .execute(MapEditCommand::PaintCells {
                    target,
                    level,
                    cells,
                })
                .map_err(|error| error.to_string())?;
            print_results(&[result], json_output)
        }
        "clear" => {
            let target = parse_target(&mut args)?;
            let level = required_option(&mut args, "--level")?
                .parse::<i32>()
                .map_err(|error| format!("invalid --level: {error}"))?;
            let json_file = required_option(&mut args, "--json-file")?;
            ensure_no_args(&args)?;
            let cells = read_json_file::<Vec<GridCoord>>(&json_file)?;
            let result = service
                .execute(MapEditCommand::ClearCells {
                    target,
                    level,
                    cells,
                })
                .map_err(|error| error.to_string())?;
            print_results(&[result], json_output)
        }
        other => Err(format!("unknown cells action `{other}`")),
    }
}

fn parse_target(args: &mut Vec<String>) -> Result<MapEditTarget, String> {
    let map_id = take_option(args, "--map-id");
    let path = take_option(args, "--path");
    match (map_id, path) {
        (Some(map_id), None) => Ok(MapEditTarget::MapId(MapId(map_id))),
        (None, Some(path)) => Ok(MapEditTarget::Path(PathBuf::from(path))),
        (Some(_), Some(_)) => Err("use either --map-id or --path, not both".to_string()),
        (None, None) => Err("missing target; expected --map-id <id> or --path <file>".to_string()),
    }
}

fn print_results(results: &[MapEditResult], json_output: bool) -> Result<(), String> {
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(results).map_err(|error| error.to_string())?
        );
        return Ok(());
    }

    for result in results {
        let map_id = result
            .summary
            .map_id
            .as_ref()
            .map(|id| id.as_str())
            .unwrap_or("<unknown>");
        let path = result
            .summary
            .path
            .as_ref()
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| "<unknown>".to_string());
        println!(
            "{} changed={} map={} path={}",
            result.summary.operation, result.changed, map_id, path
        );
        for detail in &result.summary.details {
            println!("  - {detail}");
        }
        for diagnostic in &result.diagnostics {
            println!(
                "  [{}] {} {}",
                severity_label(diagnostic.severity),
                diagnostic.code,
                diagnostic.message
            );
        }
    }

    Ok(())
}

fn has_error_diagnostics(results: &[MapEditResult]) -> bool {
    results.iter().any(|result| {
        result
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.severity == MapEditDiagnosticSeverity::Error)
    })
}

fn severity_label(severity: MapEditDiagnosticSeverity) -> &'static str {
    match severity {
        MapEditDiagnosticSeverity::Error => "error",
        MapEditDiagnosticSeverity::Warning => "warning",
        MapEditDiagnosticSeverity::Info => "info",
    }
}

fn read_json_file<T: DeserializeOwned>(path: impl AsRef<Path>) -> Result<T, String> {
    let path = path.as_ref();
    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))
}

fn default_maps_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join("data")
        .join("maps")
}

fn ensure_no_args(args: &[String]) -> Result<(), String> {
    if args.is_empty() {
        return Ok(());
    }
    Err(format!("unexpected arguments: {}", args.join(" ")))
}

fn required_option(args: &mut Vec<String>, flag: &str) -> Result<String, String> {
    take_option(args, flag).ok_or_else(|| format!("missing required {flag}"))
}

fn take_option(args: &mut Vec<String>, flag: &str) -> Option<String> {
    let index = args.iter().position(|arg| arg == flag)?;
    if index + 1 >= args.len() {
        return None;
    }
    let value = args.remove(index + 1);
    args.remove(index);
    Some(value)
}

fn take_flag(args: &mut Vec<String>, flag: &str) -> bool {
    if let Some(index) = args.iter().position(|arg| arg == flag) {
        args.remove(index);
        true
    } else {
        false
    }
}

fn usage() -> String {
    [
        "map_tool usage:",
        "  map_tool [--maps-dir <dir>] [--json] validate (--all | --map-id <id> | --path <file>)",
        "  map_tool [--maps-dir <dir>] [--json] format (--all | --map-id <id> | --path <file>)",
        "  map_tool [--maps-dir <dir>] [--json] create --map-id <id> --width <w> --height <h> [--name <name>] [--default-level <y>] [--overwrite]",
        "  map_tool [--maps-dir <dir>] [--json] entry-point upsert (--map-id <id> | --path <file>) --json-file <file>",
        "  map_tool [--maps-dir <dir>] [--json] entry-point remove (--map-id <id> | --path <file>) --entry-point-id <id>",
        "  map_tool [--maps-dir <dir>] [--json] object upsert (--map-id <id> | --path <file>) --json-file <file>",
        "  map_tool [--maps-dir <dir>] [--json] object remove (--map-id <id> | --path <file>) --object-id <id>",
        "  map_tool [--maps-dir <dir>] [--json] level add (--map-id <id> | --path <file>) --level <y>",
        "  map_tool [--maps-dir <dir>] [--json] level remove (--map-id <id> | --path <file>) --level <y>",
        "  map_tool [--maps-dir <dir>] [--json] cells paint (--map-id <id> | --path <file>) --level <y> --json-file <file>",
        "  map_tool [--maps-dir <dir>] [--json] cells clear (--map-id <id> | --path <file>) --level <y> --json-file <file>",
    ]
    .join("\n")
}
