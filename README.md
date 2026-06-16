# Open Genome

Terminal utility for genomics workflows, built on the [Linutil](https://github.com/ChrisTitusTech/linutil)-style Rust TUI: left pane categories, right pane actions, same keyboard model.

## Run from source

```bash
cargo run -p linutil_tui
```

By default the TUI links the [dna](https://github.com/Jakeelamb/dna) crate via a path dependency: from this repo’s root, that resolves to **`../dinosauria/dna`** (for example `~/Projects/genome_os` and `~/Projects/dinosauria/dna`). If `genome_os` lives next to `dna` under the same parent (e.g. `~/Projects/dinosauria/genome_os` and `~/Projects/dinosauria/dna`), change the path in `tui/Cargo.toml` to `../dna`. Set `OPEN_GENOME_USE_CTT_LOGO=1` to use the embedded PNG instead.

If you only have this repository (no sibling checkout), disable the default helix dependency:

```bash
cargo run -p linutil_tui --no-default-features --features tips
```

The Nix package builds the same way (PNG logo only): `nix build .#default`.

Release binary (workspace default):

```bash
cargo build --release -p linutil_tui
# target/release/linutil
```

### CLI flags

```bash
cargo run -p linutil_tui -- --help
```

Linutil-compatible options still apply: `--config`, `--theme`, `--skip-confirmation`, `--override-validation`, `--size-bypass`, `--mouse`, `--bypass-root`.

## Configuration (manifest + conda)

- **User manifest:** `$XDG_CONFIG_HOME/open-genome/manifest.toml` (created on first Setup action from the bundled default).
- **Privacy:** local-only user data by default. Public tools, references, and pipelines may be downloaded; reads/BAMs/VCFs/logs are not uploaded.
- **Paths:** `paths.reference`, `paths.dataset`, `paths.workdir`, `paths.threads`.
- **Conda:** Open Genome can install private Miniforge/Conda under `$XDG_DATA_HOME/open-genome/miniforge`, or use `conda.conda_exe`.
- **Samples:** Setup can scan a folder of paired FASTQ/FASTQ.gz or existing BAM/CRAM/VCF files and write a local nf-core/sarek samplesheet.
- **Reference/workflow:** Assembly actions fetch the public GATK GRCh38 bundle, index it locally, prepare an nf-core/sarek 3.8.1 germline command, and run/resume it with the Conda profile.
- **Environment:** the main `opengenome` conda spec lives at [core/tabs/open-genome/modules/opengenome/environment.yml](core/tabs/open-genome/modules/opengenome/environment.yml). Legacy per-tool module specs remain under [core/tabs/open-genome/modules/](core/tabs/open-genome/modules/) for fallback/debugging.

Legacy `paths.env` is imported **once** on bootstrap only if the manifest path fields are still empty. Example templates: [examples/open-genome.manifest.toml](examples/open-genome.manifest.toml), [examples/open-genome.paths.env](examples/open-genome.paths.env).

**Requires Python 3.11+** on the machine that runs Setup scripts (`tomllib`). Conda installs need **conda** on `PATH` (or set `conda.conda_exe`).

## Linutil-style app config (`--config`)

Optional TOML for the TUI (auto-execute, confirmations, size bypass) — same schema as upstream Linutil. Example:

```toml
skip_confirmation = false
size_bypass = false
```

`auto_execute` matches **command titles** exactly as shown in the right-hand list.

## Upstream

Forked from Chris Titus Tech’s Linutil; see upstream README and license in `LICENSE`. Contributor graphics and distro install snippets in older revisions referred to Linutil releases.

## Contributing

See [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).
