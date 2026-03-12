# Gameplay Tags Addon (Godot 4.6)

UE-style hierarchical gameplay tags for Godot, including runtime containers, query expressions, stack containers, and an editor dock.

## Features

- Global registry singleton: `GameplayTags`
- Hierarchical matching: `A.B.C` matches `A.B` and `A` (non-exact mode)
- `GameplayTagContainer` for explicit tag sets
- `GameplayTagQuery` with `ANY/ALL/NONE` on tags or nested expressions
- `GameplayTagStackContainer` for counted tag stacks
- Editor dock for tag CRUD, validation, search, and query preview
- Text registry format with stable sorted save output

## Config Format

Default config path:

`res://addons/gameplay_tags/config/gameplay_tags.ini`

Example:

```ini
[GameplayTags]
+GameplayTagList="State.Combat"
+GameplayTagList="Status.Burning"
```

Comments use `#` or `;`.

## Runtime API

`GameplayTags.request_tag(tag_name: String, error_if_not_found := true) -> StringName`

`GameplayTags.is_valid_tag(tag_name: StringName) -> bool`

`GameplayTags.matches_tag(tag_a: StringName, tag_b: StringName, exact := false) -> bool`

`GameplayTags.make_container(tags: Array[StringName]) -> GameplayTagContainer`

`GameplayTags.evaluate_query(container: GameplayTagContainer, query: GameplayTagQuery) -> bool`

## Usage Example

```gdscript
var container: GameplayTagContainer = GameplayTagContainer.new()
container.add_tag(&"Status.Burning")

var query: GameplayTagQuery = GameplayTagQuery.all_expr_match([
	GameplayTagQuery.any_tags_match([&"Status"]),
	GameplayTagQuery.no_tags_match([&"State.Dead"])
])

var matched: bool = GameplayTags.evaluate_query(container, query)
print("Matched: ", matched)
```

## Notes

- Autoload `GameplayTags` is registered when this plugin is enabled.
- Autoload is removed when this plugin is disabled, if this plugin added it.
