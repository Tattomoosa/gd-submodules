@tool
extends PopupPanel

signal added

enum Origin {
	GITHUB,
	NUL_SEP,
	CUSTOM
}
const GitSubmodulePlugin := preload("../../git_submodule_plugin.gd")
const StatusOutput := preload("../common_controls/git_submodule_output.gd")

var origin_urls := {
	Origin.GITHUB: "git@github.com:%s.git",
	Origin.CUSTOM: "%s"
}

@onready var repo_edit : LineEdit = %RepoEdit
@onready var branch_edit : LineEdit = %BranchEdit
@onready var commit_edit : LineEdit = %CommitEdit
@onready var origin_menu : OptionButton = %OriginMenu
@onready var custom_origin_edit : LineEdit = %CustomOriginEdit
@onready var output : StatusOutput = %StatusOutput

@warning_ignore("return_value_discarded")
func _ready() -> void:
	output.loading = false
	# about_to_popup.connect(reset)
	visibility_changed.connect(reset)
	output.add_theme_font_override("normal_font", get_theme_font("output_source_mono", "EditorFonts"))
	repo_edit.text_changed.connect(_on_edit_changed.unbind(1))
	branch_edit.text_changed.connect(_on_edit_changed.unbind(1))
	commit_edit.text_changed.connect(_on_edit_changed.unbind(1))
	_on_edit_changed()

func _on_edit_changed() -> void:
	var color := get_theme_color("font_disabled_color", "Editor")
	var color_tag := "[color=#%s]" % color.to_html()

	var repo_text := repo_edit.text
	if repo_text == "":
		repo_text = color_tag + "%s[/color]" % "{author}/{repo}"

	var branch_text := branch_edit.text
	if branch_text != "":
		branch_text = "-b [/color]%s%s " % [branch_text, color_tag]

	var commit_text := commit_edit.text

	output.clear()
	output.print(color_tag,
			"git clone ",
			branch_text,
			(get_origin_string()% ("[/color]" + repo_text + color_tag)),
			"[/color] ",
			commit_text)

func reset() -> void:
	push_warning("RESET")
	repo_edit.clear()
	branch_edit.clear()
	commit_edit.clear()
	custom_origin_edit.clear()
	output.clear()

func add_repo() -> void:
	output.loading = true
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
	output.loading = false
	# print(out)
	if err != OK:
		output.print(
			"[color=red]",
			"Error encountered during git clone: %s\n" % error_string(err),
			"Git Output:\n",
			"\n".join(out),
			"[/color]",
		)
		return
	output.append_text("OK")
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