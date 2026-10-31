local ok1, err1 = pcall(function() return require("ffi") end)
print("ffi:", ok1, err1 or "")
local ok2, err2 = pcall(function() return require("resty.core.hash") end)
print("resty.core.hash:", ok2, err2 or "")
