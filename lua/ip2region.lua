-- ============================================================================
-- ip2region searcher for OpenResty (LuaJIT / Lua 5.1)
-- ============================================================================
-- The upstream ip2region lua binding (Apache-2.0) targets Lua 5.3/5.4 and uses
-- native bitwise operators (`<<`, `>>`, `&`, `|`). OpenResty ships LuaJIT (a
-- Lua 5.1 dialect) which has NO such operators; it provides the `bit` library
-- instead. This file rewrites the upstream implementation to use `bit.*` so it
-- runs directly under OpenResty without any compilation.
--
-- Usage under OpenResty:
--   init_worker_by_lua_block {
--       local ip2region = require("ip2region")
--       local err = ip2region.init("/abs/path/to/data/ip2region_v4.xdb")
--       if err then ngx.log(ngx.ERR, "ip2region init failed: ", err) end
--   }
--   location /ip2region/api/ip/ {
--       content_by_lua_block {
--           local ip2region = require("ip2region")
--           local region, err = ip2region.query(ngx.var.remote_addr)
--           ...
--       }
--   }
-- Set lua_package_path to include this dir, e.g.:
--   lua_package_path "/path/to/lua/ip2region.lua;";
-- ============================================================================

local bit = require("bit")
local bor    = bit.bor
local band   = bit.band
local lshift = bit.lshift
local rshift = bit.rshift

local header_info_length = 256
local vector_index_cols  = 256
local vector_index_size  = 8
local vector_index_length = 524288  -- 256 * 256 * 8

local xdb_structure_20 = 2
local xdb_structure_30 = 3
local xdb_ipv4_id      = 4
local xdb_ipv6_id      = 6

-- ---- version definitions --------------------------------------------------
local Version = {}
Version.__tostring = function(t)
    return string.format("{id:%d, name:%s, bytes:%d, index_size:%d}",
        t.id, t.name, t.bytes, t.index_size)
end

local IPv4 = {
    id = xdb_ipv4_id,
    name = "IPv4",
    bytes = 4,
    index_size = 14,  -- 4 + 4 + 2 + 4
    ip_sub_compare = function(ip1, buff, offset)
        -- ip1: big-endian bytes parsed from input; buff: little-endian from xdb
        local l = #ip1
        local j = offset + l - 1
        for i = 1, l, 1 do
            local i1 = string.byte(ip1, i)
            local i2 = string.byte(buff, j)
            if i1 > i2 then return 1 end
            if i1 < i2 then return -1 end
            j = j - 1
        end
        return 0
    end,
}

local IPv6 = {
    id = xdb_ipv6_id,
    name = "IPv6",
    bytes = 16,
    index_size = 38,  -- 16 + 16 + 2 + 4
    ip_sub_compare = function(ip1, buff, offset)
        local ip2 = string.sub(buff, offset, offset + #ip1 - 1)
        if ip1 > ip2 then return 1
        elseif ip1 < ip2 then return -1
        else return 0 end
    end,
}

setmetatable(IPv4, Version)
setmetatable(IPv6, Version)

-- ---- internal decode helpers ---------------------------------------------
local function le_get_uint32(buff, idx)
    return bor(
        string.byte(buff, idx),
        lshift(string.byte(buff, idx + 1), 8),
        lshift(string.byte(buff, idx + 2), 16),
        lshift(string.byte(buff, idx + 3), 24)
    )
end

local function le_get_uint16(buff, idx)
    return bor(string.byte(buff, idx), lshift(string.byte(buff, idx + 1), 8))
end

-- ---- static helpers (file access, header, index, content, verify) ---------
local function open_file(db_path, mode)
    local t = type(db_path)
    local handle, _closer
    if t == "userdata" then
        handle = db_path
        _closer = function() end
    elseif t == "string" then
        handle = io.open(db_path, mode)
        if handle == nil then
            return nil, nil, string.format("failed to open xdb file `%s`", db_path)
        end
        _closer = function() handle:close() end
    end
    return handle, _closer, nil
end

local function load_header(handle)
    local c = handle:read(header_info_length)
    if c == nil then
        return nil, string.format("failed to read %d bytes", header_info_length)
    end
    return {
        version = le_get_uint16(c, 1),
        index_policy = le_get_uint16(c, 3),
        created_at = le_get_uint32(c, 5),
        start_index_ptr = le_get_uint32(c, 9),
        end_index_ptr = le_get_uint32(c, 13),
        ip_version = le_get_uint16(c, 17),
        runtime_ptr_bytes = le_get_uint16(c, 19),
        raw_data = c,
    }, nil
end

local function load_vector_index(db_path)
    local handle, closer, err = open_file(db_path, "rb")
    if err ~= nil then return nil, err end
    local r = handle:seek("set", header_info_length)
    if r == nil then closer(); return nil, string.format("failed to seek to %d", header_info_length) end
    local c = handle:read(vector_index_length)
    if c == nil then closer(); return nil, string.format("failed to read %d bytes", vector_index_length) end
    closer()
    return c, nil
end

local function load_content(db_path)
    local handle, closer, err = open_file(db_path, "rb")
    if err ~= nil then return nil, err end
    local c = handle:read("*a")
    if c == nil then closer(); return nil, "failed to read xdb content" end
    closer()
    return c, nil
end

-- Verify the current searcher is compatible with the xdb file. Call ONCE at
-- service start (not per request). Returns nil on success, error string on fail.
local function verify(db_path)
    local handle, closer, err = open_file(db_path, "rb")
    if err ~= nil then return err end
    local header, err = load_header(handle)
    if err ~= nil then closer(); return string.format("failed to load header: %s", err) end
    local runtime_ptr_bytes = 0
    if header.version == xdb_structure_20 then
        runtime_ptr_bytes = 4
    elseif header.version == xdb_structure_30 then
        runtime_ptr_bytes = header.runtime_ptr_bytes
    else
        closer(); return string.format("invalid structure version %d", header.version)
    end
    -- max file size supported = 2^(runtime_ptr_bytes*8) - 1
    -- use ^ (float) to avoid LuaJIT 32-bit shift overflow at 64-bit widths
    local max_file_ptr
    if runtime_ptr_bytes >= 32 then
        max_file_ptr = math.huge
    else
        max_file_ptr = (2 ^ (runtime_ptr_bytes * 8)) - 1
    end
    local file_bytes = handle:seek("end", 0)
    if file_bytes > max_file_ptr then
        closer(); return string.format("xdb file exceeds max supported bytes: %d", max_file_ptr)
    end
    closer()
    return nil
end

-- ---- ip parsing -----------------------------------------------------------
local function split(str, sep)
    local ps, sIndex, length = {}, 1, #str
    while true do
        local mi = string.find(str, sep, sIndex, true)
        if mi == nil then
            table.insert(ps, string.sub(str, sIndex)); break
        end
        if sIndex == mi then table.insert(ps, "")
        else table.insert(ps, string.sub(str, sIndex, mi - 1)) end
        sIndex = mi + 1
    end
    return ps
end

local function _parse_ipv4_addr(v4_str)
    local ps = split(v4_str, ".")
    if #ps ~= 4 then
        return nil, string.format("invalid ipv4 address `%s`", v4_str)
    end
    local bytes = {0, 0, 0, 0}
    for i, s in ipairs(ps) do
        local v = tonumber(s)
        if v == nil then
            return nil, string.format("invalid ipv4 part `%s`, a valid number expected", s)
        end
        if v < 0 or v > 255 then
            return nil, string.format("invalid ipv4 part `%s`, should be 0..255", s)
        end
        bytes[i] = v
    end
    return string.char(table.unpack(bytes)), nil
end

local function _ipv4_to_string(ip_bytes)
    return string.format("%d.%d.%d.%d",
        string.byte(ip_bytes, 1), string.byte(ip_bytes, 2),
        string.byte(ip_bytes, 3), string.byte(ip_bytes, 4)), nil
end

local function parse_ip(ip_str, version)
    if version ~= IPv4 then
        return nil, "IPv6 not enabled in this build (require IPv4 version)"
    end
    return _parse_ipv4_addr(ip_str)
end

local function ip_to_string(ip_bytes, version)
    if version ~= IPv4 then
        return nil, "IPv6 not enabled in this build"
    end
    return _ipv4_to_string(ip_bytes)
end

-- ---- searcher class -------------------------------------------------------
local xdb = {}
xdb.__index = xdb

local function new_base(version, db_path, v_index, c_buffer)
    local obj = setmetatable({}, xdb)
    obj.version = version
    if c_buffer ~= nil then
        obj.io_count = 0
        obj.vector_index = nil
        obj.content_buff = c_buffer
    else
        obj.io_count = 0
        obj.vector_index = v_index
        obj.handle = io.open(db_path, "r")
        if obj.handle == nil then
            return nil, string.format("failed to open xdb file `%s`", db_path)
        end
    end
    return obj, nil
end

function xdb.new_with_file_only(version, db_path)
    return new_base(version, db_path, nil, nil)
end

function xdb.new_with_vector_index(version, db_path, v_index)
    return new_base(version, db_path, v_index, nil)
end

function xdb.new_with_buffer(version, c_buffer)
    return new_base(version, nil, nil, c_buffer)
end

function xdb:search_by_string(ip_str)
    local ip_bytes, err = parse_ip(ip_str, self.version)
    if err ~= nil then
        return "", string.format("failed to parse string ip `%s`: %s", ip_str, err)
    end
    return self:search(ip_bytes)
end

function xdb:search(ip_bytes)
    if type(ip_bytes) ~= "string" then
        return "", string.format("invalid bytes ip `%s`", ip_bytes)
    end
    local version = self.version
    if #ip_bytes ~= version.bytes then
        return "", string.format("invalid ip address `%s` (%s expected)",
            ip_to_string(ip_bytes, version), version.name)
    end

    self.io_count = 0
    local vector_index = self.vector_index
    local content_buff = self.content_buff
    local read_data = self.read

    local il0 = band(string.byte(ip_bytes, 1), 0xFF)
    local il1 = band(string.byte(ip_bytes, 2), 0xFF)
    local idx = il0 * vector_index_cols * vector_index_size + il1 * vector_index_size
    local s_ptr, e_ptr = 0, 0
    if vector_index ~= nil then
        s_ptr = le_get_uint32(vector_index, idx + 1)
        e_ptr = le_get_uint32(vector_index, idx + 5)
    elseif content_buff ~= nil then
        s_ptr = le_get_uint32(content_buff, header_info_length + idx + 1)
        e_ptr = le_get_uint32(content_buff, header_info_length + idx + 5)
    else
        local buff, err = read_data(self, header_info_length + idx, vector_index_size)
        if err ~= nil then return "", string.format("read buffer: %s", err) end
        s_ptr = le_get_uint32(buff, 1)
        e_ptr = le_get_uint32(buff, 5)
    end

    if s_ptr == 0 or e_ptr == 0 then
        return "", nil
    end

    local index_size, ip_sub_compare = version.index_size, version.ip_sub_compare
    local bytes = version.bytes
    local d_bytes = lshift(bytes, 1)
    local data_ptr, data_len, p = 0, 0, 0
    local buff, err = nil, nil
    local l, m, h = 0, 0, (e_ptr - s_ptr) / index_size
    while l <= h do
        m = rshift(l + h, 1)
        p = s_ptr + m * index_size
        buff, err = read_data(self, p, index_size)
        if err ~= nil then
            return "", string.format("read segment index at %d", p)
        end
        if ip_sub_compare(ip_bytes, buff, 1) < 0 then
            h = m - 1
        elseif ip_sub_compare(ip_bytes, buff, bytes + 1) > 0 then
            l = m + 1
        else
            data_len = le_get_uint16(buff, d_bytes + 1)
            data_ptr = le_get_uint32(buff, d_bytes + 3)
            break
        end
    end

    if data_len == 0 then
        return "", nil
    end

    buff, err = read_data(self, data_ptr, data_len)
    if err ~= nil then
        return "", string.format("read data at %d:%d", data_ptr, data_len)
    end
    return buff, nil
end

function xdb:read(offset, length)
    local content_buff = self.content_buff
    local handle = self.handle
    if content_buff ~= nil then
        return string.sub(content_buff, offset + 1, offset + length), nil
    end
    local r = handle:seek("set", offset)
    if r == nil then
        return nil, string.format("seek to offset %d", offset)
    end
    self.io_count = self.io_count + 1
    local buff = handle:read(length)
    if buff == nil then
        return nil, string.format("read %d bytes", length)
    end
    return buff, nil
end

function xdb:get_io_count() return self.io_count end

function xdb:close()
    if self.handle ~= nil then self.handle:close() end
end

-- ---- public API -----------------------------------------------------------
local searcher = nil  -- global memory-backed searcher (created by init)

local M = {
    IPv4 = IPv4,
    IPv6 = IPv6,
}

-- init(db_path[, version])
-- Loads the whole xdb into memory ONCE. Call from init_worker_by_lua.
-- Returns the searcher on success, or an error string on failure.
function M.init(db_path, version)
    version = version or M.IPv4
    local content, err = load_content(db_path)
    if err ~= nil then return nil, err end
    local s, err = xdb.new_with_buffer(version, content)
    if err ~= nil then return nil, err end
    searcher = s
    return s
end

-- query(ip_str) -> (region, error)
-- region is "country|region|city|isp|country_code" or "" on not-found.
function M.query(ip_str)
    if searcher == nil then
        return "", "ip2region.init() not called; call it from init_worker_by_lua"
    end
    return searcher:search_by_string(ip_str)
end

-- verify(db_path) -> (nil | error)  -- call once at startup
function M.verify(db_path)
    return verify(db_path)
end

-- advanced: per-request file/vector-index searchers (not memory-backed)
M.new_with_file_only      = xdb.new_with_file_only
M.new_with_vector_index   = xdb.new_with_vector_index
M.new_with_buffer         = xdb.new_with_buffer
M.parse_ip                = parse_ip
M.ip_to_string            = ip_to_string

return M
