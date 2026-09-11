setup_cleanup_test() {
  export ORIGINAL_PATH="$PATH"
  export SCRIPT_SOURCE="$BATS_TEST_DIRNAME/../cleanup-tmp.sh"
  export TEST_ROOT="$BATS_TEST_TMPDIR/cleanup-tmp-test"
  export TEST_TMP="$TEST_ROOT/tmp"
  export SCRIPT_COPY="$TEST_ROOT/cleanup-tmp.sh"
  export MOCK_BIN="$TEST_ROOT/mock-bin"

  mkdir -p "$TEST_TMP" "$MOCK_BIN"
  cp "$SCRIPT_SOURCE" "$SCRIPT_COPY"
  chmod +x "$SCRIPT_COPY"

  write_lsof_mock 1
}

teardown_cleanup_test() {
  rm -rf -- "$TEST_ROOT"
}

write_lsof_mock() {
  local exit_code="$1"
  cat >"$MOCK_BIN/lsof" <<EOF
#!/usr/bin/env bash
exit $exit_code
EOF
  chmod +x "$MOCK_BIN/lsof"
}

run_cleanup() {
  run env \
    TMP_DIR="$TEST_TMP" \
    TMP_DIR_ALLOW_NONSTANDARD=1 \
    ALLOW_ROOT=1 \
    PATH="$MOCK_BIN:$ORIGINAL_PATH" \
    "$SCRIPT_COPY" "$@"
}

make_old_file() {
  local path="$1"
  printf 'old\n' >"$path"
  touch -d '3 days ago' "$path"
}

make_recent_file() {
  local path="$1"
  printf 'recent\n' >"$path"
}

make_old_tree() {
  local path="$1"
  mkdir -p "$path/subdir"
  printf 'old\n' >"$path/subdir/file.txt"
  find "$path" -exec touch -d '3 days ago' {} +
}

make_path_without_lsof() {
  local isolated="$TEST_ROOT/no-lsof-bin"
  mkdir -p "$isolated"

  local cmd resolved
  for cmd in bash readlink find basename du awk numfmt rm; do
    resolved="$(command -v "$cmd")"
    ln -s "$resolved" "$isolated/$cmd"
  done

  printf '%s\n' "$isolated"
}

assert_contains() {
  local needle="$1"
  [[ "$output" == *"$needle"* ]]
}

assert_not_contains() {
  local needle="$1"
  [[ "$output" != *"$needle"* ]]
}
