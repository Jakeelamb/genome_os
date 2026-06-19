nextflow.enable.dsl = 2

def required(name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter: ${name}"
    }
}

def optionalPath(value) {
    if (value == null) return ''
    def s = value.toString().trim()
    return s in ['', 'true', 'false', 'null'] ? '' : s
}

process READ_QC {
    tag { row_id }
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(read1), path(read2)

    output:
    tuple val(sample), val(row_id), path("${row_id}.trimmed.R1.fastq.gz"), path("${row_id}.trimmed.R2.fastq.gz"), emit: trimmed_fastq
    path "fastp.${row_id}.json", emit: fastp_json
    path "fastp.${row_id}.html", emit: fastp_html
    path "*_fastqc.html", emit: fastqc_html
    path "*_fastqc.zip", emit: fastqc_zip

    script:
    """
    fastp \\
      -i "$read1" -I "$read2" \\
      -o "${row_id}.trimmed.R1.fastq.gz" -O "${row_id}.trimmed.R2.fastq.gz" \\
      -j "fastp.${row_id}.json" -h "fastp.${row_id}.html"
    fastqc "${row_id}.trimmed.R1.fastq.gz" "${row_id}.trimmed.R2.fastq.gz"
    """

    stub:
    """
    printf '{}' > "fastp.${row_id}.json"
    printf '<html><body>fastp stub</body></html>' > "fastp.${row_id}.html"
    touch "${row_id}.trimmed.R1.fastq.gz" "${row_id}.trimmed.R2.fastq.gz"
    touch "${row_id}.trimmed.R1_fastqc.html" "${row_id}.trimmed.R1_fastqc.zip"
    touch "${row_id}.trimmed.R2_fastqc.html" "${row_id}.trimmed.R2_fastqc.zip"
    """
}

process ALIGN_FASTQ {
    tag { row_id }
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(read1), path(read2)

    output:
    tuple val(sample), val(row_id), path("${row_id}.sorted.bam"), emit: bam
    path "${row_id}.sorted.bam.bai", emit: bai

    script:
    """
    bwa mem -t ${task.cpus} -R "@RG\\tID:${row_id}\\tSM:${sample}\\tPL:ILLUMINA" "${params.fasta}" "$read1" "$read2" \\
      | samtools sort -@ ${task.cpus} -o "${row_id}.sorted.bam" -
    samtools index "${row_id}.sorted.bam"
    """

    stub:
    """
    touch "${row_id}.sorted.bam" "${row_id}.sorted.bam.bai"
    """
}

process STAGE_ALIGNMENT {
    tag { row_id }
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(alignment), val(kind)

    output:
    tuple val(sample), val(row_id), path("${row_id}.input.bam"), emit: alignment

    script:
    """
    if [[ "$kind" == "cram" ]]; then
      samtools view -@ ${task.cpus} -T "${params.fasta}" -b -o "${row_id}.input.bam" "$alignment"
    else
      cp "$alignment" "${row_id}.input.bam"
    fi
    samtools index "${row_id}.input.bam"
    """

    stub:
    """
    touch "${row_id}.input.bam"
    """
}

process ALIGNMENT_QC {
    tag { row_id }
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(alignment)

    output:
    tuple val(sample), val(row_id), path(alignment), emit: alignment_passthrough
    path "${row_id}.samtools.flagstat.txt", emit: flagstat
    path "${row_id}.samtools.stats.txt", emit: samtools_stats
    path "${row_id}.mosdepth.summary.txt", emit: mosdepth_summary

    script:
    """
    samtools flagstat "$alignment" > "${row_id}.samtools.flagstat.txt"
    samtools stats --reference "${params.fasta}" "$alignment" > "${row_id}.samtools.stats.txt"
    samtools index "$alignment"
    mosdepth -f "${params.fasta}" -t ${task.cpus} "${row_id}" "$alignment"
    """

    stub:
    """
    printf '0 + 0 in total\\n' > "${row_id}.samtools.flagstat.txt"
    printf 'SN\\tnumber of records:\\t0\\n' > "${row_id}.samtools.stats.txt"
    printf 'chrom\\tlength\\tbases\\tmean\\tmin\\tmax\\nchr1\\t12\\t360\\t30\\t0\\t45\\ntotal\\t12\\t360\\t30\\t0\\t45\\n' > "${row_id}.mosdepth.summary.txt"
    """
}

process MULTIQC_REPORT {
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    path qc_inputs

    output:
    path "multiqc_report.html", emit: report_html

    script:
    """
    if multiqc . -o . -n multiqc_report.html --force; then
      :
    else
      printf '<!doctype html><html><body><h1>MultiQC unavailable</h1><p>Open Genome could not build a MultiQC report from the staged QC files.</p></body></html>\\n' > multiqc_report.html
    fi
    """

    stub:
    """
    printf '<!doctype html><html><body><h1>MultiQC stub report</h1></body></html>\\n' > multiqc_report.html
    """
}

process GATK_GERMLINE {
    tag { row_id }
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(alignment)

    output:
    tuple val(sample), val(row_id), path("${row_id}.raw.vcf.gz"), emit: raw_vcf
    path "${row_id}.raw.vcf.gz.tbi", emit: raw_tbi

    script:
    def known = []
    def dbsnp = optionalPath(params.dbsnp)
    def knownIndels = optionalPath(params.known_indels)
    if (dbsnp) known << "--known-sites '${dbsnp}'"
    if (knownIndels) known << "--known-sites '${knownIndels}'"
    def knownArgs = known.join(' ')
    """
    gatk MarkDuplicates -I "$alignment" -O "${row_id}.md.bam" -M "${row_id}.markduplicates.metrics.txt" --CREATE_INDEX true
    if [[ -n "${knownArgs}" ]]; then
      gatk BaseRecalibrator -R "${params.fasta}" -I "${row_id}.md.bam" ${knownArgs} -O "${row_id}.recal.table"
      gatk ApplyBQSR -R "${params.fasta}" -I "${row_id}.md.bam" --bqsr-recal-file "${row_id}.recal.table" -O "${row_id}.recal.bam"
      samtools index "${row_id}.recal.bam"
      call_bam="${row_id}.recal.bam"
    else
      call_bam="${row_id}.md.bam"
    fi
    gatk HaplotypeCaller -R "${params.fasta}" -I "\$call_bam" -O "${row_id}.raw.vcf.gz"
    tabix -f -p vcf "${row_id}.raw.vcf.gz"
    """

    stub:
    """
    printf '##fileformat=VCFv4.2\\n#CHROM\\tPOS\\tID\\tREF\\tALT\\tQUAL\\tFILTER\\tINFO\\n' | bgzip -c > "${row_id}.raw.vcf.gz"
    tabix -f -p vcf "${row_id}.raw.vcf.gz" || touch "${row_id}.raw.vcf.gz.tbi"
    """
}

process NORMALIZE_VCF {
    tag { row_id }
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf)

    output:
    tuple val(sample), val(row_id), path("${row_id}.normalized.vcf.gz"), path("${row_id}.normalized.vcf.gz.tbi"), emit: normalized_vcf
    path "${row_id}.bcftools.stats.txt", emit: bcftools_stats

    script:
    """
    bcftools norm -f "${params.fasta}" -m -any "$vcf" -Oz -o "${row_id}.normalized.vcf.gz"
    tabix -f -p vcf "${row_id}.normalized.vcf.gz"
    bcftools stats "${row_id}.normalized.vcf.gz" > "${row_id}.bcftools.stats.txt"
    """

    stub:
    """
    cp "$vcf" "${row_id}.normalized.vcf.gz" || touch "${row_id}.normalized.vcf.gz"
    touch "${row_id}.normalized.vcf.gz.tbi"
    printf 'SN\\tnumber of records:\\t0\\n' > "${row_id}.bcftools.stats.txt"
    """
}

process ANNOTATE_VCF {
    tag { row_id }
    publishDir "${params.outdir}/annotations", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf), path(vcf_tbi)

    output:
    tuple val(sample), val(row_id), path("${row_id}.annotated.vcf.gz"), emit: annotated_vcf
    path "${row_id}.clinvar.matches.tsv", emit: clinvar_tsv
    path "${row_id}.variant_summary.tsv", emit: variant_tsv
    path "${row_id}.public_annotations.tsv", emit: public_annotations
    path "${row_id}.annotation_status.tsv", emit: annotation_status

    script:
    def dbsnp = optionalPath(params.dbsnp)
    def clinvar = optionalPath(params.clinvar)
    def gnomad = optionalPath(params.gnomad)
    """
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n' > "${row_id}.annotation_status.tsv"
    cp "$vcf" "${row_id}.annotated.vcf.gz"
    if [[ "${dbsnp}" != "" && -f "${dbsnp}" ]]; then
      bcftools annotate -a "${dbsnp}" -c ID "$vcf" -Oz -o "${row_id}.annotated.vcf.gz"
      printf '%s\\t%s\\tdbsnp\\tcomplete\\t%s\\n' "${row_id}" "${sample}" "${dbsnp}" >> "${row_id}.annotation_status.tsv"
    else
      printf '%s\\t%s\\tdbsnp\\tskipped\\tno dbSNP VCF configured\\n' "${row_id}" "${sample}" >> "${row_id}.annotation_status.tsv"
    fi
    tabix -f -p vcf "${row_id}.annotated.vcf.gz"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.variant_summary.tsv"
    bcftools query -f '%CHROM\\t%POS\\t%ID\\t%REF\\t%ALT[\\t%GT]\\n' "${row_id}.annotated.vcf.gz" >> "${row_id}.variant_summary.tsv"
    if [[ "${params.enable_clinvar}" == "true" && "${clinvar}" != "" && -f "${clinvar}" ]]; then
      bcftools isec -n=2 -w1 "$vcf" "${clinvar}" -Oz -p clinvar_isec
      printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
      if [[ -f clinvar_isec/0000.vcf.gz ]]; then
        bcftools query -f '%CHROM\\t%POS\\t%ID\\t%REF\\t%ALT[\\t%GT]\\n' clinvar_isec/0000.vcf.gz >> "${row_id}.clinvar.matches.tsv"
      fi
      printf '%s\\t%s\\tclinvar\\tcomplete\\t%s\\n' "${row_id}" "${sample}" "${clinvar}" >> "${row_id}.annotation_status.tsv"
    else
      printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
      printf '%s\\t%s\\tclinvar\\tskipped\\tClinVar disabled or not configured\\n' "${row_id}" "${sample}" >> "${row_id}.annotation_status.tsv"
    fi
    if [[ "${gnomad}" != "" && -f "${gnomad}" ]]; then
      bcftools isec -n=2 -w1 "$vcf" "${gnomad}" -Oz -p gnomad_isec
      printf '%s\\t%s\\tgnomad\\tcomplete\\t%s\\n' "${row_id}" "${sample}" "${gnomad}" >> "${row_id}.annotation_status.tsv"
    else
      printf '%s\\t%s\\tgnomad\\tskipped\\tgnomAD VCF not configured\\n' "${row_id}" "${sample}" >> "${row_id}.annotation_status.tsv"
    fi
    python3 - "${row_id}" "${sample}" "${row_id}.annotated.vcf.gz" "clinvar_isec/0000.vcf.gz" "gnomad_isec/0000.vcf.gz" "${row_id}.public_annotations.tsv" <<'PY'
import gzip
import sys
from pathlib import Path

row_id, sample, annotated, clinvar, gnomad, out_path = sys.argv[1:]

def open_text(path):
    p = Path(path)
    if not p.is_file():
        return None
    return gzip.open(p, "rt", encoding="utf-8", errors="replace") if p.suffix == ".gz" else p.open("r", encoding="utf-8", errors="replace")

def info_map(raw):
    out = {}
    for item in raw.split(";"):
        if not item:
            continue
        if "=" in item:
            key, value = item.split("=", 1)
        else:
            key, value = item, "present"
        out[key] = value
    return out

def iter_variants(path):
    fh = open_text(path)
    if fh is None:
        return
    with fh:
        for line in fh:
            if not line or line.startswith("#"):
                continue
            fields = line.rstrip("\\n").split("\\t")
            if len(fields) < 8:
                continue
            chrom, pos, vid, ref, alt = fields[:5]
            yield chrom, pos, vid, ref, alt, info_map(fields[7])

def write_row(fh, chrom, pos, vid, ref, alt, source, label, value, note):
    fh.write("\\t".join([row_id, sample, chrom, pos, vid, ref, alt, source, label, value, note]) + "\\n")

with open(out_path, "w", encoding="utf-8") as out:
    out.write("row_id\\tsample\\tchrom\\tpos\\tid\\tref\\talt\\tsource\\tlabel\\tvalue\\tnote\\n")
    for chrom, pos, vid, ref, alt, info in iter_variants(annotated) or []:
        if vid and vid != ".":
            write_row(out, chrom, pos, vid, ref, alt, "dbSNP", "variant ID", vid, "Known public ID on annotated VCF")
        for key in ("AF", "AF_popmax", "gnomAD_AF", "gnomADg_AF", "gnomADe_AF"):
            if key in info:
                write_row(out, chrom, pos, vid, ref, alt, "gnomAD", key, info[key], "Allele-frequency field present on VCF record")
    for chrom, pos, vid, ref, alt, info in iter_variants(clinvar) or []:
        write_row(out, chrom, pos, vid, ref, alt, "ClinVar", "overlap", "present", "Variant overlaps configured local ClinVar VCF")
    for chrom, pos, vid, ref, alt, info in iter_variants(gnomad) or []:
        write_row(out, chrom, pos, vid, ref, alt, "gnomAD", "overlap", "present", "Variant overlaps configured local gnomAD VCF")
PY
    """

    stub:
    """
    cp "$vcf" "${row_id}.annotated.vcf.gz" || touch "${row_id}.annotated.vcf.gz"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.variant_summary.tsv"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
    printf 'row_id\\tsample\\tchrom\\tpos\\tid\\tref\\talt\\tsource\\tlabel\\tvalue\\tnote\\n' > "${row_id}.public_annotations.tsv"
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n%s\\t%s\\tstub\\tcomplete\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.annotation_status.tsv"
    """
}

process CONSEQUENCE_SUMMARY {
    tag { row_id }
    publishDir "${params.outdir}/annotations", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf)

    output:
    path "${row_id}.consequence_summary.tsv", emit: consequence_tsv
    path "${row_id}.consequence_status.tsv", emit: consequence_status

    script:
    def vepCache = optionalPath(params.vep_cache)
    def snpEffDb = optionalPath(params.snpeff_db)
    """
    python3 - "${row_id}" "${sample}" "$vcf" "${row_id}.consequence_summary.tsv" "${row_id}.consequence_status.tsv" "${vepCache}" "${snpEffDb}" <<'PY'
import gzip
import re
import sys
from collections import Counter
from pathlib import Path

row_id, sample, vcf, out_table, out_status, vep_cache, snpeff_db = sys.argv[1:]

def open_text(path):
    p = Path(path)
    return gzip.open(p, "rt", encoding="utf-8", errors="replace") if p.suffix == ".gz" else p.open("r", encoding="utf-8", errors="replace")

def info_map(raw):
    out = {}
    for item in raw.split(";"):
        if not item:
            continue
        if "=" in item:
            key, value = item.split("=", 1)
        else:
            key, value = item, "present"
        out[key] = value
    return out

csq_fields = []
counts = Counter()
state = "skipped"
message = "No VEP CSQ or SnpEff ANN consequence field found; configure a local annotation step to populate this section"
with open_text(vcf) as fh:
    for line in fh:
        if line.startswith("##INFO=<ID=CSQ"):
            match = re.search(r"Format: ([^\\\"]+)", line)
            if match:
                csq_fields = [part.strip() for part in match.group(1).split("|")]
        if line.startswith("#"):
            continue
        fields = line.rstrip("\\n").split("\\t")
        if len(fields) < 8:
            continue
        info = info_map(fields[7])
        if "ANN" in info:
            state = "parsed"
            message = "Parsed SnpEff ANN fields already present in VCF"
            for ann in info["ANN"].split(","):
                parts = ann.split("|")
                consequence = parts[1] if len(parts) > 1 and parts[1] else "unknown"
                impact = parts[2] if len(parts) > 2 and parts[2] else "unknown"
                gene = parts[3] if len(parts) > 3 and parts[3] else ""
                counts[("SnpEff ANN", consequence, gene, impact, "ANN field present in VCF")] += 1
        if "CSQ" in info:
            state = "parsed"
            message = "Parsed VEP CSQ fields already present in VCF"
            for csq in info["CSQ"].split(","):
                parts = csq.split("|")
                mapped = dict(zip(csq_fields, parts)) if csq_fields else {}
                consequence = mapped.get("Consequence") or (parts[1] if len(parts) > 1 else "unknown")
                impact = mapped.get("IMPACT") or mapped.get("Impact") or "unknown"
                gene = mapped.get("SYMBOL") or mapped.get("Gene") or ""
                counts[("VEP CSQ", consequence, gene, impact, "CSQ field present in VCF")] += 1

if not counts and (vep_cache or snpeff_db):
    state = "configured_no_fields"
    message = "VEP/SnpEff configuration was present, but this VCF did not contain CSQ or ANN consequence fields"

with open(out_table, "w", encoding="utf-8") as out:
    out.write("row_id\\tsample\\ttool\\tstate\\tconsequence\\tgene\\timpact\\tcount\\tnote\\n")
    if counts:
        for (tool, consequence, gene, impact, note), count in sorted(counts.items()):
            out.write("\\t".join([row_id, sample, tool, state, consequence, gene, impact, str(count), note]) + "\\n")
    else:
        out.write("\\t".join([row_id, sample, "VEP/SnpEff", state, "not_assessed", "", "", "0", message]) + "\\n")

with open(out_status, "w", encoding="utf-8") as out:
    out.write("row_id\\tsample\\tstep\\tstate\\tmessage\\n")
    out.write("\\t".join([row_id, sample, "consequence", state, message]) + "\\n")
PY
    """

    stub:
    """
    printf 'row_id\\tsample\\ttool\\tstate\\tconsequence\\tgene\\timpact\\tcount\\tnote\\n%s\\t%s\\tVEP/SnpEff\\tstub\\tnot_assessed\\t\\t\\t0\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.consequence_summary.tsv"
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n%s\\t%s\\tconsequence\\tstub\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.consequence_status.tsv"
    """
}

process PHARMCAT {
    tag { row_id }
    publishDir "${params.outdir}/annotations/pharmcat", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf), path(vcf_tbi)

    output:
    path "${row_id}.pharmcat_status.tsv", emit: status
    path "pharmcat", emit: pharmcat_dir

    script:
    def pharmcatJar = optionalPath(params.pharmcat_jar)
    """
    mkdir -p pharmcat
    printf 'row_id\\tsample\\tstate\\tmessage\\n' > "${row_id}.pharmcat_status.tsv"
    if [[ "${params.enable_pgx}" != "true" ]]; then
      printf '%s\\t%s\\tdisabled\\tPharmCAT disabled\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    elif [[ "${pharmcatJar}" != "" && -f "${pharmcatJar}" ]]; then
      if java -jar "${pharmcatJar}" -vcf "$vcf" -o pharmcat > pharmcat/pharmcat.log 2>&1; then
        printf '%s\\t%s\\tcomplete\\tPharmCAT completed\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
      else
        printf '%s\\t%s\\tfailed\\tPharmCAT failed; see pharmcat.log\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
        exit 1
      fi
    else
      printf '%s\\t%s\\tskipped\\tPharmCAT jar not configured; PGx not assessed\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    fi
    """

    stub:
    """
    mkdir -p pharmcat
    printf 'row_id\\tsample\\tstate\\tmessage\\n%s\\t%s\\tstub\\tPharmCAT stub\\n' "${row_id}" "${sample}" > "${row_id}.pharmcat_status.tsv"
    """
}

process ASSEMBLY_QC {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(assembly)

    output:
    path "${row_id}.gfastats.txt", emit: gfastats

    script:
    """
    gfastats "$assembly" > "${row_id}.gfastats.txt"
    """

    stub:
    """
    printf '# scaffolds: 0\\n' > "${row_id}.gfastats.txt"
    """
}

process COMPILE_REPORT {
    publishDir "${params.outdir}/report", mode: 'copy'

    input:
    path report_inputs

    output:
    path "report_index.html", emit: report_index
    path "open_genome_report.html", emit: report_html
    path "findings.tsv", emit: findings_tsv
    path "evidence.json", emit: evidence_json
    path "run_manifest.json", emit: run_manifest

    script:
    def clinvar = optionalPath(params.clinvar)
    def dbsnp = optionalPath(params.dbsnp)
    def gnomad = optionalPath(params.gnomad)
    def vepCache = optionalPath(params.vep_cache)
    def snpEffDb = optionalPath(params.snpeff_db)
    def pharmcatJar = optionalPath(params.pharmcat_jar)
    """
    python3 "${params.report_compiler}" \\
      --input-dir . \\
      --out-dir . \\
      --samplesheet "${params.samplesheet}" \\
      --reference "${params.fasta}" \\
      --clinvar "${clinvar}" \\
      --dbsnp "${dbsnp}" \\
      --gnomad "${gnomad}" \\
      --vep-cache "${vepCache}" \\
      --snpeff-db "${snpEffDb}" \\
      --pharmcat-jar "${pharmcatJar}"
    """

    stub:
    """
    printf '<html><body>Open Genome stub report</body></html>\\n' > report_index.html
    printf '<html><body>Open Genome stub report</body></html>\\n' > open_genome_report.html
    printf 'sample\\tfinding\\tsource\\n' > findings.tsv
    printf '{}\\n' > evidence.json
    printf '{}\\n' > run_manifest.json
    """
}

workflow {
    required('samplesheet', params.samplesheet)
    required('fasta', params.fasta)

    Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def sample = row.sample?.toString()?.trim()
            def rowId = row.row_id?.toString()?.trim() ?: sample
            def inputType = row.input_type?.toString()?.trim()
            if (!sample) error "samplesheet row is missing sample"
            if (!rowId) error "samplesheet row for ${sample} is missing row_id"
            if (!inputType) error "samplesheet row for ${sample} is missing input_type"
            tuple(sample, rowId, inputType, row)
        }
        .set { samples_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'fastq' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.fastq_1), file(row.fastq_2)) }
        .set { fastq_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'alignment' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.bam ?: row.cram), row.bam ? 'bam' : 'cram') }
        .set { alignment_input_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'vcf' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.vcf)) }
        .set { vcf_input_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'assembly' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.assembly)) }
        .set { assembly_input_ch }

    READ_QC(fastq_ch)
    ALIGN_FASTQ(READ_QC.out.trimmed_fastq)
    STAGE_ALIGNMENT(alignment_input_ch)

    alignment_for_qc_ch = ALIGN_FASTQ.out.bam.mix(STAGE_ALIGNMENT.out.alignment)
    ALIGNMENT_QC(alignment_for_qc_ch)
    GATK_GERMLINE(ALIGNMENT_QC.out.alignment_passthrough)

    qc_report_inputs_ch = READ_QC.out.fastp_json
        .mix(READ_QC.out.fastp_html)
        .mix(READ_QC.out.fastqc_html)
        .mix(ALIGNMENT_QC.out.flagstat)
        .mix(ALIGNMENT_QC.out.samtools_stats)
        .mix(ALIGNMENT_QC.out.mosdepth_summary)
        .collect()
    MULTIQC_REPORT(qc_report_inputs_ch)

    vcf_for_norm_ch = GATK_GERMLINE.out.raw_vcf.mix(vcf_input_ch)
    NORMALIZE_VCF(vcf_for_norm_ch)
    ANNOTATE_VCF(NORMALIZE_VCF.out.normalized_vcf)
    CONSEQUENCE_SUMMARY(ANNOTATE_VCF.out.annotated_vcf)
    PHARMCAT(NORMALIZE_VCF.out.normalized_vcf)
    ASSEMBLY_QC(assembly_input_ch)

    report_inputs_ch = READ_QC.out.fastp_json
        .mix(READ_QC.out.fastp_html)
        .mix(READ_QC.out.fastqc_html)
        .mix(MULTIQC_REPORT.out.report_html)
        .mix(ALIGNMENT_QC.out.flagstat)
        .mix(ALIGNMENT_QC.out.samtools_stats)
        .mix(ALIGNMENT_QC.out.mosdepth_summary)
        .mix(NORMALIZE_VCF.out.bcftools_stats)
        .mix(ANNOTATE_VCF.out.variant_tsv)
        .mix(ANNOTATE_VCF.out.clinvar_tsv)
        .mix(ANNOTATE_VCF.out.public_annotations)
        .mix(CONSEQUENCE_SUMMARY.out.consequence_tsv)
        .mix(CONSEQUENCE_SUMMARY.out.consequence_status)
        .mix(ANNOTATE_VCF.out.annotation_status)
        .mix(PHARMCAT.out.status)
        .mix(ASSEMBLY_QC.out.gfastats)
        .collect()

    COMPILE_REPORT(report_inputs_ch)
}
