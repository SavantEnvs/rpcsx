// Stand-ins for the five thread_ctrl/thread_base entry points the rpcs3 util layer
// (File.cpp, logs.cpp, mutex.cpp, atomic.cpp) calls. Their real definitions live in
// rpcs3/util/Thread.cpp, which includes the PPU/SPU emulator core (Emu/Cell/PPUThread.h ->
// rx/cpu/cell/ppu, LLVM JIT) and cannot be built without the full -DWITH_PS3 emulator.
// The harnesses are single-threaded, so these answer as "the main thread"; emergency_exit
// keeps its [[noreturn]] contract and aborts so a fatal error is reported as a crash.
#include "stdafx.h"
#include "util/Thread.h"
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
#include <sys/syscall.h>

void thread_base::set_name(std::string) {}

void thread_ctrl::emergency_exit(std::string_view reason)
{
	std::fprintf(stderr, "thread_ctrl::emergency_exit: %.*s\n", static_cast<int>(reason.size()), reason.data());
	std::abort();
}

u64 thread_ctrl::get_tid()
{
	return static_cast<u64>(::syscall(SYS_gettid));
}

bool thread_ctrl::is_main()
{
	return true;
}

void thread_ctrl::set_native_priority(int) {}
