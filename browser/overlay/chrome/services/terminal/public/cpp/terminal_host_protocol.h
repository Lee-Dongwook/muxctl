// Copyright 2026 Manaflow, Inc.
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef CHROME_SERVICES_CMUX_TERMINAL_RENDERER_PUBLIC_CPP_CMUX_TERMINAL_HOST_PROTOCOL_H_
#define CHROME_SERVICES_CMUX_TERMINAL_RENDERER_PUBLIC_CPP_CMUX_TERMINAL_HOST_PROTOCOL_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace muxctl {
    inline constexpr std::array<uint8_t, 4> terminalHostMagic = {'C', 'M', 'T', 'H'};
}

#endif
