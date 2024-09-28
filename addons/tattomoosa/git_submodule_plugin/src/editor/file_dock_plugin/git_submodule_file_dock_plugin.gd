@tool
extends Control

const L := preload("../../util/logger.gd")
static var l: L.Logger:
	get: return L.get_logger(L.LogLevel.INFO, "GitSubmoduleFileDockPlugin")
const DebugProfiler := preload("../../util/profiler.gd")
static var p: L.Logger:
	get: return L.get_logger(L.LogLevel.WARN, "Profiler:GitSubmoduleFileDockPlugin")

const PRINT_DEBUG_MESSAGES := false
const DEBUG_CLASS_NAME := "GitSubmoduleFileDockPlugin"
const FADE_COLOR := Color(1, 1, 1, 0.5)
const UNINSTALLED_COLOR := Color(1, 1, 1, 0.2)

const GIT_ICON := preload("../../../icons/Git.svg")
const REPO_CHANGES_ICON := preload("../../../icons/GitChanges.svg")

const GitSubmodulePlugin := preload("../../git_submodule_plugin.gd")
const GitSubmoduleAccess := GitSubmodulePlugin.GitSubmoduleAccess
const TrackedEditorPluginAccess := GitSubmodulePlugin.TrackedEditorPluginAccess

var file_system_dock : FileSystemDock
var file_tree : Tree
var active := true
var mouse_inside := false

var plugin_icon : Texture2D
var git_icon : Texture2D
var changes_icon : Texture2D

func _ready() -> void:
	plugin_icon = get_theme_icon("EditorPlugin", "EditorIcons")

@warning_ignore("return_value_discarded")
func initialize() -> void:
	l.debug("Initializing GitSubmoduleFileDockPlugin")
	# Non-native Godot icon is big and needs to be resized, would probably be better to do this in the file itself..
	git_icon = _resize_icon(GIT_ICON.get_image())
	# TODO placeholder, need better git status icons
	changes_icon = REPO_CHANGES_ICON
	EditorInterface.get_editor_main_screen().add_child(self)
	file_tree = _find_file_tree()
	if !file_tree:
		push_error(DEBUG_CLASS_NAME, " file tree not found.")
	if !file_tree.is_node_ready():
		l.debug("Awaiting file tree.ready")
		await file_tree.ready
	patch_dock()
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(patch_dock)
	file_tree.resized.connect(patch_dock)
	file_system_dock = EditorInterface.get_file_system_dock()
	file_system_dock.display_mode_changed.connect(patch_dock)
	# file_system_dock.file_removed.connect(_defer_patch_dock.unbind(1))
	# file_system_dock.files_moved.connect(_defer_patch_dock.unbind(2))
	# file_system_dock.folder_color_changed.connect(_defer_patch_dock)
	# file_system_dock.folder_moved.connect(_defer_patch_dock.unbind(2))
	# file_system_dock.folder_removed.connect(_defer_patch_dock.unbind(1))
	file_system_dock.inherit.connect(patch_dock.unbind(1))
	file_system_dock.instantiate.connect(patch_dock.unbind(1))
	# file_tree.mouse_entered.connect(_on_mouse_entered)
	# file_tree.mouse_exited.connect(_on_mouse_exited)
	# file_system_dock.resource_removed.connect(_defer_patch_dock.unbind(1))
	ProjectSettings.settings_changed.connect(patch_dock)
	_connect_file_filter()

# TODO this is a hack to keep updating during file search etc and there is probably a better way
@warning_ignore("return_value_discarded")
func _connect_file_filter() -> void:
	# First line edit isn't the filter, it's just the path edit
	var found_first_line_edit := false
	for c0 in file_system_dock.get_children():
		for c1 in c0.get_children():
			for c2 in c1.get_children():
				if c2 is LineEdit and !found_first_line_edit:
					found_first_line_edit = true
					continue
				if c2 is LineEdit:
					var le := c2 as LineEdit
					# le.mouse_entered.connect(_on_mouse_entered)
					# le.mouse_exited.connect(_on_mouse_exited)
					# le.gui_input.connect(patch_dock.unbind(1))
					le.gui_input.connect(_on_file_dock_gui_input)
					return


func _on_file_dock_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		patch_dock()

# func _on_mouse_entered() -> void:
# 	mouse_inside = true
# 	_on_file_dock_gui_input()

# func _on_mouse_exited() -> void:
# 	mouse_inside = false

# func _on_file_dock_gui_input() -> void:
# 	patch_dock()
# 	if mouse_inside:
# 		await get_tree().process_frame
# 		_on_file_dock_gui_input.call_deferred()

# Patch file dock with git plugin information
@warning_ignore("return_value_discarded")
func patch_dock() -> void:
	l.debug("Patching file dock")
	if !active:
		l.debug("Aborted patching file dock - not active")
		return

	var stopwatch := DebugProfiler.Stopwatch.new()
	var root := file_tree.get_root()
	var addons_item : TreeItem = _parse_file_tree_depth_first(root, "addons")
	if !addons_item:
		l.debug("res://addons not found!")
		return
	var addon_item := addons_item.get_first_child()
	stopwatch.restart_and_log("find the addons folder item in the file tree dock", p.debug)
	var submodules := GitSubmodulePlugin.get_tracked_submodules()
	var installed_plugins := {}
	for sm in submodules:
		for ip in sm.get_installed_plugins():
			installed_plugins[ip.name] = {"plugin": ip, "submodule": sm}
	stopwatch.restart_and_log("load submodules", p.debug)

	if installed_plugins.is_empty():
		l.debug("Empty addon paths")
		return
	stopwatch.restart()
	var sw := DebugProfiler.Stopwatch.new()
	while addon_item != null:
		_patch_addon_folder_item(addon_item, installed_plugins)
		sw.restart_and_log("patch %s" % addon_item.get_text(0), p.debug)
		addon_item = addon_item.get_next()
	stopwatch.restart_and_log("patch folder items", p.info)

# Patch file dock's tree item with git plugin information
@warning_ignore("return_value_discarded")
func _patch_addon_folder_item(folder_item: TreeItem, installed_plugins: Dictionary, parent: String = "") -> bool:
	l.debug("Evaluating patch for " + folder_item.get_text(0))
	var folder_name := folder_item.get_text(0)
	var from_addons_path := parent.path_join(folder_name)
	l.debug("Matching path: " + from_addons_path)
	var matching_addon_paths : Array[String]
	matching_addon_paths.assign(
		installed_plugins.keys().filter(
			func(x: String) -> bool:
				return x.begins_with(from_addons_path))
		)
	# no match
	l.debug("Matching addon paths " + str(matching_addon_paths))
	if matching_addon_paths.is_empty():
		l.debug("No matching addon paths found for " + folder_name)
		return false
	# one match, patch item
	if matching_addon_paths.size() == 1 and from_addons_path == matching_addon_paths[0]:
		var path := matching_addon_paths[0]
		# { plugin.name : "plugin", "submodule" }
		var data : Dictionary = installed_plugins[path]
		_patch_folder_modify_item(folder_item, data)
		installed_plugins.erase(path)
		return true
	var matching_installed_plugins := {}
	for key in matching_addon_paths:
		matching_installed_plugins[key] = installed_plugins[key]
	# if all children are managed, still dim the folder
	var all_true_test := folder_item.get_child_count() > 0
	for child in folder_item.get_children():
		if !_patch_addon_folder_item(child, matching_installed_plugins, parent.path_join(folder_name)):
			# at least one child is unmanaged
			all_true_test = false
	if all_true_test:
		# no git icon here but still dim since all children are managed
		folder_item.set_custom_color(0, Color(1, 1, 1, 0.4))
		return true
	return false

# Modify a folder item with our patch
func _patch_folder_modify_item(folder_item: TreeItem, data: Dictionary) -> void:
	l.debug("Modifying folder item: " + folder_item.get_text(0))
	var icon := plugin_icon
	folder_item.set_icon(0, icon)

	if folder_item.get_button_count(0) < 1:
		folder_item.add_button(0, changes_icon, 1, false, "Git repo has changes")
	if folder_item.get_button_count(0) < 2:
		folder_item.add_button(0, git_icon, 0, false, "Managed by GitSubmodulePlugin")

	if (data["plugin"] as TrackedEditorPluginAccess).is_enabled():
		folder_item.set_custom_color(0, FADE_COLOR)
		folder_item.set_button_color(0, 0, FADE_COLOR)
		folder_item.set_button_color(0, 1, FADE_COLOR)
		folder_item.set_icon_modulate(0, get_theme_color("accent_color", "Editor"))
	else:
		folder_item.set_custom_color(0, UNINSTALLED_COLOR)
		folder_item.set_button_color(0, 1, UNINSTALLED_COLOR)
		folder_item.set_button_color(0, 0, UNINSTALLED_COLOR)
		folder_item.set_icon_modulate(0, Color(Color.WHITE, 0.2))

	# git changes
	if !(data["submodule"] as GitSubmoduleAccess).has_changes():
		folder_item.set_button_color(0, 0, Color.TRANSPARENT)

# Finds the actual tree element in the FileManager dock
func _find_file_tree() -> Tree:
	if !is_instance_valid(file_system_dock):
		file_system_dock = EditorInterface.get_file_system_dock()
	for c0 in file_system_dock.get_children():
		if c0 is SplitContainer:
			for c1 in c0.get_children():
				if c1 is Tree:
					return c1
	return null

# Find a file/directory with name
func _parse_file_tree_depth_first(root: TreeItem, seeking : String) -> TreeItem:
	if !root:
		return
	var text := root.get_text(0)
	if text == seeking:
		return root
	var child := _parse_file_tree_depth_first(root.get_first_child(), seeking)
	var next := _parse_file_tree_depth_first(root.get_next(), seeking)
	if child != null:
		return child
	return next

# Resize icon to 16*16
func _resize_icon(image: Image) -> Texture2D:
	var editor_scale := EditorInterface.get_editor_scale()
	var dim := int(16 * editor_scale)
	image.resize(dim, dim)
	return ImageTexture.create_from_image(image)

# Trigger a scan to clear modifications
func _exit_tree() -> void:
	active = false
	EditorInterface.get_resource_filesystem().scan()