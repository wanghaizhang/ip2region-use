-- sha256.lua
-- Pure Lua SHA-256 implementation
-- Compatible with LuaJIT / OpenResty / Lua 5.1

local bit = require("bit")

local band = bit.band
local bor = bit.bor
local bxor = bit.bxor
local bnot = bit.bnot
local rshift = bit.rshift
local ror = bit.ror

local MOD = 4294967296

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function add(...)
    local sum = 0
    for i = 1, select("#", ...) do
        sum = sum + (select(i, ...) % MOD)
    end
    return sum % MOD
end

local function Ch(x, y, z)
    return bxor(band(x, y), band(bnot(x), z))
end

local function Maj(x, y, z)
    return bxor(band(x, y), band(x, z), band(y, z))
end

local function Sigma0(x)
    return bxor(ror(x, 2), ror(x, 13), ror(x, 22))
end

local function Sigma1(x)
    return bxor(ror(x, 6), ror(x, 11), ror(x, 25))
end

local function sigma0(x)
    return bxor(ror(x, 7), ror(x, 18), rshift(x, 3))
end

local function sigma1(x)
    return bxor(ror(x, 17), ror(x, 19), rshift(x, 10))
end

local function to_u32(a, b, c, d)
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function sha256(message)
    assert(type(message) == "string", "message must be a string")

    local len = #message
    local bit_len = len * 8

    -- Padding
    local pad_len = (56 - (len + 1) % 64) % 64
    message = message .. "\128" .. string.rep("\0", pad_len)

    -- Append 64-bit message length (big endian)
    local high = math.floor(bit_len / MOD)
    local low = bit_len % MOD

    message = message ..
        string.char(
            math.floor(high / 16777216) % 256,
            math.floor(high / 65536) % 256,
            math.floor(high / 256) % 256,
            high % 256,
            math.floor(low / 16777216) % 256,
            math.floor(low / 65536) % 256,
            math.floor(low / 256) % 256,
            low % 256
        )

    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }

    for offset = 1, #message, 64 do
        local W = {}

        for i = 0, 15 do
            local p = offset + i * 4
            W[i] = to_u32(
                message:byte(p, p + 3)
            )
        end

        for i = 16, 63 do
            W[i] = add(
                sigma1(W[i - 2]),
                W[i - 7],
                sigma0(W[i - 15]),
                W[i - 16]
            )
        end

        local a, b, c, d, e, f, g, h =
            H[1], H[2], H[3], H[4],
            H[5], H[6], H[7], H[8]

        for i = 0, 63 do
            local T1 = add(
                h,
                Sigma1(e),
                Ch(e, f, g),
                K[i + 1],
                W[i]
            )

            local T2 = add(
                Sigma0(a),
                Maj(a, b, c)
            )

            h = g
            g = f
            f = e
            e = add(d, T1)
            d = c
            c = b
            b = a
            a = add(T1, T2)
        end

        H[1] = add(H[1], a)
        H[2] = add(H[2], b)
        H[3] = add(H[3], c)
        H[4] = add(H[4], d)
        H[5] = add(H[5], e)
        H[6] = add(H[6], f)
        H[7] = add(H[7], g)
        H[8] = add(H[8], h)
    end

    local result = {}

    for i = 1, 8 do
        result[i] = string.format("%08x", H[i])
    end

    return table.concat(result)
end

-- hmac_sha256(key, msg) -> hex string. key and msg are binary strings.
local function u32(n)
    return n % 4294967296
end

local function xor_byte(s, pad)
    local result = {}
    for i = 1, #s do
        result[i] = string.char(u32(bit.bxor(s:byte(i), pad)))
    end
    return table.concat(result)
end

local function hex_to_bin(hex)
    return hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)
end

local function hmac_sha256(key, msg)
    assert(type(key) == "string", "key must be a string")
    assert(type(msg) == "string", "msg must be a string")

    -- Step 1: Normalize key to 64 bytes
    if #key > 64 then
        key = hex_to_bin(sha256(key))
    end
    if #key < 64 then
        key = key .. string.rep("\0", 64 - #key)
    end

    -- Step 2: inner hash
    local ipad = xor_byte(key, 0x36)
    local inner = hex_to_bin(sha256(ipad .. msg))

    -- Step 3: outer hash
    local opad = xor_byte(key, 0x5c)
    local outer = sha256(opad .. inner)

    return outer
end

return { sha256 = sha256, hmac_sha256 = hmac_sha256 }
