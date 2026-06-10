/*  ericw-tools/mayhem/fuzz_assert_override.cc — additive fuzz-build override of the assert handler.
 *
 *  Upstream's logging::assert_ (common/log.cc) calls exit(1) when a Q_assert fails. The BSP reader
 *  uses Q_assert pervasively for malformed-input validation (e.g. lump_reader::read), so on adversarial
 *  input it exit()s — and exit() escapes the harness's try/catch, so libFuzzer records it as a crash
 *  ("libfuzzer fuzz target exited") instead of a malformed-input rejection.
 *
 *  This TU re-defines logging::assert_ to THROW a std::exception (which the harness already catches
 *  and discards as "not a finding"). It is linked AHEAD of libcommon.a with
 *  -Wl,--allow-multiple-definition, so this definition wins and the upstream exit(1) copy is ignored.
 *
 *  Purely additive: a new file in the mayhem/ overlay + a linker flag in mayhem/build.sh. No upstream
 *  source (common/log.cc, etc.) is modified — the all-additive integration invariant is preserved.
 *
 *  We intentionally do NOT print on failure: the harness discards the throw, logging is already
 *  silenced via preinitialize(), and printing would spam on essentially every fuzz input.
 */
#include <common/log.hh>

#include <stdexcept>

namespace logging {

void assert_(bool success, const char * /*expr*/, const char * /*file*/, int /*line*/)
{
    if (!success) {
        throw std::runtime_error("Q_assert failed (fuzz override)");
    }
}

} // namespace logging
