local sha = require("image_service.sha256")
local bit = require("bit")

-- Python hashlib reference values for these exact inputs
local ref = {
   [0]   = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
   [1]   = "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
   [3]   = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
   [40]  = "bd913ff68243d41b9611b2690dfbf2b0f6e42ea14536a98232af60e9f64ffdaa",
   [43]  = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
   [55]  = "d5e285683cd4efc02d021a5c62014694958901005d6f71e89e0989fac77e4072",
   [56]  = "04c26261370ee7541549d16dee320c723e3fd14671e66a099afe0a377c16888e",
   [57]  = "ae14a2563ccf969d99aca69ce6bb74981f734bbf9f655f73b8f06db68cab5217",
   [64]  = "7ce100971f64e7001e8fe5a51973ecdfe1ced42befe7ee8d5fd6219506b5393c",
   [100] = "09ecb6ebc8bcefc733f6f2ec44f791abeed6a99edf0cc31519637898aebd52d8",
   [70]  = "2b0e5590cef28816931efa181a42b2bde6ae180bd5ba6784f48f12b52817e321",
}
local inputs = { "", "a", "abc", ("x"):rep(40), ("x"):rep(55), ("x"):rep(56),
  ("x"):rep(57), ("x"):rep(64), ("x"):rep(100), ("\0\x01\x02\x03\xff\xfe\x00"):rep(10) }
local all_ok = true
for _, c in ipairs(inputs) do
    local got = sha.sha256(c)
    local ok = got == ref[#c]
    if not ok then all_ok = false end
    print(string.format("len=%3d  ok=%s\n  got=%s\n  exp=%s", #c, ok and "YES" or "NO", got, ref[#c]))
end

-- HMAC-SHA256 official vector (RFC 4231): hmac("key", "the quick brown fox...")
local hm = sha.hmac_sha256("key", "the quick brown fox jumps over the lazy dog")
local hm_ok = hm == "7486bd70e6574a2755b8ea4daeb283de65da7e6b055453807d1572d72599cfef"
if not hm_ok then all_ok = false end
print()
print("hmac(key,fox) ok=" .. tostring(hm_ok) .. "  got=" .. hm)

-- imgproxy signature: hmac(secret_key, salt..path)
local function hex2bytes(hex)
    local t = {}
    for h in hex:gmatch("([0-9a-fA-F][0-9a-fA-F])") do t[#t+1] = string.char(tonumber(h,16)) end
    return table.concat(t)
end
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function hex_to_b64url(hex)
    local bytes = {}
    for h in hex:gmatch("([0-9a-fA-F][0-9a-fA-F])") do bytes[#bytes+1] = tonumber(h,16) end
    local n = #bytes; local out = {}; local i = 1
    while i <= n - 2 do
        local a,b,c = bytes[i],bytes[i+1],bytes[i+2]
        out[#out+1] = b64chars:sub(bit.rshift(a,2)+1,bit.rshift(a,2)+1)
        local s2 = bit.bor(bit.lshift(bit.band(a,3),4),bit.rshift(b,4))
        out[#out+1] = b64chars:sub(s2+1,s2+1)
        local s3 = bit.bor(bit.lshift(bit.band(b,15),2),bit.rshift(c,6))
        out[#out+1] = b64chars:sub(s3+1,s3+1)
        out[#out+1] = b64chars:sub(bit.band(c,63)+1,bit.band(c,63)+1)
        i = i + 3
    end
    if n % 3 == 2 then
        local a,b = bytes[n-1],bytes[n]
        out[#out+1] = b64chars:sub(bit.rshift(a,2)+1,bit.rshift(a,2)+1)
        local s2 = bit.bor(bit.lshift(bit.band(a,3),4),bit.rshift(b,4))
        out[#out+1] = b64chars:sub(s2+1,s2+1)
        out[#out+1] = b64chars:sub(bit.lshift(bit.band(b,15),2)+1,bit.lshift(bit.band(b,15),2)+1)
    elseif n % 3 == 1 then
        local a = bytes[n]
        out[#out+1] = b64chars:sub(bit.rshift(a,2)+1,bit.rshift(a,2)+1)
        out[#out+1] = b64chars:sub(bit.lshift(bit.band(a,3),4)+1,bit.lshift(bit.band(a,3),4)+1)
    end
    return table.concat(out)
end
local KEY = "be12eaea1dce00a71da2145ae8002145291d4cd4c038f52177fea1b8e98c3398"
local SALT = "a5d933a0edf681c43bebda1d21f3096da067ecb8dbbe26ba36feb88c8937b531"
local key = hex2bytes(KEY); local salt = hex2bytes(SALT)
local path = "/rs:fill:100:100:1/plain/https://www.w3school.com.cn/i/ui/weixin-2.png"
local mac = sha.hmac_sha256(key, salt .. path)
local sig = hex_to_b64url(mac)
local img_ok = sig == "HGng7EidDAQnZtXdINxI-Ur3zu625j_wmpdoF8V5lE4"
if not img_ok then all_ok = false end
print()
print("imgproxy sig ok=" .. tostring(img_ok) .. "  got=" .. sig)

print()
print(all_ok and "ALL TESTS PASS" or "SOME TESTS FAILED")
