extends Object

const LOGGER := preload("./logger.gd")
enum LogLevel { DEBUG, INFO, WARN, ERROR }

static var loggers := {}

func _init() -> void:
	assert(false, "logger.gd is static and cannot be constructed. Use static methods or get_logger() instead")

static func debug(
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> void:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	print_rich("[color=#666666](debug)[/color] %s" % msg)

static func print(
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> void:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	print_rich(msg)

# same as print
static func info(
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> void:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	print_rich(msg)

static func warn(
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> void:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	push_warning(msg)

static func error(
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> void:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	push_error(msg)

static func label(p_label: String) -> String:
	return "[ %s ] " % p_label

static func rich_label(p_label: String) -> String:
	return "[color=#aaaaaa]%s[/color]" % label(p_label)

static func color(
	p_color: Color,
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> String:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	return "[color=#%s]%s[/color]" % [p_color.to_html(), msg]

static func dim(
	arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
) -> String:
	var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
	return "[color=#888888]%s[/color]" % msg

static func get_logger(log_level: LogLevel = LogLevel.INFO, calling_class: StringName = &"") -> Logger:
	var logger_name : String = "%s:%s" % [calling_class, LogLevel.keys()[log_level]]
	var logger : Logger = loggers.get(logger_name)
	if !logger:
		logger = Logger.new()
		logger.calling_class = calling_class
		logger.level = log_level
		loggers[logger.name] = logger
	if logger.level != log_level:
		logger.level = log_level
	return logger

class Logger extends RefCounted:
	var level : LogLevel = LogLevel.WARN
	var calling_class : StringName = ""
	var name : StringName = ""

	func debug(
		arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
	) -> void:
		if level <= LOGGER.LogLevel.DEBUG:
			var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
			LOGGER.debug(LOGGER.rich_label(calling_class), msg)

	func print(
		arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
	) -> void:
		if level <= LOGGER.LogLevel.INFO:
			var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
			LOGGER.print(LOGGER.rich_label(calling_class), msg)

	# same as print
	func info(
		arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
	) -> void:
		if level <= LOGGER.LogLevel.INFO:
			var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
			LOGGER.print(LOGGER.rich_label(calling_class), msg)

	func warn(
		arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
	) -> void:
		if level <= LOGGER.LogLevel.WARN:
			var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
			LOGGER.warn(LOGGER.label(calling_class), msg)

	func error(
		arg0: Variant="", arg1: Variant="", arg2: Variant="", arg3: Variant="", arg4: Variant="", arg5: Variant="", arg6: Variant="", arg7: Variant="", arg8: Variant="", arg9: Variant=""
	) -> void:
		if level <= LOGGER.LogLevel.ERROR:
			var msg := "".join([str(arg0), str(arg1), str(arg2), str(arg3), str(arg4), str(arg5), str(arg6), str(arg7), str(arg8), str(arg9)])
			LOGGER.error(LOGGER.label(calling_class), msg)