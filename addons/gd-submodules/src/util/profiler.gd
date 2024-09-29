const DebugProfiler := preload("./profiler.gd")

const L := preload("./logger.gd")
static var l: L.Logger:
	get: return L.get_logger(L.LogLevel.INFO, &"Profiler")

class Stopwatch extends RefCounted:
	var started_at : int
	var l: L.Logger = DebugProfiler.l

	func _init() -> void:
		started_at = Time.get_ticks_usec()
	
	func check() -> int:
		return Time.get_ticks_usec() - started_at
	
	func restart() -> void:
		started_at = Time.get_ticks_usec()

	func check_and_restart() -> int:
		var now := Time.get_ticks_usec() 
		var elapsed := now - started_at
		started_at = now
		return elapsed
	
	func restart_and_log(message: String, print_fn: Callable = l.print) -> void:
		var duration := check_and_restart()
		var ms_duration_f := float(duration) / 1000.0
		print_fn.call(("%.2f ms" % ms_duration_f), L.dim(" to ", message))
