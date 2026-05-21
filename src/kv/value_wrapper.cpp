// Copyright 2023 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"
#include "kv/value_wrapper.hpp"

#include <cstring>
#include <stdexcept>

namespace {
	enum class SerType : uint8_t {
		Null = 0,
		Bool = 1,
		Int = 2,
		Double = 3,
		String = 4,
		Array = 5,
		Map = 6
	};

	template <typename T>
	void writeLE(char*& ptr, T value) {
		for (size_t i = 0; i < sizeof(T); ++i) {
			*ptr++ = static_cast<char>(value & 0xFF);
			value >>= 8;
		}
	}

	template <typename T>
	T readLE(const char*& ptr) {
		T value = 0;
		for (size_t i = 0; i < sizeof(T); ++i) {
			value |= static_cast<T>(static_cast<uint8_t>(*ptr++)) << (i * 8);
		}
		return value;
	}

	template <typename T>
	T readLEChecked(const char*& ptr, const char* end) {
		if (ptr + sizeof(T) > end) throw std::runtime_error("Unexpected end of data");
		return readLE<T>(ptr);
	}
}

ValueWrapper::ValueWrapper(uint64_t timestamp) :
	timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(ValueVariant value, uint64_t timestamp) :
	data_(std::move(value)), timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(const std::string &value, uint64_t timestamp) :
	data_(value), timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(bool value, uint64_t timestamp) :
	data_(value), timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(int32_t value, uint64_t timestamp) :
	data_(value), timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(double value, uint64_t timestamp) :
	data_(value), timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(const MapType &value, uint64_t timestamp) :
	data_(value), timestamp_(timestamp) { }

ValueWrapper::ValueWrapper(const std::initializer_list<std::pair<const std::string, ValueWrapper>> &init_list, uint64_t timestamp) :
	timestamp_(timestamp) {
	MapType map;
	for (const auto &[key, val] : init_list) {
		map[key] = std::make_shared<ValueWrapper>(val);
	}
	data_ = map;
}

ValueWrapper::ValueWrapper(const std::initializer_list<ValueWrapper> &init_list, uint64_t timestamp) :
	timestamp_(timestamp) {
	ArrayType arr(init_list);
	data_ = arr;
}

std::optional<ValueWrapper> ValueWrapper::get(const std::string &key) const {
	const auto pval = std::get_if<MapType>(&data_);
	if (!pval) {
		return std::nullopt;
	}
	if (!pval->contains(key)) {
		return std::nullopt;
	}
	const auto &valuePtr = pval->at(key);
	if (!valuePtr) {
		return std::nullopt;
	}
	return *valuePtr;
}

std::optional<ValueWrapper> ValueWrapper::get(size_t index) const {
	if (const auto pval = std::get_if<ArrayType>(&data_)) {
		if (index < pval->size()) {
			return (*pval)[index];
		}
	}
	return std::nullopt;
}

// Serialization format (TLV binary):
// tag (1 byte) + data
//   Null:  no data
//   Bool:  1 byte (0/1)
//   Int:   4 bytes LE
//   Double:8 bytes LE
//   String:4 bytes LE (length) + UTF-8 data
//   Array: 4 bytes LE (count) + [items...]
//   Map:   4 bytes LE (count) + [4 bytes LE keyLen + key + value]...

std::string ValueWrapper::serialize() const {
	std::string out;

	std::visit([&out](const auto &arg) {
		using T = std::decay_t<decltype(arg)>;

		if constexpr (std::is_same_v<T, StringType>) {
			out.push_back(static_cast<char>(SerType::String));
			uint32_t len = static_cast<uint32_t>(arg.size());
			char buf[4];
			char* p = buf;
			writeLE(p, len);
			out.append(buf, 4);
			out.append(arg);
		} else if constexpr (std::is_same_v<T, BooleanType>) {
			out.push_back(static_cast<char>(SerType::Bool));
			out.push_back(arg ? '\1' : '\0');
		} else if constexpr (std::is_same_v<T, IntType>) {
			out.push_back(static_cast<char>(SerType::Int));
			char buf[4];
			char* p = buf;
			writeLE(p, arg);
			out.append(buf, 4);
		} else if constexpr (std::is_same_v<T, DoubleType>) {
			out.push_back(static_cast<char>(SerType::Double));
			uint64_t bits;
			std::memcpy(&bits, &arg, sizeof(bits));
			char buf[8];
			char* p = buf;
			writeLE(p, bits);
			out.append(buf, 8);
		} else if constexpr (std::is_same_v<T, ArrayType>) {
			out.push_back(static_cast<char>(SerType::Array));
			uint32_t count = static_cast<uint32_t>(arg.size());
			char buf[4];
			char* p = buf;
			writeLE(p, count);
			out.append(buf, 4);
			for (const auto &item : arg) {
				out.append(item.serialize());
			}
		} else if constexpr (std::is_same_v<T, MapType>) {
			out.push_back(static_cast<char>(SerType::Map));
			uint32_t count = static_cast<uint32_t>(arg.size());
			char buf[4];
			char* p = buf;
			writeLE(p, count);
			out.append(buf, 4);
			for (const auto &[key, val] : arg) {
				uint32_t keyLen = static_cast<uint32_t>(key.size());
				p = buf;
				writeLE(p, keyLen);
				out.append(buf, 4);
				out.append(key);
				out.append(val->serialize());
			}
		}
	}, data_);

	return out;
}

std::optional<ValueWrapper> ValueWrapper::deserialize(const char* data, size_t size, uint64_t timestamp) {
	if (size == 0) {
		return std::nullopt;
	}

	const char* ptr = data;
	const char* end = data + size;

	auto readType = [&]() -> SerType {
		if (ptr >= end) throw std::runtime_error("Unexpected end of data");
		return static_cast<SerType>(*ptr++);
	};

	auto deser = [&](auto& self) -> ValueWrapper {
		auto type = readType();
		switch (type) {
			case SerType::Null: {
				return ValueWrapper(timestamp);
			}
			case SerType::Bool: {
				if (ptr >= end) throw std::runtime_error("Unexpected end of data");
				return ValueWrapper(*ptr++ != 0, timestamp);
			}
			case SerType::Int: {
				return ValueWrapper(readLEChecked<int32_t>(ptr, end), timestamp);
			}
			case SerType::Double: {
				uint64_t bits = readLEChecked<uint64_t>(ptr, end);
				double val;
				std::memcpy(&val, &bits, sizeof(val));
				return ValueWrapper(val, timestamp);
			}
			case SerType::String: {
				uint32_t len = readLEChecked<uint32_t>(ptr, end);
				if (ptr + len > end) throw std::runtime_error("Unexpected end of data");
				std::string str(ptr, len);
				ptr += len;
				return ValueWrapper(str, timestamp);
			}
			case SerType::Array: {
				uint32_t count = readLEChecked<uint32_t>(ptr, end);
				ArrayType arr;
				arr.reserve(count);
				for (uint32_t i = 0; i < count; ++i) {
					arr.emplace_back(self(self));
				}
				return ValueWrapper(arr, timestamp);
			}
			case SerType::Map: {
				uint32_t count = readLEChecked<uint32_t>(ptr, end);
				MapType map;
				for (uint32_t i = 0; i < count; ++i) {
					uint32_t keyLen = readLEChecked<uint32_t>(ptr, end);
					if (ptr + keyLen > end) throw std::runtime_error("Unexpected end of data");
					std::string key(ptr, keyLen);
					ptr += keyLen;
					auto val = self(self);
					map[key] = std::make_shared<ValueWrapper>(val);
				}
				return ValueWrapper(map, timestamp);
			}
		}
		return ValueWrapper(timestamp);
	};

	try {
		return deser(deser);
	} catch (const std::runtime_error &) {
		return std::nullopt;
	}
}
