@tool
extends EditorPlugin

const GitSubmodulePlugin := preload("./src/git_submodule_plugin.gd")
# const GitSubmoduleSettings := preload("./src/editor/git_submodule_plugin_settings.tscn")
const GitSubmoduleSettingsTree := preload("./src/editor/git_submodule_settings_tree.tscn")

# var submodule_settings := GitSubmoduleSettings.instantiate()
var submodule_settings := GitSubmoduleSettingsTree.instantiate()

func _enter_tree() -> void:
  add_control_to_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, submodule_settings)

func _exit_tree() -> void:
  remove_control_from_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, submodule_settings)
