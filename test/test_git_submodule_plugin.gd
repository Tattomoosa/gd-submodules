extends GdUnitTestSuite

const GitSubmodulePlugin := preload("res://addons/tattomoosa/git_submodule_plugin/src/git_submodule_plugin.gd")

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

var MOCK_REPO_PATH := "res://submodules/test_author/test_repo/addons/test_repo"
var MOCK_REPO_DELETE_PATH := "res://submodules/"

func before() -> void:
	_make_mock_repo()

func after() -> void:
	_remove_mock_repo()

func _make_mock_repo() -> void:
	var path := MOCK_REPO_PATH
	var err := DirAccess.make_dir_recursive_absolute(path)
	assert(err == OK)
	var cfg_file := FileAccess.open(path.path_join("plugin.cfg"), FileAccess.WRITE)
	assert(cfg_file != null)
	cfg_file.store_string(TEST_PLUGIN_CFG)
	var plugin_gd := FileAccess.open(path.path_join("plugin.gd"), FileAccess.WRITE)
	assert(plugin_gd != null)
	plugin_gd.store_string(TEST_PLUGIN_GD)
	assert(err == OK)
	var os_err := OS.execute("$SHELL", ["-lc", "cd %s && git init" % path])
	assert(os_err == OK)

func _remove_mock_repo() -> void:
	_delete_recursive(MOCK_REPO_DELETE_PATH)
	
func _delete_recursive(path: String) -> void:
	var err : Error
	var dir := DirAccess.open(path)
	for d in dir.get_directories():
		_delete_recursive(d)
	for file in dir.get_files():
		err = dir.remove(file)
		assert(err == OK)
	err = dir.change_dir("..")
	assert(err == OK)
	err = dir.remove(path)
	assert(err == OK)

func test_can_find_mock_repo() -> void:
	var submodule := GitSubmodulePlugin.new()
	# return assert_str("King Arthur").is_equal("King Arthur")