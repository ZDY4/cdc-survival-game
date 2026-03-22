use game_data::{GridCoord, WorldCoord};

pub const DEFAULT_GRID_SIZE: f32 = 1.0;

pub fn world_to_grid(world: WorldCoord, grid_size: f32) -> GridCoord {
    GridCoord {
        x: (world.x / grid_size).floor() as i32,
        y: (world.y / grid_size).floor() as i32,
        z: (world.z / grid_size).floor() as i32,
    }
}

pub fn grid_to_world(grid: GridCoord, grid_size: f32) -> WorldCoord {
    WorldCoord {
        x: grid.x as f32 * grid_size + grid_size / 2.0,
        y: grid.y as f32 * grid_size + grid_size / 2.0,
        z: grid.z as f32 * grid_size + grid_size / 2.0,
    }
}

pub fn snap_to_grid(world: WorldCoord, grid_size: f32) -> WorldCoord {
    grid_to_world(world_to_grid(world, grid_size), grid_size)
}
