-- ============================================================================
-- output.lua : emit processed results in the requested form
-- ============================================================================
-- output.type:
--   "binary"  -> raw image bytes with correct Content-Type (default)
--   "base64"  -> JSON {"success":true,"image":{...,"data":"..."}}
--   "url"     -> JSON {"success":true,"image":{"url":"..."}} (for stored results)
-- ----------------------------------------------------------------------------

local M = {}

local function send_json(status, obj)
    local cjson = require("cjson")
    ngx.status = status
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.say(cjson.encode(obj))
end

local function send_error(status, msg)
    send_json(status, { success = false, error = msg })
end

-- Emit a processed image as raw binary.
function M.send_binary(body, ctype)
    ngx.header["Content-Type"] = ctype or "application/octet-stream"
    ngx.header["Cache-Control"] = "public, max-age=86400"
    ngx.say(body)
end

-- Emit a processed image as base64 inside JSON.
function M.send_base64(body, ctype, extra)
    local cjson = require("cjson")
    local b64 = ngx.encode_base64(body)
    -- strip trailing newlines that encode_base64 may add
    b64 = b64:gsub("\n", "")
    local obj = {
        success = true,
        image = {
            format = ctype and ctype:gsub("image/", "") or "octet-stream",
            data = b64,
        },
    }
    if extra then
        for k, v in pairs(extra) do obj.image[k] = v end
    end
    send_json(200, obj)
end

-- Emit a result URL (for stored results).
function M.send_url(url, extra)
    local obj = { success = true, image = { url = url } }
    if extra then for k, v in pairs(extra) do obj.image[k] = v end end
    send_json(200, obj)
end

M.send_error = send_error

return M
