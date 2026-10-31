local bit = require("bit")
local ROL = bit.rol
local BOR = bit.bor
local BAND = bit.band
local BNOT = bit.bnot
local BXOR = bit.bxor
local LSHIFT = bit.lshift
local RSHIFT = bit.rshift

local function add32(...)
    local args = {...}
    local s = 0
    for i = 1, #args do s = s + args[i] end
    return BAND(s, 0xffffffff)
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

local function to_hex32(x)
    return string.format("%02x%02x%02x%02x",
        BAND(RSHIFT(x, 24), 0xff), BAND(RSHIFT(x, 16), 0xff),
        BAND(RSHIFT(x, 8), 0xff), BAND(x, 0xff))
end

local function get32(s, p)
    local v1 = s:byte(p); local v2 = s:byte(p+1)
    local v3 = s:byte(p+2); local v4 = s:byte(p+3)
    return BOR(BOR(LSHIFT(v1,24), LSHIFT(v2,16)), BOR(LSHIFT(v3,8), v4))
end

local function sha256(msg)
    local bitlen = #msg * 8
    local padded = msg .. "\128"
    while #padded % 64 ~= 56 do padded = padded .. "\0" end
    padded = padded .. string.char(0,0,0,0) ..
             string.char(RSHIFT(bitlen,24), RSHIFT(bitlen,16), RSHIFT(bitlen,8), BAND(bitlen,0xff))
    local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local nblocks = #padded / 64
    print("nblocks =", nblocks)
    for blk = 0, nblocks - 1 do
        local base = blk * 64 + 1
        local w = {}
        for i = 0, 15 do w[i+1] = get32(padded, base + i*4) end
        for i = 17, 64 do
            local s0 = BXOR(BOR(ROL(w[i-15],7), ROL(w[i-15],18)), RSHIFT(w[i-15],3))
            local s1 = BXOR(BOR(ROL(w[i-2],17), ROL(w[i-2],19)), RSHIFT(w[i-2],10))
            w[i] = add32(w[i-16], s0, w[i-7], s1)
        end
        local a,b,c,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
        for i = 1, 64 do
            local s1 = BXOR(BOR(ROL(e,6), ROL(e,11), ROL(e,25)), RSHIFT(e,3))
            local ch = BXOR(BOR(BAND(e,f), BAND(BNOT(e),g)), BAND(f,g))
            local s0 = BOR(ROL(a,2), ROL(a,13), ROL(a,22))
            local maj = BXOR(BOR(BAND(a,b), BAND(b,c)), BAND(a,c))
            local t2 = add32(s0, maj, ch, s1, w[i], K[i])
            local t1 = add32(s1, ch, a, b, c, d)
            hh=g; g=f; f=e; e=add32(d,t1,t2); d=c; c=b; b=a; a=t1
        end
        h[1]=add32(h[1],a); h[2]=add32(h[2],b); h[3]=add32(h[3],c); h[4]=add32(h[4],d)
        h[5]=add32(h[5],e); h[6]=add32(h[6],f); h[7]=add32(h[7],g); h[8]=add32(h[8],hh)
        print("after block", blk, ":")
        print(to_hex32(h[1]), to_hex32(h[2]), to_hex32(h[3]), to_hex32(h[4]))
    end
    local out = ""
    for i = 1, 8 do out = out .. to_hex32(h[i]) end
    return out
end

print("sha256(abc) =", sha256("abc"))
print("expected     = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
