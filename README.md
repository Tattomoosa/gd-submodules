<div align="center">
	<br/>
	<br/>
	<img src="addons/tattomoosa/git_submodule_plugin/icons/GitPlugin.svg" width="100"/>
	<br/>
	<h1>
		Godot Submodules
		<br/>
		<sub>
		<sub>
		<sub>
		Dead simple git submodule plugin management, for <a href="https://godotengine.org/">Godot</a>
		</sub>
		</sub>
		</sub>
		<br/>
		<br/>
		<br/>
	</h1>
	<br/>
	<br/>
	<!-- <img src="./readme_images/demo.png" height="140">
	<img src="./readme_images/stress_test.png" height="140">
	<img src="./readme_images/editor_view.png" height="140"> -->
	<br/>
	<br/>
</div>

Dead simple git submodule plugin management, for Godot

> This plugin works but is in pre-release as it has not been tested for many configurations of Windows yet. Issues and pull requests appreciated!

## Features

* Add submodule plugins from remote repos
* Installs only files available via `git archive` by default
	* So most packages available on Godot's Asset Lib *just work*
	* No need to specify plugin root, even for packages with multiple plugins
* Code changes are reflected in submodule's git status (installs via symlink)
	* Seamlessly work on your own plugins inside your main project
	* PR code changes to a plugin without needing to clone separately
	* Open plugin projects (to view examples etc) seamlessly from the file dock

## Limitations

Cannot be used to install GDExtensions. Since those require a build-step they cannot
be installed via submodule.

## Installation

### Requirements

Git must be installed and in your `$PATH`

### Self-managed installation (recommended)



```
git submodule add git@github.com:tattomoosa/godot_submodule_plugins.git .submodules/tattomoosa/godot_submodule_plugins
ln -s .submodules/tattomoosa/godot_submodule_plugins addons/godot_submodule_plugins
echo ".submodules/" > .gitignore
```

Then activate the plugin via the Plugins tab in Project Settings...

TODO image

And it will find itself.

## Usage

Open the new settings pane in Project Settings

## The Future

* Support more installation options
* Seamlessly support releases + source code installations?
	* W