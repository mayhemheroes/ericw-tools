#!/usr/bin/env bash
#
# ericw-tools/mayhem/build.sh — build the Quake BSP loader fuzz target plus ericw-tools' own
# GoogleTest suite for mayhem/test.sh.
#
# Fuzz surface = parsing an attacker .bsp file. The fork's original Mayhem target was the
# file-input `bspinfo @@` binary; here we build an in-process libFuzzer harness around the same
# LoadBSPFile() parse path (target name preserved: `bspinfo`) plus a standalone reproducer.
#
# Build contract comes from the org base ENV: CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/SRC/
# STANDALONE_FUZZ_MAIN. We compile the ericw-tools `common` library ITSELF with $SANITIZER_FLAGS
# so the BSP-parsing code (not just the harness) is instrumented.
#
# embree + TBB are apt-installed in the Dockerfile: the top-level CMakeLists does
# find_package(embree 4 REQUIRED) / find_package(TBB REQUIRED), so configure needs both present
# even though `bspinfo`/`common` only link TBB (embree is the light/lightpreview raytracer dep).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

# ── 1) Sanitized build of the `common` BSP library (+ its 3rdparty static deps) ─────────────────
# Disable the heavy/irrelevant pieces for the fuzz build: tests, docs, and the lightpreview GUI
# tool. embree is still REQUIRED by configure (top-level find_package), so it must be installed —
# but with lightpreview off and only the `common` static lib + its deps built, we never link it.
# IPO/LTO off so we can link the .a's directly against the harness with clang.
cmake -S "$SRC" -B "$SRC/build" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DDISABLE_TESTS=ON \
      -DDISABLE_DOCS=ON \
      -DENABLE_LIGHTPREVIEW=OFF \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
# pareto is header-only on this version (no buildable target); common/fmt/jsoncpp are the .a's.
cmake --build "$SRC/build" -j"$MAYHEM_JOBS" --target common fmt jsoncpp_static

# Collect the static libs CMake produced (common + its transitive 3rdparty .a's). pareto is
# header-only on this version (no .a); harmless if the glob misses it.
mapfile -t LIBS < <(find "$SRC/build" -name 'libcommon.a' -o -name 'libfmt*.a' -o -name 'libjsoncpp*.a' -o -name 'libpareto*.a' | sort -u)
[ "${#LIBS[@]}" -ge 1 ] || { echo "ERROR: no static libs found under $SRC/build" >&2; find "$SRC/build" -name '*.a' >&2; exit 1; }
echo "linking harness against: ${LIBS[*]}"

HARNESS_INCLUDES=(-I "$SRC/include" -I "$SRC/3rdparty/fmt/include" -I "$SRC/3rdparty/jsoncpp/include" -I "$SRC/build")
SYS_LIBS=(-ltbb -ltbbmalloc -lpthread)
# ericw-tools hard-sets CMAKE_INTERPROCEDURAL_OPTIMIZATION ON in CMakeLists (overriding our cache
# var), so the static libs hold LLVM bitcode, not native objects. Link with lld (+ LTO) so the
# clang driver feeds those bitcode archives through the LTO plugin instead of /usr/bin/ld (bfd),
# which can't read them ("file format not recognized").
# --allow-multiple-definition: mayhem/fuzz_assert_override.cc re-defines logging::assert_ to throw
# (catchable by the harness) instead of upstream's exit(1) (which escapes the catch and libFuzzer
# flags as a crash). Linked ahead of libcommon.a, so with this flag lld keeps our definition. This
# is purely additive (overlay file + flag) — no upstream source is edited.
LINK_FLAGS=(-fuse-ld=lld -flto -Wl,--allow-multiple-definition)

# Compile the assert override as a NATIVE object (no -flto), so its strong logging::assert_ cleanly
# prevails over the bitcode libcommon.a copy at link time (with --allow-multiple-definition).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++20 "${HARNESS_INCLUDES[@]}" \
    -c "$SRC/mayhem/fuzz_assert_override.cc" -o /tmp/fuzz_assert_override.o

# Compile the ASan options override (detect_leaks=0): LSan tries to fork+ptrace the target, but
# Mayhem's coverage collection already holds a ptrace on the process, so LSan fails with
# "ptrace(PTRACE_ATTACH) failed" and the target aborts → 0 edges.  A strong
# __asan_default_options here disables LSan at runtime without removing any other ASan checks.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    -c "$SRC/mayhem/asan_options.c" -o /tmp/asan_options.o

# ── 2) libFuzzer target -> /mayhem/bspinfo (the preserved Mayhem target name) ────────────────────
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++20 \
    "${HARNESS_INCLUDES[@]}" \
    "$SRC/mayhem/fuzz_bspinfo.cc" /tmp/fuzz_assert_override.o /tmp/asan_options.o \
    $LIB_FUZZING_ENGINE "${LIBS[@]}" "${SYS_LIBS[@]}" "${LINK_FLAGS[@]}" \
    -o /mayhem/bspinfo_fuzzer

# ── 3) Standalone (non-fuzzer) reproducer -> /mayhem/bspinfo-standalone ──────────────────────────
# Compile the run-once driver as a C object so its extern "C" LLVMFuzzerTestOneInput ref isn't
# mangled by clang++ at link.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++20 \
    "${HARNESS_INCLUDES[@]}" \
    "$SRC/mayhem/fuzz_bspinfo.cc" /tmp/fuzz_assert_override.o /tmp/asan_options.o /tmp/standalone_main.o "${LIBS[@]}" "${SYS_LIBS[@]}" "${LINK_FLAGS[@]}" \
    -o /mayhem/bspinfo_fuzzer-standalone

# ── 4) ericw-tools' OWN GoogleTest suite, NORMAL flags (clean tree) so test.sh only RUNS it ──────
# This build enables tests + links liblight, so embree IS linked here — that's fine, it's apt-
# installed. googletest is fetched via FetchContent (needs git + network at build time).
env -u CFLAGS -u CXXFLAGS \
cmake -S "$SRC" -B "$SRC/build-tests" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DDISABLE_TESTS=OFF \
      -DDISABLE_DOCS=ON \
      -DENABLE_LIGHTPREVIEW=OFF \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"
cmake --build "$SRC/build-tests" -j"$MAYHEM_JOBS" --target tests

echo "build.sh complete:"
ls -la /mayhem/bspinfo_fuzzer /mayhem/bspinfo_fuzzer-standalone "$SRC"/build-tests/tests/tests 2>&1 || true
