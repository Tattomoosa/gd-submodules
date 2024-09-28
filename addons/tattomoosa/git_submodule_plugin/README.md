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

### Self-managed bootstrap installation (recommended)

From your project root, which must be a valid git repo (`git init`)

```
git submodule add git@github.com:tattomoosa/gdsm.git .submodules/tattomoosa/gdsm
ln -s .submodules/tattomoosa/gdsm addons/gdsm
echo ".submodules/" > .gitignore
```

Then activate the plugin via the Plugins tab in Project Settings...

TODO image

And it will find itself and can handle its own updates.

### Via Asset Lib

> Not actually on Asset Lib yet

Search for `gdsm` on Godot's Asset Library and install it. It will *not* self-manage.

> Managing itself after an Asset Lib install is a planned feature.

## Usage

Open the new settings pane in Project Settings

## The Future

* Support more installation options
	* From plugin project root, ignoring only project.godot
		* Needs to be configurable between addons/{rep_name} and a custom folder
	* Bypass archive rules
* Seamlessly support releases + source code installations?
	* Would not be fully submodule-backed, would make this more of an all-in-one Godot plugin manager
		* This would be ok, but the name might need to change!
* Calling out to git via the command line is slow
	* Does it matter?
		* Generally, no. For immediate updates of git status, yes
	* Possible solutions:
		* Packaging a GDExtension, or allowing an optional dependency on one
			* `godot-git-plugin`, unfortunately, does not appear to allow general purpose git use
		* Using threading and `OS.execute_with_pipe` to run commands
			* Not sure if it's any faster, need to test that
			* Asynchronous and doesn't risk locking up the editor, even if it's still slow