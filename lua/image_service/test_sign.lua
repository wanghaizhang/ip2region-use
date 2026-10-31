-- Test HMAC via ffi libcrypto
local ffi = require("ffi")

-- Declare HMAC: unsigned char *HMAC(const unsigned char *data, size_t datalen,
--                                   const unsigned char *key, size_t keylen,
--                                   unsigned char *md, unsigned int *md_len)
ffi.C.HMAC(ffi.C.unsigned_char, ffi.C.size_t, ffi.C.unsigned_char, ffi.C.size_t, ffi.C.unsigned_char, ffi.C.unsigned_int)

local function hex2bytes(hex)
    local t = {}
    for h in hex:gmatch("([0-9a-fA-F][0-9a-fA-F])") do
        t[#t + 1] = string.char(tonumber(h, 16))
    end
    return table.concat(t)
end

local secret_key = "be12eaea1dce00a71da2145ae8002145291d4cd4c038f52177fea1b8e98c3398"
local secret_salt = "a5d933a0edf681c43bebda1d21f3096da067ecb8dbbe26ba36feb88c8937b531"
local key = hex2bytes(secret_key)
local salt = hex2bytes(secret_salt)

local processed = "rs:fill:100:100:1"
local source = "https://www.w3school.com.cn/i/ui/weixin-2.png"
local path = "/" .. processed .. "/" .. source
local message = salt .. path

local data = ffi.new("unsigned char[?]", #message)
ffi.copy(data, message)
local out = ffi.new("unsigned char[32]")
local outlen = ffi.new("unsigned int[1]")

local ret = ffi.C.HMAC(data, #message, key, #key, out, outlen)
if not ret then
    print("HMAC failed")
    os.exit(1)
end

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(data, len)
    local t = {}
    local rest = #data
    local i = 1
    while i <= rest do
        local b1 = data:byte(i)
        local b2 = (i+1 <= rest) and data:byte(i+1) or 0
        local b3 = (i+2 <= rest) and data:byte(i+2) or 0
        local s1 = bit.rshift(b1, 2)
        local s2 = bit.bor(bit.lshift(bit.band(b1, 3), 4), bit.rshift(b2 or 0, 4))
        local s3 = bit.bor(bit.lshift(bit.band(b2 or 0, 15), 2), bit.rshift(b3 or 0, 6))
        local s4 = bit.band(b3 or 0, 63)
        t[#t+1] = b64chars:sub(s1+1, s1+1)
        t[#t+1] = (i+1 <= rest) and b64chars:sub(s2+1, s2+1) or "="
        t[#t+1] = (i+2 <= rest) and b64chars:sub(s3+1, s3+1) or "="
        t[#t+1] = (i+2 <= rest) and b64chars:sub(s4+1, s4+1) or "="
        i = i + 3
    end
    return table.concat(t)
end

local sig = b64(out, outlen[0])
print("computed:", sig)
print("target:   HGng7EidDAQnZtXdINxI-Ur3zu625j_wmpdoF8V5lE4")
if sig == "HGng7EidDAQnZtXdINxI-Ur3zu625j_wmpdoF8V5lE4" then
    print("MATCH ✓")
else
    print("no match ✗")
end
