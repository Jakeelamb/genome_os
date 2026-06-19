# Open Genome

Terminal utility for genomics workflows, built on a Linutil-style Rust TUI: left pane categories, right pane actions, same keyboard model.

Open Genome helps privacy-minded users set up local genomics tooling, import sequencing files, prepare references, run native Nextflow workflows, assemble long-read genomes de novo, and generate evidence reports without uploading genome data.

## Install

Run the latest GitHub release:

```bash
curl -fsSL https://raw.githubusercontent.com/Jakeelamb/opengenome/main/start.sh | sh
```

Or clone and run from source:

```bash
git clone https://github.com/Jakeelamb/opengenome.git
cd opengenome
cargo run -p opengenome_tui
```

## Run from source

```bash
cargo run -p opengenome_tui
```

The TUI uses a built-in animated DNA logo by default and does not require a sibling checkout or private path dependency. Set `OPEN_GENOME_USE_PNG_LOGO=1` to use the bundled PNG fallback. The Nix package builds the same way: `nix build .#default`.

Release binary (workspace default):

```bash
cargo build --release -p opengenome_tui
# target/release/opengenome
```

### CLI flags

```bash
cargo run -p opengenome_tui -- --help
```

Linutil-compatible options still apply: `--config`, `--theme`, `--skip-confirmation`, `--override-validation`, `--size-bypass`, `--mouse`, `--bypass-root`.

## First Run

1. Open `Start Here -> Start guided setup`.
2. Choose where results stay and select sequencing files with the native picker.
3. Use `Start Here -> Check what is ready` anytime; it is read-only.
4. Run locally with `Run Analysis -> Run local genome analysis`, or use `Run Analysis -> Run de novo assembly` for PacBio HiFi/CCS or ONT long-read inputs.
5. Review results with `Results -> Open my report` or `Results -> Explain my results`.

## Configuration (manifest + conda)

- **User manifest:** `$XDG_CONFIG_HOME/open-genome/manifest.toml` (created on first Setup action from the bundled default).
- **Privacy:** local-only user data by default. Public tools, references, and pipelines may be downloaded; reads/BAMs/VCFs/logs are not uploaded.
- **Paths:** `paths.reference`, `paths.dataset`, `paths.workdir`, `paths.threads`.
- **Conda:** Open Genome can reuse an existing `conda`/`mamba` executable or install private Miniforge/Conda under `$XDG_DATA_HOME/open-genome/miniforge`.
- **Setup path selection:** The TUI uses a native file picker for setup paths, including the automated setup path flow. Direct shell use still falls back to `fzf` when available, or Bash/readline filesystem completion. Quoted or shell-escaped pasted paths are normalized. Selecting a sequencing file imports its containing folder so paired reads and related files are found together.
- **Setup readiness:** `Start Here -> Check what is ready` is read-only. It shows completed and missing setup items, with the next action to run for each missing requirement.
- **Samples:** Setup can scan paired FASTQ/FASTQ.gz, existing BAM/CRAM, existing VCF, long-read de novo inputs, or user-provided assembly files, including mixed folders. Long-read de novo inputs are detected conservatively from file names containing markers such as `hifi`, `ccs`, `pacbio`, `revio`, `ont`, `nanopore`, or `ultralong`. It writes row-id based native Open Genome samplesheets.
- **Sample dataset:** `Start Here -> Try sample data` wires the local public GIAB/NIST HG002 benchmark VCF into the manifest for UX testing without using private data.
- **Reference/workflow:** `Start Here` owns setup and readiness. `Run Analysis -> Run local genome analysis` prepares if needed, then runs or resumes the local reference/variant Nextflow workflow through the `opengenome` conda environment. `Run Analysis -> Run de novo assembly` uses a separate hifiasm Nextflow workflow through the `opengenome-denovo` conda environment and does not require a reference FASTA. Manual reference and command steps live under advanced folders.
- **De novo assembly:** The first de novo mode is hifiasm-centered and best suited to PacBio HiFi/CCS human whole-genome reads. ONT inputs are accepted as local long-read files, but high-quality ONT-specific assembly/polishing is a future mode. Human-scale assembly can require substantial RAM, CPU, and scratch disk; set `OPEN_GENOME_DENOVO_MEMORY` before preparing the command to override the default memory request.
- **Reports:** The native workflow emits `report_index.html` plus compatibility `open_genome_report.html`, TSV findings, JSON evidence, and a run manifest. The report links FastQC/fastp/MultiQC files, shows mosdepth coverage charts, summarizes VEP `CSQ` or SnpEff `ANN` consequence fields when present, lists local ClinVar/dbSNP/gnomAD evidence, and keeps PharmCAT PGx status in its own section. Use `Start Here -> Load existing results` when results already exist on disk, then `Results -> Open my report` or `Results -> Explain my results` without rerunning.
- **Assembly reports:** The de novo workflow emits `denovo_assembly_report.html`, `denovo_assembly_summary.tsv`, `denovo_assembly_manifest.json`, primary contigs FASTA/GFA, read stats, hifiasm logs, and gfastats output. The report surfaces contig count, total assembled bases, N50, and longest contig.
- **Optional public evidence:** ClinVar, dbSNP, gnomAD, VEP/SnpEff, and PharmCAT are local-cache driven. Open Genome does not upload variants for annotation, and skipped report sections mean the matching local resource or VCF annotation field was not configured.
- **Environment:** `Start Here -> Advanced manual setup -> Install or update local tools` installs the main `opengenome` environment, the separate `opengenome-denovo` hifiasm environment, and a small IGV environment because current GATK packages require Java 17 while current IGV requires Java 21.

## Safety Boundaries

Open Genome reports are evidence summaries, not diagnosis or treatment advice. Variant matches require review by classification, source date, review status, population frequency, phenotype, family history, and clinician judgment. Negative findings do not remove genetic risk.

See [docs/privacy-and-interpretation.md](docs/privacy-and-interpretation.md).

## Verification

```bash
scripts/check-genomics.sh
```

This runs the Python scanner/report tests, shell syntax checks, Rust tab metadata test, and native/reference plus de novo Nextflow stub smoke tests when Nextflow is available directly or through `conda run -n opengenome`.

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

Open Genome keeps the upstream TUI interaction model while replacing the command surface with local genomics workflows.

## Docs

- [Privacy and interpretation boundaries](docs/privacy-and-interpretation.md)
- [Release checklist](docs/release-checklist.md)
- [Contributor notes](docs/contributor-notes.md)

## Contributing

See [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).
