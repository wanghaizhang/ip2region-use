-- ============================================================================
-- http_client.lua : minimal HTTP client over ngx.socket.tcp
-- ============================================================================
-- A dependency-free HTTP/1.1 client for talking to the internal imgproxy.
-- Supports GET with a body-less request and reading a response with a known or
-- chunked transfer encoding. Enough for imgproxy's /process endpoint.
-- ----------------------------------------------------------------------------

local M = {}

-- Split a URL "http://host:port/path" into host, port, path.
local function parse_url(url)
    local host, port, path = url:match("^https?://([^:/]+):(%d+)(.*)")
    if host then
        return host, tonumber(port), path or "/"
    end
    local h, p = url:match("^https?://([^:/]+)(.*)")
    return h, 80, p or "/"
end

-- Perform a GET request and return (status, headers, body).
-- Returns (nil, error) on failure.
function M.get(url, opts)
    opts = opts or {}
    local timeout_ms = opts.timeout_ms or 30000
    local host, port, path = parse_url(url)

    local sock, err = ngx.socket.tcp()
    if not sock then return nil, "socket create: " .. tostring(err) end
    sock:settimeout(timeout_ms)

    local ok, err = sock:connect(host, port)
    if not ok then sock:close(); return nil, "connect: " .. tostring(err) end
    -- NOTE: setoption requires the socket to be connected first; the ngx
    -- socket FFI ctx is only created on connect, so calling setoption
    -- before connect raises "socket is never created nor connected".
    sock:setoption("keepalive", true)

    local headers = opts.headers or {}
    local lines = {
        "GET " .. path .. " HTTP/1.1",
        "Host: " .. host,
        "Connection: close",
    }
    for k, v in ipairs(headers) do
        lines[#lines + 1] = k .. ": " .. v
    end
    for k, v in pairs(headers) do
        if type(v) == "string" then
            lines[#lines + 1] = k .. ": " .. v
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""

    local sent, err = sock:send(table.concat(lines, "\r\n"))
    if not sent then sock:close(); return nil, "send: " .. tostring(err) end

    local reader = ngx.socket.tcp
    local resp_reader = sock

    -- read status line (ngx cosocket reads a line via receive("*l"))
    local status_line, err = resp_reader:receive("*l")
    if not status_line then sock:close(); return nil, "status line: " .. tostring(err) end
    local status = status_line:match("(%d+)")
    if not status then sock:close(); return nil, "bad status line" end
    status = tonumber(status)

    -- read headers
    local hdrs = {}
    local ctype = "application/octet-stream"
    local content_length = 0
    local transfer_encoding = ""
    while true do
        local line, e = resp_reader:receive("*l")
        if not line then break end
        if line == "" then break end
        local key, val = line:match("^([^:]+):%s*(.*)")
        if key then
            key = key:lower()
            if key == "content-type" then ctype = val end
            if key == "content-length" then content_length = tonumber(val) or 0 end
            if key == "transfer-encoding" then transfer_encoding = val:lower() end
            hdrs[key] = val
        end
    end

    -- read body (ngx cosocket uses receive("*a") for the whole body)
    local body
    if transfer_encoding:find("chunked", 1, true) then
        body, err = M._read_chunked(resp_reader)
    elseif content_length > 0 then
        body, err = resp_reader:receive(content_length)
    else
        body, err = resp_reader:receive("*a")
    end
    sock:close()
    if not body then return nil, "read body: " .. tostring(err) end
    return status, hdrs, body, ctype
end

-- Read a chunked response body.
function M._read_chunked(sock)
    local chunks = {}
    while true do
        local size_line, err = sock:receive("*l")
        if not size_line then return nil, "chunk size line" end
        -- size_line may have trailing \r\n already stripped by receive("*l")
        local size = tonumber(size_line:match("^([0-9a-fA-F]+)"), 16)
        if not size then return nil, "bad chunk size: " .. tostring(size_line) end
        if size == 0 then
            -- final chunk; read trailing CRLF
            sock:receive("*l")
            break
        end
        local data, err = sock:receive(size)
        if not data then return nil, "chunk data" end
        chunks[#chunks + 1] = data
        -- consume trailing CRLF for this chunk
        sock:receive(2)
    end
    return table.concat(chunks)
end

-- POST a body and return (status, headers, body, ctype).
function M.post(url, body, opts)
    opts = opts or {}
    local timeout_ms = opts.timeout_ms or 30000
    local host, port, path = parse_url(url)

    local sock, err = ngx.socket.tcp()
    if not sock then return nil, "socket create: " .. tostring(err) end
    sock:settimeout(timeout_ms)

    local ok, err = sock:connect(host, port)
    if not ok then sock:close(); return nil, "connect: " .. tostring(err) end

    local headers = {
        { "Content-Type", opts.content_type or "application/octet-stream" },
        { "Content-Length", tostring(#body) },
        { "Host", host },
        { "Connection", "close" },
    }

    local lines = {
        "POST " .. path .. " HTTP/1.1",
    }
    for _, h in ipairs(headers) do
        lines[#lines + 1] = h[1] .. ": " .. h[2]
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""

    local sent, err = sock:send(table.concat(lines, "\r\n") .. body)
    if not sent then sock:close(); return nil, "send: " .. tostring(err) end

    local status_line, err = sock:getline()
    if not status_line then sock:close(); return nil, "status line" end
    local status = tonumber(status_line:match("(%d+)"))
    if not status then sock:close(); return nil, "bad status" end

    local hdrs = {}
    local ctype = "application/octet-stream"
    local content_length = 0
    local transfer_encoding = ""
    while true do
        local line, e = sock:getline()
        if not line or line == "" then break end
        local k, v = line:match("^([^:]+):%s*(.*)")
        if k then
            k = k:lower()
            if k == "content-type" then ctype = v end
            if k == "content-length" then content_length = tonumber(v) or 0 end
            if k == "transfer-encoding" then transfer_encoding = v:lower() end
            hdrs[k] = v
        end
    end

    local body_out
    if transfer_encoding:find("chunked", 1, true) then
        body_out, err = M._read_chunked(sock)
    elseif content_length > 0 then
        body_out, err = sock:read(content_length)
    else
        body_out, err = sock:read("*a")
    end
    sock:close()
    if not body_out then return nil, "read body: " .. tostring(err) end
    return status, hdrs, body_out, ctype
end

return M
