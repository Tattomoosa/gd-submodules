@tool
extends PopupPanel

signal finished

const GitSubmodulePlugin := preload("../../git_submodule_plugin.gd")
const StatusOutput := preload("../common_controls/git_submodule_output.gd")

@onready var repo_edit : LineEdit = %RepoEdit
@onready var output : StatusOutput = %StatusOutput

@warning_ignore("return_value_discarded")
func _ready() -> void:
	output.loading = false
	visibility_changed.connect(reset)
	repo_edit.text_changed.connect(_on_repo_changed)

# TODO toggle for blank
func _on_repo_changed(text: String) -> void:
	var color := get_theme_color("font_disabled_color", "Editor")
	var color_tag := "[color=#%s]" % color.to_html()
	output.clear()
	output.print(
		color_tag, 
		"Create new repo: ",
		"[/color]",
		text,
		"\n",
		color_tag,
		"This will initialize a git repository with sensible plugin default files."
	)

func init_plugin() -> void:
	output.loading = true
	var submodule := GitSubmodulePlugin.new()
	submodule.repo = repo_edit.text
	output.append_text(
		"Creating repo %s at %s" % [
			submodule.repo,
			submodule.get_submodule_path().trim_suffix("/")
		]
	)
	var out : Array[String] = []
	var err := submodule.init(out)
	if err != OK:
		output.print(
			"[color=red]",
			"Error encountered during plugin init: %s\n" % error_string(err),
			"Git Output:\n",
			"\n".join(out),
			"[/color]",
		)
		return
	output.print("OK")
	await get_tree().process_frame
	finished.emit()
	hide()

func reset() -> void:
	repo_edit.clear()
	output.clear()
	_on_repo_changed(repo_edit.text)