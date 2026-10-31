-- probe: decode + print forwarded imgproxy URL
ngx.header["Content-Type"] = "text/plain"
local imgproxy = require("image_service.imgproxy")
local source = ngx.var.arg_src or "https://www.w3school.com.cn/i/ui/weixin-2.png"
local processed = ngx.var.arg_proc or ""
local ok, dec = pcall(function() return ngx.unescape_uri(source) end)
ngx.say("raw_arg_src     = " .. source)
ngx.say("decode_uri(src) = " .. (ok and dec or ("ERR:" .. tostring(dec))))
ngx.say("processed       = " .. processed)
local url, sig = imgproxy.build_url(source, processed)
ngx.say("signature       = " .. sig)
ngx.say("FORWARDED_URL   = " .. url)
