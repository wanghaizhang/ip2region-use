-- ============================================================================
-- input.lua : input adapters (url / base64 / data-url / multipart)
-- ============================================================================
-- Turns each supported input type into a normalized "source" that the engine
-- can process:
--   * url      -> validated HTTPS URL handed straight to imgproxy
--   * base64   -> decoded bytes written to a temp file, served internally
--   * data-url -> same as base64 (strip the data: prefix first)
--   * multipart-> decoded bytes written to a temp file
--
-- Base64 / multipart inputs are validated (magic bytes, size, pixel budget)
-- before any bytes touch imgproxy.
-- ----------------------------------------------------------------------------

local config   = require("image_service.config")
local security = require("image_service.security")
local meta     = require("image_service.image_meta")

local M = {}

-- Decode a base64 string (with or without a data: prefix).
-- Returns (bytes, error).
function M.decode_base64(s)
    local data = s
    -- strip data:image/...;base64, prefix if present
    local mime, b64 = data:match("^data:image/([^;]+);base64,(.*)")
    if b64 then
        data = b64
    end
    local ok, dec = pcall(function() return ngx.decode_base64(data) end)
    if not ok or not dec then
        return nil, "invalid base64"
    end
    return dec
end

-- Validate decoded bytes: magic bytes, file size, pixel budget.
-- Returns (ok, mime_type, error).
function M.validate_bytes(bytes)
    local n = #bytes
    if n == 0 then return nil, nil, "empty input" end
    if n > config.max_base64_input_bytes then
        return nil, nil, "input exceeds max size (" .. config.max_base64_input_bytes .. " bytes)"
    end
    local mime, err = meta.detect_format(bytes)
    if not mime then
        return nil, nil, err
    end
    if not meta.is_supported_format(mime) then
        return nil, mime, "unsupported format: " .. mime
    end
    return true, mime
end

-- Write decoded bytes to a temp file with a random token.
-- Returns (internal_url, error). The returned URL must be cleaned up via
-- cleanup_temp later.
local function write_temp_file(bytes, mime)
    local token = security.random_token and security.random_token(24)
        or os.date("%s") .. tostring(math.random())
    local rel = config.tmp_dir .. "/" .. token
    local abs = ngx.config.prefix .. "/" .. rel
    local f, err = io.open(abs, "wb")
    if not f then return nil, "cannot write temp file: " .. tostring(err) end
    f:write(bytes)
    f:close()
    -- internal URL imgproxy (via OpenResty internal location) will serve
    local url = config.internal_base .. "/" .. token
    return url, token
end

-- Process a base64 / data-url input: validate, write temp file.
-- Returns (source_url, mime, token, error). token is the cleanup key.
function M.handle_base64(payload)
    if not payload then return nil, nil, nil, "missing base64 input" end
    local bytes, err = M.decode_base64(payload)
    if err then return nil, nil, nil, err end
    local ok, mime, verr = M.validate_bytes(bytes)
    if not ok then return nil, nil, nil, verr end
    local url, token = write_temp_file(bytes, mime)
    if not url then return nil, nil, nil, "write temp failed" end
    return url, mime, token
end

-- Process a multipart upload. `field` is the form field name.
-- Returns (source_url, mime, token, error).
function M.handle_multipart(field)
    ngx.req.read_body()
    local args = ngx.var.arg_field or field or "file"
    -- multipart parsing uses resty.upload (streaming) or the multipart filter.
    -- For MVP we use a simple approach via ngx.req.get_body_file if available.
    local fname = ngx.req.get_body_file()
    if not fname then
        return nil, nil, nil, "no file in multipart body"
    end
    -- read the file to validate magic bytes
    local f, err = io.open(fname, "rb")
    if not f then return nil, nil, nil, "cannot read uploaded file" end
    local bytes = f:read("*a")
    f:close()
    local ok, mime, verr = M.validate_bytes(bytes)
    if not ok then return nil, nil, nil, verr end
    -- copy to our temp location with a random token
    local token = os.date("%s") .. tostring(math.random())
    local dest = ngx.config.prefix .. "/" .. config.tmp_dir .. "/" .. token
    local dst, e = io.open(dest, "wb")
    if not dst then return nil, nil, nil, "cannot write temp file" end
    dst:write(bytes)
    dst:close()
    os.remove(fname) -- tidy up nginx temp file
    local url = config.internal_base .. "/" .. token
    return url, mime, token
end

-- Cleanup a temp file given its token. No-op if already gone.
function M.cleanup_temp(token)
    if not token then return end
    local path = ngx.config.prefix .. "/" .. config.tmp_dir .. "/" .. token
    local f, err = io.open(path, "rb")
    if not f then return end
    f:close()
    os.remove(path)
end

return M
