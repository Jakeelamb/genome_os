# Release Checklist

Use this checklist before publishing a GitHub release.

## Repository

- README describes the current product and install path.
- GitHub issue templates, security policy, and pull request template point to this repository.
- No stale upstream Linutil docs, badges, domains, or release links remain in release-facing files.
- `Start Here -> Check what is ready` gives a clear read-only readiness status for new users.

## Verification

```bash
cargo fmt --check
cargo check -p opengenome_tui --all-features
cargo test
scripts/check-genomics.sh
git diff --check
```

## Release Build

Use the GitHub release workflow from `main`. It builds Linux x86_64 and aarch64 binaries and attaches `start.sh` plus `startdev.sh`.

The binary name is `opengenome`. The public project name and release text should use Open Genome.

## Manual Smoke

1. Run the TUI from source: `cargo run -p opengenome_tui`.
2. Open `Start Here -> Check what is ready`.
3. Choose an output/work folder.
4. Set or import a small sequencing test folder.
5. Confirm the checklist updates as expected.
