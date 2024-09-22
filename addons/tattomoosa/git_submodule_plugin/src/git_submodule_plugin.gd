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
	push_warning(dir.get_current_dir())
	var symlink_dest := _get_plugin_res_path()
	push_warning(symlink_dest)
	err = dir.create_link(dir.get_current_dir(), symlink_dest)
	assert(err == OK)
	status = Status.LINKED
	return err

func symlink() -> int:
	var repo_dir := DirAccess.open(_get_plugin_module_path().path_join("addons"))
	var project_plugin_resource_path := _get_plugin_res_path()
	var plugin_roots := _find_plugin_cfgs(repo_dir.get_current_dir())
	print(plugin_roots)
	for root in plugin_roots:
		var err := repo_dir.create_link(root, project_plugin_resource_path)
		push_warning(root, ", ", project_plugin_resource_path)
		if (err != OK and err != ERR_ALREADY_EXISTS):
			push_warning(error_string(err))
	status = Status.LINKED
	return OK

# only one find deep, ignoring nested plugin.cfg - they will be included by the symlink
func _find_plugin_cfgs(path: String) -> Array[String]:
	var dir := DirAccess.open(path)
	for file in dir.get_files():
		if file.ends_with("plugin.cfg"):
			return [path]
	var cfg_paths : Array[String] = []
	for d in dir.get_directories():
		cfg_paths.append_array(_find_plugin_cfgs(path.path_join(d)))
	return cfg_paths

func clone(output: Array[String] = []) -> int:
	var err : int
	var dir := _get_or_create_submodules_dir()
	err = _make_plugin_module_dir()
	assert(err == OK or err == ERR_ALREADY_EXISTS)
	err = dir.change_dir(repo)
	assert(err == OK)
	# git clone
	# err = _execute_at(dir.get_current_dir(true), "pwd", output)
	err = _execute_at(dir.get_current_dir(), "git clone %s ." % _upstream_url(), output)
	push_error(output)
	if err != OK:
		push_error(error_string(err))
	assert(err == OK)
	status = Status.TRACKED
	return symlink()

func remove() -> int:
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

func remove_from_project() -> int:
	var dir := DirAccess.open(_get_plugin_res_path())
	push_warning(dir.get_files())
	if "plugin.cfg" in dir.get_files():
		var err := DirAccess.remove_absolute(dir.get_current_dir())
		assert(err == OK)
		status = Status.TRACKED
		return err
	push_error("plugin.cfg not found at %s" % _get_plugin_res_path())
	return ERR_FILE_BAD_PATH

func remove_submodule() -> int:
	var dir := DirAccess.open(_get_plugin_module_path())
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
		var err := _execute_at(dir.get_current_dir(), "rm -rf %s" % repo_name, output)
		push_warning(output)
		if err == OK:
			status = Status.NOT_TRACKED
		return err
	push_warning(".git not found")
	return ERR_FILE_BAD_PATH

func _get_plugin_res_path() -> String:
	return "res://addons/%s" % repo.to_lower()

func _get_plugin_module_path() -> String:
	return get_submodules_path().path_join(repo.to_lower())

static func get_submodules_path() -> String:
	return "res://".path_join(SUBMODULES_ROOT)

func _make_plugin_module_dir() -> int:
	var dir := _get_or_create_submodules_dir()
	if dir.dir_exists(repo):
		return ERR_ALREADY_EXISTS
	return dir.make_dir_recursive(repo)

func _upstream_url() -> String:
	return "git@github.com:%s.git" % repo

func _execute_at(path: String, cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	push_warning('cd \"%s\" && \"%s\"' % [path, cmd])
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
	var exists_in_git := DirAccess.dir_exists_absolute(_get_plugin_module_path().path_join(".git"))
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
	return _get_tracked_repos(get_submodules_path())

static func _get_tracked_repos(path: String) -> Array[String]:
	var dir := DirAccess.open(path)
	dir.include_hidden = true
	if ".git" in dir.get_directories():
		return [dir.get_current_dir().replace(get_submodules_path(), "")]
	var git_dirs : Array[String] = []
	for d in dir.get_directories():
		git_dirs.append_array(_get_tracked_repos(path.path_join(d)))
	return git_dirs
