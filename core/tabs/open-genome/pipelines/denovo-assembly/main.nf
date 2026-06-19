nextflow.enable.dsl = 2

def required(name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter: ${name}"
    }
}

process STAGE_LONG_READS {
    tag { row_id }
    publishDir "${params.outdir}/reads", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    tuple val(sample), val(row_id), path("${row_id}.reads.fastq.gz"), emit: reads

    script:
    """
    case "$reads" in
      *.bam)
        samtools fastq -@ ${task.cpus} "$reads" | pigz -p ${task.cpus} > "${row_id}.reads.fastq.gz"
        ;;
      *.gz)
        ln -s "$reads" "${row_id}.reads.fastq.gz"
        ;;
      *)
        pigz -c -p ${task.cpus} "$reads" > "${row_id}.reads.fastq.gz"
        ;;
    esac
    """

    stub:
    """
    printf '@read1\\nACGTACGTACGTACGTACGTACGTACGTACGT\\n+\\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\\n' | gzip -c > "${row_id}.reads.fastq.gz"
    """
}

process READ_SUMMARY {
    tag { row_id }
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    path "${row_id}.seqkit_stats.tsv", emit: summary

    script:
    """
    seqkit stats -T "$reads" > "${row_id}.seqkit_stats.tsv"
    """

    stub:
    """
    printf 'file\\tformat\\ttype\\tnum_seqs\\tsum_len\\tmin_len\\tavg_len\\tmax_len\\n%s\\tFASTQ\\tDNA\\t1\\t32\\t32\\t32.0\\t32\\n' "$reads" > "${row_id}.seqkit_stats.tsv"
    """
}

process HIFIASM_ASSEMBLE {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    tuple val(sample), val(row_id), path("${row_id}.primary.fasta"), path("${row_id}.primary.gfa"), emit: assembly
    path "${row_id}.hifiasm.log", emit: hifiasm_log

    script:
    """
    hifiasm -t ${task.cpus} -o "${row_id}" "$reads" > "${row_id}.hifiasm.log" 2>&1
    primary_gfa=""
    for candidate in "${row_id}.bp.p_ctg.gfa" "${row_id}.p_ctg.gfa" "${row_id}.bp.hap1.p_ctg.gfa" "${row_id}.asm.p_ctg.gfa"; do
      if [[ -s "\$candidate" ]]; then
        primary_gfa="\$candidate"
        break
      fi
    done
    if [[ -z "\$primary_gfa" ]]; then
      primary_gfa=\$(find . -maxdepth 1 -type f \\( -name "${row_id}*.p_ctg.gfa" -o -name "${row_id}*.ctg.gfa" \\) | sort | head -n 1 || true)
    fi
    if [[ -z "\$primary_gfa" ]]; then
      echo "hifiasm did not produce a primary contig GFA" >&2
      exit 1
    fi
    cp "\$primary_gfa" "${row_id}.primary.gfa"
    awk 'BEGIN { OFS="\\n" } /^S/ { print ">" \$2, \$3 }' "${row_id}.primary.gfa" > "${row_id}.primary.fasta"
    if [[ ! -s "${row_id}.primary.fasta" ]]; then
      echo "hifiasm GFA contained no contig sequence records" >&2
      exit 1
    fi
    """

    stub:
    """
    printf 'S\\tcontig_1\\tACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.gfa"
    printf '>contig_1\\nACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.fasta"
    printf 'hifiasm stub for %s\\n' "${row_id}" > "${row_id}.hifiasm.log"
    """
}

process ASSEMBLY_QC {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(primary_fasta), path(primary_gfa)

    output:
    path "${row_id}.gfastats.txt", emit: gfastats

    script:
    """
    gfastats "$primary_fasta" > "${row_id}.gfastats.txt"
    """

    stub:
    """
    printf 'scaffold count: 1\\ntotal scaffold length: 32\\nscaffold N50: 32\\nlongest scaffold: 32\\n' > "${row_id}.gfastats.txt"
    """
}

process COMPILE_DENOVO_REPORT {
    publishDir "${params.outdir}/report", mode: 'copy'

    input:
    path report_inputs

    output:
    path "denovo_assembly_report.html", emit: report_html
    path "denovo_assembly_summary.tsv", emit: summary_tsv
    path "denovo_assembly_manifest.json", emit: manifest_json

    script:
    """
    python3 - <<'PY'
import html
import json
from pathlib import Path

def fasta_lengths(path):
    lengths = []
    current = 0
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith(">"):
                if current:
                    lengths.append(current)
                current = 0
            else:
                current += len(line.strip())
    if current:
        lengths.append(current)
    return lengths

def n50(lengths):
    if not lengths:
        return 0
    total = sum(lengths)
    running = 0
    for value in sorted(lengths, reverse=True):
        running += value
        if running >= total / 2:
            return value
    return 0

rows = []
for fasta in sorted(Path(".").glob("*.primary.fasta")):
    row_id = fasta.name.removesuffix(".primary.fasta")
    lengths = fasta_lengths(fasta)
    gfa = Path(f"{row_id}.primary.gfa")
    stats = Path(f"{row_id}.gfastats.txt")
    log = Path(f"{row_id}.hifiasm.log")
    read_stats = Path(f"{row_id}.seqkit_stats.tsv")
    rows.append({
        "row_id": row_id,
        "contigs": len(lengths),
        "total_bases": sum(lengths),
        "n50": n50(lengths),
        "longest_contig": max(lengths) if lengths else 0,
        "primary_fasta": str(fasta),
        "primary_gfa": str(gfa) if gfa.exists() else "",
        "gfastats": str(stats) if stats.exists() else "",
        "hifiasm_log": str(log) if log.exists() else "",
        "read_summary": str(read_stats) if read_stats.exists() else "",
    })

with open("denovo_assembly_summary.tsv", "w", encoding="utf-8") as out:
    out.write("row_id\\tcontigs\\ttotal_bases\\tn50\\tlongest_contig\\tprimary_fasta\\tprimary_gfa\\tgfastats\\thifiasm_log\\tread_summary\\n")
    for row in rows:
        out.write("\\t".join(str(row[key]) for key in ("row_id", "contigs", "total_bases", "n50", "longest_contig", "primary_fasta", "primary_gfa", "gfastats", "hifiasm_log", "read_summary")) + "\\n")

manifest = {
    "pipeline": "denovo-assembly",
    "assembler": "hifiasm",
    "summary": rows,
}
Path("denovo_assembly_manifest.json").write_text(json.dumps(manifest, indent=2) + "\\n", encoding="utf-8")

cards = []
for row in rows:
    cards.append(f'''
      <section class="sample">
        <h2>{html.escape(row['row_id'])}</h2>
        <dl>
          <div><dt>Contigs</dt><dd>{row['contigs']}</dd></div>
          <div><dt>Total assembled bases</dt><dd>{row['total_bases']:,}</dd></div>
          <div><dt>N50</dt><dd>{row['n50']:,}</dd></div>
          <div><dt>Longest contig</dt><dd>{row['longest_contig']:,}</dd></div>
        </dl>
        <p>The FASTA is the assembled sequence. The GFA keeps the assembly graph, which is useful when checking repeats, bubbles, and unresolved regions.</p>
      </section>
    ''')

html_doc = f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome De Novo Assembly Report</title>
  <style>
    :root {{ color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    body {{ margin: 0; background: #f7f8fa; color: #1c2024; }}
    main {{ max-width: 1120px; margin: 0 auto; padding: 32px 20px 48px; }}
    h1 {{ margin: 0 0 8px; font-size: clamp(2rem, 5vw, 3.2rem); line-height: 1.05; }}
    h2 {{ margin-top: 0; }}
    .lede {{ max-width: 820px; color: #4a515c; font-size: 1.05rem; line-height: 1.6; }}
    .sample {{ margin-top: 22px; padding: 20px; border: 1px solid #d9dee7; border-radius: 8px; background: white; }}
    dl {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin: 18px 0; }}
    dt {{ color: #65707f; font-size: 0.82rem; }}
    dd {{ margin: 4px 0 0; font-size: 1.45rem; font-weight: 700; }}
    .note {{ margin-top: 24px; padding: 16px 18px; border-left: 4px solid #2b6cb0; background: #edf5ff; color: #20364f; }}
    @media (prefers-color-scheme: dark) {{
      body {{ background: #111417; color: #eef1f5; }}
      .lede {{ color: #bac4cf; }}
      .sample {{ background: #171b20; border-color: #2d3642; }}
      dt {{ color: #aab5c2; }}
      .note {{ background: #162433; color: #d8e9ff; }}
    }}
  </style>
</head>
<body>
  <main>
    <h1>De Novo Assembly Report</h1>
    <p class="lede">This report summarizes a local long-read assembly. Use it to inspect assembly size, contiguity, and output files before doing deeper quality checks such as BUSCO, QUAST, Merqury, or reference alignment.</p>
    {''.join(cards) if cards else '<section class="sample"><h2>No assemblies found</h2><p>The pipeline completed without a primary FASTA in the report inputs.</p></section>'}
    <div class="note">N50 is a contiguity metric, not a health or ancestry result. Higher is often better for assemblies, but coverage, read quality, contamination, and collapsed repeats still need review.</div>
  </main>
</body>
</html>
'''
Path("denovo_assembly_report.html").write_text(html_doc, encoding="utf-8")
PY
    """

    stub:
    """
    printf 'row_id\\tcontigs\\ttotal_bases\\tn50\\tlongest_contig\\tprimary_fasta\\tprimary_gfa\\tgfastats\\thifiasm_log\\tread_summary\\n' > denovo_assembly_summary.tsv
    printf '{"pipeline":"denovo-assembly","assembler":"hifiasm","summary":[]}\\n' > denovo_assembly_manifest.json
    printf '<!doctype html><html><body><h1>De Novo Assembly Report</h1></body></html>\\n' > denovo_assembly_report.html
    """
}

workflow {
    required('samplesheet', params.samplesheet)

    Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .filter { row -> row.input_type?.toString()?.trim() == 'denovo_reads' }
        .map { row ->
            def sample = row.sample?.toString()?.trim()
            def rowId = row.row_id?.toString()?.trim() ?: sample
            def reads = row.long_reads?.toString()?.trim()
            if (!sample) error "denovo_reads row is missing sample"
            if (!rowId) error "denovo_reads row for ${sample} is missing row_id"
            if (!reads) error "denovo_reads row for ${sample} is missing long_reads"
            tuple(sample, rowId, file(reads))
        }
        .ifEmpty { error "samplesheet has no denovo_reads rows; import PacBio HiFi or ONT long-read files first" }
        .set { long_reads_ch }

    STAGE_LONG_READS(long_reads_ch)
    READ_SUMMARY(STAGE_LONG_READS.out.reads)
    HIFIASM_ASSEMBLE(STAGE_LONG_READS.out.reads)
    ASSEMBLY_QC(HIFIASM_ASSEMBLE.out.assembly)

    primary_fasta_ch = HIFIASM_ASSEMBLE.out.assembly.map { sample, row_id, fasta, gfa -> fasta }
    primary_gfa_ch = HIFIASM_ASSEMBLE.out.assembly.map { sample, row_id, fasta, gfa -> gfa }

    report_inputs_ch = READ_SUMMARY.out.summary
        .mix(HIFIASM_ASSEMBLE.out.hifiasm_log)
        .mix(primary_fasta_ch)
        .mix(primary_gfa_ch)
        .mix(ASSEMBLY_QC.out.gfastats)
        .collect()

    COMPILE_DENOVO_REPORT(report_inputs_ch)
}
