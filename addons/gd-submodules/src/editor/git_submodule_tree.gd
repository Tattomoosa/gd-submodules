@tool
extends Tree

# includes
const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")
const GitSubmoduleAccess := GitSubmodulePlugin.GitSubmoduleAccess
const TrackedEditorPluginAccess := GitSubmodulePlugin.TrackedEditorPluginAccess

# Logger
const L := preload("../util/logger.gd")
const DebugProfiler := preload("../util/profiler.gd")
static var l: L.Logger:
	get: return L.get_logger(L.LogLevel.INFO, "GitSubmoduleSettingsTree")
static var p: L.Logger:
	get: return L.get_logger(L.LogLevel.WARN, "Profiler:GitSubmoduleSettingsTree")

const REPO_CHANGES_ICON := preload("../../icons/GitChanges.svg")

signal working
signal finished
signal edit_submodule(submodule: GitSubmoduleAccess)

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
enum RepoColumnButtonIndex {
	HAS_CHANGES,
	# TODO can pull
	CAN_PULL,
}
enum EditColumnButtonIndex {
	EDIT_REPO,
	EDIT_IN_GODOT,
	TERMINAL
}

const PRINT_DEBUG_MESSAGES := true
const PRINT_PREFIX := "[GitSubmodulePluginsSettingsTree]"
const CONFIRM_DELETE_TEXT := "This action will remove %s from your file system."
const CONFIG_TEXT = """\
		Name: %s
		Description: %s
		Author: %s
		Version: %s
		Script: %s
		Installs to: %s\
		"""

const ACTIVE_ICON_COLOR := Color(Color.WHITE)
const CHECKED_ICON_COLOR := Color(Color.WHITE, 0.5)
const NOT_CHECKED_ICON_COLOR := Color(Color.WHITE, 0.2)

const GIT_ICON := preload("../../icons/Git.svg")

var submodules : Array[GitSubmoduleAccess]
var _currently_deleting : GitSubmoduleAccess = null

func reset() -> void:
	l.debug("Tree reloading...")
	if !is_visible_in_tree():
		l.debug("Tree not visible. Cancelled reload.")
		return
	await _set_working()
	for child in get_root().get_children():
		get_root().remove_child(child)
	submodules.clear()
	build()
	_set_finished()
	l.debug("Tree reloaded")

# hard reset, tells plugin to reload all data
func reset_git_submodule_plugin() -> void:
	await _set_working()
	GitSubmodulePlugin.reset_internal_state()
	reset()

func build() -> void:
	var stopwatch := DebugProfiler.Stopwatch.new()
	var root := get_root()
	var tracked_submodules := GitSubmodulePlugin.get_tracked_submodules()
	for submodule in tracked_submodules:
		var sw := DebugProfiler.Stopwatch.new()
		submodules.push_back(submodule)
		var item := root.create_child()
		item.collapsed = true
		item.set_metadata(0, submodule)
		_build_submodule_tree_item(item)
		sw.restart_and_log("build submodule tree item for %s" % submodule.repo, p.debug)
	stopwatch.restart_and_log("build submodule tree", p.info)

func _confirmation_dialog_cancel() -> void:
	_currently_deleting = null
	reset()

func _confirmation_dialog_confirm() -> void:
	l.print("Removing %s..." % _currently_deleting.repo)
	var err := _currently_deleting.remove()
	if err != OK: l.error("FAILED: " + error_string(err))
	else: l.debug("OK")
	reset()

@warning_ignore("return_value_discarded")
func _ready() -> void:
	confirmation_dialog.title = "Delete files?"
	create_item()
	hide_root = true
	columns = Column.COLUMN_SIZE

	var c := Column.BLANK
	set_column_expand(c, false)
	set_column_custom_minimum_width(c, 80)
	set_column_clip_content(c, true)
	set_column_expand_ratio(c, SIZE_SHRINK_BEGIN)

	c = Column.TRACKED
	set_column_title(c, "Track")
	set_column_expand(c, false)

	c = Column.LINKED
	set_column_title(c, "Install")
	set_column_expand(c, false)

	c = Column.ACTIVE
	set_column_title(c, "Enable")
	set_column_expand(c, false)

	c = Column.REPO
	set_column_title(c, "Repo")
	set_column_expand(c, true)
	set_column_expand_ratio(c, SIZE_EXPAND)

	c = Column.BRANCH
	set_column_title(c, "Branch")
	set_column_expand(c, true)
	set_column_custom_minimum_width(c, 180)
	set_column_expand_ratio(c, SIZE_SHRINK_BEGIN)

	c = Column.COMMIT
	set_column_title(c, "Commit")
	set_column_expand_ratio(c, SIZE_SHRINK_BEGIN)
	set_column_custom_minimum_width(c, 180)
	set_column_expand(c, true)

	c = Column.EDIT
	set_column_title(c, "Edit")
	set_column_expand_ratio(c, SIZE_SHRINK_BEGIN)
	set_column_expand(c, false)
	set_column_custom_minimum_width(c, 0)

	for c_i in columns:
		set_column_title_alignment(c_i, HORIZONTAL_ALIGNMENT_LEFT)

	button_clicked.connect(_button_clicked)
	item_edited.connect(_item_edited)
	visibility_changed.connect(_on_visibility_changed)
	confirmation_dialog.confirmed.connect(_confirmation_dialog_confirm)
	confirmation_dialog.canceled.connect(_confirmation_dialog_cancel)

	if is_visible_in_tree():
		await _set_working()
		build.call_deferred()
		_set_finished()

# TODO make buttons work
func _button_clicked(item: TreeItem, col: int, id: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return

	match col:
		Column.REPO:
			var meta : Variant = item.get_metadata(0)
			if meta is GitSubmoduleAccess:
				var sm := meta as GitSubmoduleAccess
				# TODO
				pass
		Column.EDIT:
			var meta : Variant = item.get_metadata(0)
			if meta is GitSubmoduleAccess:
				var sm := meta as GitSubmoduleAccess
				match id:
					EditColumnButtonIndex.EDIT_REPO:
						edit_submodule.emit(sm)
					EditColumnButtonIndex.EDIT_IN_GODOT:
						# var exe_path := OS.get_executable_path()
						var os_err := OS.create_instance(["-e", "--path", ProjectSettings.globalize_path(sm.source_path)])
						if os_err == -1:
							push_error("Failed to create godot instance")
					EditColumnButtonIndex.TERMINAL:
						var editor_settings := EditorInterface.get_editor_settings()
						var terminal : String = editor_settings.get_setting("filesystem/external_programs/terminal_emulator")
						var flags : String = editor_settings.get_setting("filesystem/external_programs/terminal_emulator_flags")
						flags = flags.format({"directory": ProjectSettings.globalize_path(sm.source_path)})
						var os_err := OS.create_process(terminal, flags.split(" "))
						if os_err < 0:
							l.error("Could not open terminal '%s %s'" % [terminal, flags])
			return
		_:
			push_error("What button at %s?" % col)

func _on_visibility_changed() -> void:
	if !is_visible_in_tree():
		l.debug("Visibility changed to false, doing nothing.")
		return
	if visible:
		l.debug("Visibility changed to true, triggering reset")
		reset()
	# var root := get_root()
	# if !root:
	# 	push_error("Visibility changed - Tree has no root")

func _set_working() -> void:
	working.emit()
	# TODO why do we have to wait 2 frames just to get the status indicator up?
	# Shouldn't it only need one?
	if is_visible_in_tree():
		for i in 2:
			await get_tree().process_frame

func _set_finished() -> void:
	finished.emit()

func _item_edited() -> void:
	l.debug("Tree item edited")
	var item := get_selected()
	var col := get_selected_column()
	var data : Variant = item.get_metadata(0)
	var checked := item.is_checked(col)

	await _set_working()
	if data is GitSubmoduleAccess:
		var _err := OK
		var submodule : GitSubmoduleAccess = data

		match col:
			Column.TRACKED:
				if checked:
					pass
					# l.debug("Cloning %s...")
					# _err = submodule.clone()
					# if _err != OK: l.debug("FAILED")
					# else: l.debug("OK")
					# EditorInterface.get_resource_filesystem().scan()
				else:
					_currently_deleting = submodule
					confirmation_dialog.dialog_text = CONFIRM_DELETE_TEXT % submodule.repo
					confirmation_dialog.show()
					item.set_checked(col, false)
					return
			Column.LINKED:
				var indeterminate := _is_in_project_indeterminate(submodule)
				if indeterminate:
					l.debug("INDETERMINATE - setting checked false")
					checked = false
				item.set_checked(col, checked)
				if checked:
					l.debug("Installing all plugins in %s..." % submodule.repo)
					var success := submodule.install_all_plugins()
					if success: l.debug("OK");
					else: l.debug("FAILURE");
				else:
					l.debug("Uninstalling all plugins in %s..." % submodule.repo)
					var success := submodule.uninstall_all_plugins()
					if success: l.debug("OK");
					else: l.debug("FAILURE");
				EditorInterface.get_resource_filesystem().scan()
			Column.ACTIVE:
				var indeterminate := _is_enabled_indeterminate(submodule)
				if indeterminate:
					l.debug("INDETERMINATE - setting checked false")
					checked = false
				item.set_checked(col, checked)
				for plugin in submodule.plugins:
					if checked:
						l.debug("Enabling %s..." % plugin.name)
						plugin.enable()
					else:
						l.debug("Disabling %s..." % plugin.name)
						plugin.disable()
		_update_submodule_checks.call_deferred(item)

	if data is TrackedEditorPluginAccess:
		var plugin : TrackedEditorPluginAccess = data
		var _err : Error

		_set_working()
		match col:
			Column.LINKED:
				if checked:
					l.debug("Installing plugin %s..." % plugin.name)
					var err := plugin.install()
					if err != OK: l.debug("Failed")
					else: l.debug("OK")
				else:
					l.debug("Uninstalling plugin %s..." % plugin.name)
					var err := plugin.uninstall()
					if err != OK: l.debug("Failed")
					else: l.debug("OK")
				EditorInterface.get_resource_filesystem().scan()
			Column.ACTIVE:
				l.debug("Enabling %s..." % plugin.name)
				plugin.set_enabled(checked)
		_update_submodule_checks.call_deferred(item.get_parent())

	_set_finished()

@warning_ignore("narrowing_conversion")
func _build_submodule_tree_item(item: TreeItem) -> void:
	var submodule : GitSubmoduleAccess = item.get_metadata(0)

	# var c := 0
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

	item.set_tooltip_text(Column.ACTIVE, "Enabled in Project")

	c = Column.REPO
	item.set_text(c, submodule.repo)
	item.add_button(c, REPO_CHANGES_ICON, 0)

	c = Column.BRANCH
	item.set_text(c, submodule.branch_name())
	item.set_tooltip_text(c, "Git branch")

	c = Column.COMMIT
	var commit := submodule.commit_hash()
	if commit == "":
		commit = "-"
	item.set_text(c, commit)
	item.set_tooltip_text(c, "Git commit")

	for c_i: int in [Column.REPO, Column.BRANCH, Column.COMMIT]:
		item.set_selectable(c_i, true)

	c = Column.EDIT
	item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_LEFT)
	item.set_text(c, "")
	item.set_cell_mode(c, TreeItem.CELL_MODE_STRING)
	# buttons
	item.add_button(c, get_theme_icon("Edit", "EditorIcons"), EditColumnButtonIndex.EDIT_REPO)
	item.add_button(c, get_theme_icon("GodotMonochrome", "EditorIcons"), EditColumnButtonIndex.EDIT_IN_GODOT)
	item.add_button(c, get_theme_icon("Terminal", "EditorIcons"), EditColumnButtonIndex.TERMINAL)
	item.set_tooltip_text(c, "Open submodule edit window")
	item.set_button_tooltip_text(c, EditColumnButtonIndex.EDIT_IN_GODOT - 1, "Open plugin project in new Godot editor")
	item.set_button_tooltip_text(c, EditColumnButtonIndex.TERMINAL - 1, "Open terminal at submodule source root")

	var config_texts : PackedStringArray = []
	for i in submodule.plugins.size():
		var plugin := submodule.plugins[i]
		var plugin_item := item.create_child()
		var cfg_file := plugin.get_config_file()
		var plugin_name : String = cfg_file.get_value("plugin", "name", "")
		var version : String = cfg_file.get_value("plugin", "version", "")
		plugin_item.collapsed = true
		plugin_item.set_metadata(0, plugin)

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

		var cfg_name : String = cfg_file.get_value("plugin", "name", "")
		var cfg_version : String = cfg_file.get_value("plugin", "version", "")
		var config_text := CONFIG_TEXT % [
			cfg_name,
			cfg_file.get_value("plugin", "description", ""),
			cfg_file.get_value("plugin", "author", ""),
			cfg_version,
			cfg_file.get_value("plugin", "script", ""),
			plugin.install_path
		]
		@warning_ignore("return_value_discarded")
		config_texts.append("%s v%s" % [cfg_name, cfg_version])
		plugin_item.set_tooltip_text(Column.REPO, config_text)

		var config_item := plugin_item.create_child()
		for c_i in Column.COLUMN_SIZE:
			config_item.set_selectable(c_i, false)
		c = Column.REPO
		config_item.set_text(c, config_text)
		config_item.set_autowrap_mode(c, TextServer.AUTOWRAP_WORD_SMART)
		config_item.set_selectable(c, true)
	var upstream_url := submodule.get_upstream_url() 
	if upstream_url == "":
		upstream_url = "-"
	item.set_tooltip_text(
		c,
		"Upstream: " + upstream_url + "\n"\
				+ "Contains Plugins:\n"\
				+ "\n".join(config_texts)
		)

	_update_submodule_checks(item)

@warning_ignore("narrowing_conversion")
func _update_submodule_checks(item: TreeItem) -> void:
	var submodule : GitSubmoduleAccess = item.get_metadata(0)
	# var submodule_plugins := submodule.find_submodule_plugin_roots()
	var submodule_enabled_plugins := submodule.get_enabled_plugins()
	var is_tracked := submodule.is_tracked()
	var has_installed := submodule.has_plugin_installed()
	var has_enabled := submodule.has_plugin_enabled()
	var has_changes := submodule.has_changes()

	var c := Column.TRACKED
	item.set_checked(c, is_tracked)
	item.set_editable(c, !has_installed)
	if is_tracked:
		item.set_tooltip_text(c, "Tracked in Git")
		item.set_icon_modulate(c, CHECKED_ICON_COLOR)
	else:
		item.set_tooltip_text(c, "Not tracked in Git")
		item.set_icon_modulate(c, NOT_CHECKED_ICON_COLOR)

	c = Column.LINKED
	item.set_editable(c, !has_enabled)
	item.set_checked(c, has_installed)
	if has_installed:
		if submodule.has_all_plugins_installed():
			item.set_tooltip_text(c, "Installed in Project")
			item.set_indeterminate(c, false)
		else:
			var plugins_in_project := submodule.get_installed_plugins().size()
			var count_text := "(%d/%d)" % [plugins_in_project, submodule.plugins.size()]
			item.set_tooltip_text(c, "%s installed in Project" % count_text)
			item.set_indeterminate(c, true)
		item.set_icon_modulate(c, CHECKED_ICON_COLOR)
	else:
		item.set_tooltip_text(c, "Not installed in Project")
		item.set_indeterminate(c, false)
		item.set_icon_modulate(c, NOT_CHECKED_ICON_COLOR)

	c = Column.ACTIVE
	if has_enabled:
		# item.set_editable(Column.LINKED, false)
		item.set_checked(c, true)
		item.set_icon_modulate(c, ACTIVE_ICON_COLOR)
		var indeterminate := _is_enabled_indeterminate(submodule)
		var theme_icon := "GuiRadioCheckedDisabled" if indeterminate else "StatusSuccess"
		item.set_icon(c, get_theme_icon(theme_icon, &"EditorIcons"))
		if indeterminate:
			var count_text := "(%d/%d)" % [submodule_enabled_plugins.size(), submodule.plugins.size()]
			item.set_tooltip_text(c, "%s enabled in Project" % count_text)
		else:
			item.set_tooltip_text(c, "Enabled in Project")
	else:
		item.set_icon_modulate(c, NOT_CHECKED_ICON_COLOR)
		item.set_tooltip_text(c, "Not enabled in Project")
		item.set_indeterminate(c, false)
		item.set_checked(c, false)
		# item.set_editable(Column.LINKED, true)
		item.set_icon(c, get_theme_icon("GuiRadioUnchecked", "EditorIcons"))

	if has_installed and is_tracked:
		item.set_editable(Column.ACTIVE, true)
	else:
		item.set_editable(Column.ACTIVE, false)

	c = Column.REPO
	if has_changes:
		item.set_button_color(c, RepoColumnButtonIndex.HAS_CHANGES, CHECKED_ICON_COLOR)
		item.set_button_tooltip_text(c, RepoColumnButtonIndex.HAS_CHANGES, "Repo has changes")
	else:
		item.set_button_color(c, RepoColumnButtonIndex.HAS_CHANGES, Color.TRANSPARENT)
		item.set_button_tooltip_text(c, RepoColumnButtonIndex.HAS_CHANGES, "Repo has no changes")

	for i in submodule.plugins.size():
		var plugin := submodule.plugins[i]
		var plugin_item := item.get_child(i)
		var is_installed := plugin.is_installed()
		var is_enabled := plugin.is_enabled()

		# print("%s is_installed? %s is_enabled? %s" % [plugin.name, is_installed, is_enabled])
		c = Column.LINKED
		plugin_item.set_checked(c, is_installed)
		# if submodule.has_plugin_installed():
		if plugin.is_installed():
			plugin_item.set_icon_modulate(c, CHECKED_ICON_COLOR)
			plugin_item.set_tooltip_text(c, "Installed in project")
		else:
			plugin_item.set_icon_modulate(c, NOT_CHECKED_ICON_COLOR)
			plugin_item.set_tooltip_text(c, "Not installed in project")

		c = Column.ACTIVE
		plugin_item.set_checked(c, is_enabled)
		plugin_item.set_editable(c, is_installed)
		if plugin_item.is_checked(c):
			plugin_item.set_editable(Column.LINKED, false)
			item.set_icon_modulate(c, ACTIVE_ICON_COLOR)
			plugin_item.set_icon(c, get_theme_icon("StatusSuccess", "EditorIcons"))
			plugin_item.set_tooltip_text(c, "Enabled")
		else:
			plugin_item.set_editable(Column.LINKED, true)
			item.set_icon_modulate(c, NOT_CHECKED_ICON_COLOR)
			plugin_item.set_tooltip_text(c, "Not enabled")
			plugin_item.set_icon(c, get_theme_icon("GuiRadioUnchecked", "EditorIcons"))

func _is_in_project_indeterminate(submodule: GitSubmoduleAccess) -> bool:
	return !submodule.has_all_plugins_installed() and submodule.has_plugin_installed()

func _is_enabled_indeterminate(submodule: GitSubmoduleAccess) -> bool:
	return !submodule.has_all_plugins_enabled() and submodule.has_plugin_enabled()