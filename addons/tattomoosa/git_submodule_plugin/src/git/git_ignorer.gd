extends RefCounted

# TODO this doesn't work at all...
# based on: https://github.com/mherrmann/gitignore_parser/blob/master/gitignore_parser.py

var DEFAULT_GITATTRIBUTES := """\
# Normalize EOL for all files that Git considers text files.
* text=auto eol=lf
# Addon store download only includes addons folder
/**        export-ignore
/addons    !export-ignore
/addons/** !export-ignore
"""
var gitattributes : String
var root_path : String = "/"
var rules : Array[IgnoreRule]

func _init(p_gitattributes := DEFAULT_GITATTRIBUTES) -> void:
	gitattributes = p_gitattributes
	_parse_gitattributes()

func _parse_gitattributes() -> void:
	var lines := gitattributes.split("\n")
	var archive_lines : Array[String] = []
	for line in lines:
		line = line.strip_edges()
		if line.ends_with("export-ignore"):
			archive_lines.append(line)
	for line in archive_lines:
		if line.ends_with("!export-ignore"):
			line = line.trim_suffix("!export-ignore")
			var rule := _rule_from_pattern(line, true)
			if rule:
				rules.append(rule)
		else:
			line = line.trim_suffix("export-ignore")
			var rule := _rule_from_pattern(line, false)
			if rule:
				rules.append(rule)

func _handle_negation(file_path: String) -> bool:
	var rules_reversed := rules.duplicate()
	rules_reversed.reverse()
	var ignore_rules : Array[IgnoreRule]
	ignore_rules.assign(rules_reversed)
	for rule in ignore_rules:
		if rule.match(file_path):
			return !rule.negated
	return false

func ignores_path(path: String) -> bool:
	return _handle_negation(path)

func _rule_from_pattern(pattern: String, negated: bool) -> IgnoreRule:
	# var negated : bool = false # TODO og but i think gitattributes gets negated first
	var original_pattern := pattern
	if pattern.strip_edges() == "" or pattern[0] == "#":
		return
	if pattern[0] == "!":
		# negated = true # TODO og but i think gitattributes gets negated first
		negated = !negated
		pattern = pattern.substr(1)
	
	# TODO not sure what this does, throwing error

	# Multi-asterisks not surrounded by slashes (or at the start/end) should
	# be treated like single-asterisks.
	# var sub_regex0 := RegEx.create_from_string(r"([^/])\*{2,}")
	# var sub_regex1 := RegEx.create_from_string(r"\*{2,}([^/])")
	# pattern = sub_regex0.sub(pattern, r"\1*", true)
	# pattern = sub_regex1.sub(pattern, r"*\1", true)

	if pattern.strip_edges(false, true) == "/":
		return

	var directory_only := pattern[-1] == "/"
	var anchored := "/" in pattern.substr(0, pattern.length() - 2)
	if pattern[0] == "/":
		pattern = pattern.substr(1)
	if pattern[0] == "*" and pattern.length() >= 2 and pattern[1] == "*":
		pattern = pattern.substr(2)
	if pattern[-1] == "/":
		pattern = pattern.substr(0, pattern.length() - 2)
	var strip_trailing_spaces := true
	var i := pattern.length() - 1
	while i > 1 and pattern[i] == " ":
		if pattern[i - 1] == "\\":
			pattern = pattern.substr(0, i - 1)
			i = i - 1
			strip_trailing_spaces = false
		else:
			if strip_trailing_spaces:
				pattern = pattern.substr(0, i)
		i = i - 1
	return IgnoreRule.new(
		original_pattern,
		pattern,
		root_path,
		negated,
		directory_only,
		anchored
	)

class IgnoreRule:
	var original_pattern : String
	var pattern : String
	var parsed_pattern : String
	var root_path : String
	var negated : bool
	var regex : RegEx

	func _init(
		p_original_pattern: String,
		p_pattern: String,
		p_root_path: String,
		p_negated: bool,
		p_directory_only: bool,
		p_anchored: bool
	) -> void:
		original_pattern = p_original_pattern
		pattern = p_pattern
		root_path = p_root_path
		negated = p_negated
		regex = RegEx.create_from_string(_pattern_to_regex(
			p_directory_only,
			p_anchored
		))
		print(regex.get_pattern())

	func match(path: String) -> bool:
		if path == "":
			return false
		if path.begins_with(root_path):
			path = "/" + path.trim_prefix(root_path)
		if negated and path[-1] == "/":
			path += "/"
		if path.begins_with("./"):
			path = path.substr(2)
		var matches := regex.search(path)
		print("matching path: ", path, " with pattern: ", regex.get_pattern())
		print(matches != null)
		return matches != null
	
	func _pattern_to_regex(
		directory_only: bool = false,
		anchored: bool = false
	) -> String:
		var i := 0
		var n := pattern.length()

		# not needed in godot
		# seps = [re.escape(os.sep)]
		# TODO idk
		# if os.altsep is not None:
	#    seps.append(re.escape(os.altsep))

		var separator_group := r"[\/]"
		var non_separator_group := r"[^\/]"

		var results := []
		while i < n:
			var c := pattern[i]
			i += 1
			if c == "*":
				if i >= n:
					results.append("".join([non_separator_group, "*"]))
				elif pattern[i] == "*":
					i += 1
					if i >= n:
						results.append("".join([non_separator_group, "*"]))
					elif i < n and pattern[i] == "/":
						i += 1
						if i >= n:
							results.append("".join([non_separator_group, "*"]))
						else:
							results.append("".join([r"(.*", separator_group, ")?"]))
					else:
						results.append(".*")
				else:
					results.append("".join([non_separator_group, "*"]))
			elif c == "?":
				results.append(non_separator_group)
			elif c == "/":
				results.append(separator_group)
			elif c == "[":
				var j := i
				if j < n and pattern[j] == "!":
					j += 1
				if j < n and pattern[j] == "]":
					j += 1
				while j < n and pattern[j] != "]":
					j += 1
				if j >= n:
					results.append(r"\[")
				else:
					# var stuff := pattern.slice(i, j).replace("\\", "\\\\").replace("/", "")
					var stuff := pattern.substr(i, j - i).replace("\\", "\\\\").replace("/", "")
					i = j + 1
					if stuff[0] == "!":
						stuff = "".join(["^", stuff.substr(1)])
					elif stuff[0] == "^":
						stuff = "\\" + stuff
					results.append("[%s]" % stuff)
			else:
				# TODO what escaping is done here?
				# res.append(re.escape(c))
				results.append(c)
		if anchored:
			results.push_front("^")
		else:
			results.push_front("(^|%s)" % separator_group)
		if not directory_only:
			results.append("$")
		elif directory_only and negated:
			results.append("/$")
		else:
			results.append(r"($|\/)")
		return "".join(results)
