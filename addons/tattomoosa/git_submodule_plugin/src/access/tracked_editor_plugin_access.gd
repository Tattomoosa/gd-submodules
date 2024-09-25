extends RefCounted

## Name used by EditorInterface (path relative to /addons/)
var name : String
## Path to root folder in repo
var source_path : String
## Path to root folder in project
var install_path : String

const ADDONS_FOLDER_PATH := "res://addons/"

func _init(
	# p_name: String,
	p_source_path: String,
) -> void:
	# name = p_name
	source_path = p_source_path
	name = source_path.get_slice("/addons/", 1)
	install_path = ADDONS_FOLDER_PATH.path_join(name)

func is_enabled() -> bool:
	return EditorInterface.is_plugin_enabled(name)

func set_enabled(value: bool = true) -> void:
	if is_enabled() != value:
		EditorInterface.set_plugin_enabled(name, value)

func enable() -> void:
	set_enabled()

func disable() -> void:
	set_enabled(false)

func get_project_install_path() -> String:
	var project_path := "res://addons".path_join(name)
	return project_path

func is_installed() -> bool:
	# print("plugin is installed? ", install_path)
	if !DirAccess.dir_exists_absolute(install_path):
		# print("no dir")
		return false
	# print("dir exists...")
	var dir := DirAccess.open("res://")
	if !dir.is_link(install_path):
		# push_warning("Directory at '", install_path, "' is not a symbolic link")
		return false
	var link_path := ProjectSettings.localize_path(
			dir.read_link(install_path))
	link_path = link_path.trim_suffix("/")
	# print(link_path, source_path)
	if link_path == source_path:
		# print("true")
		return true
	# print("not equal!")
	return false

func uninstall() -> Error:
	print("Uninstalling %s from %s" % [name, install_path])
	if !is_installed():
		print("Failed: Not installed")
		return ERR_FILE_BAD_PATH
	if !DirAccess.dir_exists_absolute(install_path):
		print("Failed: Directory doesn't exist")
		return ERR_DOES_NOT_EXIST
	var err := DirAccess.remove_absolute(install_path)
	if err != OK:
		print("Failed: Could not remove folder at %s" % install_path)
	return err

func install(force := false) -> Error:
	# print("installing")
	var dir := DirAccess.open(ADDONS_FOLDER_PATH)
	var dest_parent := install_path.erase(install_path.rfind("/"), 100_000)
	var err := dir.make_dir_recursive(dest_parent)
	if err != OK:
		push_error("Failed to create directories along path: ", dest_parent)
		return err
	if dir.is_link(install_path):
		var links_to := dir.read_link(install_path)
		if links_to == source_path:
			push_warning("Attempted to install plugin symlink when one already exists and links to correct plugin root location.")
			return OK
		if !force:
			return ERR_ALREADY_EXISTS
		push_error("Force set to true... Removing symlink...")
		err = DirAccess.remove_absolute(install_path)
		# TODO need access to _execute to force
		# if err != OK:
		# 	push_error("Could not remove existing symlink via DirAccess. Using rm...")
		# 	var link_name := install_path.split("/")[-1]
		# 	var rm_path := ProjectSettings.globalize_path(install_path.replace(link_name, ""))
		# 	push_error("cd %s && rm %s" % [rm_path, link_name])
		# 	var output : Array[String] = []
		# 	var os_err := _execute_at(rm_path, "rm %s" % link_name, output)
		# 	if os_err != OK:
		# 		push_error(output)
		# 		return FAILED
		# 	push_error("Successfully removed symlink at ", install_path)
		# 	push_error("Creating new symlink...")
	err = dir.create_link(source_path, name)
	if err != OK:
		push_error("Could not create symlink: %s %s - " % [name, source_path], error_string(err))
		return FAILED
	print("Installed %s via symlink to %s" % [name, source_path])
	return err

func get_config_file() -> ConfigFile:
	var cf := ConfigFile.new()
	# print(source_path)
	var err := cf.load(source_path.path_join("plugin.cfg"))
	if err != OK:
		push_error("Error loading config file: ", error_string(err))
		return null
	return cf