# Open Genome bundle (modular)

This directory is embedded next to the tab trees and extracted at runtime with the TUI.

## Layout

| Path | Role |
|------|------|
| `manifest.default.toml` | Shipped defaults for local paths, privacy, sample import, GRCh38 resources, native workflow state, cache paths, results, and module toggles. Copied to `~/.config/open-genome/manifest.toml` on first use. |
| `lib/manifest_cli.py` | Read/write manifest (Python 3.11+ `tomllib`). |
| `lib/sample_scan.py` | Scan a local sequencing folder and emit Open Genome samplesheets. |
| `lib/report_compiler.py` | Compile pipeline outputs into `report_index.html`, compatibility HTML, TSV findings, and JSON evidence artifacts. |
| `pipelines/open-genome/` | Native Nextflow DSL2 pipeline for FASTQ, BAM/CRAM, VCF, and assembly-stat inputs. |
| `pipelines/denovo-assembly/` | Separate Nextflow DSL2 pipeline for hifiasm long-read de novo assembly. |
| `lib/conda_resolve.sh` | Pick `conda` from manifest + PATH, with explicit override support. |
| `lib/conda_install_module.sh` | `conda env create` / `env update` from a module `environment.yml`, with optional explicit-lock support when a maintained lock file exists. |
| `modules/<id>/module.toml` | Human metadata (`id`, `display_name`, `description`). |
| `modules/<id>/environment.yml` | Conda spec: `name:` becomes the env name; channels + packages. |
| `modules/<id>/environment.lock.*.txt` | Optional explicit conda lock for matching platforms when maintained for that module. |

## V1 local WGS flow

1. Start Here -> Start guided setup.
2. Start Here -> Check what is ready to see what is configured and what still needs attention.
3. Start Here -> Try sample data if you want to test the flow without using private genome files.
4. Run Analysis -> Run local genome analysis. It prepares the command file automatically if needed.
5. Results -> Open my report or Results -> Explain my results.
6. Results -> Understand report limits before interpreting findings.

Open Genome may download public tools and reference resources, but user reads, BAM/CRAM, VCF, logs, and metadata stay local.

The native report links FastQC/fastp/MultiQC files, summarizes mosdepth coverage, renders a chromosome coverage chart, reads VEP `CSQ` or SnpEff `ANN` consequence fields when present, lists local ClinVar/dbSNP/gnomAD evidence, and separates PharmCAT PGx status from disease-variant evidence. gnomAD, VEP/SnpEff, and PharmCAT are optional local-cache inputs; if they are not configured, the report marks those sections as skipped instead of calling an external service.

## De novo assembly flow

1. Start Here -> Start guided setup with a folder containing long-read files named with `hifi`, `ccs`, `pacbio`, `revio`, `ont`, `nanopore`, or `ultralong`.
2. Run Analysis -> Run de novo assembly. It prepares the hifiasm command automatically if needed.
3. Results -> Open my report opens the latest de novo assembly report after the run completes.

The de novo workflow writes primary contig FASTA/GFA outputs, read stats, hifiasm logs, gfastats output, `denovo_assembly_summary.tsv`, `denovo_assembly_manifest.json`, and `denovo_assembly_report.html`. The first implementation uses hifiasm as the default because it is the practical choice for PacBio HiFi/CCS human assemblies. ONT inputs are accepted, but ONT-specific assembler/polishing choices should be added as an explicit future mode.

Run `scripts/check-genomics.sh` from the repo root to verify Python scanner/report tests, shell syntax, Rust tab metadata, and the native/reference plus de novo Nextflow stub graphs.

## Adding tools

1. Prefer adding packages to `modules/opengenome/environment.yml`.
2. Keep the user-facing Start Here tab focused on the guided path; move manual tool actions behind Advanced manual setup.
3. Create a separate `modules/<id>/` environment only when dependency conflicts or tool weight make that useful, as with IGV's Java 21 requirement and hifiasm de novo assembly.

## User overrides

Edit `~/.config/open-genome/manifest.toml` - set `conda.conda_exe` to an absolute path if `conda` is not on default `PATH`. Legacy `paths.env` is imported once on bootstrap **only** when manifest path fields are still empty.
