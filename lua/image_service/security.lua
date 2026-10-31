-- ============================================================================
-- security.lua : auth, rate limiting, SSRF protection, source verification
-- ============================================================================
-- Shared helpers used by image_api. All public entry points should call the
-- relevant guard before doing any heavy work.
-- ----------------------------------------------------------------------------

local config = require("image_service.config")
local http = require("image_service.http_client")
local sha = require("image_service.sha256")

local M = {}

-- Generate a URL-safe random token for temp file names.
function M.random_token(len)
    local resty_random = require("resty.random")
    local ok, raw = pcall(resty_random.bytes, len, { urlsafe = true })
    if ok and raw then
        return raw:gsub("[%/+%=]", ""):sub(1, len)
    end
    return os.date("%Y%m%d%H%M%S") .. tostring(math.random())
end

-- ---- HMAC signing helpers -------------------------------------------------
-- imgproxy signs the processed path with HMAC-SHA256(key, salt + path) and
-- verifies the signature with base64.RawURLEncoding (URL-safe, no padding).
-- We reproduce the same HMAC and emit URL-safe base64 so imgproxy accepts it.
-- imgproxy's signatureFor() prepends "/" to the path when it does not already
-- start with one, so we mirror that here to keep the signed bytes identical.
--
-- NOTE: secret_key / secret_salt are hex-encoded (see config.lua). The HMAC
-- key bytes MUST be the decoded raw bytes, not the hex string itself.
-- This OpenResty build has NO ngx.sha256_hmac builtin (returns nil), so we use
-- the pure-Lua sha256.lua module's hmac_sha256 instead. It returns a hex string.
local function hex2bytes(hex)
    local t = {}
    for h in hex:gmatch("([0-9a-fA-F][0-9a-fA-F])") do
        t[#t + 1] = string.char(tonumber(h, 16))
    end
    return table.concat(t)
end

-- hex string -> base64.RawURLEncoding (URL-safe, no padding), as imgproxy decodes.
local function hex_to_b64url(hex)
    local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    local bytes = {}
    for h in hex:gmatch("([0-9a-fA-F][0-9a-fA-F])") do
        bytes[#bytes + 1] = tonumber(h, 16)
    end
    local n = #bytes
    local out = {}
    local i = 1
    while i <= n - 2 do
        local a, b, c = bytes[i], bytes[i+1], bytes[i+2]
        out[#out+1] = b64chars:sub(bit.rshift(a, 2)+1, bit.rshift(a, 2)+1)
        local mid = bit.bor(bit.lshift(bit.band(a, 3), 4), bit.rshift(b, 4))
        out[#out+1] = b64chars:sub(mid+1, mid+1)
        local third = bit.bor(bit.lshift(bit.band(b, 15), 2), bit.rshift(c, 6))
        out[#out+1] = b64chars:sub(third+1, third+1)
        out[#out+1] = b64chars:sub(bit.band(c, 63)+1, bit.band(c, 63)+1)
        i = i + 3
    end
    if n % 3 == 2 then
        local a, b = bytes[n-1], bytes[n]
        out[#out+1] = b64chars:sub(bit.rshift(a, 2)+1, bit.rshift(a, 2)+1)
        local mid = bit.bor(bit.lshift(bit.band(a, 3), 4), bit.rshift(b, 4))
        out[#out+1] = b64chars:sub(mid+1, mid+1)
        out[#out+1] = b64chars:sub(bit.lshift(bit.band(b, 15), 2)+1, bit.lshift(bit.band(b, 15), 2)+1)
    elseif n % 3 == 1 then
        local a = bytes[n]
        out[#out+1] = b64chars:sub(bit.rshift(a, 2)+1, bit.rshift(a, 2)+1)
        out[#out+1] = b64chars:sub(bit.lshift(bit.band(a, 3), 4)+1, bit.lshift(bit.band(a, 3), 4)+1)
    end
    return table.concat(out)
end

function M.sign_path(path)
    local key = hex2bytes(config.secret_key)
    local salt = hex2bytes(config.secret_salt)
    local message = salt
    if path:sub(1, 1) ~= "/" then
        message = message .. "/"
    end
    local hex_sig = sha.hmac_sha256(key, message .. path)
    if not hex_sig then return nil, "sha256_hmac failed" end
    return hex_to_b64url(hex_sig)
end

-- ---- rate limiting (leaky bucket per client IP) ---------------------------
-- Uses ngx.shared.DICT as a token bucket. Returns (ok, error_message).
local rate_dict
local function rate_dict()
    if not rate_dict then
        rate_dict = ngx.shared.IMAGE_RATE
    end
    return rate_dict
end

function M.check_rate_limit(client_ip)
    local dict = rate_dict()
    if not dict then
        -- dict not configured; skip limiting rather than fail the request
        return true
    end
    local now = ngx.time()
    local key = "rate:" .. client_ip
    local info, err = dict:get(key)
    if not info then
        -- first hit: allow, seed the bucket
        dict:set(key, {tokens = config.rate_limit_burst, ts = now}, 60)
        return true
    end
    local tokens = info.tokens
    local elapsed = now - info.ts
    if elapsed > 0 then
        tokens = tokens + elapsed * config.rate_limit_rps
        if tokens > config.rate_limit_burst then tokens = config.rate_limit_burst end
    end
    if tokens < 1 then
        return false, "rate limit exceeded"
    end
    dict:set(key, {tokens = tokens - 1, ts = now}, 60)
    return true
end

-- ---- SSRF / source verification -------------------------------------------
-- Validate a raw URL string. Returns (ok, normalized_url, error).
-- Rejects non-HTTP(S) schemes, private/loopback/link-local/cloud-metadata IPs.
local function ip_in_ranges(ip)
    -- loopback
    if ip:match("^127%.") or ip == "::1" or ip == "0.0.0.0" then return true end
    -- private 10/8, 172.16/12, 192.168/16
    if ip:match("^10%.") then return true end
    if ip:match("^192%.168%.") then return true end
    if ip:match("^172%(1[6-9]|2%d|3[01])%.") then return true end
    -- link-local 169.254/16
    if ip:match("^169%.254%.") then return true end
    -- 127.x handled above; 100.64.x CGNAT; 169.254 handled above
    if ip:match("^100%.64%.") then return true end
    return false
end

function M.verify_source_url(raw_url)
    local url = raw_url:gsub("^%s+", ""):gsub("%s+$", "")
    local scheme, host, rest = url:match("^([a-zA-Z][a-zA-Z0-9+.-]*)://([^:/?#]+)(.*)")
    if not scheme then
        return nil, nil, "malformed url"
    end
    -- only http/https
    if scheme:lower() ~= "http" and scheme:lower() ~= "https" then
        return nil, nil, "scheme not allowed: " .. scheme
    end
    -- reject obvious private hosts quickly (real check needs DNS)
    if host:match("^%d+%.%d+%.%d+%.%d+$") then
        if ip_in_ranges(host) then
            return nil, nil, "private/loopback source address not allowed"
        end
    end
    if host == "metadata.google.internal" or host:match("^metadata%.") then
        return nil, nil, "cloud metadata source not allowed"
    end
    -- host whitelist (trusted-domain mode)
    if #config.allowed_sources > 0 then
        local ok = false
        for _, h in ipairs(config.allowed_sources) do
            if host == h or host:match("^" .. h:gsub("%.", "%%") .. "$") then
                ok = true; break
            end
        end
        if not ok then
            return nil, nil, "source host not in allowlist: " .. host
        end
    end
    return true, url
end

-- Verify the resolved IP of a hostname to mitigate DNS rebinding. Callers that
-- fetch the source directly (not via imgproxy) should use this. imgproxy has
-- its own SSRF protection (ALLOW_*_SOURCE_ADDRESSES). We pass the hostname only
-- and rely on imgproxy to reject private targets.
function M.check_allowed_host(host)
    if #config.allowed_sources == 0 then return true end
    for _, h in ipairs(config.allowed_sources) do
        if host == h or host:match("^" .. h:gsub("%.", "%%") .. "$") then
            return true
        end
    end
    return false
end

return M
