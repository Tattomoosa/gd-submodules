extends RefCounted

const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")
const TrackedEditorPluginAccess := preload("./tracked_editor_plugin_access.gd")
const GitIgnorer := preload("../git/git_ignorer.gd")
const GitArchiveIgnorer := GitIgnorer.GitArchiveIgnorer

var repo : String
var source_path : String
var plugins : Array[TrackedEditorPluginAccess]
var ignorer : GitArchiveIgnorer

static var submodules_folder : String:
	get: return GitSubmodulePlugin.submodules_root
var author : String:
	get: return repo.get_slice("/", 0)
var repo_name : String:
	get: return repo.get_slice("/", 1)

func _init(
	p_repo: String,
	# p_submodules_root: String,
) -> void:
	repo = p_repo
	# submodules_folder = p_submodules_root
	source_path = submodules_folder.path_join(repo)
	push_warning("%s has changes: " % repo, has_changes())
	var zip_file_path := submodules_folder.path_join(repo.replace("/", ".") + "." + commit_hash() +  ".zip")
	# Tells ignorer not to make a new archive
	var only_read := FileAccess.file_exists(zip_file_path) and !has_changes()
	print("only read: true")
	ignorer = GitArchiveIgnorer.new(
		source_path,
		zip_file_path,
		only_read
	)
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

func get_upstream_url() -> String:
	var output : Array[String] = []
	var os_err := _execute_at_source_path("git config --get remote.origin.url", output)
	if os_err != OK:
		return ""
	return output[0].trim_suffix("\n")


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
	# TODO might have to change or move into GitArchiveIgnorer if using another ignorer
	var ignorer_trim_path_prefix := source_path + "/"
	if ignorer.ignores_path(path.replace(ignorer_trim_path_prefix, "") + "/"):
		print("Path %s ignored by ignorer" % path.replace(ignorer_trim_path_prefix, "") + "/")
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
	var err := dir.change_dir(submodules_folder)
	assert(err == OK)
	var os_err := _execute_at(dir.get_current_dir(), "rm -rf %s" % repo)
	err = _dir_cleanup(submodules_folder.path_join(author))
	if os_err == OK:
		return OK
	return FAILED

func _execute_at_source_path(cmd: String, output: Array[String] = []) -> int:
	return _execute_at(source_path, cmd, output)

# Walks up filesystem removing empty directories until it hits a non-empty directory
func _dir_cleanup(path: String) -> Error:
	var err : Error = OK
	var cwd := path.split("/")[-1]
	var dir := DirAccess.open(path)
	if !dir:
		push_warning("Remove cleanup: Could not cd to %s" % path)
	if dir.get_files().is_empty() and dir.get_directories().is_empty():
		err = dir.change_dir("..")
		if err != OK:
			push_warning("Remove cleanup: Could not cd to %s" % path.path_join(".."))
		err = dir.remove(cwd)
		if err != OK:
			push_warning("Remove cleanup: Could not remove dir %s" % path)
		return _dir_cleanup(dir.get_current_dir())
	return OK

static func _make_dir(p_repo: String) -> Error:
	var dir := DirAccess.open(submodules_folder)
	if dir.dir_exists(p_repo):
		return ERR_ALREADY_EXISTS
	return dir.make_dir_recursive(p_repo)

static func github_upstream_url(p_repo: String) -> String:
	return "git@github.com:%s.git" % p_repo

func commit_hash(short := true) -> String:
	var output : Array[String] = []
	var short_arg := "--short" if short else ""
	var os_err := _execute_at_source_path("git rev-parse %s HEAD" % short_arg, output)
	if os_err != OK:
		return ""
	return output[0].trim_suffix("\n")

func branch_name() -> String:
	var output : Array[String] = []
	var err := _execute_at_source_path("git symbolic-ref --short HEAD", output)
	if err != OK:
		return ""
	return output[0].trim_suffix("\n")

func has_changes() -> bool:
	var output: Array[String] = []
	var os_err := _execute_at_source_path("git status --porcelain", output)
	# print("%s has changes output: " % repo, output)
	print(repo, ":", os_err, ":", output[0].length())
	if os_err == OK and output.size() > 0:
		print(output[0].length() > 0)
		return output[0].length() > 0
	print("fell thru, true")
	return true

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

static func clone(
	p_repo: String,
	upstream_url: String = github_upstream_url(p_repo),
	output: Array[String] = []
) -> Error:
	print("Cloning %s" % p_repo)
	var err : Error
	var os_err : int
	err = _make_dir(p_repo)
	if !(err == OK or err == ERR_ALREADY_EXISTS):
		return err
	var source_folder := submodules_folder.path_join(p_repo)
	os_err = _execute_at(source_folder, "git clone %s ." % upstream_url, output)
	if os_err != OK:
		push_error(output)
		return FAILED
	print("Cloned %s" % p_repo)
	return err

# TODO test
func init(output : Array[String] = []) -> int:
	var err : int
	var dir := DirAccess.open(submodules_folder)
	err = _make_dir(repo); assert(err == OK)
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
