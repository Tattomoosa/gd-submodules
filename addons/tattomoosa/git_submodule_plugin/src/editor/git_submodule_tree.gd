@tool
extends Tree

signal working
signal finished

@export var confirmation_dialog : ConfirmationDialog

enum Column {
	BLANK,
	TRACKED,
	LINKED,
	ACTIVE,
	REPO,
	BRANCH,
	COMMIT,
	EDIT,
	COLUMN_SIZE
}

const CONFIRM_DELETE_TEXT := "This action will remove %s from your file system."
const CONFIG_TEXT = """\
		Name: %s
		Description: %s
		Author: %s
		Version: %s
		Script: %s
		Installs to: %s\
		"""

const GIT_ICON := preload("../../icons/Git.svg")

const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")

var submodules : Array[GitSubmodulePlugin]
var _currently_deleting : GitSubmodulePlugin = null

func reset() -> void:
	await _set_working()
	for child in get_root().get_children():
		get_root().remove_child(child)
	submodules.clear()
	build()
	_set_finished()

func build() -> void:
	var root := get_root()
	for submodule_repo in GitSubmodulePlugin.get_tracked_repos():
		var submodule := GitSubmodulePlugin.new()
		submodules.push_back(submodule)
		submodule.repo = submodule_repo
		var item := root.create_child()
		item.collapsed = true
		item.set_metadata(0, submodule)
		item.add_button(Column.EDIT, get_theme_icon("Edit", "EditorIcons"))
		_build_submodule_tree_item(item)

func _confirmation_dialog_cancel() -> void:
	_currently_deleting = null
	reset()

func _confirmation_dialog_confirm() -> void:
	var err := _currently_deleting.remove_submodule()
	if err != OK:
		push_error(error_string(err))
	reset()

@warning_ignore("return_value_discarded")
func _ready() -> void:
	confirmation_dialog.title = "Delete files?"
	create_item()
	# add_theme_constant_override("draw_relationship_lines", 0)
	hide_root = true
	columns = Column.COLUMN_SIZE
	set_column_expand(Column.BLANK, false)
	set_column_custom_minimum_width(Column.BLANK, 80)
	set_column_clip_content(Column.BLANK, true)
	set_column_expand_ratio(Column.BLANK, SIZE_SHRINK_BEGIN)

	set_column_title(Column.TRACKED, "Track")
	set_column_expand(Column.TRACKED, false)

	set_column_title(Column.LINKED, "Install")
	set_column_expand(Column.LINKED, false)

	set_column_title(Column.ACTIVE, "Enable")
	set_column_expand(Column.ACTIVE, false)

	set_column_title(Column.REPO, "Repo")
	set_column_expand(Column.REPO, true)
	set_column_expand_ratio(Column.REPO, SIZE_EXPAND)

	set_column_title(Column.BRANCH, "Branch")
	set_column_expand(Column.BRANCH, true)
	set_column_custom_minimum_width(Column.BRANCH, 120)
	set_column_expand_ratio(Column.BRANCH, SIZE_SHRINK_BEGIN)

	set_column_title(Column.COMMIT, "Commit")
	set_column_expand_ratio(Column.COMMIT, SIZE_SHRINK_BEGIN)
	set_column_custom_minimum_width(Column.COMMIT, 150)
	set_column_expand(Column.COMMIT, true)

	set_column_title(Column.EDIT, "Edit")
	set_column_expand(Column.EDIT, false)

	for c in columns:
		set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT)

	await _set_working()
	build.call_deferred()
	_set_finished()

	button_clicked.connect(_button_clicked)
	item_edited.connect(_item_edited)
	visibility_changed.connect(_on_visibility_changed)
	confirmation_dialog.confirmed.connect(_confirmation_dialog_confirm)
	confirmation_dialog.canceled.connect(_confirmation_dialog_cancel)

func _button_clicked(item: TreeItem, col: int, _id: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return

	if col != Column.EDIT:
		push_error("What button at %s?" % col)

	if col == Column.EDIT:
		print("COLUMN EDIT")
		item.set_editable(Column.BRANCH, true)
		item.set_editable(Column.COMMIT, true)
		return

func _on_visibility_changed() -> void:
	if !is_visible_in_tree():
		return
	var root := get_root()
	if !root:
		push_error("Visibility changed - Tree has no root")

func _set_working() -> void:
	working.emit()
	# TODO why do we have to wait 2 frames just to get the status indicator up?
	# Shouldn't it only need one?
	for i in 2:
		await get_tree().process_frame

func _set_finished() -> void:
	finished.emit()

func _item_edited() -> void:
	var item := get_selected()
	var col := get_selected_column()
	var data : Variant = item.get_metadata(0)
	# var checked := false if item.is_indeterminate(col) else item.is_checked(col)
	var checked := item.is_checked(col)

	await _set_working()
	if data is GitSubmodulePlugin:
		var err := OK
		var submodule : GitSubmodulePlugin = data

		match col:
			Column.TRACKED:
				if checked:
					err = submodule.clone()
				else:
					# err = submodule.remove_submodule()
					_currently_deleting = submodule
					confirmation_dialog.show()
					item.set_checked(col, false)
					return
				EditorInterface.get_resource_filesystem().scan()
			Column.LINKED:
				if checked:
					err = submodule.symlink_all_plugins()
				else:
					_set_all_submodule_plugins_enabled(submodule, false)
					err = submodule.remove_from_project()
				EditorInterface.get_resource_filesystem().scan()
			Column.ACTIVE:
				var indeterminate := _is_enabled_indeterminate(submodule)
				if indeterminate:
					checked = false
				if submodule.is_linked():
					_set_all_submodule_plugins_enabled(submodule, checked)
		if err != OK:
			push_warning(error_string(err))
		_update_submodule_checks.call_deferred(item)

	# TODO better naming, typing
	# GitSubmodulePlugin should be just GitSubmodule?
	# Then here instead of just plugin name String, should be
	# like GitSubmoduleGodotPlugin or something?
	if data is String:
		var plugin_root : String = data
		var submodule : GitSubmodulePlugin = item.get_parent().get_metadata(0)
		var err : Error

		_set_working()
		match col:
			Column.LINKED:
				if checked:
					err = submodule.symlink_plugin(plugin_root)
				else:
					err = submodule.remove_plugin_from_project(plugin_root.split("/")[-1])
				EditorInterface.get_resource_filesystem().scan()
			Column.ACTIVE:
				GitSubmodulePlugin.set_plugin_enabled(plugin_root, checked)

		if err != OK:
			push_warning(error_string(err))
		_update_submodule_checks.call_deferred(item.get_parent())

	_set_finished()

func _set_all_submodule_plugins_enabled(submodule: GitSubmodulePlugin, to_value: bool) -> void:
	var plugin_roots := submodule.find_submodule_plugin_roots()
	for plugin_root in plugin_roots:
		GitSubmodulePlugin.set_plugin_enabled(plugin_root, to_value)

@warning_ignore("narrowing_conversion")
func _build_submodule_tree_item(item: TreeItem) -> void:
	var submodule : GitSubmodulePlugin = item.get_metadata(0)
	var submodule_plugins := submodule.find_submodule_plugin_roots()
	var c := Column.BLANK

	item.set_selectable(c, false)
	item.set_cell_mode(c, TreeItem.CELL_MODE_CUSTOM)

	var icon_scale := 16 * EditorInterface.get_editor_scale()
	for c_i: int in [Column.TRACKED, Column.LINKED, Column.ACTIVE]:
		item.set_cell_mode(c_i, TreeItem.CELL_MODE_CHECK)
		item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)

	item.set_icon(Column.TRACKED, GIT_ICON)
	item.set_icon_max_width(Column.TRACKED, icon_scale)
	item.set_icon(Column.LINKED, get_theme_icon("Load", "EditorIcons"))
	item.set_icon_max_width(Column.LINKED, icon_scale)


	item.set_text(Column.REPO, submodule.repo)
	item.set_text(Column.BRANCH, submodule.branch_name())
	item.set_text(Column.COMMIT, submodule.commit_hash())

	item.set_text_alignment(Column.EDIT, HORIZONTAL_ALIGNMENT_CENTER)

	var config_texts : PackedStringArray = []
	for i in submodule_plugins.size():
		var plugin_item := item.create_child()
		var cfg_file := submodule.get_config(i)
		var plugin_submodule_path := submodule_plugins[i]
		var relative_path := GitSubmodulePlugin.get_plugin_root_relative_to_addons(plugin_submodule_path)
		var project_absolute_path := "res://addons/".path_join(relative_path)
		var plugin_name : String = cfg_file.get_value("plugin", "name", "")
		var version : String = cfg_file.get_value("plugin", "version", "")
		plugin_item.collapsed = true
		plugin_item.set_metadata(0, submodule_plugins[i])

		plugin_item.set_text(Column.REPO, "%s %s" % [plugin_name, (" v%s" % version) if version else ""])

		plugin_item.set_text_alignment(Column.TRACKED, HORIZONTAL_ALIGNMENT_CENTER)
		plugin_item.set_editable(Column.TRACKED, false)

		c = Column.BLANK
		plugin_item.set_selectable(c, false)
		plugin_item.set_cell_mode(c, TreeItem.CELL_MODE_CUSTOM)

		c = Column.TRACKED
		plugin_item.set_selectable(c, false)
		plugin_item.set_cell_mode(c, TreeItem.CELL_MODE_CUSTOM)

		c = Column.LINKED
		plugin_item.set_cell_mode(c, TreeItem.CELL_MODE_CHECK)
		plugin_item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
		plugin_item.set_icon_max_width(c, 16 * EditorInterface.get_editor_scale())
		plugin_item.set_icon(c, get_theme_icon("Load", "EditorIcons"))
		plugin_item.set_icon_max_width(c, 16 * EditorInterface.get_editor_scale())

		c = Column.ACTIVE
		plugin_item.set_cell_mode(c, TreeItem.CELL_MODE_CHECK)
		plugin_item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
		plugin_item.set_icon_max_width(c, 16 * EditorInterface.get_editor_scale())

		# var plugin_item_color := get_theme_color("dark_color_2", "Editor")
		# for p_i: int in [Column.BLANK, Column.REPO, Column.TRACKED, Column.LINKED, Column.ACTIVE]:
		# 	plugin_item.set_custom_bg_color(p_i, plugin_item_color)

		var config_text := CONFIG_TEXT % [
			cfg_file.get_value("plugin", "name", ""),
			cfg_file.get_value("plugin", "description", ""),
			cfg_file.get_value("plugin", "author", ""),
			cfg_file.get_value("plugin", "version", ""),
			cfg_file.get_value("plugin", "script", ""),
			project_absolute_path
		]
		@warning_ignore("return_value_discarded")
		config_texts.append(config_text)
		plugin_item.set_tooltip_text(Column.REPO, config_text)

		var config_item := plugin_item.create_child()
		for c_i in Column.COLUMN_SIZE:
			config_item.set_selectable(c_i, false)
		c = Column.REPO
		config_item.set_text(c, config_text)
		config_item.set_autowrap_mode(c, TextServer.AUTOWRAP_WORD_SMART)
		config_item.set_selectable(c, true)
		# var config_item_color := get_theme_color("dark_color_3", "Editor")
		# for c_i: int in [Column.BLANK, Column.REPO, Column.TRACKED, Column.LINKED, Column.ACTIVE]:
		# 	config_item.set_custom_bg_color(c_i, config_item_color)
	item.set_tooltip_text(c, "\n\n".join(config_texts))

	_update_submodule_checks(item)

@warning_ignore("narrowing_conversion")
func _update_submodule_checks(item: TreeItem) -> void:
	# await get_tree().process_frame
	var submodule : GitSubmodulePlugin = item.get_metadata(0)
	var submodule_plugins := submodule.find_submodule_plugin_roots()
	var submodule_enabled_plugins := submodule.get_enabled_plugin_roots()
	var is_active := submodule_enabled_plugins.size() > 0

	var c := Column.TRACKED
	item.set_checked(c, submodule.is_tracked())
	item.set_editable(c, !submodule.is_linked())
	if submodule.is_tracked():
		item.set_icon_modulate(c, Color(Color.WHITE, 0.4))
	else:
		item.set_icon_modulate(c, Color(Color.WHITE, 0.1))

	c = Column.LINKED
	item.set_editable(c, !is_active)
	item.set_checked(c, submodule.is_linked())
	if submodule.is_linked():
		if !submodule.has_all_plugins_in_project():
			item.set_indeterminate(c, true)
		else:
			item.set_indeterminate(c, false)

		item.set_icon_modulate(c, Color(Color.WHITE, 0.4))
	else:
		item.set_indeterminate(c, false)
		item.set_icon_modulate(c, Color(Color.WHITE, 0.1))

	c = Column.ACTIVE
	if is_active:
		item.set_editable(Column.LINKED, false)
		item.set_checked(c, true)
		var indeterminate := _is_enabled_indeterminate(submodule)
		item.set_indeterminate(c, indeterminate)
		var theme_icon := "GuiRadioCheckedDisabled" if indeterminate else "StatusSuccess"
		item.set_icon(c, get_theme_icon(theme_icon, &"EditorIcons"))
	else:
		item.set_indeterminate(c, false)
		item.set_checked(c, false)
		item.set_editable(Column.LINKED, true)
		item.set_icon(c, get_theme_icon("GuiRadioUnchecked", "EditorIcons"))

	if submodule.is_linked() and submodule.is_tracked():
		item.set_editable(Column.ACTIVE, true)
	else:
		item.set_editable(Column.ACTIVE, false)

	for i in submodule_plugins.size():
		var plugin_submodule_path := submodule_plugins[i]
		var relative_path := GitSubmodulePlugin.get_plugin_root_relative_to_addons(plugin_submodule_path)
		var plugin_item := item.get_child(i)
		var folder_root_name := plugin_submodule_path.split("/")[-1]
		var is_linked := submodule.has_plugin_in_project(folder_root_name)

		c = Column.LINKED
		plugin_item.set_checked(c, is_linked)
		if submodule.is_linked():
			plugin_item.set_icon_modulate(c, Color(Color.WHITE, 0.4))
		else:
			plugin_item.set_icon_modulate(c, Color(Color.WHITE, 0.1))

		c = Column.ACTIVE
		plugin_item.set_checked(c, EditorInterface.is_plugin_enabled(relative_path))
		plugin_item.set_editable(c, is_linked)
		if plugin_item.is_checked(c):
			plugin_item.set_editable(Column.LINKED, false)
			plugin_item.set_icon(c, get_theme_icon("StatusSuccess", "EditorIcons"))
		else:
			plugin_item.set_editable(Column.LINKED, true)
			plugin_item.set_icon(c, get_theme_icon("GuiRadioUnchecked", "EditorIcons"))
		# await get_tree().process_frame

func _is_enabled_indeterminate(submodule: GitSubmodulePlugin) -> bool:
	var submodule_enabled_plugins := submodule.get_enabled_plugin_roots()
	if submodule_enabled_plugins.is_empty():
		return false
	var submodule_plugins := submodule.find_submodule_plugin_roots()
	return submodule_enabled_plugins.size() < submodule_plugins.size()