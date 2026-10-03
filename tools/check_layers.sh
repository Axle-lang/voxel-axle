#!/usr/bin/env bash
# check_layers.sh — the dependency rules docs/ARCHITECTURE.md states, enforced.
#
# A rule about which file may import which is worth nothing as prose: the
# import that breaks it compiles, runs, and is only noticed when a second
# backend cannot be written without undoing it. Three rules, each one a way
# the render seam can be broken by accident:
#
#   1. The engine never imports the game, the app or the checks. Content
#      reaches it through injection seams declared next to their consumer.
#   2. A backend (engine/render/cpu, engine/render/gpu) reads the game only
#      through the frame it is handed and the world's read-only seams. It
#      never imports a creature, the world's manager, its light or block sim,
#      nor the frame BUILDER: what a frame shows is decided once, before any
#      backend sees it, and a backend that reached past the frame would be a
#      second place deciding it.
#   3. Nothing in the engine but a backend names a backend, and no backend
#      names the other: neutral code is what both of them share.
#
# `--selftest` plants each violation in a scratch copy and fails if the check
# passes on it: a gate nobody has watched reject something may be looking for
# nothing.
#
# Usage:  tools/check_layers.sh [<repo-root>]
#         tools/check_layers.sh --selftest

set -uo pipefail

note() { printf '%s\n' "$*" >&2; }

# The `use` lines of the files under a directory that match a path pattern,
# as file:line:text. Only the line a `use` starts on carries its path.
uses_matching() {
    local dir=$1 pattern=$2
    [ -d "$dir" ] || return 0
    find "$dir" -name '*.axle' -print0 \
        | xargs -0 grep -nE "^use crate::($pattern)" 2>/dev/null
}

# Rule 1 — the engine imports none of the layers above it.
check_engine_below_game() {
    local root=$1 hits
    hits=$(uses_matching "$root/src/engine" 'game|app|checks')
    if [ -n "$hits" ]; then
        note "FAIL: the engine imports the game, the app or the checks:"
        note "$hits"
        return 1
    fi
    return 0
}

# Rule 2 — a backend reads the game only through its frame and the world's seams.
check_backend_reads_frame() {
    local root=$1 rc=0 dir hits
    local forbidden='engine::entity|engine::world::(chunks|light|sim)|engine::render::frame::framebuilder'
    for dir in "$root/src/engine/render/cpu" "$root/src/engine/render/gpu"; do
        hits=$(uses_matching "$dir" "$forbidden")
        if [ -n "$hits" ]; then
            note "FAIL: a backend reaches past its frame into the game:"
            note "$hits"
            rc=1
        fi
    done
    return $rc
}

# Rule 3 — only a backend names a backend, and never the other one.
check_backends_apart() {
    local root=$1 rc=0 hits
    hits=$(find "$root/src/engine" -name '*.axle' \
               -not -path '*/render/cpu/*' -not -path '*/render/gpu/*' -print0 \
           | xargs -0 grep -nE '^use crate::engine::render::(cpu|gpu)' 2>/dev/null)
    if [ -n "$hits" ]; then
        note "FAIL: neutral engine code names a backend:"
        note "$hits"
        rc=1
    fi

    hits=$(uses_matching "$root/src/engine/render/cpu" 'engine::render::gpu')
    hits+=$(uses_matching "$root/src/engine/render/gpu" 'engine::render::cpu')
    if [ -n "$hits" ]; then
        note "FAIL: one backend names the other:"
        note "$hits"
        rc=1
    fi
    return $rc
}

run_checks() {
    local root=$1 rc=0
    check_engine_below_game "$root"   || rc=1
    check_backend_reads_frame "$root" || rc=1
    check_backends_apart "$root"      || rc=1
    return $rc
}

# Scratch tree the selftest plants its violations in. File-scope, because the
# EXIT trap that removes it runs after the function has returned.
SELFTEST_DIR=""

cleanup_selftest() {
    if [ -n "$SELFTEST_DIR" ]; then
        rm -rf "$SELFTEST_DIR"
    fi
}

# Plant one line at the top of a file in a fresh copy of the tree and require
# the check to reject it.
#   $1 the scratch root   $2 the source root   $3 the file   $4 the line   $5 the rule
expect_rejected() {
    local tmp=$1 root=$2 file=$3 line=$4 what=$5
    rm -rf "$tmp/src"
    cp -r "$root/src" "$tmp/src"
    mkdir -p "$(dirname "$tmp/$file")"
    { printf '%s\n' "$line"; cat "$tmp/$file" 2>/dev/null; } > "$tmp/$file.new"
    mv "$tmp/$file.new" "$tmp/$file"
    if run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: $what"
        return 1
    fi
    return 0
}

selftest() {
    local root=$1 rc=0 tmp
    SELFTEST_DIR=$(mktemp -d)
    tmp="$SELFTEST_DIR"
    trap cleanup_selftest EXIT

    cp -r "$root/src" "$tmp/src"
    if ! run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: the unmodified tree must pass"
        rc=1
    fi

    expect_rejected "$tmp" "$root" src/engine/world/ring.axle \
        'use crate::game::world::terraingen::TerrainGen;' \
        'rule 1 accepted the engine importing the game' || rc=1
    expect_rejected "$tmp" "$root" src/engine/render/cpu/renderer.axle \
        'use crate::engine::world::chunks::ChunkManager;' \
        'rule 2 accepted a backend importing the world manager' || rc=1
    expect_rejected "$tmp" "$root" src/engine/render/cpu/renderer.axle \
        'use crate::engine::entity::mobs::MobManager;' \
        'rule 2 accepted a backend importing the creatures' || rc=1
    expect_rejected "$tmp" "$root" src/engine/render/gpu/gpubackend.axle \
        'use crate::engine::render::frame::framebuilder::{ FrameBuilder };' \
        'rule 2 accepted a backend importing the frame builder' || rc=1
    expect_rejected "$tmp" "$root" src/engine/sky/atmosphere.axle \
        'use crate::engine::render::cpu::sky::fogtables::{ FogTable };' \
        'rule 3 accepted neutral code naming a backend' || rc=1
    expect_rejected "$tmp" "$root" src/engine/render/gpu/gpubackend.axle \
        'use crate::engine::render::cpu::renderer::Renderer;' \
        'rule 3 accepted one backend naming the other' || rc=1

    if [ $rc -eq 0 ]; then
        echo "check_layers selftest OK — every rule rejects what it is for"
    fi
    return $rc
}

main() {
    if [ "${1:-}" = "--selftest" ]; then
        selftest "$(cd "$(dirname "$0")/.." && pwd)"
        exit $?
    fi
    local root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
    if run_checks "$root"; then
        echo "check_layers OK — the engine stays below the game, and every backend behind its frame"
        exit 0
    fi
    exit 1
}

main "$@"
