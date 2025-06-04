@tool
extends EditorPlugin

const GitSubmodulePlugin := preload("./src/git_submodule_plugin.gd")
const GitSubmoduleSettingsTreeScene := preload("./src/editor/git_submodule_project_settings/git_submodule_settings.tscn")
const GitSubmoduleFileDockPugin := preload(
		"./src/editor/file_dock_plugin/git_submodule_file_dock_plugin.gd"
)

var submodule_settings := GitSubmoduleSettingsTreeScene.instantiate()
var file_system_dock_plugin := GitSubmoduleFileDockPugin.new()
var default_plugin_window : Control

const SETTINGS_PATH_USE_FILE_DOCK_PLUGIN := "gd-submodules/settings/use_file_dock_plugin"

const PROJECT_SETTINGS_DEFAULTS = {
	GitSubmodulePlugin.SETTINGS_PATH_SUBMODULES_ROOT: "res://.submodules",
	GitSubmodulePlugin.SETTINGS_PATH_SUBMODULES_CONFIG_FILE: "res://.submodules/submodules.cfg",
	SETTINGS_PATH_USE_FILE_DOCK_PLUGIN : true,
}

func _enter_tree() -> void:
	# let the check happen in the UI when plugin is enabled before we block for a second (lol)
	await get_tree().process_frame
	await get_tree().process_frame

	_add_defaults_to_missing_settings()
	_add_project_settings_tab()
	GitSubmodulePlugin.reset_internal_state()
	if ProjectSettings.get_setting(SETTINGS_PATH_USE_FILE_DOCK_PLUGIN):
		_add_file_dock_plugin()

func _add_project_settings_tab() -> void:
	add_control_to_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, submodule_settings)
	submodule_settings.get_parent().move_child(submodule_settings, 4)

func _exit_tree() -> void:
	_remove_file_dock_plugin()
	remove_control_from_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, submodule_settings)

func _add_defaults_to_missing_settings() -> void:
	for project_setting: String in PROJECT_SETTINGS_DEFAULTS.keys():
		_set_setting_to_default_if_not_found(
			project_setting,
			PROJECT_SETTINGS_DEFAULTS[project_setting]
		)

func _add_file_dock_plugin() -> void:
	file_system_dock_plugin = GitSubmoduleFileDockPugin.new()
	file_system_dock_plugin.initialize()
	file_system_dock_plugin.patch_dock()

func _remove_file_dock_plugin() -> void:
	if is_instance_valid(file_system_dock_plugin):
		file_system_dock_plugin.queue_free()

func _set_setting_to_default_if_not_found(setting_path: String, value: Variant) -> void:
	if ProjectSettings.has_setting(setting_path):
		return
	ProjectSettings.set_setting(setting_path, value)