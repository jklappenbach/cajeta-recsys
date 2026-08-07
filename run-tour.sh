#!/usr/bin/env bash
# Build the library .cja, compile the tour against it, run it.
# The tour is self-checking: non-zero exit means a demonstrated claim failed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
CAJETA="${CAJETA:-cajeta}"

# dev.cajeta.ml resolution: sibling checkout, else the archive run-tests.sh
# cached under build/.ml-cache (run the tests first on a bare runner).
ML_REPO="${ML_REPO:-$here/../cajeta-ml}"
ml_cja="${ML_CJA:-}"
if [[ -z "$ml_cja" && -d "$ML_REPO" ]]; then
    ( cd "$ML_REPO" && "$CAJETA" build >/dev/null )
    ml_cja="$(ls -t "$ML_REPO"/build/archive/dev.cajeta.ml-*.cja 2>/dev/null | head -1)"
fi
if [[ -z "$ml_cja" ]]; then
    ml_cja="$(ls -t "$here"/build/.ml-cache/dev.cajeta.ml-*.cja 2>/dev/null | head -1)"
fi
[[ -f "$ml_cja" ]] || { echo "could not resolve dev.cajeta.ml (run ./run-tests.sh first)" >&2; exit 1; }

TS_REPO="${TS_REPO:-$here/../cajeta-timeseries}"
ts_cja="${TS_CJA:-}"
if [[ -z "$ts_cja" && -d "$TS_REPO" ]]; then
    ( cd "$TS_REPO" && "$CAJETA" build >/dev/null )
    ts_cja="$(ls -t "$TS_REPO"/build/archive/dev.cajeta.timeseries-*.cja 2>/dev/null | head -1)"
fi
if [[ -z "$ts_cja" ]]; then
    ts_cja="$(ls -t "$here"/build/.ts-cache/dev.cajeta.timeseries-*.cja 2>/dev/null | head -1)"
fi
[[ -f "$ts_cja" ]] || { echo "could not resolve dev.cajeta.timeseries (run ./run-tests.sh first)" >&2; exit 1; }

DOCS_REPO="${DOCS_REPO:-$here/../cajeta-docs}"
docs_cja="${DOCS_CJA:-}"
if [[ -z "$docs_cja" && -d "$DOCS_REPO" ]]; then
    ( cd "$DOCS_REPO" && "$CAJETA" build >/dev/null )
    docs_cja="$(ls -t "$DOCS_REPO"/build/archive/dev.cajeta.docs-*.cja 2>/dev/null | head -1)"
fi
if [[ -z "$docs_cja" ]]; then
    docs_cja="$(ls -t "$here"/build/.docs-cache/dev.cajeta.docs-*.cja 2>/dev/null | head -1)"
fi
[[ -f "$docs_cja" ]] || { echo "could not resolve dev.cajeta.docs (run ./run-tests.sh first)" >&2; exit 1; }

echo ">> building dev.cajeta.recsys"
"$CAJETA" build >/dev/null
art="$(ls -t "$here"/build/archive/dev.cajeta.recsys-*.cja | head -1)"

echo ">> compiling the tour"
mkdir -p build/tour
"$CAJETA" --emit=exe --classpath="$art,$ml_cja,$ts_cja,$docs_cja" \
    -o build/tour/rs-tour \
    dev.cajeta.recsys.tour.Tour.main "$here/tour/src" build/tour >/dev/null

echo ">> running"
exec ./build/tour/rs-tour
