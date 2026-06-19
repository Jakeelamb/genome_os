#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


class ReportCompilerTests(unittest.TestCase):
    def test_counts_are_attributed_per_row_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            inputs = root / "inputs"
            out = root / "out"
            inputs.mkdir()
            samplesheet = root / "samples.csv"
            samplesheet.write_text(
                "sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n"
                "alice,alice_L001,L001,vcf,,,,,/tmp/alice.vcf.gz,,,NA,0\n"
                "bob,bob_L001,L001,vcf,,,,,/tmp/bob.vcf.gz,,,NA,0\n",
                encoding="utf-8",
            )
            (inputs / "alice_L001.variant_summary.tsv").write_text(
                "chrom\tpos\tid\tref\talt\tgt\nchr1\t10\trs1\tA\tG\t0/1\n",
                encoding="utf-8",
            )
            (inputs / "bob_L001.variant_summary.tsv").write_text(
                "chrom\tpos\tid\tref\talt\tgt\nchr1\t10\trs1\tA\tG\t0/1\nchr1\t20\trs2\tC\tT\t0/1\n",
                encoding="utf-8",
            )
            (inputs / "alice_L001.clinvar.matches.tsv").write_text("chrom\tpos\tid\tref\talt\tgt\n", encoding="utf-8")
            (inputs / "bob_L001.clinvar.matches.tsv").write_text(
                "chrom\tpos\tid\tref\talt\tgt\nchr1\t20\trs2\tC\tT\t0/1\n",
                encoding="utf-8",
            )
            public_rows = ["row_id\tsample\tchrom\tpos\tid\tref\talt\tsource\tlabel\tvalue\tnote\n"]
            for idx in range(250):
                public_rows.append(
                    f"bob_L001\tbob\tchr1\t{20 + idx}\trs{idx}\tC\tT\tdbSNP\tvariant ID\trs{idx}\tKnown public ID\n"
                )
            (inputs / "bob_L001.public_annotations.tsv").write_text("".join(public_rows), encoding="utf-8")
            (inputs / "bob_L001.consequence_summary.tsv").write_text(
                "row_id\tsample\ttool\tstate\tconsequence\tgene\timpact\tcount\tnote\n"
                "bob_L001\tbob\tSnpEff ANN\tparsed\tmissense_variant\tGENE1\tMODERATE\t2\tANN field present\n",
                encoding="utf-8",
            )
            (inputs / "bob_L001.mosdepth.summary.txt").write_text(
                "chrom\tlength\tbases\tmean\tmin\tmax\nchr1\t100\t3000\t30\t0\t80\ntotal\t100\t3000\t30\t0\t80\n",
                encoding="utf-8",
            )
            (inputs / "multiqc_report.html").write_text("<html>multiqc</html>\n", encoding="utf-8")
            (inputs / "bob_L001.trimmed.R1_fastqc.html").write_text("<html>fastqc</html>\n", encoding="utf-8")
            (inputs / "bob_L001.gfastats.txt").write_text("N50: 12345\n# scaffolds: 2\n", encoding="utf-8")
            (inputs / "bob_L001.pharmcat_status.tsv").write_text(
                "row_id\tsample\tstep\tstate\tmessage\nbob_L001\tbob\tpharmcat\tskipped\tPharmCAT jar not configured\n",
                encoding="utf-8",
            )

            subprocess.run(
                [
                    "python3",
                    str(HERE / "report_compiler.py"),
                    "--input-dir",
                    str(inputs),
                    "--out-dir",
                    str(out),
                    "--samplesheet",
                    str(samplesheet),
                ],
                check=True,
            )

            evidence = json.loads((out / "evidence.json").read_text(encoding="utf-8"))
            by_row = {row["row_id"]: row["counts"] for row in evidence["rows"]}
            self.assertEqual(1, by_row["alice_L001"]["variant_rows"])
            self.assertEqual(2, by_row["bob_L001"]["variant_rows"])
            self.assertEqual(0, by_row["alice_L001"]["clinvar_rows"])
            self.assertEqual(1, by_row["bob_L001"]["clinvar_rows"])
            self.assertEqual(250, by_row["bob_L001"]["public_annotation_rows"])
            self.assertEqual(1, by_row["bob_L001"]["consequence_rows"])
            self.assertEqual(1, by_row["bob_L001"]["covered_chromosomes"])
            public_preview = next(row for row in evidence["rows"] if row["row_id"] == "bob_L001")["public_annotations"]
            self.assertEqual(200, len(public_preview))
            with (out / "findings.tsv").open("r", encoding="utf-8", newline="") as fh:
                findings = list(csv.DictReader(fh, delimiter="\t"))
            variant_counts = {
                row["row_id"]: row["count"]
                for row in findings
                if row["finding"] == "Variants normalized and summarized"
            }
            self.assertEqual({"alice_L001": "1", "bob_L001": "2"}, variant_counts)
            report = (out / "report_index.html").read_text(encoding="utf-8")
            self.assertIn("Quality Reports", report)
            self.assertIn("Coverage", report)
            self.assertIn("Variant Consequences", report)
            self.assertIn("ClinVar, dbSNP, and gnomAD", report)
            self.assertIn("Pharmacogenomics (PGx)", report)
            self.assertIn("N50", report)
            self.assertTrue((out / "open_genome_report.html").is_file())
            self.assertEqual("0o600", oct((out / "evidence.json").stat().st_mode & 0o777))


if __name__ == "__main__":
    unittest.main()
