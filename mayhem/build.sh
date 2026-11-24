#!/usr/bin/env bash
#
# mayhem/build.sh — build the rpcsx fuzz targets and the functional-test drivers.
#
# rpcsx's full CMake build (-DWITH_PS3=ON) needs ~38 submodules (LLVM, FFmpeg, opencv, ...)
# that the fork does not carry. The targets here only need the rpcs3 util layer (File, StrFmt,
# logs, mutex, atomic, cond), the rx object library and the parser under test (+ Crypto for PUP), so this script
# compiles exactly those translation units from the tree, against apt's libfmt-dev,
# nlohmann-json3-dev and zlib1g-dev. The one piece that cannot be compiled stand-alone is
# rpcs3/util/Thread.cpp (it includes the PPU/SPU emulator core); mayhem/harnesses/thread_stubs.cpp
# provides its five functions the util layer calls.
#
# Outputs (all under mayhem/out/, gitignored by mayhem/.gitignore):
#   bin/fuzz_psf, bin/fuzz_iso, bin/fuzz_pup (+ -standalone)   libFuzzer, ASan+UBSan
#   bin/unself                                     AFL (afl-clang-fast++), ASan+UBSan
#   test/{psf,iso,pup}_dump, test/unself            normal flags, run by mayhem/test.sh
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT="$SRC/mayhem/out"
mkdir -p "$OUT/bin" "$OUT/test" "$OUT/obj-fuzz" "$OUT/obj-test"

INCLUDES=(-I"$SRC/rpcs3" -I"$SRC/rx/include" -I"$SRC/rx/include/rx")
CXXSTD=(-std=c++23 -DZLIB_CONST=1)  # ZLIB_CONST as upstream 3rdparty/zlib sets it
# Project sources the targets need (paths relative to $SRC).
LIB_SRCS=(
  rpcs3/Loader/PSF.cpp
  rpcs3/dev/iso.cpp
  rpcs3/Loader/PUP.cpp
  rpcs3/Crypto/sha1.cpp
  rpcs3/Crypto/sha256.cpp
  rpcs3/Crypto/aesni.cpp
  rpcs3/Crypto/aes.cpp
  rpcs3/Crypto/utils.cpp
  rpcs3/util/File.cpp
  rpcs3/util/StrFmt.cpp
  rpcs3/util/logs.cpp
  rpcs3/util/mutex.cpp
  rpcs3/util/atomic.cpp
  rpcs3/util/cond.cpp
  rx/src/debug.cpp
  rx/src/die.cpp
  rx/src/FileLock.cpp
  rx/src/hexdump.cpp
  rx/src/mem.cpp
  rx/src/SharedAtomic.cpp
  rx/src/SharedCV.cpp
  rx/src/SharedMutex.cpp
  mayhem/harnesses/thread_stubs.cpp
)
LIBS=(-lfmt -lz -lpthread)

# compile_all <objdir> <flags...> : compile LIB_SRCS in parallel into <objdir>, print the object list.
compile_all() {
  local objdir="$1"; shift
  printf '%s\n' "${LIB_SRCS[@]}" | xargs -P "$MAYHEM_JOBS" -I{} sh -c '
    o="$0/$(echo "{}" | tr / _).o"
    exec "$CXX" "$@" -c "'"$SRC"'/{}" -o "$o"' "$objdir" "${CXXSTD[@]}" "${INCLUDES[@]}" "$@"
  for s in "${LIB_SRCS[@]}"; do printf '%s ' "$objdir/$(echo "$s" | tr / _).o"; done
}

# 1) Sanitized project objects + libFuzzer harnesses (+ standalone reproducers).
FUZZ_FLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS -O1)
FUZZ_OBJS=$(compile_all "$OUT/obj-fuzz" "${FUZZ_FLAGS[@]}" -fsanitize=fuzzer-no-link)
"$CXX" "${FUZZ_FLAGS[@]}" -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/obj-fuzz/lsan_off.o"
"$CC" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/obj-fuzz/standalone_main.o"
for h in fuzz_psf fuzz_iso fuzz_pup; do
  "$CXX" "${CXXSTD[@]}" "${INCLUDES[@]}" "${FUZZ_FLAGS[@]}" -fsanitize=fuzzer-no-link \
    -c "$SRC/mayhem/harnesses/$h.cpp" -o "$OUT/obj-fuzz/$h.o"
  # shellcheck disable=SC2086
  "$CXX" "${FUZZ_FLAGS[@]}" $LIB_FUZZING_ENGINE "$OUT/obj-fuzz/$h.o" $FUZZ_OBJS \
    "$OUT/obj-fuzz/lsan_off.o" "${LIBS[@]}" -o "$OUT/bin/$h"
  # shellcheck disable=SC2086
  "$CXX" "${FUZZ_FLAGS[@]}" "$OUT/obj-fuzz/standalone_main.o" "$OUT/obj-fuzz/$h.o" $FUZZ_OBJS \
    "$OUT/obj-fuzz/lsan_off.o" "${LIBS[@]}" -o "$OUT/bin/$h-standalone"
done

# 2) unself (tools/unself/unself.cpp): the upstream CLI itself, AFL-instrumented + sanitized.
#    It is an AFL target, so the binary is its own reproducer (no -standalone).
afl-clang-fast++ "${CXXSTD[@]}" $SANITIZER_FLAGS $DEBUG_FLAGS -O1 \
  "$SRC/tools/unself/unself.cpp" "$SRC/mayhem/lsan_off.cc" -o "$OUT/bin/unself"

# 3) Functional-test drivers with the project's NORMAL flags (no sanitizers), for mayhem/test.sh.
TEST_FLAGS=(-O2 $COVERAGE_FLAGS)
TEST_OBJS=$(compile_all "$OUT/obj-test" "${TEST_FLAGS[@]}")
for t in psf_dump iso_dump pup_dump; do
  # shellcheck disable=SC2086
  "$CXX" "${CXXSTD[@]}" "${INCLUDES[@]}" "${TEST_FLAGS[@]}" "$SRC/mayhem/tests/$t.cpp" $TEST_OBJS \
    "${LIBS[@]}" -o "$OUT/test/$t"
done
"$CXX" "${CXXSTD[@]}" "${TEST_FLAGS[@]}" "$SRC/tools/unself/unself.cpp" -o "$OUT/test/unself"

ls -la "$OUT/bin" "$OUT/test"
