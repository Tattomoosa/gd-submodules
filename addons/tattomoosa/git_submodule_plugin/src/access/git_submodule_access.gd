extends RefCounted

const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")
const TrackedEditorPluginAccess := preload("./tracked_editor_plugin_access.gd")
const GitIgnorer := preload("../git/git_ignorer.gd")
const GitArchiveIgnorer := GitIgnorer.GitArchiveIgnorer

const DebugProfiler := preload("../util/profiler.gd")
const L := preload("../util/logger.gd")
static var l: L.Logger:
	get: return L.get_logger(L.LogLevel.WARN, &"GitSubmoduleAccess")
static var p: L.Logger:
	get: return L.get_logger(L.LogLevel.WARN, &"Profiler:GitSubmoduleAccess")

var repo : String
var source_path : String
var plugins : Array[TrackedEditorPluginAccess]

static var submodules_folder : String:
	get: return GitSubmodulePlugin.submodules_root
var author : String:
	get: return repo.get_slice("/", 0)
var repo_name : String:
	get: return repo.get_slice("/", 1)

func _init(p_repo: String) -> void:
	repo = p_repo
	source_path = submodules_folder.path_join(repo)
	var sw := DebugProfiler.Stopwatch.new()
	plugins = _get_plugins()
	# sw.restart_and_log(
	# 	"load submodule plugins: %s" % plugins\
	# 		.map(func(x: TrackedEditorPluginAccess) -> String: return x.name),
	# 		p.info
	# 	)

func _get_plugins() -> Array[TrackedEditorPluginAccess]:
	var sw := DebugProfiler.Stopwatch.new()
	var roots := _find_plugin_roots()
	sw.restart_and_log("find plugin roots", p.debug)
	var plugs : Array[TrackedEditorPluginAccess] = []
	for root in roots:
		var plug := TrackedEditorPluginAccess.new(root)
		plugs.push_back(plug)
		sw.restart_and_log("load plugin %s" % plug.name, p.debug)
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

func get_upstream_url(cached := true) -> String:
	if cached and GitSubmodulePlugin.has_submodule_setting(repo, "remote_origin_url"):
		return GitSubmodulePlugin.get_submodule_setting(repo, "remote_origin_url")
	var output : Array[String] = []
	var os_err := _execute_at_source_path("git config --get remote.origin.url", output)
	if os_err != OK:
		return ""
	var origin := output[0].trim_suffix("\n")
	GitSubmodulePlugin.set_submodule_setting(repo, "remote_origin_url", origin)
	return origin

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
	var commit := commit_hash(true, false)
	var branch := branch_name(false)
	var plugin_roots : Array[String]
	var sw := DebugProfiler.Stopwatch.new()
	if !has_changes(false):
		if GitSubmodulePlugin.has_submodule_setting(repo, "plugin_roots"):
			var commit_in_settings : String = GitSubmodulePlugin.get_submodule_setting(repo, "commit", "")
			var branch_in_settings : String  = GitSubmodulePlugin.get_submodule_setting(repo, "branch", "")
			if commit_in_settings == commit and branch_in_settings == branch:
				l.debug("returning plugin roots from settings")
				sw.restart_and_log("get plugin roots for %s (from settings)" % repo, p.debug)
				return GitSubmodulePlugin.get_submodule_setting(repo, "plugin_roots")
	var addons_path := source_path.path_join("addons")
	var zip_file_path := submodules_folder.path_join(repo.replace("/", ".") + "." + commit_hash() +  ".zip")
	var ignorer := GitArchiveIgnorer.new(source_path, zip_file_path)
	l.debug("Finding plugin roots in filesystem...")
	plugin_roots = _find_plugin_roots_recursive(addons_path, ignorer)
	sw.restart_and_log("find plugin roots for %s (from parsing filesystem)" % repo, p.debug)
	GitSubmodulePlugin.set_submodule_setting(repo, "commit", commit)
	GitSubmodulePlugin.set_submodule_setting(repo, "branch", branch)
	GitSubmodulePlugin.set_submodule_setting(repo, "plugin_roots", plugin_roots)
	sw.restart_and_log("update settings", p.debug)
	return plugin_roots

func _find_plugin_roots_recursive(path: String, ignorer: GitArchiveIgnorer) -> Array[String]:
	var dir := DirAccess.open(path)
	if !dir:
		return []
	# TODO might have to change or move into GitArchiveIgnorer if using another ignorer
	var ignorer_trim_path_prefix := source_path + "/"
	if ignorer.ignores_path(path.replace(ignorer_trim_path_prefix, "") + "/"):
		l.debug("Path %s ignored by ignorer" % path.replace(ignorer_trim_path_prefix, "") + "/")
		return []
	dir.include_hidden = true
	for file in dir.get_files():
		if file.ends_with(".gdignore"):
			return []
		if file.ends_with("plugin.cfg"):
			return [path]
	var cfg_paths : Array[String] = []
	for d in dir.get_directories():
		cfg_paths.append_array(_find_plugin_roots_recursive(path.path_join(d), ignorer))
	return cfg_paths

func remove() -> Error:
	if !uninstall_all_plugins():
		push_error("Could not uninstall %s" % repo)

	var dir := DirAccess.open(source_path)
	if !dir:
		return ERR_CANT_OPEN

	dir.include_hidden = true
	if ".git" not in dir.get_files() or ".git" not in dir.get_directories():
		return ERR_FILE_BAD_PATH
	var err := dir.change_dir(submodules_folder)
	assert(err == OK)
	var output : Array[String] = []
	var os_err := _execute_at(dir.get_current_dir(), "git rm -f %s" % repo, output)
	if os_err != OK:
		push_error(output)
	err = _dir_cleanup(submodules_folder.path_join(author))
	if os_err == OK:
		return OK
	return FAILED

func _execute_at_source_path(cmd: String, output: Array[String] = []) -> int:
	var err := _execute_at(source_path, cmd, output)
	return err

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

func commit_hash(short := true, use_cached := true) -> String:
	if use_cached and GitSubmodulePlugin.has_submodule_setting(repo, "commit"):
		return GitSubmodulePlugin.get_submodule_setting(repo, "commit")
	var output : Array[String] = []
	var short_arg := "--short" if short else ""
	var os_err := _execute_at_source_path("git rev-parse %s HEAD" % short_arg, output)
	if os_err != OK:
		return ""
	var commit := output[0].trim_suffix("\n")
	GitSubmodulePlugin.set_submodule_setting(repo, "commit", commit)
	return commit

func branch_name(use_cached := true) -> String:
	if use_cached and GitSubmodulePlugin.has_submodule_setting(repo, "branch"):
		return GitSubmodulePlugin.get_submodule_setting(repo, "branch")
	var output : Array[String] = []
	var err := _execute_at_source_path("git symbolic-ref --short HEAD", output)
	if err != OK:
		return ""
	var branch := output[0].trim_suffix("\n")
	GitSubmodulePlugin.set_submodule_setting(repo, "branch", branch)
	return branch

func has_changes(use_cached := true) -> bool:
	if use_cached and GitSubmodulePlugin.has_submodule_setting(repo, "changes"):
		return GitSubmodulePlugin.get_submodule_setting(repo, "changes")
	var output: Array[String] = []
	var os_err := _execute_at_source_path("git status --porcelain", output)
	if os_err == OK and output.size() > 0:
		var changes := output[0].length() > 0
		GitSubmodulePlugin.set_submodule_setting(repo, "changes", changes)
		return changes
	return true

func is_tracked() -> bool:
	return FileAccess.file_exists(source_path.path_join(".git"))\
		or DirAccess.dir_exists_absolute(source_path.path_join(".git"))

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

static func add_submodule(
	p_repo: String,
	upstream_url: String = github_upstream_url(p_repo),
	branch : String = "",
	# TODO would need to checkout after add_submodule to go straight
	# to specific commit
	_commit: String = "",
	shallow: bool = false,
	# TODO i guess submodules can't be bare?
	_bare: bool = false,
	output: Array[String] = []
) -> Error:
	l.info("Cloning %s" % p_repo, " from %s" % upstream_url)
	var err : Error
	var os_err : int
	var author_name := p_repo.get_slice("/", 0)
	err = _make_dir(author_name)
	if !(err == OK or err == ERR_ALREADY_EXISTS):
		return err
	if !branch.is_empty():
		branch = "-b " + branch
	var shallow_text := "--depth=1" if shallow else ""
	# var bare_text := "--bare" if bare else ""
	var source_folder := submodules_folder.path_join(p_repo)
	# var author_folder := submodules_folder.path_join(author_name)
	var git_cmd := "git submodule add %s %s %s %s" % [
			shallow_text,
			# bare_text,
			branch,
			upstream_url,
			ProjectSettings.globalize_path(source_folder)
			# commit
		]
	os_err = _execute_at("res://", git_cmd, output)
	if os_err != OK:
		# TODO cleanup files
		push_error(output)
		return FAILED
	l.info("Added submodule %s" % p_repo)
	return err

func checkout(
	branch: String = "",
	commit: String = "",
	output: Array[String] = []
) -> Error:
	var checkout_string := branch if commit.is_empty() else commit
	l.info("Checking out %s" % checkout_string)
	var git_cmd := "git checkout %s" % checkout_string
	var os_err := _execute_at(source_path, git_cmd, output)
	if os_err != OK:
		push_error(output)
		return FAILED
	l.info("Checked out %s" % checkout_string)
	return OK

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
	var installed := install_all_plugins()
	if !installed:
		push_error("Created repo but was unable to install created plugin.")
	return err

static func _execute_at(path: String, cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	var os_cmd := 'cd \"%s\" && %s' % [path, cmd]
	l.debug("Executing " + os_cmd, l)
	var sw := DebugProfiler.Stopwatch.new()
	var err := OS.execute(
		"$SHELL",
		["-lc", os_cmd],
		output,
		true)
	sw.restart_and_log("execute '%s'" % cmd, p.debug)
	return err

static func github_upstream_url(p_repo: String) -> String:
	return "git@github.com:%s.git" % p_repo

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