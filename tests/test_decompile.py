"""Exercise decompile.sh output handling without downloading decompiler tools.

Run with python3 -m unittest discover -s tests -v. Requires Bash and unzip;
on Windows, set BASH to the Git Bash executable if it is not on PATH.
"""

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
printf 'fixture-java' > "$FAKE_JAVA_MARKER"
out="${!#}"
mkdir -p "$out"
case "$FAKE_LAYOUT" in
  direct) cp -R "$FAKE_SOURCES/." "$out/" ;;
  archive) cp "$FAKE_ARCHIVE" "$out/input.jar" ;;
esac
exit "$FAKE_STATUS"
"""

JADX = """#!/usr/bin/env bash
set -eu
[[ "$1" == "-d" ]]
mkdir -p "$2/sources"
printf 'class JadxResult {}\n' > "$2/sources/JadxResult.java"
"""


class DecompileOutputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get("BASH") or shutil.which("bash")
        if not cls.bash:
            raise unittest.SkipTest("Bash is required")
        check = subprocess.run(
            [cls.bash, "-c", "command -v unzip"],
            capture_output=True, text=True, timeout=10,
        )
        if check.returncode:
            raise unittest.SkipTest("unzip is required in Bash's PATH")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="decompile output ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, content in {"java": JAVA, "jadx": JADX}.items():
            path = self.bin / name
            path.write_text(content, encoding="utf-8", newline="\n")
            path.chmod(0o755)
        self.sources = self.root / "fixture"
        self.sources.mkdir()
        self.output = self.root / "output"
        # The boundary under test starts after decompilation, so no real bytecode is needed.
        (self.root / "input.jar").touch()
        (self.root / "fernflower.jar").touch()

    def run_decompile(self, files=(), *, layout="direct", status=0, engine="fernflower"):
        for name in files:
            path = self.sources / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// fixture source\n", encoding="utf-8")
        archive = self.root / "result.zip"
        with zipfile.ZipFile(archive, "w") as result:
            for path in self.sources.rglob("*"):
                if path.is_file():
                    result.write(path, path.relative_to(self.sources).as_posix())
        env = os.environ.copy()
        env.update({
            "TEST_BIN": self.bin.as_posix(),
            "FERNFLOWER_JAR_PATH": (self.root / "fernflower.jar").as_posix(),
            "FERNFLOWER_TIMEOUT_SECONDS": "0",
            "FAKE_SOURCES": self.sources.as_posix(),
            "FAKE_ARCHIVE": archive.as_posix(),
            "FAKE_LAYOUT": layout,
            "FAKE_STATUS": str(status),
            "FAKE_JAVA_MARKER": (self.root / "java-called").as_posix(),
        })
        # Git Bash may prepend its own tools on startup; restore fixture precedence inside it.
        result = subprocess.run(
            [self.bash, "-c",
             'if command -v cygpath >/dev/null; then TEST_BIN=$(cygpath -u "$TEST_BIN"); fi; '
             'export PATH="$TEST_BIN:$PATH"; exec bash "$@"',
             "test", SCRIPT.as_posix(), "--engine", engine, "-o", self.output.as_posix(),
             (self.root / "input.jar").as_posix()],
            env=env, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=30,
        )
        self.assertTrue((self.root / "java-called").is_file(), result.stdout + result.stderr)
        return result

    def assert_success(self, result, files, *, engine="fernflower"):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        dest = self.output / "fernflower" if engine == "both" else self.output
        for name in files:
            self.assertTrue((dest / "sources" / name).is_file(), result.stdout + result.stderr)
        self.assertNotIn("produced no", result.stderr)
        return dest

    def test_direct_kotlin_is_normalized(self):
        files = ["Root.kt", "com/example/Checkout.kt"]
        result = self.run_decompile(files)
        dest = self.assert_success(result, files)
        self.assertFalse((dest / "Root.kt").exists())
        self.assertIn("Java/Kotlin files decompiled by Fernflower: 2", result.stdout)

    def test_archived_kotlin_is_usable(self):
        files = ["com/example/Checkout.kt"]
        result = self.run_decompile(files, layout="archive")
        dest = self.assert_success(result, files)
        self.assertFalse((dest / "input.jar").exists())

    def test_mixed_java_and_kotlin_are_both_counted(self):
        files = ["com/example/Checkout.kt", "com/example/Legacy.java"]
        result = self.run_decompile(files)
        self.assert_success(result, files)
        self.assertIn("Java/Kotlin files decompiled by Fernflower: 2", result.stdout)

    def test_java_only_still_works(self):
        files = ["com/example/Legacy.java"]
        self.assert_success(self.run_decompile(files), files)

    def test_archived_java_still_works(self):
        files = ["com/example/Legacy.java"]
        self.assert_success(self.run_decompile(files, layout="archive"), files)

    def test_nonzero_exit_with_kotlin_is_partial_success(self):
        files = ["com/example/Checkout.kt"]
        result = self.run_decompile(files, status=17)
        self.assert_success(result, files)
        self.assertIn("status 17", result.stderr)
        self.assertIn("partial success", result.stderr)

    def test_empty_output_is_failure(self):
        result = self.run_decompile(["README.txt", "Kotlin.kt.bak"])
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("produced no", result.stderr)

    def test_failed_decompiler_without_sources_still_fails(self):
        result = self.run_decompile(status=17)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("exited with status 17", result.stderr)

    def test_timeout_without_sources_still_fails(self):
        result = self.run_decompile(status=124)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("exceeded timeout", result.stderr)

    def test_both_engines_include_kotlin_in_comparison(self):
        files = ["com/example/Checkout.kt"]
        result = self.run_decompile(files, engine="both")
        self.assert_success(result, files, engine="both")
        self.assertIn("Fernflower:  1 Java/Kotlin files", result.stdout)
        self.assertTrue((self.output / "jadx/sources/JadxResult.java").is_file())


if __name__ == "__main__":
    unittest.main()
