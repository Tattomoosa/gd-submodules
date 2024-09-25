extends RefCounted

var name : String
var source_path : String
var dest_path : String:
	get:
		return "res://%s" % name

func _init(
	p_name: String,
	p_source_path: String,
) -> void:
	name = p_name
	source_path = p_source_path

func is_enabled() -> bool:
	return EditorInterface.is_plugin_enabled(name)

func set_enabled(value: bool = true) -> void:
	if is_enabled() != value:
		EditorInterface.set_plugin_enabled(name, value)

func enable() -> void:
	set_enabled()

func disable() -> void:
	set_enabled(false)

func get_project_install_path() -> String:
	var project_path := "res://addons".path_join(name)
	return project_path