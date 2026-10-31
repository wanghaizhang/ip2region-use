local security = require("image_service.security")
local config = require("image_service.config")
config.secret_key = "imgproxy"
config.secret_salt = "imgproxy"

local function dump(name, ...)
    local args = {...}
    print(name .. " -> n=" .. #args .. " values:")
    for i, v in ipairs(args) do
        print("   [" .. i .. "] type=" .. type(v) .. " val=" .. tostring(v))
    end
end

local s1, e1 = security.sign_path("/asd")
dump("sign_path('/asd')", s1, e1)
