@tool
extends EditorPlugin

const GitSubmodulePlugin := preload("./src/git_submodule_plugin.gd")
const GitSubmoduleSettingsTreeScene := preload("./src/editor/git_submodule_project_settings/git_submodule_settings.tscn")
const GitSubmoduleFileDockPugin := preload(
    "./src/editor/file_dock_plugin/git_submodule_file_dock_plugin.gd"
)
const EditorProfiler := preload("src/util/profiler.gd")

const L := preload("src/util/logger.gd")
static var l: L.Logger:
  get: return L.get_logger(L.LogLevel.INFO, &"GitSubmoduleEditorPlugin")
static var p: L.Logger:
  get: return L.get_logger(L.LogLevel.WARN, &"Profiler:GitSubmoduleEditorPlugin")

var submodule_settings := GitSubmoduleSettingsTreeScene.instantiate()
var file_system_dock_plugin := GitSubmoduleFileDockPugin.new()
var default_plugin_window : Control

const PROJECT_SETTINGS_DEFAULTS = {
  GitSubmodulePlugin.SETTINGS_PATH_SUBMODULES_ROOT: "res://.submodules",
  GitSubmodulePlugin.SETTINGS_PATH_SUBMODULES_CONFIG_FILE: "res://.submodules/submodules.cfg",
  "git_submodules/settings/use_file_dock_plugin": true,
}

func _enter_tree() -> void:
  await get_tree().process_frame
  await get_tree().process_frame
  EditorInterface.get_editor_settings().erase("git_submodule_plugin/submodules_root")
  var stopwatch := EditorProfiler.Stopwatch.new()
  for project_setting: String in PROJECT_SETTINGS_DEFAULTS.keys():
    _set_setting_to_default_if_not_found(
      project_setting,
      PROJECT_SETTINGS_DEFAULTS[project_setting]
    )
  stopwatch.restart_and_log("load ProjectSettings", p.info)
  GitSubmodulePlugin.reset_internal_state()
  stopwatch.restart()
  _add_file_dock_plugin()
  stopwatch.restart_and_log("add file dock plugin", p.info)
  add_control_to_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, submodule_settings)
  submodule_settings.get_parent().move_child(submodule_settings, 4)
  stopwatch.restart_and_log("add settings panel", p.info)

func _exit_tree() -> void:
  _remove_file_dock_plugin()
  remove_control_from_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, submodule_settings)

func _add_file_dock_plugin() -> void:
  file_system_dock_plugin = GitSubmoduleFileDockPugin.new()
  file_system_dock_plugin.initialize()
  file_system_dock_plugin.patch_dock()

func _remove_file_dock_plugin() -> void:
  file_system_dock_plugin.queue_free()

func _set_setting_to_default_if_not_found(setting_path: String, value: Variant) -> void:
  if ProjectSettings.has_setting(setting_path):
    return
  ProjectSettings.set_setting(setting_path, value)