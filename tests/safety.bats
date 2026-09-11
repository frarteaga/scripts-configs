#!/usr/bin/env bats

load 'test_helper.bash'

setup() {
  setup_cleanup_test
}

teardown() {
  teardown_cleanup_test
}

@test "protected names are never candidates in dry-run or apply" {
  local names=(
    ssh-example
    tmux-example
    .X11-unix
    systemd-private-example
    snap-private-tmp
    snap.example
  )
  local name path

  for name in "${names[@]}"; do
    path="$TEST_TMP/$name"
    make_old_tree "$path"
  done

  run_cleanup
  [ "$status" -eq 0 ]
  assert_not_contains "CANDIDATE"

  for name in "${names[@]}"; do
    path="$TEST_TMP/$name"
    assert_contains "SKIP protected:"
    [ -e "$path" ]
  done

  run_cleanup --apply
  [ "$status" -eq 0 ]
  assert_not_contains "CANDIDATE"

  for name in "${names[@]}"; do
    path="$TEST_TMP/$name"
    [ -e "$path" ]
  done
}

@test "--apply fails when lsof is unavailable" {
  local isolated_path
  isolated_path="$(make_path_without_lsof)"

  run env \
    TMP_DIR="$TEST_TMP" \
    TMP_DIR_ALLOW_NONSTANDARD=1 \
    ALLOW_ROOT=1 \
    PATH="$isolated_path" \
    "$SCRIPT_COPY" --apply

  [ "$status" -eq 1 ]
  assert_contains "ERROR: --apply requires lsof"
}

@test "--apply as root requires ALLOW_ROOT=1" {
  if [ "$(id -u)" -ne 0 ]; then
    skip "Bash EUID is readonly; this guard is exercised only when the test process is root"
  fi

  run env \
    TMP_DIR="$TEST_TMP" \
    TMP_DIR_ALLOW_NONSTANDARD=1 \
    PATH="$MOCK_BIN:$ORIGINAL_PATH" \
    "$SCRIPT_COPY" --apply

  [ "$status" -eq 1 ]
  assert_contains "ERROR: refusing --apply as root"
}

@test "a candidate reported busy by lsof is not deleted" {
  local candidate="$TEST_TMP/busy-file.txt"
  make_old_file "$candidate"
  write_lsof_mock 0

  run_cleanup --apply

  [ "$status" -eq 0 ]
  [ -e "$candidate" ]
  assert_contains "SKIP busy/open:"
  assert_contains "$candidate"
  assert_not_contains "REMOVED: $candidate"
}
