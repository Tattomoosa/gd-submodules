extends RefCounted


const Ignorer := preload("../git/git_ignorer.gd")

## Name used by EditorInterface (path relative to /addons/)
var name : String
## Path to root folder in repo
var source_path : String
## Path to root folder in project
var install_path : String

const ADDONS_FOLDER_PATH := "res://addons/"

func _init(
	p_source_path: String,
) -> void:
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
	if !DirAccess.dir_exists_absolute(install_path):
		return false
	var dir := DirAccess.open("res://")
	if !dir.is_link(install_path):
		return false
	var link_path := ProjectSettings.localize_path(
			dir.read_link(install_path))
	link_path = link_path.trim_suffix("/")
	if link_path == source_path:
		return true
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
	var uninstalled_folder := install_path.split("/")[-1]
	var delete_path := install_path.trim_suffix(uninstalled_folder)
	# TODO doesn't seem to work, should get rid of empty folders in addons/
	if !delete_path.ends_with("addons/"):
		err = _dir_cleanup(delete_path)
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
			push_warning("Remove cleanup: Could not remove dir %s" % path, " Error: %s" % error_string(err))
		return _dir_cleanup(dir.get_current_dir())
	return OK

func install(force := false) -> Error:
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
		# TODO would need another _execute to force... should add a helper
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
	#
	var version_string : String = get_config_file().get_value("plugin", "version", "")
	if version_string != "":
		version_string = "v%s " % version_string

	# print("Installed %s %svia symlink to %s" % [name, version_string, source_path])
	print("Installed %s %svia symlink" % [name, version_string])
	return err

func get_config_file() -> ConfigFile:
	var cf := ConfigFile.new()
	var err := cf.load(source_path.path_join("plugin.cfg"))
	if err != OK:
		push_error("Error loading config file: ", error_string(err))
		return null
	return cf