mod app;
mod bbmodel_links;
mod catalog;
mod commands;
mod preview;
mod socket_editor;
mod state;
mod ui;

fn main() {
    app::run(parse_initial_model_arg());
}

fn parse_initial_model_arg() -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--select-model" {
            return args.next();
        }
    }
    None
}
