"""AAR input routing tests for the real Bash script, with offline tool fixtures.

Run: python3 -m unittest discover -s tests -v
Requires Bash and unzip; Windows users can set BASH to Git Bash's executable.
"""

import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh"
)

JAVA = """#!/usr/bin/env bash
set -eu
input="${@: -2:1}"
out="${!#}"
printf '%s' "$input" > "$JAVA_MARKER"
cmp "$input" "$EXPECTED_JAR"
mkdir -p "$out"
case "$JAVA_LAYOUT" in
  direct)
    mkdir -p "$out/smoke"
    printf 'package smoke; class Library {}\n' > "$out/smoke/Library.java" ;;
  archive) cp "$RESULT_ARCHIVE" "$out/$(basename "$input")" ;;
esac
exit "$JAVA_STATUS"
"""

DEX2JAR = """#!/usr/bin/env bash
set -eu
printf 'called' > "$D2J_MARKER"
output=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) input="$1"; shift ;;
  esac
done
# AAR bytecode is already a JAR: using this converter is the reported bug.
[[ "$input" != *.aar ]] || exit 99
if [[ "$D2J_OUTPUT" == yes ]]; then cp "$EXPECTED_JAR" "$output"; fi
exit "$D2J_STATUS"
"""

JADX = """#!/usr/bin/env bash
set -eu
[[ "$1" == -d ]]
mkdir -p "$2/sources"
printf 'class Library {}\n' > "$2/sources/Library.java"
"""


def archive_bytes(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, content in entries.items():
            archive.writestr(name, content)
    return buffer.getvalue()


class AarInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get("BASH") or shutil.which("bash")
        if not cls.bash:
            raise unittest.SkipTest("Bash is required")
        result = subprocess.run(
            [cls.bash, "-c", "command -v unzip"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode:
            raise unittest.SkipTest("unzip is required in Bash's PATH")

    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="aar input ")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, source in {"java": JAVA, "d2j-dex2jar": DEX2JAR, "jadx": JADX}.items():
            path = self.bin / name
            path.write_text(source, encoding="utf-8", newline="\n")
            path.chmod(0o755)
        # The tool fixture checks the exact nested JAR bytes, not real JVM instructions.
        self.jar = archive_bytes({"smoke/Library.class": b"fixture bytecode"})
        (self.root / "expected.jar").write_bytes(self.jar)
        (self.root / "fernflower.jar").touch()
        (self.root / "result.zip").write_bytes(archive_bytes({
            "smoke/Library.java": "package smoke; class Library {}\n",
        }))
        self.output = self.root / "output"

    def invoke(self, *, ext="aar", aar_entries=None, raw=None, engine="fernflower",
               layout="direct", status=0, converter_output="yes", converter_status=0):
        input_file = self.root / ("library case." + ext)
        if raw is not None:
            input_file.write_bytes(raw)
        elif ext == "jar":
            input_file.write_bytes(self.jar)
        else:
            entries = {"classes.jar": self.jar, "AndroidManifest.xml": "<manifest/>"}
            if aar_entries is not None:
                entries = aar_entries
            input_file.write_bytes(archive_bytes(entries))
        env = os.environ.copy()
        env.update({
            "TEST_BIN": self.bin.as_posix(),
            "FERNFLOWER_JAR_PATH": (self.root / "fernflower.jar").as_posix(),
            "FERNFLOWER_TIMEOUT_SECONDS": "0",
            "EXPECTED_JAR": (self.root / "expected.jar").as_posix(),
            "JAVA_MARKER": (self.root / "java-called").as_posix(),
            "D2J_MARKER": (self.root / "d2j-called").as_posix(),
            "RESULT_ARCHIVE": (self.root / "result.zip").as_posix(),
            "JAVA_LAYOUT": layout, "JAVA_STATUS": str(status),
            "D2J_OUTPUT": converter_output, "D2J_STATUS": str(converter_status),
        })
        return subprocess.run(
            [self.bash, "-c",
             'if command -v cygpath >/dev/null; then TEST_BIN=$(cygpath -u "$TEST_BIN"); fi; '
             'export PATH="$TEST_BIN:$PATH"; exec bash "$@"',
             "test", SCRIPT.as_posix(), "--engine", engine, "-o", self.output.as_posix(),
             input_file.as_posix()],
            env=env, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=30,
        )

    def check_success(self, result, *, engine="fernflower"):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.output / "fernflower" if engine == "both" else self.output
        self.assertTrue((output / "sources/smoke/Library.java").is_file(), result.stdout)
        self.assertTrue((self.root / "java-called").is_file(), result.stdout + result.stderr)
        self.assertFalse((output / "intermediate").exists(), result.stdout)
        return output

    def test_aar_extracts_exact_classes_jar_without_dex2jar(self):
        self.check_success(self.invoke())
        self.assertFalse((self.root / "d2j-called").exists())

    def test_aar_result_archive_is_extracted(self):
        output = self.check_success(self.invoke(layout="archive"))
        self.assertFalse(list(output.glob("*.jar")))
        self.assertFalse((self.root / "d2j-called").exists())

    def test_both_engines_accept_aar(self):
        self.check_success(self.invoke(engine="both"), engine="both")
        self.assertTrue((self.output / "jadx/sources/Library.java").is_file())
        self.assertFalse((self.root / "d2j-called").exists())

    def test_missing_classes_jar_is_reported_before_running_tools(self):
        result = self.invoke(aar_entries={"AndroidManifest.xml": "<manifest/>"})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("classes.jar", result.stderr)
        self.assertFalse((self.root / "java-called").exists())
        self.assertFalse((self.root / "d2j-called").exists())
        self.assertFalse(list(self.output.rglob("*.jar")))

    def test_corrupt_aar_is_rejected_without_a_partial_jar(self):
        result = self.invoke(raw=b"not a zip archive")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("classes.jar", result.stderr)
        self.assertFalse((self.root / "java-called").exists())
        self.assertFalse((self.root / "d2j-called").exists())
        self.assertFalse(list(self.output.rglob("*.jar")))

    def test_usable_output_after_nonzero_exit_keeps_partial_success(self):
        result = self.invoke(status=17)
        self.check_success(result)
        self.assertIn("partial success", result.stderr)

    def test_no_output_retains_extracted_jar_for_diagnosis(self):
        result = self.invoke(layout="none", status=17)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("produced no", result.stderr)
        self.assertNotIn("dex2jar artifact", result.stderr)
        retained = list((self.output / "intermediate").glob("*.jar"))
        self.assertEqual(len(retained), 1, result.stderr)
        self.assertEqual(retained[0].read_bytes(), self.jar)

    def test_apk_still_uses_dex2jar(self):
        self.check_success(self.invoke(ext="apk"))
        self.assertTrue((self.root / "d2j-called").is_file())

    def test_failed_apk_conversion_does_not_invoke_java(self):
        result = self.invoke(ext="apk", converter_output="no", converter_status=17)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("dex2jar conversion failed with status 17", result.stderr)
        self.assertFalse((self.root / "java-called").exists())

    def test_jar_still_bypasses_dex2jar(self):
        self.check_success(self.invoke(ext="jar"))
        self.assertFalse((self.root / "d2j-called").exists())


if __name__ == "__main__":
    unittest.main()
