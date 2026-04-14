# Cargo Profile Tuning For Faster Daily Iteration

## Summary

Optimize the Rust workspace for `开发迭代速度` as the default goal.
Keep `dev` as the everyday profile, but make it lighter on debug info and better balanced for Bevy:
own crates compile fast, heavy dependencies run reasonably fast, and release remains available for final runtime/perf checks.

## Implementation Changes

- Update [`rust/Cargo.toml`](G:\Projects\cdc_survival_game\rust\Cargo.toml) with a tuned `dev` profile:
  - `[profile.dev]`
  - `opt-level = 1`
  - `debug = 1`
  - `incremental = true`
- Add dependency override for Bevy-style development:
  - `[profile.dev.package."*"]`
  - `opt-level = 3`
- Keep tests close to dev behavior unless a specific issue appears:
  - either leave `test` implicit, or set `[profile.test] debug = 1`
- Add a lightweight “playable optimized” profile for non-debug runs without fully paying the heaviest release cost:
  - `[profile.play]`
  - `inherits = "release"`
  - `debug = 0`
  - `lto = "off"`
  - `codegen-units = 16`
- Add matching launch scripts or script variants so usage is explicit:
  - existing `run_bevy_xxx.bat` continues using `cargo run -p ...`
  - add `run_bevy_xxx_play.bat` variants using `cargo run --profile play -p ...`
  - keep existing release script only for final perf/packaging checks

## Recommended Profile Values

Use this exact starting point:

```toml
[profile.dev]
opt-level = 1
debug = 1
incremental = true

[profile.dev.package."*"]
opt-level = 3

[profile.play]
inherits = "release"
debug = 0
lto = "off"
codegen-units = 16
```

Behavioral intent:
- `dev`: fastest day-to-day coding loop with smaller debug info than full default debug
- `dev.package."*"`: dependencies like Bevy stay performant enough that the app/editor is usable
- `play`: for “just run it” sessions when you do not need debugger-friendly output
- `release`: reserved for final realism, profiling, and shipping-oriented validation

## Public Interfaces / Workflow Changes

No gameplay or runtime API changes.
Developer workflow changes:
- Use `run_bevy_xxx.bat` for coding and frequent reruns.
- Use new `run_bevy_xxx_play.bat` for normal use, smoke testing, and lower-PDB / higher-performance runs.
- Use release only when validating near-final runtime behavior.

## Test Plan

- Run `cargo check` in [`rust`](G:\Projects\cdc_survival_game\rust).
- Run one representative app in `dev` and confirm first incremental rebuild is reduced after a small local code change.
- Run the same app in `play` and confirm startup/runtime behavior is acceptable without debug-oriented overhead.
- Compare three cases after a tiny code edit:
  - `cargo run -p bevy_debug_viewer`
  - `cargo run --profile play -p bevy_debug_viewer`
  - `cargo run -r -p bevy_debug_viewer`
- Acceptance criteria:
  - `dev` remains the fastest edit-run loop
  - `play` feels meaningfully better than `dev` for normal running
  - `release` remains the slowest compile but best for final validation

## Assumptions

- Main pain point is Windows Bevy workspace iteration speed, not packaging size.
- You do not need full debugger-quality symbol detail for every daily run.
- The biggest improvement from profiles alone will come from reducing dev debug burden and avoiding full release for routine runs.
- If compile/link time is still too high after this, the next highest-value step is not more profile tuning but adding a faster linker via `.cargo/config.toml`.
