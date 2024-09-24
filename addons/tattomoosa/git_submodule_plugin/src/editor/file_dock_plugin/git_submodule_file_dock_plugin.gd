@tool
extends Control

const FADE_COLOR := Color(1, 1, 1, 0.4)
const GIT_ICON := preload("../../../icons/Git.svg")
const GitSubmodulePlugin := preload("../../git_submodule_plugin.gd")

var file_system_dock : FileSystemDock
var file_tree : Tree
var active := true
var mouse_inside := true

var plugin_icon : Texture2D
var git_icon : Texture2D

func _ready() -> void:
	plugin_icon = get_theme_icon("EditorPlugin", "EditorIcons")

@warning_ignore("return_value_discarded")
func initialize() -> void:
	git_icon = _resize_icon(GIT_ICON.get_image())
	EditorInterface.get_editor_main_screen().add_child(self)
	file_tree = _find_file_tree()
	if !file_tree.is_node_ready():
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
	# file_system_dock.resource_removed.connect(_defer_patch_dock.unbind(1))
	# file_tree.get_parent().gui_input.connect(patch_dock.unbind(1))
	# file_tree.mouse_entered.connect(_on_mouse_entered)
	# file_tree.mouse_exited.connect(_on_mouse_exited)

# func _on_mouse_entered() -> void:
# 	print("mouse enter")
# 	mouse_inside = true

# func _on_mouse_exited() -> void:
# 	print("mouse exit")
# 	mouse_inside = false

# func _process(delta: float) -> void:
# 	if mouse_inside:
# 		patch_dock()

# Patch file dock with git plugin information
@warning_ignore("return_value_discarded")
func patch_dock() -> void:
	if !active:
		return

	var root := file_tree.get_root()
	var addons_item : TreeItem = _parse_file_tree_depth_first(root, "addons")
	if !addons_item:
		return
	var addon_item := addons_item.get_first_child()
	var addon_paths : Array[String] = GitSubmodulePlugin.get_all_managed_plugin_folder_names()
	while addon_item != null:
		_patch_addon_folder_item(addon_item, addon_paths)
		addon_item = addon_item.get_next()

# Patch file dock's tree item with git plugin information
func _patch_addon_folder_item(folder_item: TreeItem, addon_paths: Array[String]) -> bool:
	var folder_name := folder_item.get_text(0)
	var matching_addon_paths : Array[String]
	matching_addon_paths.assign(
		addon_paths.filter(func(x: String) -> bool: return x.begins_with(folder_name)))
	# no match
	if matching_addon_paths.is_empty():
		return false
	# one match, patch item
	if matching_addon_paths.size() == 1 and folder_name == matching_addon_paths[0]:
		_patch_folder_modify_item(folder_item)
		addon_paths.erase(matching_addon_paths[0])
		return true
	# trim this folder off matching path and recurse
	var child_matching_addon_paths : Array[String]
	child_matching_addon_paths.assign(
		matching_addon_paths.map(func(x: String) -> String: return x.get_slice("/", 1))
	)
	# if all children are managed, still dim the folder
	var all_true_test := folder_item.get_child_count() > 0
	for child in folder_item.get_children():
		if !_patch_addon_folder_item(child, child_matching_addon_paths):
			# at least one child is unmanaged
			all_true_test = false
	if all_true_test:
		# no git icon here but still dim since all children are managed
		folder_item.set_custom_color(0, Color(1, 1, 1, 0.4))
		return true
	return false

# Modify a folder item with our patch
func _patch_folder_modify_item(folder_item: TreeItem) -> void:
	folder_item.set_icon(0, plugin_icon)
	folder_item.set_custom_color(0, FADE_COLOR)
	if folder_item.get_button_count(0) < 1:
		# TODO listen to buttons
		folder_item.add_button(0, git_icon, -1, false, "Managed by GitSubmodulePlugin")
	folder_item.set_button_color(0, 0, FADE_COLOR)

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