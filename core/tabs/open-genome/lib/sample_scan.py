#!/usr/bin/env python3
"""Scan local sequencing files and write an nf-core/sarek-compatible samplesheet."""
from __future__ import annotations

import argparse
import csv
import re
import sys
import tomllib
from pathlib import Path

import manifest_cli


FASTQ_SUFFIXES = (".fastq.gz", ".fq.gz", ".fastq", ".fq")


def _strip_fastq_suffix(name: str) -> str:
    for suffix in FASTQ_SUFFIXES:
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def _is_fastq(path: Path) -> bool:
    return path.name.endswith(FASTQ_SUFFIXES)


def _read_token(name: str) -> str | None:
    if re.search(r"(^|[._-])R1([._-]|$)", name, flags=re.IGNORECASE):
        return "R1"
    if re.search(r"(^|[._-])R2([._-]|$)", name, flags=re.IGNORECASE):
        return "R2"
    if re.search(r"(^|[._-])1([._-]|$)", name):
        return "R1"
    if re.search(r"(^|[._-])2([._-]|$)", name):
        return "R2"
    return None


def _pair_key(path: Path) -> tuple[str, str]:
    stem = _strip_fastq_suffix(path.name)
    lane_match = re.search(r"(^|[._-])(L\d{3})([._-]|$)", stem, flags=re.IGNORECASE)
    lane = lane_match.group(2) if lane_match else "lane_1"
    sample = re.sub(r"(^|[._-])R[12]([._-]|$)", r"\1", stem, flags=re.IGNORECASE)
    sample = re.sub(r"(^|[._-])[12]([._-]|$)", r"\1", sample)
    sample = re.sub(r"(^|[._-])L\d{3}([._-]|$)", r"\1", sample, flags=re.IGNORECASE)
    sample = re.sub(r"[._-]+$", "", re.sub(r"^[._-]+", "", sample))
    sample = sample or "sample"
    return sample, lane


def _find_fastq_rows(root: Path) -> tuple[list[dict[str, str]], list[str]]:
    grouped: dict[tuple[str, str], dict[str, Path]] = {}
    warnings: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not _is_fastq(path):
            continue
        token = _read_token(path.name)
        if token is None:
            warnings.append(f"unpaired/unknown FASTQ read token: {path}")
            continue
        sample, lane = _pair_key(path)
        grouped.setdefault((sample, lane), {})[token] = path

    rows: list[dict[str, str]] = []
    for (sample, lane), reads in sorted(grouped.items()):
        if "R1" not in reads or "R2" not in reads:
            warnings.append(f"missing mate for sample={sample} lane={lane}")
            continue
        rows.append(
            {
                "patient": sample,
                "sex": "NA",
                "status": "0",
                "sample": sample,
                "lane": lane,
                "fastq_1": str(reads["R1"].resolve()),
                "fastq_2": str(reads["R2"].resolve()),
            }
        )
    return rows, warnings


def _find_alignment_rows(root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        sample = path.stem
        if path.suffix == ".bam":
            rows.append({"patient": sample, "sex": "NA", "status": "0", "sample": sample, "lane": "lane_1", "bam": str(path.resolve())})
        elif path.suffix == ".cram":
            rows.append({"patient": sample, "sex": "NA", "status": "0", "sample": sample, "lane": "lane_1", "cram": str(path.resolve())})
    return rows


def _find_vcf_rows(root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.name.endswith(".vcf") or path.name.endswith(".vcf.gz"):
            sample = path.name.removesuffix(".vcf.gz").removesuffix(".vcf")
            rows.append({"patient": sample, "sample": sample, "vcf": str(path.resolve())})
    return rows


def _write_samplesheet(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        raise ValueError("no sample rows to write")
    columns = list(rows[0].keys())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def _load_manifest() -> dict:
    user = manifest_cli._user_manifest()
    if not user.is_file():
        return {}
    return tomllib.loads(user.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)

    root = args.input_dir.expanduser().resolve()
    if not root.is_dir():
        print(f"Input is not a directory: {root}", file=sys.stderr)
        return 1

    data = _load_manifest()
    workdir = str(data.get("paths", {}).get("workdir", "") or "")
    if not workdir:
        workdir = str((Path.home() / ".local" / "share" / "open-genome" / "work").resolve())
    out = args.out or Path(workdir) / "samples" / "sarek_samplesheet.csv"

    fastq_rows, warnings = _find_fastq_rows(root)
    if fastq_rows:
        rows = fastq_rows
        mode = "fastq"
    else:
        align_rows = _find_alignment_rows(root)
        if align_rows:
            rows = align_rows
            mode = "alignment"
        else:
            rows = _find_vcf_rows(root)
            mode = "vcf"

    if not rows:
        print(f"No paired FASTQ, BAM/CRAM, or VCF inputs found under {root}", file=sys.stderr)
        for warning in warnings:
            print(f"warning: {warning}", file=sys.stderr)
        return 1

    _write_samplesheet(out, rows)
    first = rows[0]
    user = manifest_cli._user_manifest()
    data.setdefault("paths", {})["dataset"] = str(root)
    sample = data.setdefault("sample", {})
    sample["input_dir"] = str(root)
    sample["sample_id"] = first.get("sample", "")
    sample["patient_id"] = first.get("patient", first.get("sample", ""))
    sample["sex"] = first.get("sex", "NA")
    sample["status"] = first.get("status", "0")
    sample["samplesheet"] = str(out.resolve())
    manifest_cli._write_manifest(user, data)

    print(f"Detected input mode: {mode}")
    print(f"Rows written: {len(rows)}")
    print(f"Samplesheet: {out.resolve()}")
    for warning in warnings:
        print(f"warning: {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
