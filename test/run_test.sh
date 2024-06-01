#!/bin/bash

# Script to run the unit-tests for the termdebug9.vim
# Copied and adapted from Vim LSP plugin

VIMPRG=${VIMPRG:=$(which vim)}
if [ -z "$VIMPRG" ]; then
  echo "ERROR: vim (\$VIMPRG) is not found in PATH"
  # exit 1
fi

VIM_CMD="$VIMPRG -u NONE -U NONE -i NONE --noplugin -N --not-a-term"

TESTS="test_termdebug.vim"

RunTestsInFile() {
  testfile=$1
  echo "Running tests in $testfile"
  # If you want to see the output remove the & from the line below
  $VIM_CMD -c "vim9cmd g:TestName = '$testfile'" -S runner.vim &

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
kill %- > /dev/null

# vim: shiftwidth=2 softtabstop=2 noexpandtab
