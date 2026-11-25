#@tool
# NOTE: to run these on the command line, must inherit
# from SceneTree. Running in the editor extends EditorScript
# and the @tool annotation
# TODO: should be its own project
class_name TestHarness extends SceneTree

const RES: String = "res://"
const SUFFIX_SCRIPT: String = ".gd"
const PREFIX_TEST: String = "test_"
const KEY_SUITE = "suite"
const KEY_METHODS = "methods"

var num_tests: int = 0
var num_tests_passed: int = 0
var num_tests_failed: int = 0
var passed: bool = true
var this_file: String
var test_args: Array
var test_files: Array[String]
var test_suites: Array[TestSuite] = []
var tests: Dictionary = {}

# required I guess?
func _init() -> void:
	parse_args()
	_run()

func _run() -> void:
	get_test_files()
	gather_tests()
	run_tests()
	quit(0 if passed else 100)

func is_valid_file(filename: String, dir: String) -> bool:
	return filename.begins_with(PREFIX_TEST) && \
		filename.ends_with(SUFFIX_SCRIPT) && \
		path_to_file(filename, dir) != this_file

func path_to_file(filename: String, path: String) -> String:
	return path + "/" + filename

func gather_tests() -> void:
	for f in test_files:
		# each
		# must make an object to get the methods
		var suite = load(f).new()
		var m = suite.get_method_list()
		var names = m.map(func(x): return x.get("name"))
		var s = names.filter(func(x): return x.begins_with(PREFIX_TEST))
		tests[f] = {KEY_SUITE: suite, KEY_METHODS: s}
		
func get_test_files(path: String = ".") -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	var dir_files: Array[String] = []
	dir_files.assign(dir.get_files())
	var tf: Array = dir_files.filter(func (x): return is_valid_file(x, path)).map(func(x): return path_to_file(x, path))
	test_files.append_array(tf)
	
	for d in DirAccess.get_directories_at(path):
		get_test_files(d)

func parse_args() -> void:
	var args = Array(OS.get_cmdline_args())
	# this file is the last item in the args that are consumed
	# by godot. Our args come afterward
	this_file = get_script().resource_path.substr(RES.length())
	test_args = args.slice(args.find(this_file) + 1)

func run_tests() -> void:
	for f in tests:
		DebugUtils.debug_println("RUNNING TESTS FOR " + f)
		var d: Dictionary = tests[f]
		var suite = d[KEY_SUITE]
		for m in d[KEY_METHODS]:
			DebugUtils.debug_println("RUNNING TEST " + m)
			suite.call(m)
		var n: int = suite.num_tests()
		var p: int = suite.num_passed()
		var x: int = suite.num_failed()
		var r: bool = suite.passed()
		num_tests += n
		num_tests_passed += p
		num_tests_failed += x
		passed = passed && r
		DebugUtils.debug_println("SUITE {f} RESULTS".format({"f": f}))
		DebugUtils.debug_println(
			"TOTAL TESTS: {n}; PASSED: {p} ({pp}%); FAILED: {x} ({xp}%); SUITE RESULT: {r}".format(
				{
					"n": n,
					"p": p,
					"pp": snappedf(0.0 if n <= 0 else 100.0 * float(p) / n, 0.01),
					"x": x,
					"xp": snappedf(0.0 if n <= 0 else 100.0 * float(x) / n, 0.01),
					"r": TestUtils.pass_fail_str(r),
				}
			), true
		)
	DebugUtils.debug_println(
		"SUMMARY: {ns} SUITES; {nt} TESTS; {np} PASSED ({pp}%); {nx} FAILED ({xp}%); FINAL RESULT: {r}".format(
			{
				"ns": tests.size(),
				"nt": num_tests,
				"np": num_tests_passed,
				"pp": snappedf(0.0 if num_tests <= 0 else 100.0 * float(num_tests_passed) / num_tests, 0.01),
				"nx": num_tests_failed,
				"xp": snappedf(0.0 if num_tests <= 0 else 100.0 * float(num_tests_failed) / num_tests, 0.01),
				"r": TestUtils.pass_fail_str(passed),
			}
		), true
	)

class TestUtils:

	static func pass_fail_str(res: bool) -> String:
		return format_result(res, "passed" if res else "failed")

	static func format_result(res: bool, txt: String):
		var c: String = "green" if res else "red"
		return "[color={c}][b]{txt}[/b][/color]".format({"c": c, "txt": txt})


# a test suite maps to a file and comprises multiple test cases.
# it passes only if all of the cases pass
class TestSuite:
	var results: Array[bool] = []
	
	func _eval(op: String, did_pass: bool, err_msg: String = "") -> void:
		results.append(did_pass)
		var r_txt: String = "\t" + op + ": " + TestUtils.pass_fail_str(did_pass) + ("" if did_pass else " - " + err_msg)
		DebugUtils.debug_println(r_txt, true)
	
	func eq(expected: Variant, actual: Variant, tolerance: float = 0.0) -> void:
		# numbers
		if expected is int || expected is float:
			var diff = abs(expected - actual)
			_eval(
				"eq",
				diff <= tolerance,
				"actual {actual} outside tolerance {tolerance} of {expected}: {diff}".format(
					{"actual": actual, "tolerance": tolerance, "expected": expected, "diff": diff}
				)
			)
			return
		
		# everything else, using ==
		_eval("eq", expected == actual, "actual {actual} != {expected}".format({"actual": actual, "expected": expected}))

	# can compare ints or floats
	func gt(expected: Variant, actual: Variant) -> void:
		# numbers
		if ! expected is int && ! expected is float:
			_eval("gt", false, "expected value must be a number: {expected}".format({"expected": expected}))
			return
		_eval(
			"gt",
			actual > expected,
			"actual {actual} <= {expected}: {diff}".format({"actual": actual, "expected": expected})
		)

	func has_count(expected: int, actual: Array) -> void:
		_eval(
			"has_count",
			actual.size() == expected,
			"actual has wrong number of items: {actual} != {expected}".format(
				{"actual": actual.size(), "expected": expected}
			)
		)

	func is_false(actual: bool) -> void:
		_eval("is_false", ! actual, "expected false, actual is true")
		
	func is_null(actual: Variant) -> void:
		_eval("is_null", actual == null, "expected null, actual is not null: {actual}".format({"actual": actual}))
		
	func is_not_null(actual: Variant) -> void:
		_eval("is_not_null", actual != null, "expected non-null, actual is null")
		
	func is_true(actual: bool) -> void:
		_eval("is_true", actual, "expected true, actual is false")

	func num_failed() -> int:
		return results.filter(func(x): return ! x).size()
	
	func num_passed() -> int:
		return results.filter(func(x): return x).size()

	func num_tests() -> int:
		return results.size()

	func passed() -> bool:
		return num_tests() == num_passed()
