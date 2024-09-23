@tool
extends Control


const GitSubmodulePlugin := preload("../git_submodule_plugin.gd")

var repo : String = ""

@onready var git_submodule : GitSubmodulePlugin = %GitSubmodulePlugin
@onready var repo_edit : LineEdit = %RepoEdit

func _ready() -> void:
	git_submodule.repo = repo
	repo_edit.text = repo