# Heartbeat for raw `xcodebuild test` output.
#
# xcsift prints its report only after xcodebuild exits, so a long test run
# shows nothing for minutes. This filter reads the same raw stream and prints
# a short progress line every INTERVAL test cases, plus every failure, build
# error, and phase change as soon as it appears. Point it at stderr so the
# structured xcsift report on stdout stays clean.
#
# Counts are raw "Test case" lines, so a parameterized test counts once per
# argument; the xcsift report and assert-xcresult-tests.sh stay authoritative.
#
# Usage: xcodebuild test 2>&1 | tee >(awk -f scripts/test-progress.awk >&2) | xcsift
BEGIN {
  interval = ENVIRON["PROWL_TEST_PROGRESS_INTERVAL"] + 0
  if (interval < 1) interval = 250
  passed = failed = skipped = compiled = 0
}

function now(   t) {
  "date +%T" | getline t
  close("date +%T")
  return t
}

function say(message) {
  printf "[%s] %s\n", now(), message
  fflush()
}

function tick() {
  total = passed + failed + skipped
  if (total % interval == 0) say(passed " passed, " failed " failed, " skipped " skipped")
}

# Swift Testing and XCTest both print one line per finished test case.
/^Test [Cc]ase '.*' passed/  { passed++; tick(); next }
/^Test [Cc]ase '.*' skipped/ { skipped++; tick(); next }
/^Test [Cc]ase '.*' failed/  { failed++; say("FAIL " $0); next }

/^Testing started/ { say("testing started"); next }
/^\*\* (TEST|BUILD) (SUCCEEDED|FAILED) \*\*/ { say($0); next }

# One line when the app binary links: the build phase is nearly over.
/^Ld .*\.app\/Contents\/MacOS\// { say("app binary linked"); next }
/^(SwiftCompile|CompileSwift) / {
  compiled++
  if (compiled % 500 == 0) say(compiled " compile steps")
  next
}

# Compiler diagnostics and fatal xcodebuild errors.
/: error:/ || /^xcodebuild: error:/ || /^error:/ { say($0); next }

# xcodebuild can flush buffered test-case lines after its own summary, so the
# final tally waits for the end of the stream.
END {
  if (passed + failed + skipped > 0) say("done: " passed " passed, " failed " failed, " skipped " skipped")
}
