local bit = require("bit")
local BOR = bit.bor
local BAND = bit.band
local BNOT = bit.bnot
local BXOR = bit.bxor
local LSHIFT = bit.lshift
local RSHIFT = bit.rshift
local U32 = 4294967296
local function u32(x)
    local r = x % U32
    if r < 0 then r = r + U32 end
    return r
end
local function ror(x, n)
    x = u32(x)
    if n == 0 then return x end
    local lo = BAND(x, (2 ^ n) - 1)
    return u32(BOR(BAND(RSHIFT(x, n), 0xffffffff), LSHIFT(lo, 32 - n)))
end
local function add32(...)
    local s = 0
    for _, a in ipairs({...}) do s = s + u32(a) end
    return u32(s)
end
local function get32(tbl, p)
    return u32(BOR(BOR(LSHIFT(tbl[p] or 0, 24), LSHIFT(tbl[p + 1] or 0, 16)), BOR(LSHIFT(tbl[p + 2] or 0, 8), tbl[p + 3] or 0)))
end
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local msg = "abc"
local bytes = {}
local n = #msg
for i = 1, n do bytes[i] = msg:byte(i) end
n = n + 1; bytes[n] = 0x80
while (n % 64) ~= 56 do n = n + 1; bytes[n] = 0x00 end
n = n + 1; bytes[n] = 0x00; n = n + 1; bytes[n] = 0x00
n = n + 1; bytes[n] = 0x00; n = n + 1; bytes[n] = 0x00
n = n + 1; bytes[n] = BAND(RSHIFT(#msg*8, 24), 0xff)
n = n + 1; bytes[n] = BAND(RSHIFT(#msg*8, 16), 0xff)
n = n + 1; bytes[n] = BAND(RSHIFT(#msg*8, 8), 0xff)
n = n + 1; bytes[n] = BAND(#msg*8, 0xff)
local w = {}
for i = 1, 16 do w[i] = get32(bytes, (i-1)*4 + 1) end
for i = 17, 64 do
    local s0 = BXOR(BXOR(ror(w[i-15],7), ror(w[i-15],18)), RSHIFT(w[i-15],3))
    local s1 = BXOR(BXOR(ror(w[i-2],17), ror(w[i-2],19)), RSHIFT(w[i-2],10))
    w[i] = add32(w[i-16], s0, w[i-7], s1)
end
print("w[1..16]:")
for i = 1, 16 do print(string.format("  w[%d]=0x%08x", i, w[i])) end
print("w[17..24]:")
for i = 17, 24 do print(string.format("  w[%d]=0x%08x", i, w[i])) end
print("K[1..4]:", string.format("0x%08x 0x%08x 0x%08x 0x%08x", K[1],K[2],K[3],K[4]))
print("K[16]:", string.format("0x%08x", K[16]))
print("w[1]:", string.format("0x%08x", w[1]))

local h1 = 0x6a09e667; local h2 = 0xbb67ae85; local h3 = 0x3c6ef372; local h4 = 0xa54ff53a
local h5 = 0x510e527f; local h6 = 0x9b05688c; local h7 = 0x1f83d9ab; local h8 = 0x5be0cd19
local a,b,c,d,e,f,g,hh = h1,h2,h3,h4,h5,h6,h7,h8
for i = 1, 64 do
    local s1 = BXOR(BXOR(ror(e, 6), ror(e, 11), ror(e, 25)), RSHIFT(e, 3))
    local ch = BXOR(BAND(e, f), BAND(BNOT(e), g))
    local s0 = BXOR(ror(a, 2), ror(a, 13), ror(a, 22))
    local maj = BXOR(BXOR(BAND(a, b), BAND(b, c)), BAND(a, c))
    local t2 = add32(s0, maj)
    local t1 = add32(s1, ch, w[i], K[i])
    hh = g; g = f; f = e; e = add32(d, t1); d = c; c = b; b = a; a = add32(t1, t2)
    if i <= 3 then
        print(string.format("  r=%2d a=0x%08x b=0x%08x c=0x%08x d=0x%08x e=0x%08x f=0x%08x g=0x%08x hh=0x%08x s1=0x%08x ch=0x%08x s0=0x%08x maj=0x%08x t1=0x%08x t2=0x%08x", i, a,b,c,d,e,f,g,hh, u32(s1), u32(ch), u32(s0), u32(maj), t1, t2))
    end
end
print("FINAL:", string.format("%08x%08x%08x%08x%08x%08x%08x%08x", add32(h1,a),add32(h2,b),add32(h3,c),add32(h4,d),add32(h5,e),add32(h6,f),add32(h7,g),add32(h8,hh)))
