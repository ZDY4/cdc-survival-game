extends RefCounted

const REPO_DATA_RELATIVE_PATH := "res://../data"
const REPO_ASSETS_RELATIVE_PATH := "res://../assets"


static func repo_root() -> String:
	return ProjectSettings.globalize_path("res://..").simplify_path()


static func data_root() -> String:
	return ProjectSettings.globalize_path(REPO_DATA_RELATIVE_PATH).simplify_path()


static func assets_root() -> String:
	return ProjectSettings.globalize_path(REPO_ASSETS_RELATIVE_PATH).simplify_path()


static func domain_path(domain_dir: String) -> String:
	return data_root().path_join(domain_dir).simplify_path()
