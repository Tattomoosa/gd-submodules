@tool
extends PopupPanel

signal added

enum Origin {
	GITHUB,
	NUL_SEP,
	CUSTOM
}
const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")


var origin_urls := {
	Origin.GITHUB: "git@github.com:%s.git",
	Origin.CUSTOM: "%s"
}


@onready var repo_edit : LineEdit = %RepoEdit
@onready var branch_edit : LineEdit = %BranchEdit
@onready var commit_edit : LineEdit = %CommitEdit
@onready var origin_menu : OptionButton = %OriginMenu
@onready var custom_origin_edit : LineEdit = %CustomOriginEdit
@onready var output : RichTextLabel = %StatusOutput


@warning_ignore("return_value_discarded")
func _ready() -> void:
	about_to_popup.connect(reset)
	output.add_theme_font_override("normal_font", get_theme_font("output_source_mono", "EditorFonts"))

func reset() -> void:
	repo_edit.clear()
	branch_edit.clear()
	commit_edit.clear()
	custom_origin_edit.clear()
	output.clear()

func add_repo() -> void:
	var repo := repo_edit.text
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = repo
	output.append_text(
		"Cloning from %s into %s..." % [
			(get_origin_string() % repo),
			submodule.get_submodule_path().trim_suffix("/")
	])
	await get_tree().process_frame
	var out : Array[String] = []
	var err := submodule.clone(out)
	print(out)
	if err != OK:
		output.append_text(
			"\n[color=red]"
			+ "Error encountered during git clone: %s\n" % error_string(err)
			+ "Git Output: "
			+ "\n".join(out)
			+ "[/color]\n"
		)
		return
	output.append_text("OK\n")
	await get_tree().process_frame
	added.emit()
	hide()

func get_origin_string() -> String:
	var index := origin_menu.selected
	if index == Origin.CUSTOM:
		return custom_origin_edit.text
	return origin_urls[index]

func update_origin(origin: int) -> void:
	print("update origin: ", origin)
	if origin == Origin.CUSTOM:
		custom_origin_edit.editable = true
		return
	custom_origin_edit.editable = false
	match origin:
		Origin.GITHUB:
			custom_origin_edit.text = "git@github.com:%s.git"