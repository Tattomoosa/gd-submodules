extends RefCounted

# const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")
const TrackedEditorPluginAccess := preload("./tracked_editor_plugin_access.gd")

var repo : String
var source_path : String
var submodules_root : String
var plugins : Array[TrackedEditorPluginAccess]
var author : String:
	get: return repo.get_slice("/", 0)
var repo_name : String:
	get: return repo.get_slice("/", 1)

func _init(
	p_repo: String,
	p_submodules_root: String,
) -> void:
	repo = p_repo
	submodules_root = p_submodules_root
	source_path = submodules_root.path_join(repo)
	plugins = _get_plugins()

func _get_plugins() -> Array[TrackedEditorPluginAccess]:
	var roots := _find_plugin_roots()
	var plugs : Array[TrackedEditorPluginAccess] = []
	for root in roots:
		plugs.push_back(TrackedEditorPluginAccess.new(root))
	return plugs

func get_plugin(plugin_name: String) -> TrackedEditorPluginAccess:
	for plugin in plugins:
		if plugin.name == plugin_name:
			return plugin
	return null

func get_installed_plugins() -> Array[TrackedEditorPluginAccess]:
	var installed : Array[TrackedEditorPluginAccess]
	for plugin in plugins:
		if plugin.is_installed():
			installed.push_back(plugin)
	return installed

func uninstall_all_plugins() -> bool:
	var all_uninstalled := true
	for plugin in get_installed_plugins():
		var err := plugin.uninstall()
		if err != OK:
			push_error("Error uninstalling %s from %s" % [plugin.name, repo])
			all_uninstalled = false
	return all_uninstalled

func install_all_plugins() -> bool:
	var all_installed := true
	for plugin in plugins:
		if plugin.is_installed():
			continue
		var err := plugin.install()
		if err != OK:
			all_installed = false
	return all_installed

func _find_plugin_roots() -> Array[String]:
	var addons_path := source_path.path_join("addons")
	return _find_plugin_roots_recursive(addons_path)

func _find_plugin_roots_recursive(path: String) -> Array[String]:
	var dir := DirAccess.open(path)
	if !dir:
		return []
	dir.include_hidden = true
	for file in dir.get_files():
		if file.ends_with(".gdignore"):
			return []
		if file.ends_with("plugin.cfg"):
			return [path]
	var cfg_paths : Array[String] = []
	for d in dir.get_directories():
		cfg_paths.append_array(_find_plugin_roots_recursive(path.path_join(d)))
	return cfg_paths

func remove() -> Error:
	if !uninstall_all_plugins():
		push_error("Could not uninstall %s" % repo)

	var dir := DirAccess.open(source_path)
	if !dir:
		return ERR_CANT_OPEN

	dir.include_hidden = true
	if ".git" not in dir.get_directories():
		return ERR_FILE_BAD_PATH
	var err := dir.change_dir(submodules_root)
	assert(err == OK)
	# print("cd ", dir.get_current_dir(), " && rm -rf %s" % repo)
	var os_err := _execute_at(dir.get_current_dir(), "rm -rf %s" % repo)
	err = dir.change_dir(author)
	if !dir:
		push_warning("Remove cleanup: Could not cd to %s" % submodules_root.path_join(author))
	if dir.get_files().is_empty() and dir.get_directories().is_empty():
		err = dir.change_dir("..")
		if err != OK:
			push_warning("Remove cleanup: Could not cd to %s" % submodules_root)
		err = dir.remove(author)
		if err != OK:
			push_warning("Remove cleanup: Could not remove dir %s" % submodules_root.path_join(author))
		
	if os_err == OK:
		return OK
	return FAILED

func _make_dir() -> Error:
	var dir := DirAccess.open(submodules_root)
	if dir.dir_exists(repo):
		return ERR_ALREADY_EXISTS
	return dir.make_dir_recursive(repo)

func upstream_url() -> String:
	return "git@github.com:%s.git" % repo

func commit_hash(short := true) -> String:
	var output : Array[String] = []
	var short_arg := "--short" if short else ""
	var os_err := _execute_at(source_path, "git rev-parse %s HEAD" % short_arg, output)
	if os_err != OK:
		# push_error(output)
		return ""
	return output[0]

func branch_name() -> String:
	var output : Array[String] = []
	var err := _execute_at(source_path, "git symbolic-ref --short HEAD", output)
	if err != OK:
		return ""
	return output[0]

func is_tracked() -> bool:
	return DirAccess.dir_exists_absolute(source_path.path_join(".git"))

func has_plugin_installed() -> bool:
	return get_installed_plugins().size() > 0

func has_all_plugins_installed() -> bool:
	return get_installed_plugins().size() == plugins.size()

func get_enabled_plugins() -> Array[TrackedEditorPluginAccess]:
	var enabled : Array[TrackedEditorPluginAccess]
	for plugin in plugins:
		if plugin.is_enabled():
			enabled.push_back(plugin)
	return enabled

func has_plugin_enabled() -> bool:
	return get_enabled_plugins().size() > 0

func has_all_plugins_enabled() -> bool:
	return get_enabled_plugins().size() == plugins.size()

func clone(output: Array[String] = [])  -> Error:
	print("Cloning %s" % repo)
	var err : Error
	var os_err : int
	var dir := DirAccess.open("res://")
	err = _make_dir()
	if !(err == OK or err == ERR_ALREADY_EXISTS):
		return err
	err = dir.change_dir(source_path)
	if err != OK:
		return err
	os_err = _execute_at(dir.get_current_dir(), "git clone %s ." % upstream_url(), output)
	if os_err != OK:
		push_error(output)
		return FAILED
	print("Cloned %s" % repo)
	plugins = _get_plugins()
	return err

# TODO test
func init(output : Array[String] = []) -> int:
	var err : int
	var dir := DirAccess.open(submodules_root)
	err = _make_dir(); assert(err == OK)
	err = dir.change_dir(repo); assert(err == OK)
	# git init
	err = _execute_at(dir.get_current_dir(), "git init", output)
	if err != OK: push_error(output); assert(err == OK)
	# make project config
	var project_godot := FileAccess.open(
		dir.get_current_dir().path_join("project.godot"),
		FileAccess.WRITE
	)
	project_godot.store_string(PROJECT_GODOT_CONTENTS)
	# make addon dir at addons/author/repo
	var addon_root := "addons".path_join(repo)
	err = dir.make_dir_recursive(addon_root)
	assert(err == OK)
	# change to addon dir
	err = dir.change_dir(addon_root)
	assert(err == OK)
	# if err != OK: return err
	# make plugin config
	var plugin_cfg := FileAccess.open(
		dir.get_current_dir().path_join("plugin.cfg"),
		FileAccess.WRITE
	)
	plugin_cfg.store_string(PLUGIN_CFG_CONTENTS % [
		# name
		repo_name,
		# description
		"",
		# author
		author,
		# version
		"0.1.0",
		# script
		"plugin.gd",
	])
	var plugin_gd := FileAccess.open(
		dir.get_current_dir().path_join("plugin.gd"),
		FileAccess.WRITE,
	)
	plugin_gd.store_string(PLUGIN_GD_CONTENTS)
	plugins = _get_plugins()
	print("plugins: ", plugins)
	var installed := install_all_plugins()
	if !installed:
		push_error("Created repo but was unable to install created plugin.")
	return err

# TODO some kind of OS cmd helper
static func _execute_at(path: String, cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	# print_debug("Executing: " + 'cd \"%s\" && \"%s\"' % [path, cmd])
	return OS.execute(
		"$SHELL",
		["-lc", 'cd \"%s\" && %s' % [path, cmd]],
		output,
		true)

var PLUGIN_CFG_CONTENTS := """\
[plugin]
name="%s"
description="%s"
author="%s"
version="%s"
script="%s"
"""

var PROJECT_GODOT_CONTENTS := """
config_version=5
[debug]

gdscript/warnings/exclude_addons=false
gdscript/warnings/untyped_declaration=1
gdscript/warnings/unsafe_property_access=1
gdscript/warnings/unsafe_method_access=1
gdscript/warnings/return_value_discarded=1
"""

var PLUGIN_GD_CONTENTS := """
@tool
extends EditorPlugin

func _enter_tree() -> void:
  pass

func _exit_tree() -> void:
  pass
"""
