-- Test security.sign_path via resty.bat, prints JSON-ish output.
-- env: IMGPROXY_SECRET_KEY, IMGPROXY_SECRET_SALT
local security = require("image_service.security")
local config = require("image_service.config")

print("secret_key=" .. config.secret_key)
print("secret_salt=" .. config.secret_salt)

local paths = {
    "/asd",
    "asd",
    "/resize/w:100/h:100/f:jpg/q:80/some-image.jpg",
    "/process/resize/to:w/100/to:h/100/https://example.com/a.jpg",
}

for _, p in ipairs(paths) do
    local sig, err = security.sign_path(p)
    if err then
        print("ERR path=" .. p .. " err=" .. err)
    else
        print("SIG\t" .. p .. "\t" .. sig)
    end
end

-- also test verify_source_url
local cases = {
    "https://example.com/a.jpg",
    "http://example.com/a.jpg",
    "ftp://example.com/a.jpg",
    "https://127.0.0.1/a.jpg",
    "https://169.254.169.254/latest/meta-data/",
    "not a url",
}
print("--- verify_source_url ---")
for _, c in ipairs(cases) do
    local ok, url, err = security.verify_source_url(c)
    print("VSR\t" .. c .. "\tok=" .. tostring(ok) .. "\terr=" .. tostring(err))
end
