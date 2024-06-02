#!/bin/bash

# Script to run the unit-tests for the termdebug9.vim
# Copied and adapted from Vim LSP plugin

VIM_PRG=${VIM_PRG:=$(which vim)}
if [ -z "$VIM_PRG" ]; then
  echo "ERROR: vim (\$VIM_PRG) is not found in PATH"
  # exit 1
fi

VIM_CMD='$VIM_PRG -u NONE -U NONE -i NONE --noplugin -N --not-a-term'

# Add comma separated tests, i.e. "test_termdebug.vim, test_pippo.vim, etc"
TESTS="test_termdebug.vim"

RunTestsInFile() {
  testfile=$1
  echo "Running tests in $testfile"
  # If you want to see the output remove the & from the line below
  eval $VIM_CMD " -c \"vim9cmd g:TestName = '$testfile'\" -S runner.vim"

  if ! [ -f results.txt ]; then
    echo "ERROR: Test results file 'results.txt' is not found."
    # exit 2
  fi

  cat results.txt

  if grep -qw FAIL results.txt; then
    echo "ERROR: Some test(s) in $testfile failed."
    # exit 3
  fi

  echo "SUCCESS: All the tests in $testfile passed."
  echo
}

for testfile in $TESTS
do
  RunTestsInFile $testfile
done

echo "SUCCESS: All the tests passed."
# UBA: uncomment the line below
# exit 0
# kill %- > /dev/null

# vim: shiftwidth=2 softtabstop=2 noexpandtab
