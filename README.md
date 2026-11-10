# pyhmmer-pyodide

[![build](https://github.com/LaBiOmicS/pyhmmer-pyodide/actions/workflows/build.yml/badge.svg)](https://github.com/LaBiOmicS/pyhmmer-pyodide/actions/workflows/build.yml)

A [pyhmmer](https://github.com/althonos/pyhmmer) wheel for [Pyodide](https://pyodide.org), so that
HMMER searches (`hmmsearch`, `nhmmer`, `phmmer`, ...) run in a web browser or in Node.js, on the
user's machine, with no server.

| | Version |
|---|---|
| pyhmmer | 0.12.3 (PyPI sdist, SHA-256 checked) |
| Pyodide | 0.27.8 (Python 3.12) |
| Emscripten | 3.1.58 |
| Wheel tag | `cp312-abi3-pyodide_2024_0_wasm32` |

The wheel is built from the unmodified PyPI source plus one patch,
[`patches/pyhmmer-0.12.3-pyodide.patch`](patches/pyhmmer-0.12.3-pyodide.patch), described below.
pyhmmer has no WebAssembly build of its own; this repository is independent of the pyhmmer project.

## Results are identical to native pyhmmer

Inside Pyodide (Node.js 22/24), the wheel passes:

- **pyhmmer's own test suite**: 995 tests, 0 failures. Two tests error because they need
  `multiprocessing`, which Pyodide does not have; 247 are skipped by the suite itself.
- **A filter regression test** ([`test/filters_regression.py`](test/filters_regression.py)): with the
  SIMD pre-filters on, the strong hits (E < 1e-10) and their bit scores must equal those of a search
  with every filter off, for protein (`hmmsearch`) and nucleotide (`nhmmer`) queries.

The first real user of the wheel, [HumaninFinder](https://github.com/LaBiOmicS/humaninfinder), also
produces byte-identical output in the browser and natively on its validation sets (370 mitogenomes,
2,560 annotated loci).

CI rebuilds the wheel from scratch and runs both test sets on every push.

The tests do catch the bug fixed below: a wheel built without the `uint8_t` fix fails 51 of
pyhmmer's tests (16 more error out), every case of the filter regression test reports 0 hits
against 1-12 with filters off, and `hmmsearch` of PF02826 finds 0 hits instead of 22.

## Use

Host the wheel next to your page (GitHub release assets cannot be fetched cross-origin from a
browser) and install it with micropip:

```js
const pyodide = await loadPyodide();          // Pyodide 0.27.x
await pyodide.loadPackage("micropip");
// pyhmmer imports psutil, which Pyodide does not package; a stub is enough with cpus=1
pyodide.FS.writeFile("/tmp/psutil.py", "def cpu_count(logical=True):\n    return 1\n");
await pyodide.runPythonAsync(`
import sys; sys.path.insert(0, "/tmp")
import micropip
await micropip.install("./pyhmmer-0.12.3-cp312-abi3-pyodide_2024_0_wasm32.whl", deps=False)

import pyhmmer
# ... use pyhmmer as usual, always with cpus=1
`);
```

Limits of the platform, not of the wheel:

- **One thread.** Pass `cpus=1` to `pyhmmer.hmmer.*`. Pyodide has no threads or `multiprocessing`.
- **Memory.** A browser tab has a few GB at most; whole nuclear genomes are out of reach.
- **Speed.** SSE is emulated on WebAssembly SIMD128. On HumaninFinder's workload (`nhmmer` and
  `hmmsearch` over mitogenomes, Node.js 24 vs native x86-64, one thread) the WebAssembly run took
  10-15% longer: 326 s vs 298 s for 343 mitogenomes, 38.7 s vs 33.8 s for 27. Other workloads may
  differ.

## What the patch changes

| File | Change | Why |
|---|---|---|
| `vendor/hmmer/src/impl_sse/p7_oprofile.c` | `(uint8_t) sc` → `(uint8_t) (int) sc` in `biased_byteify`, `unbiased_byteify`, `wordify` | **Correctness.** `sc` can be a negative float. Converting a negative float to an unsigned integer is undefined in C: on x86 the value wraps around (the code relies on this), on WebAssembly it saturates to 0. Without the fix every MSV/SSV byte score is wrong, the pre-filter discards everything, and searches **silently return no hits**. Going through `int` reproduces the x86 result. |
| `vendor/easel/esl_cpu.c` | No `cpuid` under Emscripten; SSE/SSE4.1 reported as available | There is no `cpuid` in WebAssembly; SSE is compiled in through emulation. |
| `vendor/easel/esl_sse.{c,h}`, `vendor/hmmer/src/impl_sse/decoding.c` | `<x86intrin.h>` → `<smmintrin.h>` under Emscripten | Emscripten emulates the SSE headers up to SSE4.1, not `x86intrin.h`. |
| `src/pyhmmer/platform/{__init__.pxd,CMakeLists.txt}` | Emscripten uses the Linux file-object layer | Emscripten's musl libc has `fopencookie`. |
| `CMakeLists.txt` | Hidden symbol visibility under Emscripten; build with `BUILD_SHARED_LIBS=false` | With shared `libeasel`/`libhmmer`, calls between extension modules go through JavaScript, which cannot carry SIMD (`v128`) arguments, and Pyodide aborts. Static libraries keep every call inside one module. |

The emulated SSE intrinsics themselves were checked against native x86 on random inputs (every
intrinsic used by the SSV/MSV filters): identical results.

The `uint8_t` conversion is a latent bug on any non-x86 target; it is worth reporting upstream.

## Build

```sh
./build.sh                # needs uv, git, curl and about 2 GB of disk
npm install
node test/run-tests.mjs dist/*.whl
```

`build.sh` pins every version (Pyodide cross-build environment, Emscripten, `pyodide-build`,
`wheel`), checks the SHA-256 of the pyhmmer sdist, applies the patch, builds with static libraries,
retags the wheel for Pyodide 0.27's micropip, and adds the HMMER and Easel licenses to it.

## Licenses

The scripts, tests and patch in this repository are MIT-licensed ([LICENSE](LICENSE)). The wheel
contains pyhmmer (MIT, Martin Larralde), HMMER and Easel (BSD 3-Clause, Sean R. Eddy and the
President and Fellows of Harvard College); all three license texts are shipped inside the wheel and
kept in [`LICENSES/`](LICENSES).

If you use the wheel, please cite pyhmmer (Larralde & Zeller 2023, *Bioinformatics* 39:btad214) and
HMMER.

Maintained by LaBiOmicS, Universidade de Mogi das Cruzes (UMC), Brazil.
