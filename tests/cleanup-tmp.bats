#!/usr/bin/env bats

load 'test_helper.bash'

setup() {
  setup_cleanup_test
}

teardown() {
  teardown_cleanup_test
}

@test "runs in dry-run mode by default and deletes nothing" {
  local candidate="$TEST_TMP/old-file.txt"
  make_old_file "$candidate"

  run_cleanup

  [ "$status" -eq 0 ]
  [ -e "$candidate" ]
  assert_contains "Mode: dry-run"
  assert_contains "CANDIDATE"
  assert_contains "$candidate"
  assert_contains "Nothing was deleted."
}

@test "--apply deletes an old non-protected non-busy candidate" {
  local candidate="$TEST_TMP/old-file.txt"
  make_old_file "$candidate"

  run_cleanup --apply

  [ "$status" -eq 0 ]
  [ ! -e "$candidate" ]
  assert_contains "REMOVED: $candidate"
  assert_contains "removed: 1"
}

@test "recent content inside MIN_AGE_DAYS is skipped" {
  local recent="$TEST_TMP/recent-file.txt"
  make_recent_file "$recent"

  run_cleanup

  [ "$status" -eq 0 ]
  [ -e "$recent" ]
  assert_contains "SKIP recent:"
  assert_contains "$recent"
  assert_not_contains "CANDIDATE"
}

@test "--age accepts a positive integer" {
  local candidate="$TEST_TMP/old-file.txt"
  make_old_file "$candidate"

  run_cleanup --age 1

  [ "$status" -eq 0 ]
  assert_contains "Minimum age: 1 day(s)"
  assert_contains "CANDIDATE"
}

@test "--age rejects non-numeric and non-positive values with exit 2" {
  local value
  for value in 0 -1 abc 1.5 ''; do
    run_cleanup --age "$value"
    [ "$status" -eq 2 ]
    assert_contains "ERROR: age must be an integer >= 1"
  done
}

@test "nonstandard TMP_DIR requires explicit opt-in" {
  run env \
    TMP_DIR="$TEST_TMP" \
    PATH="$MOCK_BIN:$ORIGINAL_PATH" \
    "$SCRIPT_COPY"

  [ "$status" -eq 1 ]
  assert_contains "ERROR: refusing to operate on"

  run env \
    TMP_DIR="$TEST_TMP" \
    TMP_DIR_ALLOW_NONSTANDARD=1 \
    PATH="$MOCK_BIN:$ORIGINAL_PATH" \
    "$SCRIPT_COPY"

  [ "$status" -eq 0 ]
  assert_contains "Mode: dry-run"
}

@test "summary counts candidates, removals, and skips for a mixed dry-run" {
  local candidate="$TEST_TMP/old-candidate.txt"
  local protected="$TEST_TMP/ssh-protected"
  local recent="$TEST_TMP/recent-file.txt"

  make_old_file "$candidate"
  make_old_tree "$protected"
  make_recent_file "$recent"

  run_cleanup

  [ "$status" -eq 0 ]
  assert_contains "candidates: 1"
  assert_contains "skipped by safety checks: 2"
  assert_contains "removed: 0"
  [ -e "$candidate" ]
  [ -e "$protected" ]
  [ -e "$recent" ]
}
