-- ============================================================================
-- ip2region_api.lua : helper for OpenResty content_by_lua blocks
-- ============================================================================
-- Given a region string "country|region|city|isp|country_code", emit JSON.
-- Call like:  require("ip2region_api").send(ip, region, err)
-- ----------------------------------------------------------------------------
--   success=true  -> 200 + full JSON
--   success=false -> 400 + error JSON
-- ============================================================================

local function json_escape(s)
    -- minimal escaping for the region fields (may contain Chinese / quotes)
    return s:gsub('"', '\\"'):gsub("\\", "\\\\")
end

local M = {}

function M.send(ip, region, err)
    if err then
        ngx.status = 400
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.say(string.format(
            '{"success":false,"ip":"%s","error":"%s"}',
            json_escape(ip), json_escape(err)))
        return
    end

    if region == "" then
        -- IP valid but not in database
        ngx.status = 200
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.say(string.format(
            '{"success":false,"ip":"%s","error":"ip not found"}',
            json_escape(ip)))
        return
    end

    -- region = "country|region|city|isp|country_code"
    local country, reg, city, isp, cc = region:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")

    ngx.status = 200
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.say(string.format(
        '{"success":true,"ip":"%s","country":"%s","province":"%s","city":"%s","isp":"%s","country_code":"%s"}',
        json_escape(ip),
        json_escape(country or ""),
        json_escape(reg or ""),
        json_escape(city or ""),
        json_escape(isp or ""),
        json_escape(cc or "")))
end

return M
