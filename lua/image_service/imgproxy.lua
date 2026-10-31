-- ============================================================================
-- imgproxy.lua : build signed imgproxy requests and call the internal engine
-- ============================================================================
-- imgproxy signs the processed path with HMAC-SHA256(key, salt + path). The
-- signature is embedded in the internal URL so callers cannot tamper with
-- width/height/format/quality. We reproduce the same signing so the internal
-- request is accepted.
-- ----------------------------------------------------------------------------

local config   = require("image_service.config")
local security = require("image_service.security")
local http     = require("image_service.http_client")

local M = {}

-- Build the internal imgproxy URL for the given source + processed path.
-- imgproxy v4 routes are catch-all "/*"; the signature is the first path segment:
--   /{signature}/{processed_path}/{source_url}
-- NOTE: there is NO "/process/" prefix in v4 — the handler is mounted at "/*".
-- Putting "/process/" in front would make imgproxy treat "process" as the
-- signature, which fails verification.
function M.build_url(source_url, processed_path)
    -- imgproxy v4 URL:  /{sig}/{processed_path}/{source}
    -- processed_path is never empty: imgproxy still needs a modifier so it
    -- knows what to do. When the caller supplies no params we default to
    -- "rs:fill:100:100:1".
    -- The source part: "/plain/" tells imgproxy the following address is a
    -- plain http(s):// URL (format 1); without it the source must be
    -- base64-encoded (format 2). Our source is already a decoded real URL, so
    -- we always emit "/plain/".
    -- ngx.var.arg_src arrives percent-encoded (e.g. https%3A%2F%2F...). Decode it
    -- so imgproxy sees a real URL. Temp-file sources (/__imgsrv_tmp/token) have
    -- no %XX sequences, so decode_uri is a no-op for them.
    source_url = ngx.unescape_uri(source_url)
    if processed_path == "" then
        processed_path = "rs:fill:100:100:1"
    end
    local path = "/" .. processed_path .. "/plain/" .. source_url
    local sig = security.sign_path(path)
    if not sig then return nil, "sign failed" end
    -- signature MUST be the first path segment after the port:
    --   http://host:port/{sig}/{processed_path}/{source_url}
    local url = string.format("http://%s:%d/%s%s", config.imgproxy_host, config.imgproxy_port, sig, path)
    return url, sig
end

-- Process an image via imgproxy.
-- source_url: validated source (internal temp URL or allowed HTTPS URL)
-- processed_path: imgproxy params (e.g. "w800/h600/if_webp/q80")
-- Returns (status, body, ctype, error).
function M.process(source_url, processed_path)
    local url, err = M.build_url(source_url, processed_path)
    if not url then return nil, nil, nil, err end

    local status, hdrs, body, ctype = http.get(url, { timeout_ms = config.process_timeout_ms })
    if not status then
        return nil, nil, nil, "imgproxy request failed: " .. tostring(err)
    end
    if status >= 400 then
        -- imgproxy returns error body; surface status without leaking internals
        return status, body, ctype, "imgproxy error status " .. tostring(status)
    end
    return status, body, ctype or "application/octet-stream"
end

-- Fetch image info (dimensions/format) via imgproxy.
-- NOTE: imgproxy v4 has NO dedicated /info endpoint — the router is catch-all
-- "/*", so a bare source URL with a signature just returns the original image
-- (no processing options). There is no JSON info payload anymore.
function M.info(source_url)
    local path = "/" .. source_url
    local sig = security.sign_path(path)
    if not sig then return nil, "sign failed" end
    local url = string.format("http://%s:%d%s", config.imgproxy_host, config.imgproxy_port, path) .. "/" .. sig
    local status, hdrs, body, ctype = http.get(url, { timeout_ms = config.process_timeout_ms })
    if not status then return nil, "imgproxy request failed" end
    if status >= 400 then return nil, "imgproxy error status " .. tostring(status) end
    return body
end

return M
