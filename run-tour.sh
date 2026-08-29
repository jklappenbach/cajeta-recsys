#!/usr/bin/env bash
# Build the library .cja, compile the tour against it, run it.
# The tour is self-checking: non-zero exit means a demonstrated claim failed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
CAJETA="${CAJETA:-cajeta}"


# --- artifact discovery -------------------------------------------------
# Where a checkout's .cja is. Prefers `cajeta artifact-path`, which reads
# that project's OWN manifest -- so a project that moves its artifacts with
# settings.output is followed rather than guessed, and the version comes
# from details.version instead of whichever file happens to be newest.
#
# Falls back to the historical build/archive glob only when the toolchain
# does not HAVE the verb (it lands after 0.24.0), so this keeps working on
# an older cajeta and starts using the verb as soon as a newer one is on
# PATH -- no flag day.
#
# The gate is the CAPABILITY, not the outcome. A fallback keyed on "the
# verb failed" would silently mask a verb that ran and answered wrongly,
# which is the very failure this replaces; keyed on "the verb is absent",
# it cannot. An empty result still means "not in this checkout", exactly
# as the glob did, so callers' registry fallbacks are unchanged.
cajeta_artifact_path() {
    local dir="$1" name="$2"
    local cj="${CAJETA:-${CAJETA_BIN:-cajeta}}"
    if [[ -z "${_cajeta_has_ap:-}" ]]; then
        if "$cj" artifact-path --help 2>/dev/null \
                | grep -q 'artifact-path \[options\]'; then
            _cajeta_has_ap=yes
        else
            _cajeta_has_ap=no
        fi
    fi
    if [[ "$_cajeta_has_ap" == yes ]]; then
        # Only report a path that EXISTS. The verb answers where the
        # artifact would be even when nothing has built it, but the glob
        # this replaces returned empty in that case, and every caller
        # reads empty as "not in this checkout" and falls back to the
        # registry. Handing back a path to a missing file instead would
        # turn that into a confusing compile failure.
        local p
        p=$( cd "$dir" 2>/dev/null && "$cj" artifact-path 2>/dev/null ) || return 0
        [[ -n "$p" && -f "$p" ]] && printf '%s\n' "$p"
        return 0
    else
        ls -t "$dir"/build/archive/"$name"-*.cja 2>/dev/null | head -1
    fi
}

# dev.cajeta.ml resolution: sibling checkout, else the archive run-tests.sh
# cached under build/.ml-cache (run the tests first on a bare runner).
ML_REPO="${ML_REPO:-$here/../cajeta-ml}"
ml_cja="${ML_CJA:-}"
if [[ -z "$ml_cja" && -d "$ML_REPO" ]]; then
    ( cd "$ML_REPO" && "$CAJETA" build >/dev/null )
    ml_cja="$(cajeta_artifact_path "$ML_REPO" dev.cajeta.ml 2>/dev/null)"
fi
if [[ -z "$ml_cja" ]]; then
    ml_cja="$(ls -t "$here"/build/.ml-cache/dev.cajeta.ml-*.cja 2>/dev/null | head -1)"
fi
[[ -f "$ml_cja" ]] || { echo "could not resolve dev.cajeta.ml (run ./run-tests.sh first)" >&2; exit 1; }

TS_REPO="${TS_REPO:-$here/../cajeta-timeseries}"
ts_cja="${TS_CJA:-}"
if [[ -z "$ts_cja" && -d "$TS_REPO" ]]; then
    ( cd "$TS_REPO" && "$CAJETA" build >/dev/null )
    ts_cja="$(cajeta_artifact_path "$TS_REPO" dev.cajeta.timeseries 2>/dev/null)"
fi
if [[ -z "$ts_cja" ]]; then
    ts_cja="$(ls -t "$here"/build/.ts-cache/dev.cajeta.timeseries-*.cja 2>/dev/null | head -1)"
fi
[[ -f "$ts_cja" ]] || { echo "could not resolve dev.cajeta.timeseries (run ./run-tests.sh first)" >&2; exit 1; }

DOCS_REPO="${DOCS_REPO:-$here/../cajeta-docs}"
docs_cja="${DOCS_CJA:-}"
if [[ -z "$docs_cja" && -d "$DOCS_REPO" ]]; then
    ( cd "$DOCS_REPO" && "$CAJETA" build >/dev/null )
    docs_cja="$(cajeta_artifact_path "$DOCS_REPO" dev.cajeta.docs 2>/dev/null)"
fi
if [[ -z "$docs_cja" ]]; then
    docs_cja="$(ls -t "$here"/build/.docs-cache/dev.cajeta.docs-*.cja 2>/dev/null | head -1)"
fi
[[ -f "$docs_cja" ]] || { echo "could not resolve dev.cajeta.docs (run ./run-tests.sh first)" >&2; exit 1; }

echo ">> building dev.cajeta.recsys"
"$CAJETA" build >/dev/null
art="$(cajeta_artifact_path "$here" dev.cajeta.recsys)"

echo ">> compiling the tour"
mkdir -p build/tour
"$CAJETA" --emit=exe --classpath="$art,$ml_cja,$ts_cja,$docs_cja" \
    -o build/tour/rs-tour \
    dev.cajeta.recsys.tour.Tour.main "$here/tour/src" build/tour >/dev/null

echo ">> running"
exec ./build/tour/rs-tour
