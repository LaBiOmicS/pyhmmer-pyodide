// Runs pyhmmer's own unit tests and the filter regression test inside Pyodide (Node.js).
//
//   npm install pyodide@0.27.8
//   node test/run-tests.mjs dist/pyhmmer-*-pyodide_2024_0_wasm32.whl
//
// Exits non-zero on any failure. Errors from tests that need `multiprocessing`, which does not
// exist in Pyodide, are reported but not counted.
import { loadPyodide } from "pyodide";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const whl = process.argv[2];
if (!whl) { console.error("usage: node run-tests.mjs <pyhmmer wheel>"); process.exit(2); }

const py = await loadPyodide({ stdout: (s) => console.log(s), stderr: (s) => console.error(s) });
await py.loadPackage(["micropip"]);
py.FS.writeFile("/tmp/" + path.basename(whl), fs.readFileSync(whl));
// psutil is not packaged for Pyodide; pyhmmer only calls cpu_count() when cpus=0
py.FS.writeFile("/tmp/psutil.py", "def cpu_count(logical=True):\n    return 1\n");
py.FS.writeFile("/tmp/filters_regression.py", fs.readFileSync(path.join(here, "filters_regression.py")));

const status = await py.runPythonAsync(`
import sys, unittest, runpy
sys.path.insert(0, "/tmp")
import micropip
await micropip.install("emfs:/tmp/${path.basename(whl)}", deps=False)
import pyhmmer, pyhmmer.tests
print("pyhmmer", pyhmmer.__version__, "on", sys.platform)

suite = unittest.defaultTestLoader.loadTestsFromModule(pyhmmer.tests)
r = unittest.TextTestRunner(verbosity=1, stream=sys.stdout).run(suite)
unsupported = [(t, tb) for t, tb in r.errors if "_multiprocessing" in tb]
real_errors = [(t, tb) for t, tb in r.errors if "_multiprocessing" not in tb]
print(f"unit tests: ran {r.testsRun}, failures {len(r.failures)}, errors {len(real_errors)}, "
      f"multiprocessing-only errors {len(unsupported)}, skipped {len(r.skipped)}")
for t, tb in r.failures + real_errors:
    print("  FAILED", t.id(), "::", tb.strip().splitlines()[-1][:300])

try:
    runpy.run_path("/tmp/filters_regression.py", run_name="__main__")
    regression_ok = True
except SystemExit as e:
    regression_ok = (e.code in (0, None))

int(bool(r.failures or real_errors or not regression_ok))
`);
process.exit(status);
