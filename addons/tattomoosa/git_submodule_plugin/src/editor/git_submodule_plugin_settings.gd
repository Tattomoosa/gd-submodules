@tool
extends Control

const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")
const GitSubmodulePluginForm := preload("./git_submodule_plugin_form.gd")

@export var git_submodule_plugin_form : PackedScene

@onready var form_list : Control = %FormList

func _ready() -> void:
	for repo in GitSubmodulePlugin.get_tracked_repos():
		add_row(repo)

func add_row(repo: String = "") -> void:
	var row := git_submodule_plugin_form.instantiate() as GitSubmodulePluginForm
	row.repo = repo
	form_list.add_child(row)

func remove_untracked() -> void:
	for row in form_list.get_children():
		if !row is GitSubmodulePluginForm:
			continue
		if (row as GitSubmodulePluginForm).git_submodule.status == GitSubmodulePlugin.Status.NOT_TRACKED:
			row.queue_free()