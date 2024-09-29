extends RefCounted

const DebugProfiler := preload("../util/profiler.gd")
const L := preload("../util/logger.gd")
static var l: L.Logger:
	get: return L.get_logger(L.LogLevel.INFO, &"GitSubmoduleAccess")
static var p: L.Logger:
	get: return L.get_logger(L.LogLevel.INFO, &"Profiler:GitSubmoduleAccess")

# TODO this is a stub and currently untested/unused
# But the idea is to talk to git async, which would allow more querying of git status more often

signal result(err: Error, output: Array[String])

var mutex := Mutex.new()
var semaphore := Semaphore.new()
var thread := Thread.new()

# mutexed
var should_exit := false
var cmd_path := ""
var cmd := ""
var os_err := 0

func _init() -> void:
	var err := thread.start(_thread_fn)
	if err != OK:
		l.error("Could not create thread")

func _thread_fn() -> void:
	while true:
		semaphore.wait()
		mutex.lock()
		var exit := should_exit
		mutex.unlock()
		if exit:
			break
		mutex.lock()
		var output : Array[String] = []
		os_err = _execute_at(cmd_path, cmd, output)
		get_results.call_deferred(os_err, output)
		mutex.unlock()

func post_command(p_cmd_path: String, p_cmd: String) -> void:
	mutex.lock()
	cmd_path = p_cmd_path
	cmd = p_cmd
	mutex.unlock()
	semaphore.post()

func get_results(err: int, output: Array[String]) -> void:
	result.emit(err, output)

static func _execute_at(path: String, p_cmd: String, output: Array[String] = []) -> int:
	path = ProjectSettings.globalize_path(path)
	var os_cmd := 'cd \"%s\" && %s' % [path, p_cmd]
	l.debug("Executing " + os_cmd, l)
	var sw := DebugProfiler.Stopwatch.new()
	var err := OS.execute(
		"$SHELL",
		["-lc", os_cmd],
		output,
		true)
	sw.restart_and_log("execute '%s' for %s" % [p_cmd, path], p.debug)
	return err