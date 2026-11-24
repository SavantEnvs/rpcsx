// libFuzzer harness: PS3 firmware update container (PS3UPDAT.PUP), rpcs3/Loader/PUP.cpp.
// The input is the PUP file, wrapped in an in-memory fs::file and handed to pup_object, which
// parses the header and file/hash tables and verifies each entry's HMAC-SHA1, as the firmware
// installer does. The entries the installer reads (0x100 version string, 0x300 update_files.tar,
// and the other well-known ids) are then extracted with get_file and read in full.
#include "stdafx.h"
#include "Loader/PUP.h"
#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	pup_object pup{fs::file(data, size)};
	const pup_error err = static_cast<pup_error>(pup);
	if (err != pup_error::ok && err != pup_error::hash_mismatch)
		return 0;

	static constexpr u64 ids[] = {0x100, 0x101, 0x102, 0x103, 0x104, 0x200, 0x201, 0x300, 0x301, 0x302, 0x501, 0x601, 0x602};
	for (u64 id : ids)
	{
		fs::file f = pup.get_file(id);
		if (!f)
			continue;
		std::vector<u8> buf;
		(void)f.read(buf, f.size());
	}
	return 0;
}
