// libFuzzer harness: PS3 PARAM.SFO (PSF) loader, rpcs3/Loader/PSF.cpp.
// The input bytes are wrapped in an in-memory fs::file and handed to psf::load,
// exactly as the emulator does with a PARAM.SFO read from a game directory/PKG.
// Accepted registries are queried, re-serialized with psf::save_object and re-loaded.
#include "stdafx.h"
#include "Loader/PSF.h"
#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	fs::file f(data, size);
	auto res = psf::load(f, "fuzz.sfo");
	if (!res)
		return 0;

	for (const auto& [key, value] : res.sfo)
	{
		(void)value.size();
		(void)value.is_valid();
		if (value.type() == psf::format::integer)
			(void)value.as_integer();
		else
			(void)value.as_string();
	}
	(void)psf::get_string(res.sfo, "TITLE_ID");
	(void)psf::get_integer(res.sfo, "ATTRIBUTE");
	(void)psf::check_registry(res.sfo);

	std::vector<u8> out = psf::save_object(res.sfo);
	fs::file f2(out.data(), out.size());
	(void)psf::load(f2, "fuzz-resaved.sfo");
	return 0;
}
