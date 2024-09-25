extends RefCounted

# const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")
const TrackedEditorPluginAccess := preload("./tracked_editor_plugin_access.gd")

var repo : String
var source_path : String

func _init(
	p_repo: String,
	p_source_path: String,
) -> void:
	repo = p_repo
	source_path = p_source_path

func get_plugins() -> Array[TrackedEditorPluginAccess]:
	var roots := _find_plugin_roots()
	var plugins : Array[TrackedEditorPluginAccess] = []
	for root in roots:
		plugins.push_back(TrackedEditorPluginAccess.new(
			root,
			source_path + root,	
		))
	return plugins

func _find_plugin_roots() -> Array[String]:
	var addons_path := source_path.path_join("addons")
	return _find_plugin_roots_recursive(addons_path)

func _find_plugin_roots_recursive(path: String) -> Array[String]:
	var dir := DirAccess.open(path)
	dir.include_hidden = true
	for file in dir.get_files():
		if file.ends_with(".gdignore"):
			return []
		if file.ends_with("plugin.cfg"):
			return [path]
	var cfg_paths : Array[String] = []
	for d in dir.get_directories():
		# if d in ignore:
		# 	continue
		cfg_paths.append_array(_find_plugin_roots_recursive(path.path_join(d)))
	return cfg_paths

