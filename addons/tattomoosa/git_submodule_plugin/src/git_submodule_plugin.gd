@tool
extends Node

signal repo_loaded(repo: String)
signal not_tracked
signal tracked
signal linked

enum Status {
	NOT_TRACKED,
	TRACKED,
	LINKED,
}

const SUBMODULES_ROOT := "submodules/"

@export var repo : String:
	set(value):
		if repo == value:
			return
		repo = value
		_determine_status()

@export var description : String

var status : Status:
	set(value):
		status = value
		print("EMITTING STATUS ", status)
		match status:
			Status.TRACKED: tracked.emit()
			Status.NOT_TRACKED: not_tracked.emit()
			Status.LINKED: linked.emit()

var plugin_cfg_contents := """\
[plugin]
name="%s"
description="%s"
author="%s"
version="%s"
script="%s"
"""

var project_godot_contents := """
config_version=5
[debug]

gdscript/warnings/exclude_addons=false
gdscript/warnings/untyped_declaration=1
gdscript/warnings/unsafe_property_access=1
gdscript/warnings/unsafe_method_access=1
gdscript/warnings/return_value_discarded=1
"""

var plugin_gd_contents := """
@tool
extends EditorPlugin

func _enter_tree() -> void:
  pass

func _exit_tree() -> void:
  pass
"""

var author : String:
	get: return repo.split("/")[0].to_lower()

var repo_name : String:
	get: return repo.split("/")[1].to_lower()

func _ready() -> void:
	_determine_status()
	repo_loaded.emit(repo)

func set_repo(p_repo: String) -> void:
	repo = p_repo

func _get_or_create_submodules_dir() -> DirAccess:
	var submodules_path := "res://".path_join(SUBMODULES_ROOT)
	var dir := DirAccess.open(submodules_path)
	if !dir:
		var err := DirAccess.make_dir_absolute(submodules_path)
		assert(err == OK)
		var file := FileAccess.open(submodules_path.path_join(".gdignore"), FileAccess.WRITE)
		file.store_buffer([])
		dir = DirAccess.open(submodules_path)
	return dir

func init(output : Array[String] = []) -> int:
	var err : int
	var dir := _get_or_create_submodules_dir()
	err = _make_plugin_module_dir(); assert(err == OK)
	err = dir.change_dir(repo); assert(err == OK)
	# git init
	err = _execute_at(dir.get_current_dir(), "git init", output)
	if err != OK: push_error(output); assert(err == OK)
	# make project config
	var project_godot := FileAccess.open(
		dir.get_current_dir().path_join("project.godot"),
		FileAccess.WRITE
	)
	project_godot.store_string(project_godot_contents)
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
	plugin_cfg.store_string(plugin_cfg_contents % [
		# name
		repo_name,
		# description
		description,
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
	plugin_gd.store_string(plugin_gd_contents)
	err = dir.make_dir("src")
	assert(err == OK)
	err = DirAccess.make_dir_absolute("res://addons/%s" % author.to_lower())
	assert(err == OK or err == ERR_ALREADY_EXISTS)
	# make resource addon link
	# print_debug(dir.get_current_dir())
	# var symlink_dest := _get_plugin_res_path()
	# print_debug(symlink_dest)
	# err = dir.create_link(dir.get_current_dir(), symlink_dest)
	err = symlink()
	assert(err == OK)
	# status = Status.LINKED
	return err

func symlink() -> Error:
	var repo_dir := DirAccess.open(get_submodule_path().path_join("addons"))
	var project_plugin_resource_path := _get_plugin_res_path()
	var plugin_roots := find_plugin_roots()
	print(plugin_roots)
	for root in plugin_roots:
		print_debug("Found plugin root:\n", root, "\n", project_plugin_resource_path)
		var relative_root := root.replace(repo_dir.get_current_dir(), "")
		var project_install_path := "res://addons".path_join(relative_root)
		var err := repo_dir.create_link(root, project_install_path)
		if (err != OK and err != ERR_ALREADY_EXISTS):
			push_warning("Could not create symlink at %s" % project_install_path, error_string(err))
	status = Status.LINKED
	return OK

## Find plugin roots, or any directory with a present plugin.cfg
## Only looks one plugin.cfg deep, ignores nested ones,
## they would be included by the symlink anyway
func find_plugin_roots() -> Array[String]:
	var plugin_addons_path := get_submodule_path().path_join("addons")
	return _find_plugin_roots(plugin_addons_path)

func _find_plugin_roots(path: String) -> Array[String]:
	if !is_tracked:
		push_error("Repo must be in tracked state (cloned locally) to find plugin roots")
		return []
	var dir := DirAccess.open(path)
	if !dir:
		push_error("Plugin root not found")
		return []
	for file in dir.get_files():
		if file.ends_with("plugin.cfg"):
			return [path]
	var cfg_paths : Array[String] = []
	for d in dir.get_directories():
		cfg_paths.append_array(_find_plugin_roots(path.path_join(d)))
	return cfg_paths

func get_all_plugin_configs() -> Array[ConfigFile]:
	var roots := find_plugin_roots()
	var arr : Array[ConfigFile]
	for i in roots.size():
		arr.push_back(get_config(i))
	return arr

func get_config(root_index := 0) -> ConfigFile:
	var plugin_cfgs := find_plugin_roots()
	var cfg0_path := plugin_cfgs[root_index].path_join("plugin.cfg")
	var cf := ConfigFile.new()
	var err := cf.load(cfg0_path)
	if err != OK:
		push_warning("Failed to load config from path " + cfg0_path + " ", error_string(err))
		return null
	print_debug("Loaded config from path " + cfg0_path)
	return cf

func get_version_string() -> String:
	var cf := get_config()
	if !cf:
		return ""
	return cf.get_value("plugin", "version", "")

func clone(output: Array[String] = []) -> Error:
	var err : Error
	var os_err : int
	var dir := _get_or_create_submodules_dir()
	err = _make_plugin_module_dir()
	if !(err == OK or err == ERR_ALREADY_EXISTS):
		return err
	err = dir.change_dir(repo)
	if err != OK:
		return err
	# git clone
	# err = _execute_at(dir.get_current_dir(true), "pwd", output)
	os_err = _execute_at(dir.get_current_dir(), "git clone %s ." % _upstream_url(), output)
	if os_err != OK:
		push_error(output)
		return FAILED
	status = Status.TRACKED
	return err
	# return symlink()

func remove() -> Error:
	if !repo:
		return ERR_INVALID_DATA
	var err := remove_from_project()
	if err != OK:
		push_warning(error_string(err))
	err = remove_submodule()
	if err != OK:
		push_warning(error_string(err))
	assert(err == OK)
	return err

func remove_from_project() -> Error:
	var dir := DirAccess.open(_get_plugin_res_path())
	push_warning(dir.get_files())
	if "plugin.cfg" in dir.get_files():
		var err := DirAccess.remove_absolute(dir.get_current_dir())
		assert(err == OK)
		status = Status.TRACKED
		return err
	push_error("plugin.cfg not found at %s" % _get_plugin_res_path())
	return ERR_FILE_BAD_PATH

func remove_submodule() -> Error:
	var dir := DirAccess.open(get_submodule_path())
	push_warning(dir)
	if !dir:
		return ERR_CANT_OPEN
	dir.include_hidden = true
	push_warning(dir.get_directories())
	if ".git" in dir.get_directories():
		push_warning(dir.get_current_dir())
		var output : Array[String] = []
		var err0 := dir.change_dir("..")
		assert(err0 == OK)
		var os_err := _execute_at(dir.get_current_dir(), "rm -rf %s" % repo_name, output)
		if os_err == OK:
			status = Status.NOT_TRACKED
			return OK
		push_error(output)
		return FAILED
	push_warning(".git not found")
	return ERR_FILE_BAD_PATH

func _get_plugin_res_path() -> String:
	var plugin_addons_path := get_submodule_path().path_join("addons")
	var cfg_path : String = find_plugin_roots()[0]
	var rel_path := cfg_path.replace(plugin_addons_path, "")
	return "res://addons/%s" % rel_path
	# return "res://addons/%s" % repo.to_lower()

func get_submodule_path() -> String:
	return get_submodules_root_path().path_join(repo.to_lower())

static func get_submodules_root_path() -> String:
	return "res://".path_join(SUBMODULES_ROOT)

func _make_plugin_module_dir() -> Error:
	var dir := _get_or_create_submodules_dir()
	if dir.dir_exists(repo):
		return ERR_ALREADY_EXISTS
	return dir.make_dir_recursive(repo)

func _upstream_url() -> String:
	return "git@github.com:%s.git" % repo

func _execute_at(path: String, cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	print_debug("Executing: " + 'cd \"%s\" && \"%s\"' % [path, cmd])
	return OS.execute(
		"$SHELL",
		[
			"-lc",
			'cd \"%s\" && %s' % [path, cmd]
		],
		output,
		true)

func _determine_status() -> void:
	if !repo:
		status = Status.NOT_TRACKED
		return
	var exists_in_git := DirAccess.dir_exists_absolute(get_submodule_path().path_join(".git"))
	var exists_in_project := DirAccess.dir_exists_absolute(_get_plugin_res_path())
	if exists_in_git and exists_in_project:
		status = Status.LINKED
		return
	if exists_in_git:
		status = Status.TRACKED
		return
	status = Status.NOT_TRACKED
	return

static func get_tracked_repos() -> Array[String]:
	return _get_tracked_repos(get_submodules_root_path())

static func _get_tracked_repos(path: String) -> Array[String]:
	var dir := DirAccess.open(path)
	dir.include_hidden = true
	if ".git" in dir.get_directories():
		return [dir.get_current_dir().replace(get_submodules_root_path(), "")]
	var git_dirs : Array[String] = []
	for d in dir.get_directories():
		git_dirs.append_array(_get_tracked_repos(path.path_join(d)))
	return git_dirs

func commit_hash(short := true) -> String:
	var submodule_root := get_submodule_path()
	var short_arg := "--short" if short else ""
	var output : Array[String] = []
	var err := _execute_at(submodule_root, "git rev-parse %s HEAD" % short_arg, output)
	if err != OK:
		return ""
	return output[0]

func branch_name() -> String:
	# git symbolic-ref --short HEAD
	var submodule_root := get_submodule_path()
	var output : Array[String] = []
	var err := _execute_at(submodule_root, "git symbolic-ref --short HEAD", output)
	if err != OK:
		return ""
	return output[0]

func is_tracked() -> bool:
	return status == Status.TRACKED or status == Status.LINKED

func is_linked() -> bool:
	return status == Status.LINKED

func get_enabled_plugin_roots() -> Array[String]:
	var enabled : Array[String] = []
	var roots := find_plugin_roots()
	for i in roots.size():
		var root := roots[i]
		var folder_name := root.split("/")[-1]
		push_warning(folder_name)
		if EditorInterface.is_plugin_enabled(folder_name):
			enabled.push_back(root)
	return enabled