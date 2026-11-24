// libFuzzer harness: ISO9660 disc image reader, rpcs3/dev/iso.cpp (iso_dev).
// The input is the disc image, exposed through an in-memory block_dev with 2048-byte sectors
// (the same geometry file_block_dev uses). iso_dev::open parses the volume descriptors; the
// directory tree is then walked through the fs::device_base interface (open_dir/stat/open/read),
// as the VFS does when a game ISO is mounted.
#include "stdafx.h"
#include "dev/iso.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

namespace
{
	class mem_block_dev final : public block_dev
	{
		std::vector<std::uint8_t> m_data;

	public:
		mem_block_dev(const std::uint8_t* data, std::size_t size)
			: m_data(data, data + size)
		{
			set_block_info(2048, size / 2048);
		}

		std::size_t read(std::size_t blockIndex, void* data, std::size_t blockCount) override
		{
			if (blockIndex >= block_count())
				return 0;
			blockCount = std::min(blockCount, block_count() - blockIndex);
			std::memcpy(data, m_data.data() + blockIndex * block_size(), blockCount * block_size());
			return blockCount;
		}

		std::size_t write(std::size_t, const void*, std::size_t) override
		{
			return 0;
		}
	};

	void walk(iso_dev& dev, const std::string& path, int depth, int& budget)
	{
		if (depth > 8)
			return;
		auto dir = dev.open_dir(path);
		if (!dir)
			return;
		fs::dir_entry entry;
		while (budget-- > 0 && dir->read(entry))
		{
			if (entry.name == "." || entry.name == "..")
				continue;
			std::string child = path == "/" ? "/" + entry.name : path + "/" + entry.name;
			fs::stat_t st{};
			(void)dev.stat(child, st);
			if (entry.is_directory)
			{
				walk(dev, child, depth + 1, budget);
				continue;
			}
			auto file = dev.open(child, fs::read);
			if (!file)
				continue;
			char buf[4096];
			(void)file->size();
			(void)file->read(buf, sizeof(buf));
			(void)file->read_at(entry.size > 16 ? entry.size - 16 : 0, buf, 16);
		}
	}
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	auto dev = iso_dev::open(std::make_unique<mem_block_dev>(data, size));
	if (!dev)
		return 0;
	fs::device_stat ds{};
	(void)dev->statfs("/", ds);
	int budget = 256;
	walk(*dev, "/", 0, budget);
	return 0;
}
