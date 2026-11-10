#!/usr/bin/env bash
# Build a pyhmmer wheel for Pyodide from the PyPI sdist and the patch in patches/.
#
# Needs: uv, git, curl, ~2 GB of disk. Pyodide 0.27.8 = Python 3.12 + Emscripten 3.1.58.
# Output: dist/ (or $DIST)/pyhmmer-0.12.3-cp312-abi3-pyodide_2024_0_wasm32.whl
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/_build}
DIST=${DIST:-$HERE/dist}
PYODIDE=0.27.8
EMSDK_VERSION=3.1.58
PYHMMER=0.12.3
PYHMMER_SDIST_SHA256=0a4b2f5d8c6c106fce8eb77603387aff94ad8ff8ff1c8094f30fb18cb7694d6e

mkdir -p "$WORK" && cd "$WORK"
[ -d .venv ] || uv venv -q -p 3.12 .venv
. .venv/bin/activate
uv pip install -q "pyodide-build==0.39.3" "wheel==0.48.0"
pyodide xbuildenv install "$PYODIDE"
[ -d emsdk ] || git clone -q --depth 1 https://github.com/emscripten-core/emsdk.git
./emsdk/emsdk install "$EMSDK_VERSION" >/dev/null && ./emsdk/emsdk activate "$EMSDK_VERSION" >/dev/null
source emsdk/emsdk_env.sh >/dev/null 2>&1

URL=$(curl -s "https://pypi.org/pypi/pyhmmer/$PYHMMER/json" | python -c "import sys,json;print([u['url'] for u in json.load(sys.stdin)['urls'] if u['packagetype']=='sdist'][0])")
curl -sL -o "pyhmmer-$PYHMMER.tar.gz" "$URL"
echo "$PYHMMER_SDIST_SHA256  pyhmmer-$PYHMMER.tar.gz" | sha256sum -c -
rm -rf "pyhmmer-$PYHMMER" && tar xzf "pyhmmer-$PYHMMER.tar.gz"
(cd "pyhmmer-$PYHMMER" && patch -p2 < "$HERE/patches/pyhmmer-$PYHMMER-pyodide.patch")

mkdir -p "$DIST" && rm -f "$DIST"/*.whl
(cd "pyhmmer-$PYHMMER" && BUILD_SHARED_LIBS=false pyodide build -o "$DIST" .)
# pyodide-build >= 0.30 tags wheels pyemscripten_2024_0; micropip in Pyodide 0.27 expects pyodide_2024_0 (same ABI)
(cd "$DIST" && python -m wheel tags --remove --platform-tag pyodide_2024_0_wasm32 ./*.whl)
# Ship the HMMER and Easel licenses (BSD 3-Clause) inside the wheel, next to pyhmmer's
(
  cd "$DIST" && WHL=$(ls ./*.whl) && rm -rf _unpacked && python -m wheel unpack -d _unpacked "$WHL"
  LIC=$(ls -d _unpacked/*/*.dist-info)/licenses && mkdir -p "$LIC"
  cp "$WORK/pyhmmer-$PYHMMER/vendor/hmmer/LICENSE" "$LIC/HMMER-LICENSE"
  cp "$WORK/pyhmmer-$PYHMMER/vendor/easel/LICENSE" "$LIC/Easel-LICENSE"
  rm "$WHL" && python -m wheel pack -d . _unpacked/* && rm -rf _unpacked
)
ls -l "$DIST"
