<div align="center">
	<br/>
	<br/>
	<img src="https://raw.githubusercontent.com/Tattomoosa/gd-submodules/refs/heads/main/addons/gd-submodules/icons/GitPlugin.svg" width="100"/>
	<br/>
	<h1>
		Gd-Submodules
		<br/>
		<br/>
		<sub>
		<sub>
		Dead simple plugin management via git submodule, for <a href="https://godotengine.org/">Godot</a>
		</sub>
		</sub>
		</sub>
		<br/>
		<br/>
		<br/>
	</h1>
	<br/>
	<br/>
	<img src="https://raw.githubusercontent.com/Tattomoosa/gd-submodules/refs/heads/main/media/image.png" height="400">
	<!-- <img src="./readme_images/stress_test.png" height="140"> -->
	<!-- <img src="./readme_images/editor_view.png" height="140"> -->
	<br/>
	<br/>
</div>

> This plugin is in pre-release as it has not been tested for many configurations of Windows yet. Issues / pull requests appreciated!

## Features

* Add Godot plugins as submodules from remote repos
* Plugins [built to spec](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) *just work*
	* Installation only includes files available via `git archive`
	* No need to specify plugin root, even for packages with multiple plugins
	* Plugins within the plugin's source project which are not meant to be installed by the end user won't be
	* This includes almost all plugins available on the Asset Library
* Independent installation of plugins from repos with multiple plugins
* Code changes are reflected in submodule's git status (installs via symlink)
	* Seamlessly work on your own plugins inside your main project
	* PR code changes to a plugin without needing to clone separately
	* Open plugin projects (to view examples etc) seamlessly from the file dock
* Does not interference with plugins installed via other means

## Limitations

Plugins that are stored at their repo root (instead of within `./addons/`) are not currently supported. (Support planned)

Plugins which use but don't properly ignore development dependencies in their archive will list those
dependencies as available plugins. In this case, instead of installing all plugins in the archive,
open the repo in the settings and install only the plugins you actually want.

Cannot be used to install GDExtensions. Since those require a
build-step they cannot be installed via submodule. (No support planned, out of scope)

## Installation

### Requirements

Git must be installed and in your `$PATH`. Your project must be a valid git repo.

> This git repo *probably* has to have the same root as your project, but maybe not! (Testing needed)

### Self-managed bootstrap installation (recommended)

From your project root, which must be a valid git repo (`git init`)

```bash
mkdir -p ./.submodules ./addons
touch .submodules/.gdignore
git submodule add git@github.com:tattomoosa/gd-submodules.git ./.submodules/tattomoosa/gd-submodules
cd addons && ln -s ../.submodules/tattomoosa/gd-submodules/addons/gd-submodules ./gd-submodules
```

Then activate the plugin via the Plugins tab in Project Settings...

TODO image

And it will find itself and can handle its own updates from here!

### Via Asset Lib

> Not actually on Asset Lib yet

Search for `gd-submodules` on Godot's Asset Library and install it. It will *not* self-manage.

> Managing itself after an Asset Lib install is a planned feature.

## Usage

Open the new settings pane in Project Settings, click Add Repo.
This makes your project start tracking 

> Do NOT .gitignore the .submodules folder or the addons folder. Gd-Submodules depends on
> git submodules to sync repo state, so the folders must be available to git for it to do
> its job
>
> When cloning your project, use
```
git clone --recurse-submodules
```
## The Future

* Commandline usage
	* Who doesn't love to be headless
* More options available via GUI
	* Git Pull for submodules is probably the big one lol
* Bootstrap via Asset Lib
	* This actually shouldn't be too bad
* Support more installation options
	* From plugin project root, ignoring only project.godot
		* Needs to be configurable between addons/{rep_name} and a custom folder
	* Bypass archive rules, include all
	* No symlink, true install
* Support archive releases / GitExtension
	* Probably out of scope
	* Would not be fully submodule-backed, would make this more of an all-in-one Godot plugin manager
		* This would be cool, but the name would need to change!
* Faster calls to git?
	* Does it matter?
		* Generally, no. For immediate updates of git status and other nice-to-haves, yes.
	* Possible solutions:
		* Packaging a GDExtension, or supporting an optional dependency on one
			* `godot-git-plugin`, unfortunately, does not appear to allow general purpose git use
		* Using threading and `OS.execute_with_pipe` to run commands
			* Not sure if it's any faster, need to test that
			* Asynchronous and doesn't risk locking up the editor, even if it's still just as slow
* Dependency Management?
	* Wouldn't that be nice!
		* End user dependency management is fairly easy