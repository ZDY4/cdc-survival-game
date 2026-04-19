mod content;
mod changed;
mod diff_summary;
mod format;
mod references;
mod summarize;

use std::env;

use changed::validate_changed_content;
use content::{locate_content, repo_root, validate_content};
use diff_summary::print_diff_summary;
use format::format_content;
use references::references_content;
use summarize::summarize_content;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Command {
    Locate,
    Validate,
    Summarize,
    References,
    DiffSummary,
    Format,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ContentKind {
    Item,
    Recipe,
    Character,
    Map,
}

pub(crate) fn run() -> Result<i32, String> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first() else {
        return Err(usage());
    };
    let command = parse_command(command)?;
    let repo_root = repo_root();

    match (command, args.as_slice()) {
        (Command::DiffSummary, [_, flag, path]) if flag == "--path" => {
            print_diff_summary(&repo_root, path)
        }
        (Command::Format, [_, changed]) if changed == "changed" => format_content(None, None, &repo_root),
        (Command::Validate, [_, changed]) if changed == "changed" => {
            validate_changed_content(&repo_root)
        }
        (command, [_, kind, target_id]) => {
            let kind = parse_kind(kind)?;
            match command {
                Command::Locate => locate_content(kind, target_id, &repo_root),
                Command::Validate => validate_content(kind, target_id, &repo_root),
                Command::Summarize => summarize_content(kind, target_id, &repo_root),
                Command::References => references_content(kind, target_id, &repo_root),
                Command::DiffSummary => Err(usage()),
                Command::Format => format_content(Some(kind), Some(target_id.as_str()), &repo_root),
            }
        }
        _ => Err(usage()),
    }
}

fn parse_command(value: &str) -> Result<Command, String> {
    match value {
        "locate" => Ok(Command::Locate),
        "validate" => Ok(Command::Validate),
        "summarize" => Ok(Command::Summarize),
        "references" => Ok(Command::References),
        "diff-summary" => Ok(Command::DiffSummary),
        "format" => Ok(Command::Format),
        _ => Err(format!("unknown command: {value}")),
    }
}

fn parse_kind(value: &str) -> Result<ContentKind, String> {
    match value {
        "item" => Ok(ContentKind::Item),
        "recipe" => Ok(ContentKind::Recipe),
        "character" => Ok(ContentKind::Character),
        "map" => Ok(ContentKind::Map),
        _ => Err(format!("unknown content kind: {value}")),
    }
}

fn usage() -> String {
    concat!(
        "usage: content_tools <locate|validate|summarize|references|format> ",
        "<item|recipe|character|map> <id>\n",
        "       content_tools validate changed\n",
        "       content_tools format changed\n",
        "       content_tools diff-summary --path <repo-relative-or-absolute-path>\n",
        "note: references currently supports item and map"
    )
    .to_string()
}

impl ContentKind {
    pub(super) fn label(self) -> &'static str {
        match self {
            ContentKind::Item => "item",
            ContentKind::Recipe => "recipe",
            ContentKind::Character => "character",
            ContentKind::Map => "map",
        }
    }
}
