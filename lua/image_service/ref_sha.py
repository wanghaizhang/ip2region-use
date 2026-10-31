import hashlib, hmac, base64

cases = ["", "a", "abc", "The quick brown fox jumps over the lazy dog",
  "1234567890123456789012345678901234567890",
  "x"*55, "x"*56, "x"*57, "x"*64, "x"*100,
  ("\x00\x01\x02\x03\xff\xfe\x00")*10]

for c in cases:
    print(f'len={len(c)} sha256={hashlib.sha256(c.encode()).hexdigest()}')

KEY = bytes.fromhex("be12eaea1dce00a71da2145ae8002145291d4cd4c038f52177fea1b8e98c3398")
SALT = bytes.fromhex("a5d933a0edf681c43bebda1d21f3096da067ecb8dbbe26ba36feb88c8937b531")
path = "/rs:fill:100:100:1/plain/https://www.w3school.com.cn/i/ui/weixin-2.png"
mac = hmac.new(KEY, SALT + path.encode(), hashlib.sha256).digest()
sig = base64.urlsafe_b64encode(mac).decode().rstrip("=")
print()
print("imgproxy sig =", sig)
print("expected       = HGng7EidDAQnZtXdINxI-Ur3zu625j_wmpdoF8V5lE4")
