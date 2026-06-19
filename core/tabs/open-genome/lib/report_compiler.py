#!/usr/bin/env python3
"""Compile Open Genome pipeline artifacts into static HTML/TSV/JSON."""
from __future__ import annotations

import argparse
import csv
import gzip
import html
import json
import os
import re
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterable


PUBLIC_ANNOTATION_PREVIEW_LIMIT = 200


def _private_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def _private_open_csv(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    return os.fdopen(fd, "w", encoding="utf-8", newline="")


def _safe_int(value: object, default: int = 0) -> int:
    try:
        return int(float(str(value).strip()))
    except (TypeError, ValueError):
        return default


def _safe_float(value: object, default: float = 0.0) -> float:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return default


def _fmt_number(value: object) -> str:
    if isinstance(value, float):
        return f"{value:.2f}".rstrip("0").rstrip(".")
    if isinstance(value, int):
        return f"{value:,}"
    return html.escape(str(value or ""))


def _count_rows(path: Path) -> int:
    if not path.is_file():
        return 0
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        lines = [line for line in fh if line.strip() and not line.startswith("#")]
    if lines and lines[0].lower().startswith(("chrom\t", "sample\t", "row_id\t")):
        return max(0, len(lines) - 1)
    return len(lines)


def _read_samples(samplesheet: Path) -> list[dict[str, str]]:
    if not samplesheet.is_file():
        return []
    with samplesheet.open("r", encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    for row in rows:
        row.setdefault("row_id", row.get("sample", "unknown"))
        row.setdefault("lane", "lane_1")
    return rows


def _prefix(path: Path, suffix: str) -> str:
    name = path.name
    return name[: -len(suffix)] if name.endswith(suffix) else path.stem


def _read_tsv(path: Path, limit: int | None = None) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open("r", encoding="utf-8", newline="", errors="replace") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        if not reader.fieldnames:
            return []
        rows = []
        for idx, row in enumerate(reader):
            if limit is not None and idx >= limit:
                break
            rows.append(dict(row))
        return rows


def _read_status(path: Path) -> list[dict[str, str]]:
    return _read_tsv(path)


def _read_fastp_json(path: Path) -> dict[str, object]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"file": str(path), "state": "unreadable"}
    summary = data.get("summary", {}) if isinstance(data, dict) else {}
    before = summary.get("before_filtering", {}) if isinstance(summary, dict) else {}
    after = summary.get("after_filtering", {}) if isinstance(summary, dict) else {}
    return {
        "file": str(path),
        "state": "parsed",
        "reads_before": _safe_int(before.get("total_reads")),
        "reads_after": _safe_int(after.get("total_reads")),
        "bases_after": _safe_int(after.get("total_bases")),
        "q30_rate_after": _safe_float(after.get("q30_rate")),
    }


def _parse_mosdepth_summary(path: Path) -> dict[str, object]:
    rows: list[dict[str, object]] = []
    total_row: dict[str, object] | None = None
    for row in _read_tsv(path):
        chrom = (row.get("chrom") or row.get("#chrom") or "").strip()
        if not chrom:
            continue
        parsed = {
            "chrom": chrom,
            "length": _safe_int(row.get("length")),
            "bases": _safe_float(row.get("bases")),
            "mean": _safe_float(row.get("mean")),
            "min": _safe_float(row.get("min")),
            "max": _safe_float(row.get("max")),
        }
        if chrom.lower() in {"total", "genome"}:
            total_row = parsed
        else:
            rows.append(parsed)
    if total_row is None and rows:
        length = sum(_safe_int(row.get("length")) for row in rows)
        bases = sum(_safe_float(row.get("bases")) for row in rows)
        total_row = {
            "chrom": "total",
            "length": length,
            "bases": bases,
            "mean": bases / length if length else 0.0,
            "min": min(_safe_float(row.get("min")) for row in rows),
            "max": max(_safe_float(row.get("max")) for row in rows),
        }
    return {"file": str(path), "chromosomes": rows, "total": total_row or {}}


def _parse_assembly_stats(path: Path) -> dict[str, object]:
    metrics: list[dict[str, str]] = []
    wanted = ("n50", "n90", "auN", "ng50", "total", "scaffold", "contig")
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        lower = line.lower()
        if not any(token.lower() in lower for token in wanted):
            continue
        if ":" in line:
            key, value = line.split(":", 1)
        elif "\t" in line:
            key, value = line.split("\t", 1)
        else:
            parts = re.split(r"\s{2,}", line, maxsplit=1)
            key, value = (parts + [""])[:2]
        metrics.append({"metric": key.strip(), "value": value.strip()})
    return {"file": str(path), "metrics": metrics[:12]}


def _relative_link(path: str | Path, out_dir: Path) -> str:
    p = Path(path)
    try:
        return os.path.relpath(p.resolve(), out_dir.resolve())
    except OSError:
        return str(path)


def _file_anchor(path: str | Path, out_dir: Path, label: str | None = None) -> str:
    href = _relative_link(path, out_dir)
    text = label or Path(path).name
    return f'<a href="{html.escape(href, quote=True)}">{html.escape(text)}</a>'


def _row_id_from_fastqc(path: Path) -> str:
    name = path.name.split("_fastqc.html", 1)[0]
    for suffix in (".trimmed.R1", ".trimmed.R2", ".R1", ".R2", "_R1", "_R2"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def _collect(input_dir: Path, samples: list[dict[str, str]]) -> dict:
    files = {
        "fastp_json": sorted(input_dir.rglob("fastp.*.json")),
        "fastp_html": sorted(input_dir.rglob("fastp.*.html")),
        "fastqc": sorted(input_dir.rglob("*_fastqc.html")),
        "multiqc": sorted(input_dir.rglob("*multiqc_report.html")),
        "samtools_stats": sorted(input_dir.rglob("*.samtools.stats.txt")),
        "mosdepth": sorted(input_dir.rglob("*.mosdepth.summary.txt")),
        "vcf_stats": sorted(input_dir.rglob("*.bcftools.stats.txt")),
        "variant_tables": sorted(input_dir.rglob("*.variant_summary.tsv")),
        "clinvar_tables": sorted(input_dir.rglob("*.clinvar.matches.tsv")),
        "public_annotations": sorted(input_dir.rglob("*.public_annotations.tsv")),
        "consequence_summary": sorted(input_dir.rglob("*.consequence_summary.tsv")),
        "consequence_status": sorted(input_dir.rglob("*.consequence_status.tsv")),
        "annotation_status": sorted(input_dir.rglob("*.annotation_status.tsv")),
        "pharmcat_status": sorted(input_dir.rglob("*.pharmcat_status.tsv")),
        "assembly_stats": sorted(input_dir.rglob("*.gfastats.txt")),
    }

    by_row: dict[str, dict] = defaultdict(
        lambda: {
            "files": defaultdict(list),
            "counts": defaultdict(int),
            "statuses": [],
            "qc": [],
            "coverage": [],
            "public_annotations": [],
            "consequences": [],
            "assembly": [],
        }
    )
    row_to_sample = {row.get("row_id") or row.get("sample", "unknown"): row.get("sample", "unknown") for row in samples}
    for row_id, sample in row_to_sample.items():
        by_row[row_id]["sample"] = sample
        by_row[row_id]["row_id"] = row_id

    suffixes = {
        "fastp_json": (".json", "fastp."),
        "fastp_html": (".html", "fastp."),
        "samtools_stats": (".samtools.stats.txt", ""),
        "mosdepth": (".mosdepth.summary.txt", ""),
        "vcf_stats": (".bcftools.stats.txt", ""),
        "variant_tables": (".variant_summary.tsv", ""),
        "clinvar_tables": (".clinvar.matches.tsv", ""),
        "public_annotations": (".public_annotations.tsv", ""),
        "consequence_summary": (".consequence_summary.tsv", ""),
        "consequence_status": (".consequence_status.tsv", ""),
        "annotation_status": (".annotation_status.tsv", ""),
        "pharmcat_status": (".pharmcat_status.tsv", ""),
        "assembly_stats": (".gfastats.txt", ""),
    }

    for key, paths in files.items():
        if key == "multiqc":
            continue
        if key == "fastqc":
            for path in paths:
                row_id = _row_id_from_fastqc(path)
                by_row[row_id]["row_id"] = row_id
                by_row[row_id]["files"][key].append(str(path))
                by_row[row_id]["counts"]["qc_reports"] += 1
            continue
        suffix, prefix = suffixes.get(key, ("", ""))
        for path in paths:
            name = path.name.removeprefix(prefix)
            row_id = _prefix(Path(name), suffix)
            by_row[row_id]["row_id"] = row_id
            by_row[row_id].setdefault("sample", row_to_sample.get(row_id, row_id))
            by_row[row_id]["files"][key].append(str(path))
            if key == "fastp_json":
                by_row[row_id]["qc"].append(_read_fastp_json(path))
                by_row[row_id]["counts"]["qc_reports"] += 1
            elif key == "fastp_html":
                by_row[row_id]["counts"]["qc_reports"] += 1
            elif key == "mosdepth":
                coverage = _parse_mosdepth_summary(path)
                by_row[row_id]["coverage"].append(coverage)
                by_row[row_id]["counts"]["covered_chromosomes"] += len(coverage["chromosomes"])
            elif key == "variant_tables":
                by_row[row_id]["counts"]["variant_rows"] += _count_rows(path)
            elif key == "clinvar_tables":
                by_row[row_id]["counts"]["clinvar_rows"] += _count_rows(path)
            elif key == "public_annotations":
                rows = _read_tsv(path, limit=PUBLIC_ANNOTATION_PREVIEW_LIMIT)
                by_row[row_id]["public_annotations"].extend(rows)
                by_row[row_id]["counts"]["public_annotation_rows"] += _count_rows(path)
            elif key == "consequence_summary":
                rows = _read_tsv(path)
                by_row[row_id]["consequences"].extend(rows)
                by_row[row_id]["counts"]["consequence_rows"] += sum(1 for row in rows if _safe_int(row.get("count")) > 0)
            elif key == "assembly_stats":
                by_row[row_id]["assembly"].append(_parse_assembly_stats(path))
                by_row[row_id]["counts"]["assembly_reports"] += 1
            elif key in {"annotation_status", "pharmcat_status", "consequence_status"}:
                by_row[row_id]["statuses"].extend(_read_status(path))

    rows = []
    for row_id in sorted(by_row):
        item = by_row[row_id]
        item["files"] = {key: value for key, value in sorted(item["files"].items())}
        item["counts"] = {
            "variant_rows": int(item["counts"].get("variant_rows", 0)),
            "clinvar_rows": int(item["counts"].get("clinvar_rows", 0)),
            "public_annotation_rows": int(item["counts"].get("public_annotation_rows", 0)),
            "consequence_rows": int(item["counts"].get("consequence_rows", 0)),
            "covered_chromosomes": int(item["counts"].get("covered_chromosomes", 0)),
            "qc_reports": int(item["counts"].get("qc_reports", 0)),
            "assembly_reports": int(item["counts"].get("assembly_reports", 0)),
        }
        rows.append(item)

    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        for key, value in row["counts"].items():
            counts[key] += int(value)

    return {
        "files": {key: [str(path) for path in value] for key, value in files.items()},
        "rows": rows,
        "counts": dict(counts),
    }


def _write_findings(path: Path, samples: list[dict[str, str]], evidence: dict) -> None:
    counts_by_row = {row["row_id"]: row["counts"] for row in evidence["rows"]}
    status_by_row = {row["row_id"]: row.get("statuses", []) for row in evidence["rows"]}
    with _private_open_csv(path) as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(
            [
                "sample",
                "row_id",
                "section",
                "finding",
                "source",
                "count",
                "what_this_means",
                "what_this_does_not_mean",
            ]
        )
        for sample in samples or [{"sample": "unknown", "row_id": "unknown"}]:
            sample_id = sample.get("sample", "unknown")
            row_id = sample.get("row_id") or sample_id
            counts = counts_by_row.get(row_id, {})
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Variants",
                    "Variants normalized and summarized",
                    "bcftools",
                    counts.get("variant_rows", 0),
                    "Variants were normalized into a reviewable evidence table.",
                    "This is not a diagnosis and does not imply disease risk by itself.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Coverage",
                    "Coverage summary generated",
                    "mosdepth",
                    counts.get("covered_chromosomes", 0),
                    "Read depth was summarized by reference sequence when alignments were available.",
                    "Coverage does not guarantee every clinically relevant region was confidently assessed.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Public annotation",
                    "ClinVar overlap table generated",
                    "ClinVar",
                    counts.get("clinvar_rows", 0),
                    "Variants overlapping the configured ClinVar VCF were listed for review.",
                    "A match requires review by classification, review status, date, and clinical context.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Public annotation",
                    "dbSNP/gnomAD annotation table generated",
                    "dbSNP/gnomAD",
                    counts.get("public_annotation_rows", 0),
                    "Known IDs and configured population-frequency overlaps were listed when local resources were present.",
                    "Population frequency is not disease prediction and can be ancestry/context dependent.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Consequences",
                    "VEP/SnpEff consequence summary generated",
                    "ANN/CSQ",
                    counts.get("consequence_rows", 0),
                    "Existing VEP CSQ or SnpEff ANN consequence fields were summarized when present.",
                    "Consequence labels are computational predictions and need review against transcript choice and evidence.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "PGx",
                    "PharmCAT status recorded",
                    "PharmCAT",
                    "",
                    "PGx was kept in a separate report section.",
                    "PGx output is not prescribing advice.",
                ]
            )
            for status in status_by_row.get(row_id, []):
                writer.writerow(
                    [
                        sample_id,
                        row_id,
                        status.get("step", "Status"),
                        f"{status.get('step', 'status')} {status.get('state', 'unknown')}",
                        "pipeline-status",
                        "",
                        status.get("message", "Review status before interpretation."),
                        "Skipped or missing optional resources mean that section was not fully assessed.",
                    ]
                )


def _html_table(headers: list[str], rows: Iterable[Iterable[object]], empty: str) -> str:
    body_rows = []
    for row in rows:
        body_rows.append("<tr>" + "".join(f"<td>{_fmt_number(value)}</td>" for value in row) + "</tr>")
    if not body_rows:
        return f'<p class="empty">{html.escape(empty)}</p>'
    header = "".join(f"<th>{html.escape(label)}</th>" for label in headers)
    return f"<table><thead><tr>{header}</tr></thead><tbody>{''.join(body_rows)}</tbody></table>"


def _coverage_chart(row: dict) -> str:
    coverage_sets = row.get("coverage", [])
    chrom_rows: list[dict[str, object]] = []
    for coverage in coverage_sets:
        chrom_rows.extend(coverage.get("chromosomes", []))
    chrom_rows = [item for item in chrom_rows if _safe_float(item.get("mean")) > 0][:28]
    if not chrom_rows:
        return '<p class="empty">No chromosome coverage chart is available for this sample.</p>'
    width = 920
    height = 280
    left = 48
    bottom = 44
    top = 20
    chart_h = height - bottom - top
    max_mean = max(_safe_float(item.get("mean")) for item in chrom_rows) or 1.0
    gap = 5
    bar_w = max(8, int((width - left - 24 - (len(chrom_rows) - 1) * gap) / len(chrom_rows)))
    parts = [
        f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="Chromosome coverage chart" class="coverage-chart">',
        f'<line x1="{left}" y1="{height-bottom}" x2="{width-16}" y2="{height-bottom}" class="axis" />',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{height-bottom}" class="axis" />',
        f'<text x="8" y="{top+8}" class="axis-label">{max_mean:.1f}x</text>',
    ]
    for idx, item in enumerate(chrom_rows):
        mean = _safe_float(item.get("mean"))
        bar_h = max(1, int(chart_h * mean / max_mean))
        x = left + 10 + idx * (bar_w + gap)
        y = height - bottom - bar_h
        chrom = str(item.get("chrom", ""))
        parts.append(f'<rect x="{x}" y="{y}" width="{bar_w}" height="{bar_h}" rx="2" class="bar" />')
        parts.append(f'<title>{html.escape(chrom)}: {mean:.2f}x mean coverage</title>')
        if idx % 2 == 0 or len(chrom_rows) <= 16:
            parts.append(f'<text x="{x + bar_w / 2:.1f}" y="{height-18}" class="tick">{html.escape(chrom[:8])}</text>')
    parts.append("</svg>")
    return "".join(parts)


def _status_text(row: dict) -> str:
    statuses = []
    for status in row.get("statuses", []):
        step = status.get("step") or "PGx"
        state = status.get("state", "unknown")
        statuses.append(f"{step}: {state}")
    return "; ".join(statuses) or "not assessed"


def _sample_rows(samples: list[dict[str, str]], evidence: dict) -> list[list[object]]:
    evidence_by_row = {row["row_id"]: row for row in evidence["rows"]}
    rows = []
    for sample in samples or [{"sample": "unknown", "row_id": "unknown", "input_type": "unknown"}]:
        row_id = sample.get("row_id") or sample.get("sample", "unknown")
        row = evidence_by_row.get(row_id, {"counts": {}, "statuses": []})
        counts = row.get("counts", {})
        rows.append(
            [
                sample.get("sample", "unknown"),
                row_id,
                sample.get("input_type", "unknown"),
                sample.get("sex", "NA") or "NA",
                counts.get("qc_reports", 0),
                counts.get("covered_chromosomes", 0),
                counts.get("variant_rows", 0),
                counts.get("clinvar_rows", 0),
                counts.get("public_annotation_rows", 0),
                counts.get("consequence_rows", 0),
                _status_text(row),
            ]
        )
    return rows


def _qc_section(evidence: dict, out_dir: Path) -> str:
    links = []
    for path in evidence["files"].get("multiqc", []):
        links.append(f"<li>{_file_anchor(path, out_dir, 'MultiQC report')}</li>")
    for path in evidence["files"].get("fastqc", [])[:24]:
        links.append(f"<li>{_file_anchor(path, out_dir)}</li>")
    for path in evidence["files"].get("fastp_html", [])[:24]:
        links.append(f"<li>{_file_anchor(path, out_dir)}</li>")
    if not links:
        return '<p class="empty">No FastQC, fastp, or MultiQC HTML reports were found.</p>'
    return "<ul class=\"file-list\">" + "".join(links) + "</ul>"


def _coverage_section(evidence: dict) -> str:
    blocks = []
    for row in evidence["rows"]:
        coverage_rows = []
        for coverage in row.get("coverage", []):
            total = coverage.get("total", {})
            if total:
                coverage_rows.append(
                    [
                        total.get("chrom", "total"),
                        _safe_int(total.get("length")),
                        _safe_float(total.get("mean")),
                        _safe_float(total.get("min")),
                        _safe_float(total.get("max")),
                    ]
                )
        if not coverage_rows:
            continue
        blocks.append(
            f"<h3>{html.escape(row.get('sample', row.get('row_id', 'sample')))}</h3>"
            + _coverage_chart(row)
            + _html_table(["Region", "Length", "Mean depth", "Min", "Max"], coverage_rows, "No coverage rows found.")
        )
    return "".join(blocks) or '<p class="empty">No mosdepth coverage summaries were found.</p>'


def _consequence_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        for item in sample.get("consequences", []):
            rows.append(
                [
                    sample.get("sample", item.get("sample", "")),
                    item.get("tool", ""),
                    item.get("state", ""),
                    item.get("consequence", ""),
                    item.get("impact", ""),
                    item.get("gene", ""),
                    _safe_int(item.get("count")),
                    item.get("note", ""),
                ]
            )
    return _html_table(
        ["Sample", "Tool", "State", "Consequence", "Impact", "Gene", "Count", "Note"],
        rows[:80],
        "No VEP CSQ or SnpEff ANN consequence rows were found.",
    )


def _public_annotation_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        for item in sample.get("public_annotations", []):
            variant = f"{item.get('chrom', '')}:{item.get('pos', '')} {item.get('ref', '')}>{item.get('alt', '')}"
            rows.append(
                [
                    sample.get("sample", item.get("sample", "")),
                    item.get("source", ""),
                    variant,
                    item.get("id", ""),
                    item.get("label", ""),
                    item.get("value", ""),
                    item.get("note", ""),
                ]
            )
    return _html_table(
        ["Sample", "Source", "Variant", "ID", "Label", "Value", "Note"],
        rows[:120],
        "No ClinVar, dbSNP, or gnomAD rows were found. Configure local public resources to populate this table.",
    )


def _pgx_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        for status in sample.get("statuses", []):
            if (status.get("step") or "").lower() in {"pgx", "pharmcat"} or "pharmcat" in status.get("message", "").lower():
                rows.append(
                    [
                        sample.get("sample", status.get("sample", "")),
                        "PharmCAT",
                        status.get("state", ""),
                        status.get("message", ""),
                    ]
                )
    return _html_table(
        ["Sample", "Tool", "State", "Message"],
        rows,
        "No PharmCAT status was found. PGx is not assessed unless PharmCAT is enabled with a local jar.",
    )


def _assembly_section(evidence: dict, out_dir: Path) -> str:
    rows = []
    for sample in evidence["rows"]:
        for assembly in sample.get("assembly", []):
            metrics = assembly.get("metrics", [])
            file_name = Path(str(assembly["file"])).name
            if not metrics:
                rows.append([sample.get("sample", ""), file_name, "report", "generated"])
            for metric in metrics:
                rows.append(
                    [
                        sample.get("sample", ""),
                        file_name,
                        metric.get("metric", ""),
                        metric.get("value", ""),
                    ]
                )
    return _html_table(["Sample", "File", "Metric", "Value"], rows[:80], "No assembly continuity statistics were found.")


def _write_html(path: Path, samples: list[dict[str, str]], evidence: dict, args: argparse.Namespace) -> None:
    counts = evidence.get("counts", {})
    body = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome Report</title>
  <style>
    :root {{
      color-scheme: light;
      --ink: #172026;
      --muted: #5d6a72;
      --line: #d9e0e4;
      --surface: #f6f8f9;
      --accent: #196b69;
      --accent-2: #7a4f12;
      --good: #1f7a4d;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink);
      background: #ffffff;
      line-height: 1.5;
    }}
    main {{ max-width: 1180px; margin: 0 auto; padding: 28px 22px 56px; }}
    header {{ border-bottom: 1px solid var(--line); padding: 34px 0 28px; margin-bottom: 24px; }}
    h1 {{ font-size: clamp(2rem, 3.8vw, 3.6rem); margin: 0 0 10px; line-height: 1.05; letter-spacing: 0; }}
    h2 {{ font-size: 1.35rem; margin: 34px 0 10px; }}
    h3 {{ font-size: 1rem; margin: 24px 0 8px; }}
    p {{ margin: 0 0 12px; }}
    a {{ color: var(--accent); }}
    code {{ background: var(--surface); border: 1px solid var(--line); padding: 0.08rem 0.28rem; border-radius: 4px; }}
    .lede {{ max-width: 820px; color: var(--muted); font-size: 1.05rem; }}
    .generated {{ color: var(--muted); }}
    .boundary {{ border-left: 5px solid var(--accent-2); background: #fff8ed; padding: 14px 16px; margin: 20px 0; }}
    .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; margin: 18px 0 8px; }}
    .metric {{ border: 1px solid var(--line); border-radius: 8px; padding: 14px; background: var(--surface); }}
    .metric strong {{ display: block; font-size: 1.55rem; line-height: 1.1; color: var(--accent); }}
    .metric span {{ color: var(--muted); font-size: 0.88rem; }}
    table {{ border-collapse: collapse; width: 100%; margin: 12px 0 18px; font-size: 0.94rem; }}
    th, td {{ border: 1px solid var(--line); padding: 0.48rem 0.55rem; text-align: left; vertical-align: top; }}
    th {{ background: var(--surface); }}
    .file-list {{ columns: 2 280px; padding-left: 1.1rem; }}
    .empty {{ color: var(--muted); background: var(--surface); border: 1px solid var(--line); padding: 12px; border-radius: 8px; }}
    .coverage-chart {{ width: 100%; max-height: 320px; border: 1px solid var(--line); border-radius: 8px; background: #fbfcfc; }}
    .axis {{ stroke: #9aa7ae; stroke-width: 1; }}
    .axis-label, .tick {{ fill: #5d6a72; font-size: 12px; text-anchor: middle; }}
    .axis-label {{ text-anchor: start; }}
    .bar {{ fill: var(--accent); }}
    .sources {{ color: var(--muted); font-size: 0.92rem; }}
  </style>
</head>
<body>
<main>
  <header>
    <h1>Open Genome Report</h1>
    <p class="lede">A local, privacy-preserving summary of sequencing quality, coverage, variant evidence, public annotations, and optional pharmacogenomics outputs.</p>
    <p class="generated">Generated {html.escape(evidence['generated_utc'])} from files on this computer.</p>
  </header>

  <section class="boundary">
    <strong>Interpretation boundary:</strong>
    This report is evidence, not diagnosis or treatment advice. Public database matches and computational consequence labels need human review.
  </section>

  <section class="cards" aria-label="Report totals">
    <div class="metric"><strong>{_fmt_number(len(samples) or len(evidence['rows']))}</strong><span>samples</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('variant_rows', 0))}</strong><span>variant rows</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('covered_chromosomes', 0))}</strong><span>coverage rows</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('public_annotation_rows', 0))}</strong><span>public annotation rows</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('consequence_rows', 0))}</strong><span>consequence rows</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('assembly_reports', 0))}</strong><span>assembly reports</span></div>
  </section>

  <h2>Samples</h2>
  {_html_table(["Sample", "Row ID", "Input", "Sex", "QC reports", "Coverage rows", "Variants", "ClinVar", "Public annotations", "Consequences", "Status"], _sample_rows(samples, evidence), "No samples were found.")}

  <h2>Quality Reports</h2>
  <p>FastQC, fastp, and MultiQC files are linked here when the pipeline produced them.</p>
  {_qc_section(evidence, path.parent)}

  <h2>Coverage</h2>
  <p>Coverage comes from mosdepth summaries. The chart shows mean depth by reference sequence so sparse or uneven alignments are visible.</p>
  {_coverage_section(evidence)}

  <h2>Variant Consequences</h2>
  <p>This section summarizes VEP <code>CSQ</code> or SnpEff <code>ANN</code> fields when they are present in the VCF.</p>
  {_consequence_section(evidence)}

  <h2>ClinVar, dbSNP, and gnomAD</h2>
  <p>These rows come only from local public resources or IDs already present in the VCF. Nothing is sent to an external service.</p>
  {_public_annotation_section(evidence)}

  <h2>Pharmacogenomics (PGx)</h2>
  <p>PharmCAT is separated from the rest of the report because PGx findings are medication-context evidence, not general disease-risk findings.</p>
  {_pgx_section(evidence)}

  <h2>Assembly and Continuity</h2>
  <p>N50 and related assembly metrics appear here when an assembly FASTA was supplied.</p>
  {_assembly_section(evidence, path.parent)}

  <h2>Evidence Files</h2>
  <ul class="file-list">
    <li>{_file_anchor(path.parent / 'findings.tsv', path.parent, 'findings.tsv')}</li>
    <li>{_file_anchor(path.parent / 'evidence.json', path.parent, 'evidence.json')}</li>
    <li>{_file_anchor(path.parent / 'run_manifest.json', path.parent, 'run_manifest.json')}</li>
  </ul>
  <p class="sources">Reference: <code>{html.escape(args.reference or '')}</code> · ClinVar: <code>{html.escape(args.clinvar or '')}</code> · dbSNP: <code>{html.escape(args.dbsnp or '')}</code> · gnomAD: <code>{html.escape(args.gnomad or '')}</code> · PharmCAT: <code>{html.escape(args.pharmcat_jar or '')}</code></p>
</main>
</body>
</html>
"""
    _private_write(path, body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--samplesheet", type=Path, required=True)
    parser.add_argument("--reference", default="")
    parser.add_argument("--clinvar", default="")
    parser.add_argument("--dbsnp", default="")
    parser.add_argument("--gnomad", default="")
    parser.add_argument("--vep-cache", default="")
    parser.add_argument("--snpeff-db", default="")
    parser.add_argument("--pharmcat-jar", default="")
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.out_dir.chmod(0o700)
    samples = _read_samples(args.samplesheet)
    evidence = _collect(args.input_dir, samples)
    evidence["samples"] = samples
    evidence["generated_utc"] = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")

    _private_write(args.out_dir / "evidence.json", json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    _write_findings(args.out_dir / "findings.tsv", samples, evidence)
    _write_html(args.out_dir / "report_index.html", samples, evidence, args)
    _write_html(args.out_dir / "open_genome_report.html", samples, evidence, args)
    manifest = {
        "generated_utc": evidence["generated_utc"],
        "samplesheet": str(args.samplesheet),
        "reference": args.reference,
        "clinvar": args.clinvar,
        "dbsnp": args.dbsnp,
        "gnomad": args.gnomad,
        "vep_cache": args.vep_cache,
        "snpeff_db": args.snpeff_db,
        "pharmcat_jar": args.pharmcat_jar,
        "report_index": "report_index.html",
        "legacy_report": "open_genome_report.html",
    }
    _private_write(args.out_dir / "run_manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
