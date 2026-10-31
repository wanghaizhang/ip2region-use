local sha = require("image_service.sha256")
local tests = { "", "a", "abc", ("x"):rep(40), ("x"):rep(55), ("x"):rep(56), ("x"):rep(57), ("x"):rep(64), ("x"):rep(100), ("x"):rep(1000) }
for _, c in ipairs(tests) do
    print(string.format("len=%-6d  %s", #c, sha.sha256(c)))
end
