import strutils

# https://github.com/nim-lang/nimble#nimble-reference

# Include the version number.
include metar/ver

author = "Steve Flenniken"
description = "Metadata Reader for Images"
license = "MIT"
binDir = "bin"

requires "nim >= 0.17.0"

skipExt = @["nim"]
# skipDirs = @["tests", "private"]

proc build_metar_and_python_module(ignoreOutput: bool = false) =
  var ignore: string
  if ignoreOutput:
    ignore = ">/dev/null 2>&1"
  else:
    ignore = ""
  exec r"find . -name \*.pyc -delete"
  exec r"nim c -d:buidingLib --threads:on --tlsEmulation:off --app:lib --out:bin/metar.so metar/metar " & ignore
  exec r"nim c --out:bin/metar metar/metar" & ignore


task m, "Build metar exe and python module":
  build_metar_and_python_module()

proc test_module(filename: string): string =
  ## Test one module.
  const cmd = "nim c --verbosity:0 --hints:off -r --out:bin/$1 tests/$1"
  result = (cmd % [filename])

proc get_test_filenames(): seq[string] =
  ## Return each nim file in the tests folder.
  exec "find tests -type f -name \\*.nim -depth 1 | sed 's/tests\\///' | sed 's/.nim//' >testfiles.txt"
  let text = slurp("testfiles.txt")
  result = @[]
  for filename in text.splitLines():
    if filename.len > 0:
      result.add(filename)
  exec "rm -f testfiles.txt"

proc runShellTests() =
  echo ""
  echo "\e[1;34m[Suite] \e[00mShell Tests"
  exec "bash -c tests/test_shell.sh"

proc runTests() =
  ## Test each nim file in the tests folder.
  for filename in get_test_filenames():
    let source = test_module(filename)
    exec source

  # Build the python module and run its tests.
  build_metar_and_python_module(true)
  echo ""
  echo "\e[1;34m[Suite] \e[00mTest Python Module\n"
  # echo "\e[1;32m    [OK] \e[00mtest getAppeInfo\n"
  exec "python python/test_metar.py"

  runShellTests()


task shell, "Run tests from the shell":
  echo "building metar and python module"
  build_metar_and_python_module(true)
  runShellTests()


task test, "Run all the tests":
  runTests()

task showtests, "Show command line to run tests":
  for filename in get_test_filenames():
    let source = test_module(filename)
    echo source
  echo ""
  echo "Run one test like this:"
  let source = test_module("test_metar.nim")
  echo source & """ "happy path""""

# Is there a way to pass a filename?
# task one, "Test the test_readerJpeg file.":
#   test_module("test_readerJpeg")

task clean, "Delete unneed files":
  ## Delete binary files in the test dir (files with no extension).
  exec "find tests -type f ! -name \"*.*\" | xargs rm"

  # # Delete binary files in the metar dir (files with no extension).
  exec "find metar -type f ! -name \"*.*\" | xargs rm"

  # Delete files generated by dot.
  exec "rm -f metar/metar.deps"
  exec "rm -f metar/metar.dot"
  exec "rm -f metar/my.dot"
  exec "rm -f metar/metar.png"
  exec "rm -f testfiles.txt"
  exec "rm -f docfiles.txt"
  exec "rm -f names.txt"

  # Delete files generated by coverage.
  exec "rm -f coverage.info"
  exec "rm -fr metar/coverage"



proc doc_module(name: string) =
  const cmd = "nim doc0 --index:on --out:docs/$1.html metar/$1.nim"
  let source = cmd % name
  exec source

task docs, "Build all the docs":
  exec "find metar -type f -name \\*.nim | sed 's;metar/;;' | grep -v '^private' | sed 's/.nim//' >docfiles.txt"
  let fileLines = slurp("docfiles.txt")
  for filename in fileLines.splitLines():
    if filename.len > 0:
      # echo filename
      doc_module(filename)

  exec "nim buildIndex --out:docs/theindex.html docs/"
  exec "nim rst2html --out:docs/index.html docs/index.rst"
  exec "open docs/index.html"

task tree, "Show the project directory tree":
  exec "tree -I '*~|nimcache'"

task t, "Build and run t.nim":
  exec "nim c -r --out:bin/t metar/private/t"

task t2, "Build and run t2.nim":
  exec "nim c -r --out:bin/t2 metar/private/t2"

task coverage, "Run code coverage of tests":

  # var test_filenames = get_test_filenames()
  var test_filenames = ["test_readerJpeg"]

  # Compile test code with coverage support.
  for filename in test_filenames:
    exec "nim --debugger:native --passC:--coverage --passL:--coverage c tests/" & filename

  exec "lcov --base-directory . --directory . --zerocounters -q"

  # Run test code.
  for filename in test_filenames:
    exec "tests/" & filename

  exec "lcov --base-directory . --directory . -c -o coverage.info"

  # Remove Nim system libs from the coverage info.
  exec "lcov --remove coverage.info \"*/lib/*\" -o coverage.info"

  exec "genhtml -o metar/coverage/html coverage.info"
  exec "open metar/coverage/html/index.html"

task dot, "Show dependency graph":
  exec "nim genDepend metar/metar.nim"
  # Create my.dot file with the contents of metar.dot after stripping
  # out nim modules.  Add the dotted lines for ver.nim.
  exec """find metar -name \*.nim -depth 1 | sed "s:metar/::" | sed "s:.nim::" >names.txt"""
  exec "python python/dotMetar.py names.txt metar/metar.dot >metar/my.dot"
  exec "dot -Tsvg metar/my.dot -o bin/dependencies.svg"
  exec "open bin/dependencies.svg"

  # You can set the border color like this:
  # macros [color = red];
  # strutils [color = red];
  # json [color = red];
  # tables [color = red];

  # Set the line color to blue:
  # abc -> def [color = blue]

  # Set the arrowhead shape:
  # abc -> def [arrowhead = diamond]

  # find all files in the project and set their color blue.
  # find metar -name \*.nim -depth 1 | sed 's%metar/%%' | sed 's/.nim/ [color blue]/'

  # Make a dotted line.
  # version -> ver [style = dotted]
  # metar -> ver [style = dotted]


task showtestfiles, "Show command line to debug code":
  echo ""
  echo "Common switches:"
  echo "  nimswitches='c --debugger:native --verbosity:0 --hints:off'"
  echo ""

  echo "Compile test_readerJpeg with debugging info:"
  echo "  nim $nimswitches --out:bin/test_readerJpeg tests/test_readerJpeg.nim"
  echo ""

  echo "Compile metar with debugging info:"
  echo "  nim $nimswitches --out:bin/metar metar/metar.nim"
  echo ""
  echo "Launch metar with the debugger:"
  echo "  lldb bin/metar testfiles/image.jpg"
  echo ""
