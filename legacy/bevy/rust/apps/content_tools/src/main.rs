mod app;

fn main() {
    let exit_code = match app::run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("content_tools error: {error}");
            1
        }
    };
    std::process::exit(exit_code);
}
