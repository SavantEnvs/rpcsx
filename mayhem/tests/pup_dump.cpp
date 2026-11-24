// Functional-test driver: open a PUP with pup_object (rpcs3/Loader/PUP.cpp), print the load
// status (pup_error) and the contents of entries 0x100 (version) and 0x300.
// mayhem/test.sh diffs the output against golden files for a valid and a tampered PUP.
#include "stdafx.h"
#include "Loader/PUP.h"
#include <cstdio>

int main(int argc, char** argv)
{
	if (argc != 2)
		return 2;
	pup_object pup{fs::file(argv[1])};
	std::printf("pup_error=%u\n", static_cast<unsigned>(static_cast<pup_error>(pup)));
	for (u64 id : {0x100ull, 0x300ull, 0x999ull})
	{
		fs::file f = pup.get_file(id);
		if (!f)
		{
			std::printf("0x%llx: missing\n", static_cast<unsigned long long>(id));
			continue;
		}
		std::string s = f.to_string();
		std::printf("0x%llx: %zu bytes: %s\n", static_cast<unsigned long long>(id), s.size(), s.c_str());
	}
	return 0;
}
