# scripts-configs

Small, reviewable scripts and configuration snippets for everyday system administration.

## `cleanup-tmp.sh`

A conservative Linux `/tmp` cleanup helper. It runs in **dry-run mode by default** and only deletes when `--apply` is explicitly supplied.

### Safety model

A direct child of the target temporary directory is considered a candidate only when:

- it is not a protected OS/session name;
- it is a regular file, directory, or symbolic link;
- neither it nor any descendant was modified within the configured age window;
- the entire tree can be inspected successfully;
- `lsof` does not report an open file in the candidate tree.

Before deletion, recency and open-file checks are performed again to reduce the race window between discovery and `rm`.

Additional safeguards:

- default target is `/tmp`;
- using another directory requires `TMP_DIR_ALLOW_NONSTANDARD=1`;
- `--apply` refuses to run if `lsof` is unavailable;
- `--apply` refuses to run as root unless `ALLOW_ROOT=1` is explicitly set;
- deletion uses GNU `rm --one-file-system`;
- a permission failure on one candidate is reported and does not abort the remaining cleanup.

### Requirements

Linux with Bash and GNU userland tools (`find`, `du`, `rm`, `readlink`). `lsof` is required for deletion mode. `numfmt` is optional and is used only for human-readable summary sizes.

### Usage

Dry run with the default minimum age of 2 days:

```bash
./cleanup-tmp.sh
```

Dry run using a 7-day minimum age:

```bash
./cleanup-tmp.sh --age 7
```

Delete candidates after reviewing a dry run:

```bash
./cleanup-tmp.sh --apply
```

Use a nonstandard temporary directory deliberately:

```bash
TMP_DIR=/path/to/tmp TMP_DIR_ALLOW_NONSTANDARD=1 ./cleanup-tmp.sh
```

Running deletion as root is intentionally blocked unless explicitly enabled:

```bash
sudo ALLOW_ROOT=1 ./cleanup-tmp.sh --apply
```

### Running tests

The test suite uses [bats-core](https://github.com/bats-core/bats-core). On Ubuntu/Debian, install the packaged bats-core runner with:

```bash
sudo apt-get update
sudo apt-get install -y bats
```

Then run:

```bash
bats tests/
```

Every test uses a temporary test directory through `TMP_DIR` plus `TMP_DIR_ALLOW_NONSTANDARD=1`; the suite never points the cleanup script at the real `/tmp` directory.

The root-protection test runs only when Bats itself is executed as root. On ordinary non-root CI runners it is reported as skipped because Bash's `EUID` is readonly and is not safely mockable as an environment variable.

### Notes and limitations

This script is intentionally conservative, but no cleanup script can completely eliminate races with processes creating or opening files concurrently. The immediate pre-delete re-check reduces that risk but does not make deletion atomic.

`lsof +D` recursively scans directories and can be slow on very large trees. The script is aimed at ordinary Linux temporary directories rather than huge filesystems.

The reported byte counts are estimates based on `du` at discovery time. Files may change between measurement and deletion.

### Privacy / portability audit

The published script contains no environment-specific hostnames, usernames, IP addresses, repository names, cloud identifiers, service URLs, credentials, tokens, or project-specific paths. Its only built-in target path is the generic Linux `/tmp` directory.

## License

MIT. See [`LICENSE`](LICENSE).
