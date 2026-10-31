-- ============================================================================
-- image_api.lua : unified entry point & request dispatcher
-- ============================================================================
-- Routes:
--   GET  /api/v1/image              -> URL input, binary output
--   GET  /api/v1/style/:style       -> preset style, binary output
--   GET  /api/v1/info               -> image info (dimensions/format)
--   POST /api/v1/image:process      -> base64 / multipart input, JSON output
--
-- The module validates every request against a parameter whitelist, builds a
-- signed imgproxy request, and returns the processed image. It never exposes
-- raw imgproxy parameters or internal paths to clients.
-- ----------------------------------------------------------------------------

local config   = require("image_service.config")
local security = require("image_service.security")
local input    = require("image_service.input")
local ops      = require("image_service.operations")
local imgproxy = require("image_service.imgproxy")
local output   = require("image_service.output")
local meta     = require("image_service.image_meta")

local M = {}

-- ---- helpers --------------------------------------------------------------
local function set_cors()
    ngx.header["Access-Control-Allow-Origin"] = config.cors_allow_origin
    ngx.header["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    ngx.header["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
end

local function cors_preflight()
    set_cors()
    ngx.status = 204
    ngx.say("")
    return true
end

-- ---- GET: /api/v1/image (URL input) ---------------------------------------
function M.handle_url()
    if ngx.var.arg_src == nil then
        return output.send_error(400, "missing 'src' parameter")
    end
    local ok, url, err = security.verify_source_url(ngx.var.arg_src)
    if not ok then
        return output.send_error(400, err)
    end

    -- Build imgproxy v4 processing options from whitelisted query args.
    -- v4 joins "key:value" segments with "/". Only present params are emitted;
    -- empty segments are skipped. See reference doc for full key list.
    local parts = {}
    local function add_int(name, maxv)
        local v = ngx.var["arg_" .. name]
        if v then
            local n = tonumber(v)
            if n and n > 0 and n <= (maxv or config.max_output_dimension) then
                return n
            end
        end
    end
    local function add_int_range(name, minv, maxv)
        local v = ngx.var["arg_" .. name]
        if v then
            local n = tonumber(v)
            if n and n >= minv and n <= maxv then
                return n
            end
        end
    end

    -- ---- resize / dimensions ------------------------------------------------
    local w = add_int("w")
    local h = add_int("h")
    if w or h then
        local rt = "fill"
        local fit = ngx.var.arg_fit
        if fit == "contain" then rt = "fit" end
        parts[#parts + 1] = "rs:" .. rt .. ":" .. (w or 0) .. ":" .. (h or 0) .. ":1"
    end
    local min_w = add_int("min_w")
    local min_h = add_int("min_h")
    if min_w or min_h then
        parts[#parts + 1] = "min-width:" .. (min_w or 0) .. "/min-height:" .. (min_h or 0)
    end
    local gravity = ngx.var.arg_gravity
    if gravity then parts[#parts + 1] = "gravity:" .. gravity end

    -- ---- crop ---------------------------------------------------------------
    local crop_w = add_int("crop_w")
    local crop_h = add_int("crop_h")
    if crop_w and crop_h then
        local cg = ngx.var.arg_crop_gravity or gravity
        parts[#parts + 1] = "crop:" .. crop_w .. ":" .. crop_h .. ":" .. (cg or "ce")
    end

    -- ---- output format / quality --------------------------------------------
    local q = add_int_range("q", 1, 100)
    if q then parts[#parts + 1] = "quality:" .. q end
    local fmt = ngx.var.arg_format
    if fmt then
        local map = { jpg = "format:jpg", jpeg = "format:jpg", png = "format:png", webp = "format:webp", gif = "format:gif", avif = "format:avif" }
        if map[fmt] then parts[#parts + 1] = map[fmt] end
    end

    -- ---- image adjustments --------------------------------------------------
    local rotate = add_int_range("rotate", 0, 360)
    if rotate then parts[#parts + 1] = "rotate:" .. rotate end
    local auto_rotate = ngx.var.arg_auto_rotate
    if auto_rotate and auto_rotate ~= "0" then parts[#parts + 1] = "auto_rotate:1" end
    local flip = ngx.var.arg_flip
    if flip == "1" then parts[#parts + 1] = "flip:1"
    elseif flip == "0" then parts[#parts + 1] = "flip:0" end
    local flip_v = ngx.var.arg_flip_v
    if flip_v == "1" then parts[#parts + 1] = "flip:0:1" end
    local blur = add_int_range("blur", 1, 1000)
    if blur then parts[#parts + 1] = "blur:" .. blur end
    local sharpen = add_int_range("sharpen", 1, 1000)
    if sharpen then parts[#parts + 1] = "sharpen:" .. sharpen end
    local pixelate = add_int_range("pixelate", 1, 10000)
    if pixelate then parts[#parts + 1] = "pixelate:" .. pixelate end

    -- ---- extend / padding / trim --------------------------------------------
    local bg = ngx.var.arg_background
    if bg then parts[#parts + 1] = "background:" .. bg end
    local dpr = add_int("dpr")
    if dpr then parts[#parts + 1] = "dpr:" .. dpr end
    local padding = ngx.var.arg_padding
    if padding then parts[#parts + 1] = "padding:" .. padding end
    local trim_thresh = add_int_range("trim", 0, 255)
    if trim_thresh then
        local trim_color = ngx.var.arg_trim_color
        parts[#parts + 1] = "trim:" .. trim_thresh .. (trim_color and (":" .. trim_color) or "")
    end

    -- ---- watermark / metadata -----------------------------------------------
    local wm = add_int_range("watermark", 0, 100)
    if wm then parts[#parts + 1] = "watermark:0." .. string.format("%02d", wm) end
    local strip_meta = ngx.var.arg_strip_metadata
    if strip_meta and strip_meta ~= "0" then parts[#parts + 1] = "strip_metadata:1" end
    local keep_cr = ngx.var.arg_keep_copyright
    if keep_cr and keep_cr ~= "0" then parts[#parts + 1] = "keep_copyright:1" end
    local preserve_hdr = ngx.var.arg_preserve_hdr
    if preserve_hdr and preserve_hdr ~= "0" then parts[#parts + 1] = "preserve_hdr:1" end

    local processed = table.concat(parts, "/")
    local status, body, ctype, ierr = imgproxy.process(url, processed)
    if not status then
        return output.send_error(502, ierr)
    end
    if status >= 400 then
        return output.send_error(502, "imgproxy processing failed")
    end
    output.send_binary(body, ctype)
end

-- ---- GET: /api/v1/style/:style --------------------------------------------
function M.handle_style(style_name)
    local style_ops = ops.preset(style_name)
    if not style_ops then
        return output.send_error(404, "unknown style: " .. style_name)
    end
    if ngx.var.arg_src == nil then
        return output.send_error(400, "missing 'src' parameter")
    end
    local ok, url, err = security.verify_source_url(ngx.var.arg_src)
    if not ok then
        return output.send_error(400, err)
    end
    local processed, err = ops.build(nil, style_ops)
    if not processed then
        return output.send_error(400, err)
    end
    local status, body, ctype, ierr = imgproxy.process(url, processed)
    if not status then return output.send_error(502, ierr) end
    if status >= 400 then return output.send_error(502, "imgproxy processing failed") end
    output.send_binary(body, ctype)
end

-- ---- GET: /api/v1/info ----------------------------------------------------
function M.handle_info()
    if ngx.var.arg_src == nil then
        return output.send_error(400, "missing 'src' parameter")
    end
    local ok, url, err = security.verify_source_url(ngx.var.arg_src)
    if not ok then
        return output.send_error(400, err)
    end
    local body, ierr = imgproxy.info(url)
    if not body then
        return output.send_error(502, ierr)
    end
    local cjson = require("cjson")
    local obj = cjson.decode(body)
    obj.success = true
    ngx.status = 200
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.say(cjson.encode(obj))
end

-- ---- POST: /api/v1/image:process (base64 / multipart) ---------------------
function M.handle_process()
    ngx.req.read_body()
    local ct = ngx.var.content_type or ""

    if ct:find("multipart/form-data", 1, true) then
        return M.handle_multipart()
    end

    local body = ngx.req.get_body_data()
    if not body then
        return output.send_error(400, "empty request body")
    end
    local cjson = require("cjson")
    local ok, req = pcall(cjson.decode, body)
    if not ok then
        return output.send_error(400, "invalid JSON: " .. tostring(req))
    end

    -- input type
    local input_type = req.input and req.input.type or "base64"
    local operations = req.operations
    local out_type = (req.output and req.output.type) or "base64"

    local source_url, mime, token, ierr
    if input_type == "base64" then
        source_url, mime, token, ierr = input.handle_base64(req.input and req.input.data)
    elseif input_type == "data-url" then
        source_url, mime, token, ierr = input.handle_base64(req.input and req.input.data)
    else
        return output.send_error(400, "unsupported input type: " .. tostring(input_type))
    end

    -- cleanup temp file on error
    local function cleanup()
        if token then input.cleanup_temp(token) end
    end

    if not source_url then
        cleanup()
        return output.send_error(400, ierr)
    end

    local processed, err = ops.build(nil, operations)
    if not processed then
        cleanup()
        return output.send_error(400, err)
    end

    local status, img_body, ctype, ierr = imgproxy.process(source_url, processed)
    if not status then
        cleanup()
        return output.send_error(502, ierr)
    end
    if status >= 400 then
        cleanup()
        return output.send_error(502, "imgproxy processing failed")
    end

    cleanup()

    if out_type == "base64" then
        output.send_base64(img_body, ctype)
    elseif out_type == "url" then
        output.send_url(nil, { format = ctype })
    else
        -- default binary is not ideal for JSON POST; still support it
        output.send_binary(img_body, ctype)
    end
end

-- ---- POST: multipart ------------------------------------------------------
function M.handle_multipart()
    local source_url, mime, token, ierr = input.handle_multipart("file")
    local function cleanup()
        if token then input.cleanup_temp(token) end
    end
    if not source_url then
        cleanup()
        return output.send_error(400, ierr)
    end

    -- operations come from the "operations" query/form field (JSON string)
    local ops_raw = ngx.var.arg_operations
    local operations
    if ops_raw then
        local cjson = require("cjson")
        local ok, decoded = pcall(cjson.decode, ops_raw)
        if ok then operations = decoded end
    end

    local processed, err = ops.build(nil, operations)
    if not processed then
        cleanup()
        return output.send_error(400, err or "invalid operations")
    end

    local out_type = ngx.var.arg_output or "base64"

    local status, img_body, ctype, ierr = imgproxy.process(source_url, processed)
    if not status then
        cleanup()
        return output.send_error(502, ierr)
    end
    if status >= 400 then
        cleanup()
        return output.send_error(502, "imgproxy processing failed")
    end
    cleanup()

    if out_type == "base64" then
        output.send_base64(img_body, ctype)
    elseif out_type == "url" then
        output.send_url(nil, { format = ctype })
    else
        output.send_binary(img_body, ctype)
    end
end

-- ---- router ---------------------------------------------------------------
function M.route()
    set_cors()

    local method = ngx.req.get_method()
    if method == "OPTIONS" then
        return cors_preflight()
    end

    local uri = ngx.var.uri
    if method == "GET" then
        if uri == "/api/v1/image" then
            return M.handle_url()
        elseif uri:match("^/api/v1/style/.+$") then
            local style = uri:match("^/api/v1/style/(.+)$")
            return M.handle_style(style)
        elseif uri == "/api/v1/info" then
            return M.handle_info()
        end
    elseif method == "POST" then
        if uri == "/api/v1/image:process" then
            return M.handle_process()
        end
    end

    output.send_error(404, "unknown endpoint: " .. method .. " " .. uri)
end

return M
