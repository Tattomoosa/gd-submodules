@warning_ignore("return_value_discarded")
class_name TestGitSubmodulePlugin
extends GdUnitTestSuite

const GitSubmodulePlugin := preload("res://addons/tattomoosa/git_submodule_plugin/src/git_submodule_plugin.gd")

var TEST_REPO := "test_author/test_plugin"
var MOCK_REPO_DELETE_PATH := "res://submodules/test_author"
var MOCK_REPO_SUBMODULE_PATH := "res://submodules/test_author/test_plugin"
var MOCK_REPO_ADDON_PATH := "res://submodules/test_author/test_plugin/addons/test_repo"

const TEST_PLUGIN_CFG := """\
[plugin]
name="test_plugin"
description="test_description"
author="test_author"
version="0.1.0"
script="plugin.gd"
"""
const TEST_PLUGIN_GD := """\
@tool
extends EditorPlugin

func _enter_tree() -> void:
  pass

func _exit_tree() -> void:
  pass
"""

func before() -> void:
	_make_mock_repo()

func after() -> void:
	pass
	# _remove_mock_repo()

func test_set_repo() -> void:
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = TEST_REPO
	assert_str(submodule.repo).is_equal(TEST_REPO)

func test_finds_test_repo_submodule_directory() -> void:
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = TEST_REPO
	assert_str(submodule.get_submodule_path()).is_equal(MOCK_REPO_SUBMODULE_PATH)

func test_sees_test_repo_as_tracked() -> void:
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = TEST_REPO
	await get_tree().process_frame
	assert_bool(submodule.is_tracked()).is_true()

func test_gets_test_repo_commit_hash() -> void:
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = TEST_REPO
	assert_str(submodule.commit_hash()).is_not_empty()

func test_gets_test_repo_branch() -> void:
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = TEST_REPO
	assert_str(submodule.branch_name()).is_not_empty()

func test_gets_test_repo_config_file() -> void:
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = TEST_REPO
	var config := submodule.get_config()
	assert_that(config).is_not_null()
	assert_str(config.get_value("plugin", "name")).is_equal("test_plugin")







func _make_mock_repo() -> void:
	var path := MOCK_REPO_ADDON_PATH
	var err := DirAccess.make_dir_recursive_absolute(path)
	assert(err == OK)
	var cfg_file := FileAccess.open(path.path_join("plugin.cfg"), FileAccess.WRITE)
	assert(cfg_file != null)
	cfg_file.store_string(TEST_PLUGIN_CFG)
	var plugin_gd := FileAccess.open(path.path_join("plugin.gd"), FileAccess.WRITE)
	assert(plugin_gd != null)
	plugin_gd.store_string(TEST_PLUGIN_GD)
	assert(err == OK)
	var output := []
	var mock_repo_path := ProjectSettings.globalize_path(MOCK_REPO_SUBMODULE_PATH)
	var cmd := " ".join(["cd \"%s\"" % mock_repo_path, "&& git init && echo wow >> file.txt && git add -A && git commit -m 'ok'"])
	var os_err := OS.execute(
		"$SHELL", [
			"-lc",
			cmd
		], output, true)
	# push_error(output)
	assert(os_err == OK)

func _remove_mock_repo() -> void:
	_delete_recursive(MOCK_REPO_DELETE_PATH)
	
func _delete_recursive(path: String) -> void:
	print(path)
	var err : Error
	var dir := DirAccess.open(path)
	if !dir:
		push_error("WTF")
		push_error(error_string(DirAccess.get_open_error()))
		return
	dir.include_hidden = true
	for d in dir.get_directories():
		_delete_recursive(dir.get_current_dir().path_join(d))
	for file in dir.get_files():
		err = dir.remove(file)
		assert(err == OK)
	err = dir.change_dir("..")
	assert(err == OK)
	err = dir.remove(path)
	assert(err == OK)
