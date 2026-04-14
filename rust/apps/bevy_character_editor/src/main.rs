//! 角色编辑器入口。
//! 这里只负责声明模块并启动应用，避免业务逻辑继续堆积在 `main.rs`。

mod app;
mod data;
mod preview;
mod state;
mod ui;

fn main() {
    app::run();
}
