// Functional-test driver: load a PARAM.SFO with psf::load and print every entry
// ("KEY<TAB>type<TAB>value"), then re-save with psf::save_object, re-load and print
// "roundtrip ok"/"roundtrip mismatch". mayhem/test.sh diffs the output against a golden file.
#include "stdafx.h"
#include "Loader/PSF.h"
#include <cstdio>

int main(int argc, char** argv)
{
	if (argc != 2)
		return 2;
	fs::file f(argv[1]);
	if (!f)
		return 3;
	auto res = psf::load(f, argv[1]);
	std::printf("errc=%d entries=%zu\n", static_cast<int>(res.errc), res.sfo.size());
	for (const auto& [key, value] : res.sfo)
	{
		if (value.type() == psf::format::integer)
			std::printf("%s\tinteger\t%u\n", key.c_str(), value.as_integer());
		else
			std::printf("%s\t%s\t%s\tmax=%u\n", key.c_str(), value.type() == psf::format::string ? "string" : "array", value.as_string().c_str(), value.max(true));
	}
	std::printf("TITLE_ID=%s\n", std::string(psf::get_string(res.sfo, "TITLE_ID", "none")).c_str());
	std::vector<u8> out = psf::save_object(res.sfo);
	fs::file f2(out.data(), out.size());
	auto again = psf::load(f2, "resaved");
	bool same = again.sfo.size() == res.sfo.size();
	for (auto a = res.sfo.begin(), b = again.sfo.begin(); same && a != res.sfo.end(); ++a, ++b)
		same = a->first == b->first && a->second.type() == b->second.type() &&
		       (a->second.type() == psf::format::integer ? a->second.as_integer() == b->second.as_integer() : a->second.as_string() == b->second.as_string());
	std::printf("roundtrip %s\n", same ? "ok" : "mismatch");
	return 0;
}
