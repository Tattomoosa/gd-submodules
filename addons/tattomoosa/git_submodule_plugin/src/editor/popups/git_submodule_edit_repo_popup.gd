@tool
extends PopupPanel

signal checked_out

const GitSubmodulePlugin := preload("../../git_submodule_plugin.gd")
const GitSubmoduleAccess := GitSubmodulePlugin.GitSubmoduleAccess

var submodule : GitSubmoduleAccess
const StatusOutput := preload("../common_controls/git_submodule_output.gd")

@onready var repo_edit: LineEdit = %RepoEdit
@onready var origin_edit: LineEdit = %OriginEdit
@onready var branch_edit: LineEdit = %BranchEdit
@onready var commit_edit: LineEdit = %CommitEdit
@onready var output: StatusOutput = %StatusOutput

@warning_ignore("return_value_discarded")
func _ready() -> void:
	repo_edit.text_changed.connect(_on_edit_changed.unbind(1))
	origin_edit.text_changed.connect(_on_edit_changed.unbind(1))
	branch_edit.text_changed.connect(_on_edit_changed.unbind(1))
	commit_edit.text_changed.connect(_on_edit_changed.unbind(1))

func open(p_submodule: GitSubmoduleAccess) -> void:
	submodule = p_submodule
	repo_edit.text = submodule.repo
	origin_edit.text = submodule.get_upstream_url()
	branch_edit.placeholder_text = submodule.branch_name()
	commit_edit.placeholder_text = submodule.commit_hash()
	_on_edit_changed()
	show()

func checkout() -> void:
	output.loading = true
	var checkout_str := commit_edit.text if commit_edit.text else branch_edit.text
	output.print("Checking out %s..." % checkout_str)
	await get_tree().process_frame
	await get_tree().process_frame
	var out : Array[String] = []
	var err := submodule.checkout(
		branch_edit.text,
		commit_edit.text,
		out
	)
	if err != OK:
		output.print(
			"[color=red]",
			"Error encountered during git checkout: %s\n" % error_string(err),
			"Git Output:\n",
			"\n".join(out),
			"[/color]",
		)
		return
	output.print("OK")
	await get_tree().process_frame
	checked_out.emit()
	hide()


func _on_edit_changed() -> void:
	var color := get_theme_color("font_disabled_color", "Editor")
	var color_tag := "[color=#%s]" % color.to_html()
	var text := ""
	if commit_edit.text:
		text = commit_edit.text
	elif branch_edit.text:
		text = branch_edit.text
	
	output.clear()
	if text != "":
		text = "[/color]%s%s" % [text, color_tag]
		output.print(
			color_tag,
			"git checkout ",
			text
		)
	else:
		output.print(color_tag, "Nothing to do.[/color]")