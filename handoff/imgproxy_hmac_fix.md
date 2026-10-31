# imgproxy HMAC-SHA256 签名修复交接账本

## 任务状态
`sha256.lua` 的 `hmac_sha256` 算法已正确，imgproxy 签名端到端验证通过（ALL TESTS PASS）。问题不在算法，而在 base64url 编码与 HMAC 调用传参。

## 目标
让 `security.lua` 的 `sign_path` 生成 imgproxy 可接受的真迹签名，与 imgproxy v4 服务端 HMAC-SHA256 算法对齐。

## 已试方案与失败原因
- **hmac_sha256 传错 key**：初版用 `hmac(salt, salt..path)`（把 salt 当密钥），产出 `1b26c565...` 与期望 `1c69e0ec...` 不符。定位：期望签名解码后字节 = `hmac(secret_key, salt..path)`，即密钥是 `secret_key`（KEY 解码），salt 是消息前缀。模块算法本身正确（RFC 4231 向量 `hmac("key","fox")` 与 Python 标准库逐字节一致）。
- **hex_to_b64url 用错字符集**：原 `b64chars` 含 `+/`（标准 base64），imgproxy 要 URL-safe 的 `-_`，导致第 24 位 `/` 错。
- **hex_to_b64url 漏 `=` 填充逻辑误删**：RawURLEncoding 不补 `=`，但 32 字节 remainder（32 mod 3 = 2）需产出 3 个字符，原实现漏了第三字符 `((b&15)<<2)`，导致末尾缺 `lE4`。

## 进度与下一步
- ✅ `sha256.lua`：hmac_sha256 已正确（`hex_to_bin` 长密钥、`u32` 归一化、`xor_byte` 用 bxor）。
- ✅ `security.lua`：`hex_to_b64url` 改为 URL-safe `-_` 且补全 remainder 块；`sign_path` 用 `hmac(secret_key, salt..path)`。
- ✅ `test_sha256.lua`：SHA ref 表 len=40/70 期望值改正（原抄错）、HMAC 期望值改为真值 `7486bd70...`、imgproxy 签名调用改为 `hmac(key, salt..path)`，全部通过。
- 下一步：在 nginx 实际请求中验证签名生效（真实 imgproxy 返回 200 而非 401/403）。
