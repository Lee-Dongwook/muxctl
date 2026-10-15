#include "chrome/services/terminal/public/cpp/terminal_host_protocol.h"

#include <algorithm>
#include <iterator>
#include <limits>
#include <unordered_set>
#include <utility>

namespace muxctl {
    namespace {
        constexpr size_t clientHelloLength = 60;
        constexpr size_t hostHelloLength = 40;
        constexpr uint64_t maxKittyImageBytes = 10'000'000;
        constexpr uint64_t maxKittyInflightBytes = 13'595'480;
        constexpr uint64_t maxKittyImages = 4'096;
        constexpr uint64_t maxKittyPlacements = 16'384;

        void AppendU16(std::vector<uint8_t>* output, uint16_t value) {
            output->push_back(static_cast<uint8_t>(value));
            output->push_back(static_cast<uint8_t>(value >> 8));
        }

        void AppendU32(std::vector<uint8_t>* output, uint32_t value) {
            for (size_t index = 0; index < sizeof(value); ++index) {
                output->push_back(static_cast<uint8_t>(value >> (index * 8)));
            }
        }
        //TODO
    }
}
