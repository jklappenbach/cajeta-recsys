#!/usr/bin/env bash
# Build + run the cajeta-recsys unit tests.
#
# The suite lives under src/test/cajeta and is driven by cajeta-unit's reflective
# @Test discovery (dev.cajeta.unit.Runner). It compiles ONLY the test sources into
# an executable, with the recsys library, dev.cajeta.ml, dev.cajeta.timeseries, and cajeta-unit
# supplied as .cja classpath dependencies — the compiler links their bitcode
# into the test binary.
#
# Override paths via env:
#   CAJETA    — compiler binary (default: cajeta on PATH)
#   UNIT_REPO — path to the cajeta-unit checkout (default: ../cajeta-unit)
#   ML_REPO   — path to the cajeta-ml checkout   (default: ../cajeta-ml)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
CAJETA="${CAJETA:-cajeta}"
UNIT_REPO="${UNIT_REPO:-$here/../cajeta-unit}"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# cajeta-unit resolution (the cajeta-logging pattern), in order:
#   1. $UNIT_CJA        — explicit archive path, used verbatim
#   2. $UNIT_REPO       — sibling checkout when it exists: build it and use
#                         whatever version it emits (local dev, unit HEAD)
#   3. $OLLA_HOME store — an installed dev.cajeta.unit at the version pinned
#                         in cajeta.json's dev-dependencies
#   4. Olla registry    — /v2/resolve + /v2/blob (the toolchain's own fetch
#                         protocol), sha256-verified, cached under build/.
#                         The CI flow: bare runners have no checkout.
OLLA_HOME="${OLLA_HOME:-$HOME/.olla}"
OLLA_URL="${OLLA_URL:-https://olla.cajeta.dev}"
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1;
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
unit_cja="${UNIT_CJA:-}"
if [[ -z "$unit_cja" && -d "$UNIT_REPO" ]]; then
    echo ">> building cajeta-unit from checkout ($UNIT_REPO)"
    ( cd "$UNIT_REPO" && "$CAJETA" build >/dev/null )
    unit_cja="$(ls -t "$UNIT_REPO"/build/archive/dev.cajeta.unit-*.cja 2>/dev/null | head -1)"
fi
if [[ -z "$unit_cja" ]]; then
    UNIT_VER="$(sed -n 's/.*"dev\.cajeta\.unit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$here/cajeta.json" | head -1)"
    [[ -n "$UNIT_VER" ]] || { echo "no dev.cajeta.unit pin in cajeta.json" >&2; exit 1; }
    store_cja="$OLLA_HOME/dev.cajeta.unit/$UNIT_VER/dev.cajeta.unit-$UNIT_VER.cja"
    cache_cja="$here/build/.unit-cache/dev.cajeta.unit-$UNIT_VER.cja"
    if [[ -f "$store_cja" ]]; then unit_cja="$store_cja"
    elif [[ -f "$cache_cja" ]]; then unit_cja="$cache_cja"
    else
        echo ">> fetching dev.cajeta.unit $UNIT_VER from $OLLA_URL"
        meta="$(curl -fsS "$OLLA_URL/v2/resolve?name=dev.cajeta.unit&version=$UNIT_VER")"
        sha="$(printf '%s' "$meta" | sed -n 's/.*"sha256":"sha256:\([0-9a-f]*\)".*/\1/p')"
        [[ -n "$sha" ]] || { echo "/v2/resolve gave no sha256" >&2; exit 1; }
        mkdir -p "$(dirname "$cache_cja")"
        curl -fsS -o "$cache_cja" "$OLLA_URL/v2/blob/$sha"
        got="$(sha256_of "$cache_cja")"
        [[ "$got" == "$sha" ]] || { rm -f "$cache_cja"; echo "sha256 mismatch fetching unit" >&2; exit 1; }
        unit_cja="$cache_cja"
    fi
fi
[[ -f "$unit_cja" ]] || { echo "could not resolve a dev.cajeta.unit archive" >&2; exit 1; }
echo ">> cajeta-unit: $unit_cja"

# dev.cajeta.ml resolution — same ladder as cajeta-unit. The library proper
# depends on it (Metrics for forecast scoring, settings.dependencies), so it
# is threaded through BOTH the library and the test classpaths:
#   1. $ML_CJA      — explicit archive path, used verbatim
#   2. $ML_REPO     — sibling checkout (default ../cajeta-ml): build and use it
#   3. $OLLA_HOME   — installed dev.cajeta.ml at the cajeta.json pin
#   4. Olla registry — sha256-verified fetch, cached under build/.ml-cache
ML_REPO="${ML_REPO:-$here/../cajeta-ml}"
ml_cja="${ML_CJA:-}"
if [[ -z "$ml_cja" && -d "$ML_REPO" ]]; then
    echo ">> building cajeta-ml from checkout ($ML_REPO)"
    ( cd "$ML_REPO" && "$CAJETA" build >/dev/null )
    ml_cja="$(ls -t "$ML_REPO"/build/archive/dev.cajeta.ml-*.cja 2>/dev/null | head -1)"
fi
if [[ -z "$ml_cja" ]]; then
    ML_VER="$(sed -n 's/.*"dev\.cajeta\.ml"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$here/cajeta.json" | head -1)"
    [[ -n "$ML_VER" ]] || { echo "no dev.cajeta.ml pin in cajeta.json" >&2; exit 1; }
    store_ml="$OLLA_HOME/dev.cajeta.ml/$ML_VER/dev.cajeta.ml-$ML_VER.cja"
    cache_ml="$here/build/.ml-cache/dev.cajeta.ml-$ML_VER.cja"
    if [[ -f "$store_ml" ]]; then ml_cja="$store_ml"
    elif [[ -f "$cache_ml" ]]; then ml_cja="$cache_ml"
    else
        echo ">> fetching dev.cajeta.ml $ML_VER from $OLLA_URL"
        meta="$(curl -fsS "$OLLA_URL/v2/resolve?name=dev.cajeta.ml&version=$ML_VER")"
        sha="$(printf '%s' "$meta" | sed -n 's/.*"sha256":"sha256:\([0-9a-f]*\)".*/\1/p')"
        [[ -n "$sha" ]] || { echo "/v2/resolve gave no sha256" >&2; exit 1; }
        mkdir -p "$(dirname "$cache_ml")"
        curl -fsS -o "$cache_ml" "$OLLA_URL/v2/blob/$sha"
        got="$(sha256_of "$cache_ml")"
        [[ "$got" == "$sha" ]] || { rm -f "$cache_ml"; echo "sha256 mismatch fetching ml" >&2; exit 1; }
        ml_cja="$cache_ml"
    fi
fi
[[ -f "$ml_cja" ]] || { echo "could not resolve a dev.cajeta.ml archive" >&2; exit 1; }
echo ">> cajeta-ml: $ml_cja"

# dev.cajeta.timeseries resolution — same ladder again (mSSA consumes its
# trajectory transform, settings.dependencies):
#   1. $TS_CJA      — explicit archive path, used verbatim
#   2. $TS_REPO     — sibling checkout (default ../cajeta-timeseries)
#   3. $OLLA_HOME   — installed dev.cajeta.timeseries at the cajeta.json pin
#   4. Olla registry — sha256-verified fetch, cached under build/.ts-cache
TS_REPO="${TS_REPO:-$here/../cajeta-timeseries}"
ts_cja="${TS_CJA:-}"
if [[ -z "$ts_cja" && -d "$TS_REPO" ]]; then
    echo ">> building cajeta-timeseries from checkout ($TS_REPO)"
    ( cd "$TS_REPO" && "$CAJETA" build >/dev/null )
    ts_cja="$(ls -t "$TS_REPO"/build/archive/dev.cajeta.timeseries-*.cja 2>/dev/null | head -1)"
fi
if [[ -z "$ts_cja" ]]; then
    TS_VER="$(sed -n 's/.*"dev\.cajeta\.timeseries"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$here/cajeta.json" | head -1)"
    [[ -n "$TS_VER" ]] || { echo "no dev.cajeta.timeseries pin in cajeta.json" >&2; exit 1; }
    store_ts="$OLLA_HOME/dev.cajeta.timeseries/$TS_VER/dev.cajeta.timeseries-$TS_VER.cja"
    cache_ts="$here/build/.ts-cache/dev.cajeta.timeseries-$TS_VER.cja"
    if [[ -f "$store_ts" ]]; then ts_cja="$store_ts"
    elif [[ -f "$cache_ts" ]]; then ts_cja="$cache_ts"
    else
        echo ">> fetching dev.cajeta.timeseries $TS_VER from $OLLA_URL"
        meta="$(curl -fsS "$OLLA_URL/v2/resolve?name=dev.cajeta.timeseries&version=$TS_VER")"
        sha="$(printf '%s' "$meta" | sed -n 's/.*"sha256":"sha256:\([0-9a-f]*\)".*/\1/p')"
        [[ -n "$sha" ]] || { echo "/v2/resolve gave no sha256" >&2; exit 1; }
        mkdir -p "$(dirname "$cache_ts")"
        curl -fsS -o "$cache_ts" "$OLLA_URL/v2/blob/$sha"
        got="$(sha256_of "$cache_ts")"
        [[ "$got" == "$sha" ]] || { rm -f "$cache_ts"; echo "sha256 mismatch fetching ml" >&2; exit 1; }
        ts_cja="$cache_ts"
    fi
fi
[[ -f "$ts_cja" ]] || { echo "could not resolve a dev.cajeta.timeseries archive" >&2; exit 1; }
echo ">> cajeta-timeseries: $ts_cja"


echo ">> building recsys library .cja"
"$CAJETA" --emit=cja -o "$out/recsys.cja" \
    --classpath="$ml_cja,$ts_cja" \
    dev.cajeta.recsys.Recsys.run "$here/src/main/cajeta" "$out" >/dev/null

echo ">> building + running the test binary"
"$CAJETA" --emit=exe --profile=test \
    --classpath="$out/recsys.cja,$unit_cja,$ml_cja,$ts_cja" \
    -o "$out/rstests" \
    dev.cajeta.recsys.selftest.TestMain.run "$here/src/test/cajeta" "$out" >/dev/null

# Parity tests load Surprise-1.1.5/sklearn-1.9.0-pinned golden fixtures
# from tools/fixtures via this env var (committed .npy, gen_recsys.py).
export RS_FIXTURES="$here/tools/fixtures"
"$out/rstests"
