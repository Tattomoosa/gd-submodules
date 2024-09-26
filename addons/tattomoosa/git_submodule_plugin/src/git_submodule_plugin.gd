@tool
extends RefCounted

# Static 

const Self := preload("./git_submodule_plugin.gd")
const GitSubmoduleAccess := preload("./access/git_submodule_access.gd")
const TrackedEditorPluginAccess := preload("./access/tracked_editor_plugin_access.gd")

const SUBMODULES_ROOT_SETTINGS_PATH := "git_submodule_plugin/paths/submodules_root"
const SUBMODULES_DEFAULT_ROOT := "res://.submodules"


static func _static_init():
	pass

static var submodules_root := SUBMODULES_DEFAULT_ROOT:
	get:
		if _is_moving_submodule_dir:
			return _last_known_submodules_root
		if !ProjectSettings.has_setting(SUBMODULES_ROOT_SETTINGS_PATH):
			ProjectSettings.set_setting(SUBMODULES_ROOT_SETTINGS_PATH, SUBMODULES_DEFAULT_ROOT)
		var path : String = ProjectSettings.get_setting(SUBMODULES_ROOT_SETTINGS_PATH)
		if path != _last_known_submodules_root:
			print("Submodule root changed - last known: %s, current: %s" % [_last_known_submodules_root, path])
			var err := _move_submodules_dir(_last_known_submodules_root, path)
			if err:
				return _last_known_submodules_root
		return path

static var _last_known_submodules_root : String = ProjectSettings.get_setting(SUBMODULES_ROOT_SETTINGS_PATH)
static var _is_moving_submodule_dir := false

static func _execute_at(path: String, cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	# print_debug("Executing: " + 'cd \"%s\" && \"%s\"' % [path, cmd])
	return OS.execute(
		"$SHELL",
		["-lc", 'cd \"%s\" && %s' % [path, cmd]],
		output,
		true
	)

static func get_tracked_plugins() -> Array[TrackedEditorPluginAccess]:
	var plugins : Array[TrackedEditorPluginAccess]
	for sm in get_tracked_submodules():
		plugins.append_array(sm.plugins)
	return plugins

static var submodules : Array[GitSubmoduleAccess] = []

static func get_tracked_submodules() -> Array[GitSubmoduleAccess]:
	var repos := _get_tracked_repos(get_submodules_root_path())
	var sm_names := submodules.map(func(x: GitSubmoduleAccess) -> String: return x.repo)
	# clear removed
	for sm in submodules:
		if sm.repo not in repos:
			submodules.erase(sm)
	# populate new
	for repo in repos:
		if !repo in sm_names:
			submodules.push_back(GitSubmoduleAccess.new(repo))
	return submodules.duplicate()

static func reset_internal_state() -> void:
	submodules.clear()
	@warning_ignore("return_value_discarded")
	get_tracked_submodules()

static func _get_tracked_repos(path: String) -> Array[String]:
	var dir := DirAccess.open(path)
	dir.include_hidden = true
	if ".git" in dir.get_directories():
		return [
			dir.get_current_dir()\
					.replace(get_submodules_root_path(), "")\
					# .trim_suffix("/")
					.trim_prefix("/")
		]
	var git_dirs : Array[String] = []
	for d in dir.get_directories():
		git_dirs.append_array(_get_tracked_repos(path.path_join(d)))
	return git_dirs

static func get_submodules_root_path() -> String:
	var root := submodules_root
	# TODO abs paths windows?
	if !(root.begins_with("res://") or root.begins_with("user://") or root.begins_with("/")):
		push_warning("submodules root '%s' does not begin with res://, user://, or / - prefixing with 'res://'" % root)
		root = "res://" + root
	return root

static func _get_or_create_submodules_dir() -> DirAccess:
	var submodules_path := get_submodules_root_path()
	var dir := DirAccess.open(submodules_path)
	if !dir:
		print("Creating submodules root path'%s'" % submodules_path)
		var err := DirAccess.make_dir_absolute(submodules_path)
		assert(err == OK)
		var file := FileAccess.open(submodules_path.path_join(".gdignore"), FileAccess.WRITE)
		file.store_buffer([])
		dir = DirAccess.open(submodules_path)
	return dir

# TODO does this still work?
static func _move_submodules_dir(from_path: String, to_path: String) -> Error:
	_is_moving_submodule_dir = true
	var old_dir_abs := ProjectSettings.globalize_path(from_path)
	var new_dir_abs := ProjectSettings.globalize_path(to_path)

	push_warning("Moving submodules directory from %s to %s" % [old_dir_abs, new_dir_abs])
	if DirAccess.dir_exists_absolute(new_dir_abs):
		push_warning("New directory '%s' already exists. Updating submodule root directory to new directory. No action taken." % new_dir_abs)
		_last_known_submodules_root = to_path
		_is_moving_submodule_dir = false
		return OK

	if !DirAccess.dir_exists_absolute(old_dir_abs):
		push_warning("Known submodule folder '%s' does not exist." % old_dir_abs)
		push_warning("Creating new submodules folder at %s" % new_dir_abs)
		_last_known_submodules_root = to_path
		var dir := _get_or_create_submodules_dir()
		if !dir:
			push_error(error_string(DirAccess.get_open_error()))
			_is_moving_submodule_dir = false
			return FAILED
		_is_moving_submodule_dir = false
		push_warning("Created new submodule dir")
		return OK

	# { plugin : submodule } to re-add easily
	var enabled_plugins := {}
	var installed_plugins := {}

	var err := OK
	for submodule_repo in _get_tracked_repos(from_path):
		var sm := GitSubmoduleAccess.new(submodule_repo)
		sm.repo = submodule_repo
		for plugin in sm.get_installed_plugins():
			installed_plugins[plugin.name] = sm.repo
		for plugin in sm.get_enabled_plugins():
			enabled_plugins[plugin.name] = sm.repo
			#TODO maybe we don't need to disable
			# set_plugin_enabled(plugin, false)
		err = sm.remove()
		if err != OK:
			push_error("COULD NOT REMOVE FROM PROJECT: %s %s" % [sm.repo, error_string(err)])
			_is_moving_submodule_dir = false
			return FAILED

	err = DirAccess.rename_absolute(old_dir_abs, new_dir_abs)
	if err != OK:
		push_error(
				"Could not move submodule root %s to %s. " % old_dir_abs, new_dir_abs,
				"Error: ", error_string(err))
		_is_moving_submodule_dir = false
		return err
	_last_known_submodules_root = to_path

	for old_plugin: GitSubmoduleAccess.TrackedEditorPluginAccess in installed_plugins:
		var sm := GitSubmoduleAccess.new(installed_plugins[old_plugin])
		var plugin := sm.get_plugin(old_plugin.name)
		err = plugin.install()
		if err != OK:
			push_error("Failed to re-install %s" % plugin.name)
	for old_plugin: GitSubmoduleAccess.TrackedEditorPluginAccess in enabled_plugins:
		var sm := GitSubmoduleAccess.new(installed_plugins[old_plugin])
		var plugin := sm.get_plugin(old_plugin.name)
		plugin.enable()

	if err != OK:
		push_error(error_string(DirAccess.get_open_error()))
		_is_moving_submodule_dir = false
		return FAILED

	_is_moving_submodule_dir = false
	return OK
