/*  ericw-tools/mayhem/fuzz_bspinfo.cc — libFuzzer harness for the Quake BSP loader.
 *
 *  Fuzz surface: an attacker-controlled .bsp file parsed by common's LoadBSPFile() — the
 *  same entry the `bspinfo` CLI tool drives (bspinfo/main.cc). The fork's original Mayhem
 *  target was the file-input `bspinfo @@` binary; this is the in-process libFuzzer port of
 *  that same parse path (target name preserved: `bspinfo`). LoadBSPFile takes a filesystem
 *  path, so each iteration materializes the input as a temp .bsp and loads it.
 *
 *  We exercise the loader and the BSP->generic format conversion (the bulk of the parsing /
 *  bounds logic) but stop short of the filesystem-init / texture-area math the CLI does after
 *  load, which need a populated game data tree we don't have under the fuzzer.
 */
#include <common/bspfile.hh>
#include <common/cmdlib.hh>
#include <common/log.hh>
#include "common/fs.hh"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <unistd.h>

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
    // Silence the tools' logging so the fuzzer isn't drowned in output.
    logging::preinitialize();
    return 0;
}

// Smallest structurally-meaningful BSP header (Quake 1 dheader_t): a 4-byte ident followed by
// 15 lump directory entries of 8 bytes each = 124 bytes. The loader reads a full header up front,
// so inputs below this can only ever trip a truncated-header read — a shallow artifact of the
// tool requiring a complete header, not the deep parsing logic we want to fuzz. Skipping them lets
// the fuzzer spend its budget exploring lump-offset / per-format decode paths instead.
static constexpr size_t kMinBspHeader = 4 + 15 * 8;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < kMinBspHeader) {
        return 0;
    }

    // LoadBSPFile reads from a path, so stage the fuzz bytes in a temp .bsp.
    // Use /dev/shm (shared memory, always writable) rather than /tmp: Mayhem runs the
    // target under docker --read-only during coverage collection, where /tmp is read-only
    // unless an explicit --tmpfs is mounted.  /dev/shm is a tmpfs that is always writable
    // in the container and is the canonical scratch space for read-only container targets.
    char tmpl[] = "/dev/shm/fuzz_bspinfo_XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) {
        return 0;
    }

    bool wrote = true;
    size_t off = 0;
    while (off < size) {
        ssize_t n = write(fd, data + off, size - off);
        if (n <= 0) {
            wrote = false;
            break;
        }
        off += static_cast<size_t>(n);
    }
    close(fd);

    if (wrote) {
        try {
            fs::path source = tmpl;
            bspdata_t bsp;
            LoadBSPFile(source, &bsp);
            // Convert to the generic in-memory format — exercises the per-format decoders
            // the same way bspinfo does before it prints.
            ConvertBSPFormat(&bsp, &bspver_generic);
        } catch (const std::exception &) {
            // ericw-tools signals malformed input by throwing; not a finding.
        } catch (...) {
        }
        fs::clear();
    }

    unlink(tmpl);
    return 0;
}
