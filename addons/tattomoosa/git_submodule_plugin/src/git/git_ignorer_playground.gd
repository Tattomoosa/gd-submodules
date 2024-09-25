extends Control

const GitIgnorer := preload("./git_ignorer.gd")

@onready var paths_edit: CodeEdit = %PathsEdit
@onready var git_attributes_edit: CodeEdit = %GitAttributesEdit
@onready var ignore_output: RichTextLabel = %IgnoreOutput

@warning_ignore("return_value_discarded")
func _ready() -> void:
	paths_edit.text_changed.connect(_update)
	git_attributes_edit.text_changed.connect(_update)

func _update() -> void:
	var ignorer := GitIgnorer.new(git_attributes_edit.text)
	var output_lines : Array[String] = []
	for line in paths_edit.text.split("\n"):
		if ignorer.ignores_path(line):
			output_lines.append("[color=gray]%s[/color]" % line)
		else:
			output_lines.append(line)
	ignore_output.text = "\n".join(output_lines)
