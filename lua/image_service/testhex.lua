local bit = require("bit")
local BOR = bit.bor
local BAND = bit.band
local BNOT = bit.bnot
local BXOR = bit.bxor
local LSHIFT = bit.lshift
local RSHIFT = bit.rshift

local function add32(...)
    local args = {...}
    local s = 0
    for i = 1, #args do
        local v = args[i]
        if v < 0 then v = v + 4294967296 end
        s = s + v
    end
    if s >= 4294967296 then s = s - 4294967296 * math.floor(s / 4294967296) end
    return s
end

local function ror(x, n)
    if n == 0 then return x end
    local mask = (2 ^ n) - 1
    local lo = BAND(x, mask)
    return BAND(BOR(BAND(RSHIFT(x, n), 0xffffffff), LSHIFT(lo, 32 - n)), 0xffffffff)
end

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function get32(tbl, p)
    return BOR(BOR(LSHIFT(tbl[p], 24), LSHIFT(tbl[p + 1], 16)), BOR(LSHIFT(tbl[p + 2], 8), tbl[p + 3]))
end

local function to_hex32(x)
    return bit.tohex(x, 8)
end

-- Full sha256("abc")
local msg = "abc"
local bytes = {}
local n = #msg
for i = 1, n do bytes[i] = msg:byte(i) end
n = n + 1; bytes[n] = 0x80
while (n % 64) ~= 56 do n = n + 1; bytes[n] = 0x00 end
local bitlen = #msg * 8
n = n + 1; bytes[n] = 0x00; n = n + 1; bytes[n] = 0x00; n = n + 1; bytes[n] = 0x00; n = n + 1; bytes[n] = 0x00
n = n + 1; bytes[n] = BAND(RSHIFT(bitlen, 24), 0xff)
n = n + 1; bytes[n] = BAND(RSHIFT(bitlen, 16), 0xff)
n = n + 1; bytes[n] = BAND(RSHIFT(bitlen, 8), 0xff)
n = n + 1; bytes[n] = BAND(bitlen, 0xff)

local w = {}
for i = 1, 16 do w[i] = get32(bytes, (i-1)*4 + 1) end
for t = 17, 64 do
    local s0 = BXOR(BOR(ror(w[t-15], 7), ror(w[t-15], 18)), RSHIFT(w[t-15], 3))
    local s1 = BXOR(BOR(ror(w[t-2], 17), ror(w[t-2], 19)), RSHIFT(w[t-2], 10))
    w[t] = add32(w[t-16], s0, w[t-7], s1)
end

local h1 = 0x6a09e667; local h2 = 0xbb67ae85; local h3 = 0x3c6ef372; local h4 = 0xa54ff53a
local h5 = 0x510e527f; local h6 = 0x9b05688c; local h7 = 0x1f83d9ab; local h8 = 0x5be0cd19
local a, b, c, d, e, f, g, hh = h1, h2, h3, h4, h5, h6, h7, h8
for i = 1, 64 do
    local s1 = BXOR(BOR(ror(e, 6), ror(e, 11), ror(e, 25)), RSHIFT(e, 3))
    local ch = BXOR(BOR(BAND(e, f), BAND(BNOT(e), g)), BAND(f, g))
    local s0 = BOR(ror(a, 2), ror(a, 13), ror(a, 22))
    local maj = BXOR(BOR(BAND(a, b), BAND(b, c)), BAND(a, c))
    local t2 = add32(s0, maj, ch, s1, w[i], K[i])
    local t1 = add32(hh, s1, ch, w[i], K[i])
    hh = g; g = f; f = e; e = add32(d, t1, t2); d = c; c = b; b = a; a = t1
    if i <= 6 or i == 64 then
        print(string.format("round %2d: a=0x%08x e=0x%08x t1=0x%08x t2=0x%08x", i, a, e, t1, t2))
    end
end
local H = { add32(h1,a), add32(h2,b), add32(h3,c), add32(h4,d), add32(h5,e), add32(h6,f), add32(h7,g), add32(h8,hh) }
print("Lua H:", table.concat({to_hex32(H[1]),to_hex32(H[2]),to_hex32(H[3]),to_hex32(H[4]),to_hex32(H[5]),to_hex32(H[6]),to_hex32(H[7]),to_hex32(H[8])}))
print("Python: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
