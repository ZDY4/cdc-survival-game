#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <jps_collision/map_util.h>
#include <jps_planner/jps_planner/jps_planner.h>

#include <memory>
#include <unordered_set>
#include <vector>

namespace godot {

class NativeJpsPlanner : public RefCounted {
	GDCLASS(NativeJpsPlanner, RefCounted)

public:
	NativeJpsPlanner();

	void rebuild_static_map(const Dictionary &p_bounds, const Array &p_blocked_cells);
	void set_runtime_blocked_cells(const Array &p_blocked_cells);
	Array find_path(const Vector3i &p_start_grid, const Vector3i &p_goal_grid, bool p_use_jps = true);
	void clear_runtime_state();

protected:
	static void _bind_methods();

private:
	static constexpr signed char CELL_FREE = 0;
	static constexpr signed char CELL_BLOCKED = 100;

	bool _has_bounds = false;
	Vector3i _min_grid = Vector3i();
	Vector3i _max_grid = Vector3i();
	Vector2i _dims = Vector2i();

	std::unordered_set<int64_t> _static_blocked;
	std::unordered_set<int64_t> _runtime_blocked;
	std::vector<signed char> _occupancy;
	bool _map_dirty = true;

	std::shared_ptr<JPS::MapUtil<2>> _map_util;
	std::unique_ptr<JPSPlanner2D> _planner;

	bool _apply_bounds(const Dictionary &p_bounds);
	void _set_blocked_set(std::unordered_set<int64_t> &r_target, const Array &p_blocked_cells);
	void _rebuild_occupancy();
	bool _ensure_planner_ready();
	bool _is_inside_bounds(const Vector3i &p_grid) const;
	Vector2i _to_local_cell(const Vector3i &p_grid) const;
	Vec2f _to_local_world_point(const Vector3i &p_grid) const;
	Vector3i _to_world_grid(const Vec2f &p_point) const;
	int _flatten_local_cell(const Vector2i &p_cell) const;
	int64_t _cell_key(const Vector3i &p_grid) const;
};

} // namespace godot
