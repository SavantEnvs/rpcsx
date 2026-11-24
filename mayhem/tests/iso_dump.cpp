// Functional-test driver: open an ISO9660 image with iso_dev (rpcs3/dev/iso.cpp) through
// file_block_dev and print the directory tree ("path<TAB>size<TAB>first line of content").
// mayhem/test.sh diffs the output against a golden file.
#include "stdafx.h"
#include "dev/iso.hpp"
#include <algorithm>
#include <cstdio>
#include <vector>

static void walk(iso_dev& dev, const std::string& path)
{
	auto dir = dev.open_dir(path);
	if (!dir)
	{
		std::printf("open_dir failed: %s\n", path.c_str());
		return;
	}
	std::vector<fs::dir_entry> entries;
	fs::dir_entry e;
	while (dir->read(e))
		if (e.name != "." && e.name != "..")
			entries.push_back(e);
	std::sort(entries.begin(), entries.end(), [](auto& a, auto& b) { return a.name < b.name; });
	for (auto& entry : entries)
	{
		std::string child = path == "/" ? "/" + entry.name : path + "/" + entry.name;
		if (entry.is_directory)
		{
			std::printf("%s/\n", child.c_str());
			walk(dev, child);
			continue;
		}
		auto file = dev.open(child, fs::read);
		std::string content(entry.size, '\0');
		u64 got = file ? file->read(content.data(), content.size()) : 0;
		content.resize(got);
		if (auto nl = content.find('\n'); nl != std::string::npos)
			content.resize(nl);
		std::printf("%s\t%llu\t%s\n", child.c_str(), static_cast<unsigned long long>(entry.size), content.c_str());
	}
}

int main(int argc, char** argv)
{
	if (argc != 2)
		return 2;
	fs::file f(argv[1]);
	if (!f)
		return 3;
	auto dev = iso_dev::open(std::make_unique<file_block_dev>(std::move(f)));
	if (!dev)
	{
		std::printf("not an iso\n");
		return 1;
	}
	walk(*dev, "/");
	return 0;
}
