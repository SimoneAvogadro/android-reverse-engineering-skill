"""Exercise actual bundle extraction/dispatch with offline decompiler fixtures.

Run: python3 -m unittest discover -s tests -p test_decompile_bundles.py -v
Requires Bash and unzip. On Windows, set BASH to Git Bash's executable.
"""

import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = (Path(__file__).resolve().parents[1]
          / "plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh")
CREATE_FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0

JADX = r'''#!/usr/bin/env bash
set -eu
out=""
deobf=false
no_res=false
while [[ $# -gt 1 ]]; do
  case "$1" in
    -d) out="$2"; shift 2 ;;
    --deobf) deobf=true; shift ;;
    --no-res) no_res=true; shift ;;
    --show-bad-code) shift ;;
    *) exit 93 ;;
  esac
done
input="$1"
payload=$(unzip -p "$input" payload.txt)
printf '%s|%s|%s\n' "$payload" "$deobf" "$no_res" >> "$JADX_LOG"
mkdir -p "$out/sources/smoke"
printf '%s' "$payload" > "$out/sources/smoke/Mock.java"
'''

DEX2JAR = r'''#!/usr/bin/env bash
set -eu
input=""
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -f) shift ;;
    *) input="$1"; shift ;;
  esac
done
printf '%s\n' "$(unzip -p "$input" payload.txt)" >> "$D2J_LOG"
cp "$input" "$out"
'''

JAVA = r'''#!/usr/bin/env bash
set -eu
input="${@: -2:1}"
out="${!#}"
payload=$(unzip -p "$input" payload.txt)
printf '%s\n' "$payload" >> "$JAVA_LOG"
mkdir -p "$out/smoke"
printf '%s' "$payload" > "$out/smoke/Mock.java"
'''


def archive_bytes(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as archive:
        for name, content in entries.items():
            archive.writestr(name, content)
    return buf.getvalue()


def apk_bytes(payload):
    # Only fixture markers, not executable Android/JVM bytecode.
    return archive_bytes({"classes.dex": b"fixture", "payload.txt": payload})


class BundleInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get("BASH") or shutil.which("bash")
        if not cls.bash:
            raise unittest.SkipTest("Bash is required")
        probe = subprocess.run(
            [cls.bash, "-c", "command -v unzip"], capture_output=True,
            timeout=10, creationflags=CREATE_FLAGS,
        )
        if probe.returncode:
            raise unittest.SkipTest("unzip is required in Bash's PATH")

    def invoke(self, ext, *, engine="jadx", options=(), entries=None, raw=None,
               default_output=False, fingerprint_first=False):
        tmp = tempfile.TemporaryDirectory(prefix="decompile bundle ")
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        tools = root / "bin"
        tools.mkdir()
        for name, source in {"jadx": JADX, "d2j-dex2jar": DEX2JAR, "java": JAVA}.items():
            tool = tools / name
            tool.write_text(source, encoding="utf-8", newline="\n")
            tool.chmod(0o755)
        temp_dir = root / "temporary files"
        temp_dir.mkdir()
        home = root / "home"
        home.mkdir()
        input_file = root / ("bundle case." + ext)
        if raw is None:
            if entries is None:
                entries = {"base.apk": apk_bytes("base"),
                           "splits/feature app.apk": apk_bytes("feature")}
            raw = archive_bytes(entries)
        input_file.write_bytes(raw)
        output = root / ("bundle case-decompiled" if default_output else "output files")
        ff_jar = root / "fernflower.jar"
        ff_jar.touch()
        env = os.environ.copy()
        env.update({
            "TEST_BIN": tools.as_posix(), "TEST_TMP": temp_dir.as_posix(),
            "HOME": home.as_posix(), "FERNFLOWER_JAR_PATH": ff_jar.as_posix(),
            "FERNFLOWER_TIMEOUT_SECONDS": "0",
            "JADX_LOG": (root / "jadx.log").as_posix(),
            "D2J_LOG": (root / "d2j.log").as_posix(),
            "JAVA_LOG": (root / "java.log").as_posix(),
        })
        args = [SCRIPT.as_posix(), "--engine", engine, *options]
        if not default_output:
            args += ["-o", output.as_posix()]
        args.append(input_file.as_posix())
        runner = [
            self.bash, "-c",
            'if command -v cygpath >/dev/null; then '
            'TEST_BIN=$(cygpath -u "$TEST_BIN"); TEST_TMP=$(cygpath -u "$TEST_TMP"); fi; '
            'export PATH="$TEST_BIN:$PATH" TMPDIR="$TEST_TMP"; exec bash "$@"',
            "test",
        ]
        if fingerprint_first:
            fingerprint = subprocess.run(
                [*runner, SCRIPT.with_name("fingerprint.sh").as_posix(), input_file.as_posix()],
                cwd=root, env=env, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=30, creationflags=CREATE_FLAGS,
            )
            self.assertEqual(fingerprint.returncode, 0, fingerprint.stdout + fingerprint.stderr)
            self.assertIn("=== APK Fingerprint:", fingerprint.stdout)
            self.assertEqual(list(temp_dir.iterdir()), [])
        result = subprocess.run(
            [*runner, *args],
            cwd=root, env=env, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=30, creationflags=CREATE_FLAGS,
        )
        return result, root, output, temp_dir

    def assert_outputs(self, result, output, *, engine="jadx"):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name, payload in (("base", "base"), ("feature app", "feature")):
            engines = ("jadx", "fernflower") if engine == "both" else ("",)
            for subdir in engines:
                self.assertEqual(
                    (output / name / subdir / "sources/smoke/Mock.java").read_text(),
                    payload, result.stdout + result.stderr,
                )

    def test_bundle_formats_decompile_every_nested_apk_separately(self):
        for ext in ("xapk", "apks", "apkm"):
            with self.subTest(ext=ext):
                result, root, output, temp_dir = self.invoke(ext)
                self.assert_outputs(result, output)
                self.assertIn(f"=== {ext.upper()} decompilation complete ===", result.stdout)
                self.assertEqual((root / "jadx.log").read_text().splitlines(),
                                 ["base|false|false", "feature|false|false"])
                self.assertEqual(list(temp_dir.iterdir()), [], result.stdout)

    def test_new_bundle_formats_keep_both_engines_and_jadx_options(self):
        for ext in ("apks", "apkm"):
            with self.subTest(ext=ext):
                result, root, output, temp_dir = self.invoke(
                    ext, engine="both", options=("--deobf", "--no-res"),
                )
                self.assert_outputs(result, output, engine="both")
                self.assertEqual((root / "jadx.log").read_text().splitlines(),
                                 ["base|true|true", "feature|true|true"])
                for name in ("d2j", "java"):
                    self.assertEqual((root / (name + ".log")).read_text().splitlines(),
                                     ["base", "feature"])
                self.assertEqual(list(temp_dir.iterdir()), [])

    def test_fingerprint_then_decompile_accepts_the_same_bundle_without_renaming(self):
        for ext in ("apks", "apkm"):
            with self.subTest(ext=ext):
                result, _, output, _ = self.invoke(ext, fingerprint_first=True)
                self.assert_outputs(result, output)

    def test_bundle_extensions_are_case_insensitive_with_explicit_output(self):
        for ext in ("APKS", "APKM"):
            with self.subTest(ext=ext):
                result, _, output, _ = self.invoke(ext)
                self.assert_outputs(result, output)

    def test_bundle_default_output_keeps_the_original_basename(self):
        for ext in ("apks", "apkm"):
            with self.subTest(ext=ext):
                result, _, output, _ = self.invoke(ext, default_output=True)
                self.assert_outputs(result, output)

    def test_empty_bundles_are_rejected_before_invoking_a_decompiler(self):
        for ext in ("xapk", "apks", "apkm"):
            with self.subTest(ext=ext):
                result, root, _, temp_dir = self.invoke(ext, entries={"toc.pb": "metadata"})
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("No APK files found", result.stderr)
                self.assertFalse((root / "jadx.log").exists())
                self.assertEqual(list(temp_dir.iterdir()), [])

    def test_invalid_bundle_is_not_sent_directly_to_jadx(self):
        for ext in ("apks", "apkm"):
            with self.subTest(ext=ext):
                result, root, _, _ = self.invoke(ext, raw=b"not a zip")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Unsupported file type", result.stderr)
                self.assertFalse((root / "jadx.log").exists())

    def test_plain_apk_still_goes_directly_to_jadx(self):
        result, root, output, temp_dir = self.invoke("apk", raw=apk_bytes("single"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((output / "sources/smoke/Mock.java").read_text(), "single")
        self.assertEqual((root / "jadx.log").read_text().strip(), "single|false|false")
        self.assertEqual(list(temp_dir.iterdir()), [])

    def test_xapk_metadata_and_obb_reporting_are_unchanged(self):
        manifest = '{"package_name":"example.test"}'
        result, _, output, _ = self.invoke("xapk", entries={
            "base.apk": apk_bytes("base"), "manifest.json": manifest,
            "Android/obb/example.test/main.obb": b"game data",
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((output / "xapk-manifest.json").read_text(), manifest)
        self.assertIn("main.obb", result.stdout)
        self.assertFalse((output / "main").exists())

    def test_unrelated_zip_extension_is_still_rejected(self):
        result, root, _, _ = self.invoke("zip")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Unsupported file type", result.stderr)
        self.assertFalse((root / "jadx.log").exists())


if __name__ == "__main__":
    unittest.main()
