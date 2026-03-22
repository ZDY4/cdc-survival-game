# Native JPS GDExtension

This folder contains a Godot GDExtension that exposes `NativeJpsPlanner` to the game.

## What it does

- Wraps a 2D `jps3d` planner for the game's `x/z` grid.
- Accepts:
  - static blocked cells
  - runtime blocked cells
  - min/max grid bounds
- Returns a `Vector3i` path that plugs into the existing `PathPlannerService`.
- If the extension is not present or cannot handle the current `GridWorld`, the game falls back to the existing GDScript A* planner automatically.

## Relevant Godot-side files

- [path_planner_service.gd](/G:/Projects/cdc_survival_game/systems/path_planner_service.gd)
- [path_planner_jps_native.gd](/G:/Projects/cdc_survival_game/systems/path_planner_jps_native.gd)
- [movement_component.gd](/G:/Projects/cdc_survival_game/systems/movement_component.gd)

## Build in Visual Studio 2026

1. Open Visual Studio 2026.
2. Open the folder:
   - `G:\Projects\cdc_survival_game\native\jps_extension`
3. Let CMake configure the project.
4. Build `Debug` and/or `Release` for `x64`.

The extension uses `FetchContent`, so CMake will download:

- `godot-cpp`
- `Eigen`
- `jps3d`

## Expected output

After a successful build, these files should exist:

- `G:\Projects\cdc_survival_game\native\jps_extension\bin\libnative_jps.windows.template_debug.x86_64.dll`
- `G:\Projects\cdc_survival_game\native\jps_extension\bin\libnative_jps.windows.template_release.x86_64.dll`

The `.gdextension` file is already set up here:

- [native_jps.gdextension](/G:/Projects/cdc_survival_game/native/jps_extension/native_jps.gdextension)

## Runtime behavior

- [`path_planner_jps_native.gd`](/G:/Projects/cdc_survival_game/systems/path_planner_jps_native.gd) attempts to load the `.gdextension`.
- If `NativeJpsPlanner` is registered successfully, the planner service will use it when the current `GridWorld` provides finite pathfinding bounds.
- Otherwise the game continues using the GDScript fallback planner.

## Notes

- This extension currently targets bounded grids. That is already suitable for the overworld pathfinding case.
- The local unbounded default grid still falls back safely unless explicit bounds are provided later.
- The `boost::heap::d_ary_heap` dependency used by upstream `jps3d` is shimmed locally under:
  - [d_ary_heap.hpp](/G:/Projects/cdc_survival_game/native/jps_extension/third_party/compat/boost/heap/d_ary_heap.hpp)
