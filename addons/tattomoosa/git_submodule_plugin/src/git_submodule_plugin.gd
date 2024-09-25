@tool
extends RefCounted

const Self := preload("./git_submodule_plugin.gd")
const GitSubmoduleAccess := preload("./access/git_submodule_access.gd")

const SUBMODULES_DEFAULT_ROOT_SETTINGS_PATH := "git_submodule_plugin/paths/submodules_root"
const SUBMODULES_DEFAULT_ROOT := "res://.submodules"

static var submodules_root := SUBMODULES_DEFAULT_ROOT:
	get:
		if _is_moving_submodule_dir:
			return _last_known_submodules_root
		if !ProjectSettings.has_setting(SUBMODULES_DEFAULT_ROOT_SETTINGS_PATH):
			ProjectSettings.set_setting(SUBMODULES_DEFAULT_ROOT_SETTINGS_PATH, SUBMODULES_DEFAULT_ROOT)
		var path : String = ProjectSettings.get_setting(SUBMODULES_DEFAULT_ROOT_SETTINGS_PATH)
		if path != _last_known_submodules_root:
			print("Submodule root changed - last known: %s, current: %s" % [_last_known_submodules_root, path])
			var err := _move_submodules_dir(_last_known_submodules_root, path)
			if err:
				return _last_known_submodules_root
			# assert(err == OK)
		# TODO temporary until submodule root can move
		return path

static var _last_known_submodules_root : String = ProjectSettings.get_setting(SUBMODULES_DEFAULT_ROOT_SETTINGS_PATH)
static var _is_moving_submodule_dir := false

@export var repo : String:
	set(value):
		if repo == value:
			return
		repo = value

@export var description : String

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
	err = symlink_all_plugins()
	assert(err == OK)
	return err

func symlink_all_plugins() -> Error:
	var plugin_roots := find_submodule_plugin_roots()
	if plugin_roots.is_empty():
		push_error("Symlink all failed - No valid plugins found in submodule")
		return ERR_DOES_NOT_EXIST
	print("Symlinking all plugins:\n", "\n".join(plugin_roots), "\n")
	for root in plugin_roots:
		var err := symlink_plugin(root)
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error(error_string(err))
	return OK

func _plugin_root_from_plugin_name(plugin_name: String) -> String:
	var plugin_roots := find_submodule_plugin_roots()
	for root in plugin_roots:
		if root.ends_with(plugin_name):
			return root
	return ""

func symlink_plugin(plugin_root: String, force := false) -> Error:
	var dir_path := get_submodule_path().path_join("addons")
	var repo_dir := DirAccess.open(dir_path)
	if !repo_dir:
		push_error(
			"Error symlinking plugin '%s' " % plugin_root,
			" Could not open submodule directory '%s'" % dir_path,
			" Error: ", error_string(DirAccess.get_open_error())
		)
	repo_dir.include_hidden = true
	var relative_root := plugin_root.replace(repo_dir.get_current_dir(), "")
	var project_install_path := "res://addons".path_join(relative_root)
	var root_folder_name := relative_root.split("/")[-1]
	var mkdirs := project_install_path.replace(root_folder_name, "")
	var err := DirAccess.make_dir_recursive_absolute(mkdirs)
	if err != OK:
		push_error("Failed to create directories along path: ", mkdirs)
		return err
	
	if repo_dir.is_link(project_install_path):
		var links_to := repo_dir.read_link(project_install_path)
		if links_to == plugin_root:
			push_warning("Attempted to create symlink when one already exists and links to correct plugin root location ")
			return OK
		else:
			push_error("Symlink already exists and links to another plugin location : %s" % links_to)
			if !force:
				return ERR_ALREADY_EXISTS
			push_error("Force set to true... Removing symlink...")
			err = DirAccess.remove_absolute(project_install_path)
			if err != OK:
				push_error("Could not remove existing symlink via DirAccess. Using rm...")
				var link_name := project_install_path.split("/")[-1]
				var rm_path := ProjectSettings.globalize_path(project_install_path.replace(link_name, ""))
				push_error("cd %s && rm %s" % [rm_path, link_name])
				var output : Array[String] = []
				var os_err := _execute_at(rm_path, "rm %s" % link_name, output)
				if os_err != OK:
					push_error(output)
					return FAILED
				push_error("Successfully removed symlink at ", project_install_path)
				push_error("Creating new symlink...")

	err = repo_dir.create_link(plugin_root, project_install_path)
	if err != OK:
		push_error(
			"Could not create symlink: %s %s - " % [plugin_root, project_install_path], error_string(err))
	print("Created symlink between %s %s" % [plugin_root, project_install_path])
	return err

## Find plugin roots, or any directory with a present plugin.cfg
## Only looks one plugin.cfg deep, ignores nested ones,
## they would be included by the symlink_all_plugins anyway
func find_submodule_plugin_roots() -> Array[String]:
	# TODO this needlessly runs a lot...
	# push_warning("find submodule plugin roots")
	var submodule_path := get_submodule_path()
	var plugin_addons_path := submodule_path.path_join("addons")
	return _find_plugin_roots(plugin_addons_path)

func find_project_plugin_roots() -> Array[String]:
	if !is_tracked():
		push_error("Repo must be in tracked state (cloned locally) to find plugin roots")
		return []
	var submodule_plugin_roots := find_submodule_plugin_roots()
	var project_roots : Array[String] = []
	for root in submodule_plugin_roots:
		project_roots.append(convert_submodule_path_to_project_path(root))
	return project_roots

func convert_submodule_path_to_project_path(path: String) -> String:
	var relative := path.erase(0, path.find("/addons/") + 8)
	var project_path := "res://addons/".path_join(relative)
	return project_path

func get_all_plugin_configs() -> Array[ConfigFile]:
	var roots := find_submodule_plugin_roots()
	var arr : Array[ConfigFile]
	for i in roots.size():
		arr.push_back(get_config(i))
	return arr

func get_config(root_index := 0) -> ConfigFile:
	var plugin_cfgs := find_submodule_plugin_roots()
	var cfg0_path := plugin_cfgs[root_index].path_join("plugin.cfg")
	var cf := ConfigFile.new()
	var err := cf.load(cfg0_path)
	if err != OK:
		push_warning("Failed to load config from path " + cfg0_path + " ", error_string(err))
		return null
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
	os_err = _execute_at(dir.get_current_dir(), "git clone %s ." % upstream_url(), output)
	if os_err != OK:
		push_error(output)
		return FAILED
	return err

func remove() -> Error:
	if !repo:
		return ERR_INVALID_DATA
	var err := remove_from_project()
	if err != OK:
		return err
	err = remove_submodule()
	if err != OK:
		return err
	assert(err == OK)
	return err

func remove_from_project() -> Error:
	var err := OK
	for submodule_root in find_submodule_plugin_roots():
		# TODO method for this?
		# var root_dir_name := submodule_roots.split("/")[-1]
		var root_dir_name := get_plugin_root_relative_to_addons(submodule_root)
		# var path := project_plugin_path_from_root_dir_name(root_dir_name)
		if has_plugin_in_project(root_dir_name):
			var err0 := remove_plugin_from_project(root_dir_name)
			if err0 != OK:
				err = err0
				push_error(error_string(err0))
	return err

func remove_plugin_from_project(plugin_root_dir_name: String) -> Error:
	var path := project_plugin_path_from_root_dir_name(plugin_root_dir_name)
	if path:
		if !DirAccess.dir_exists_absolute(path):
			return ERR_DOES_NOT_EXIST
		var err := DirAccess.remove_absolute(path)
		return err
	return ERR_CANT_RESOLVE

func get_plugins_in_project() -> Array[String]:
	var plugin_roots := find_submodule_plugin_roots()
	var arr : Array[String]
	arr.assign(plugin_roots.filter(
		func(x: String) -> bool:
			return has_plugin_in_project(x.split("/")[-1])
	).map(
		func(x: String) -> String:
			return get_plugin_root_relative_to_addons(x)
	))
	if !arr.is_empty():
		print("Found symlinked plugins %s in %s" % [str(arr), repo])
	return arr

func has_plugin_in_project(plugin_root_dir_name: String) -> bool:
	var path := project_plugin_path_from_root_dir_name(plugin_root_dir_name)
	if !DirAccess.dir_exists_absolute(path):
		return false
	# need to instantiate to check link matches...
	var dir := DirAccess.open("res://")
	# exists, is it a link?
	if !dir.is_link(path):
		push_warning("Directory at '", path, "' is not a symbolic link")
		return false
	# is the link to the right place?
	var link_path := dir.read_link(path)
	return link_path.begins_with(ProjectSettings.globalize_path(get_submodule_path()))

func has_plugin_enabled(plugin_root_dir_name: String) -> bool:
	return _is_plugin_enabled(plugin_root_dir_name) and has_plugin_in_project(plugin_root_dir_name)

func has_all_plugins_in_project() -> bool:
	var plugin_roots := find_submodule_plugin_roots()
	for root in plugin_roots:
		if !has_plugin_in_project(root.split("/")[-1]):
			return false
	return true

func has_any_plugins_in_project() -> bool:
	var plugin_roots := find_submodule_plugin_roots()
	for root in plugin_roots:
		if has_plugin_in_project(root.split("/")[-1]):
			return true
	return false

func project_plugin_path_from_root_dir_name(plugin_root_dir_name: String) -> String:
	var plugin_roots := find_project_plugin_roots()
	var plugin_root : String = ""
	for p in plugin_roots:
		if p.ends_with(plugin_root_dir_name):
			plugin_root = p
	return plugin_root

func remove_submodule(output: Array[String] = []) -> Error:
	var dir := DirAccess.open(get_submodule_path())
	if !dir:
		return ERR_CANT_OPEN
	dir.include_hidden = true
	if ".git" in dir.get_directories():
		var err0 := dir.change_dir("..")
		assert(err0 == OK)
		var os_err := _execute_at(dir.get_current_dir(), "rm -rf %s" % repo_name, output)
		if os_err == OK:
			return OK
		return FAILED
	push_warning("Error removing submodule - folder .git not found at %s" % dir.get_current_dir())
	return ERR_FILE_BAD_PATH

func get_submodule_path() -> String:
	return get_submodules_root_path().path_join(repo.to_lower())

func _make_plugin_module_dir() -> Error:
	var dir := _get_or_create_submodules_dir()
	if dir.dir_exists(repo):
		return ERR_ALREADY_EXISTS
	return dir.make_dir_recursive(repo)

# TODO support non-github
func upstream_url() -> String:
	return "git@github.com:%s.git" % repo

static func _execute_at(path: String, cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	# print_debug("Executing: " + 'cd \"%s\" && \"%s\"' % [path, cmd])
	return OS.execute(
		"$SHELL",
		["-lc", 'cd \"%s\" && %s' % [path, cmd]],
		output,
		true)

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
	return DirAccess.dir_exists_absolute(get_submodule_path().path_join(".git"))

func is_linked() -> bool:
	return has_any_plugins_in_project()

func is_fully_linked() -> bool:
	return has_all_plugins_in_project()

func get_enabled_plugin_roots() -> Array[String]:
	var enabled : Array[String] = []
	var roots := find_submodule_plugin_roots()
	for i in roots.size():
		var root := roots[i]
		var folder_name := root.get_slice("/addons/", 1)
		if has_plugin_enabled(folder_name):
			enabled.push_back(root)
	return enabled

static func get_tracked_repos() -> Array[String]:
	return _get_tracked_repos(get_submodules_root_path())

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

static func _get_all_managed_plugin_roots() -> Array[String]:
	var repos := get_tracked_repos()
	var plugin_roots : Array[String] = []
	for r in repos:
		var sm := Self.new()
		sm.repo = r
		plugin_roots.append_array(sm.find_project_plugin_roots())
	return plugin_roots

static func get_all_managed_plugin_folder_names() -> Array[String]:
	var managed_plugins := _get_all_managed_plugin_roots()
	var arr : Array[String]
	arr.assign(managed_plugins.map(
		func(x: String) -> String:
			return x.get_slice("/addons/", 1)
	))
	return arr

static func _find_plugin_roots(path: String, ignore := [], include_paths : PackedStringArray = []) -> Array[String]:
	if !include_paths.is_empty():
		# TODO idea is to read .gitattributes and only pull in what's allowed in the archive,
		# but still restrict to downstream of plugin.cfg
		# guess it could just check for /addons/whatever !export-ignore ?
		# that seems flaky...
		pass
	# TODO this gets called a lot more than it needs to
	# print("finding plugin root, ", path)
	var dir := DirAccess.open(path)
	if !dir:
		push_error("Finding plugin roots, directory not found at path '%s' " % path)
		return []
	dir.include_hidden = true
	# TODO hangs for some reason...
	# it reads gitignore right now anyway
	# and should read gitattributes, but not sure how
	# to do that in static class...
	# Finding plugin roots might need to be instance-only
	# if _is_folder_ignored_in_archive(path):
	# 	push_error("Finding plugin roots, folder ignored by archive: " % path)
	# 	return []
	# var file_abs := dir.get_current_dir().path_join(file)
	# print("\n\nfile ", file_abs, " in include paths ", include_paths, " ? ", file_abs in include_paths)
	for file in dir.get_files():
		# TODO i think this can just be file == ".gdignore"
		if file.ends_with(".gdignore"):
			# print("found .gdignore, returning []")
			return []
		# TODO see above
		if file.ends_with("plugin.cfg"):
			# print("found plugin.cfg, returning [%s]" % path)
			return [path]
	var cfg_paths : Array[String] = []
	for d in dir.get_directories():
		if d in ignore:
			# print("%s in %s, continuing..." % [d, ignore])
			continue
		cfg_paths.append_array(_find_plugin_roots(path.path_join(d), ignore, include_paths))
	# print("returning cfg paths: ", cfg_paths)
	return cfg_paths

static func get_plugin_root_relative_to_addons(plugin_root: String) -> String:
	return plugin_root.get_slice("/addons/", 1)

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

	# TODO remove symlinks - kind of a problem
	var err := OK
	for submodule_repo in _get_tracked_repos(from_path):
		var sm := Self.new()
		sm.repo = submodule_repo
		# installed_plugins.append_array(sm.get_plugins_in_project())
		for plugin in sm.get_plugins_in_project():
			installed_plugins[plugin] = sm
		for plugin in sm.get_enabled_plugin_roots():
			enabled_plugins[plugin] = sm
			set_plugin_enabled(plugin, false)
		err = sm.remove_from_project()
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

	for plugin: String in installed_plugins:
		var sm : Self = installed_plugins[plugin]
		var plugin_root := sm._plugin_root_from_plugin_name(plugin)
		err = sm.symlink_plugin(plugin_root)
		if err != OK:
			push_error("Failed to re-install %s" % plugin)
		else:
			print("Re-installed ", plugin)
	for plugin: String in enabled_plugins:
		set_plugin_enabled(plugin, true)
		print("Re-enabled", plugin)

	if err != OK:
		push_error(error_string(DirAccess.get_open_error()))
		_is_moving_submodule_dir = false
		return FAILED

	_is_moving_submodule_dir = false
	return OK

# this should work with res://addons, res://<submodule dir>, .../addons/, etc
static func set_plugin_enabled(plugin_root: String, value: bool) -> void:
	var plugin_name := get_plugin_root_relative_to_addons(plugin_root)
	if EditorInterface.is_plugin_enabled(plugin_name) != value:
		EditorInterface.set_plugin_enabled(plugin_name, value)

# TODO multiple copies of a plugin can't be differentiated here
# this should work with res://addons, res://<submodule dir>, .../addons/, etc
static func _is_plugin_enabled(plugin_root: String) -> bool:
	var plugin_name := get_plugin_root_relative_to_addons(plugin_root)
	return EditorInterface.is_plugin_enabled(plugin_name)

# TODO idea to simplify logic
# class TrackedEditorPluginAccess:
