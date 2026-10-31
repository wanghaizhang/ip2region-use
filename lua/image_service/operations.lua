-- ============================================================================
-- operations.lua : parse & validate the custom operations list, then build an
--                  imgproxy-compatible request path.
-- ============================================================================
-- The API defines its own operation schema (see README). This module validates
-- each operation against a whitelist and translates it into imgproxy URL
-- parameters. It never accepts raw imgproxy parameters from the client.
-- ----------------------------------------------------------------------------

local config = require("image_service.config")

local M = {}

-- Whitelisted operations. Each entry: {field, type, min, max, default}
-- type: "int" | "enum" | "float"
local OP_SCHEMA = {
    resize = {
        width  = { type = "int", min = 1, max = config.max_output_dimension },
        height = { type = "int", min = 1, max = config.max_output_dimension },
        fit    = { type = "enum", values = { "contain", "cover", "fill", "forcescale" } },
    },
    format = { output_format = { type = "enum", values = { "jpeg", "png", "webp", "gif", "avif" } } },
    quality = { value = { type = "int", min = 1, max = 100 } },
    crop = {
        type = { type = "enum", values = { "auto", "left top", "right top", "left bottom", "right bottom", "center" } },
    },
    rotate = { value = { type = "enum", values = { 0, 90, 180, 270 } } },
    sharpen = { value = { type = "float", min = 0, max = 10 } },
    blur = { value = { type = "int", min = 0, max = 100 } },
    watermark = { text = { type = "string" } },
    background = { value = { type = "string", match = "^%x%x%x%x%x%x$" } },
    strip_metadata = { value = { type = "enum", values = { "true", "false" } } },
}

-- Validate a single operation and return (ok, error).
local function validate_op(op)
    local op_type = op.type
    if not op_type then return nil, "operation missing 'type'" end
    local schema = OP_SCHEMA[op_type]
    if not schema then return nil, "unknown operation: " .. op_type end
    for field, rules in pairs(schema) do
        local v = op[field]
        if v == nil then
            -- LuaJIT/Lua 5.1 has no `continue`; skip nil fields this way.
        elseif rules.type == "int" then
            local n = tonumber(v)
            if not n or math.floor(n) ~= n then
                return nil, string.format("%s.%s must be an integer", op_type, field)
            end
            if rules.min and n < rules.min then
                return nil, string.format("%s.%s below min %d", op_type, field, rules.min)
            end
            if rules.max and n > rules.max then
                return nil, string.format("%s.%s above max %d", op_type, field, rules.max)
            end
        elseif rules.type == "float" then
            local n = tonumber(v)
            if not n then return nil, string.format("%s.%s must be a number", op_type, field) end
            if rules.min and n < rules.min then return nil, string.format("%s.%s below min", op_type, field) end
            if rules.max and n > rules.max then return nil, string.format("%s.%s above max", op_type, field) end
        elseif rules.type == "enum" then
            local ok = false
            for _, val in ipairs(rules.values) do
                if tostring(v) == val then ok = true; break end
            end
            if not ok then
                return nil, string.format("%s.%s invalid: %s", op_type, field, v)
            end
        elseif rules.match then
            if not tostring(v):match(rules.match) then
                return nil, string.format("%s.%s format invalid: %s", op_type, field, v)
            end
        end
    end
    return true
end

-- Translate a validated operation into an imgproxy URL parameter fragment.
-- imgproxy uses "w800/h600" for resize, "q80" for quality, "if_webp" for
-- format output, etc. We build the parameter string imgproxy understands.
local function to_imgproxy_params(op)
    local parts = {}
    if op.type == "resize" then
        if op.width then parts[#parts + 1] = "w" .. op.width end
        if op.height then parts[#parts + 1] = "h" .. op.height end
        if op.fit then
            -- imgproxy fit_type: "fill", "crop", "auto", "scale"
            -- NOTE: LuaJIT/Lua 5.1 cannot index a table literal directly;
            -- wrap it in parentheses so the [op.fit] field access parses.
            local ft = ({ contain = "fill", cover = "crop", fill = "fill", forcescale = "forcescale" })[op.fit]
            if ft then parts[#parts + 1] = "ft_" .. ft end
        end
    elseif op.type == "format" then
        local f = op.output_format
        -- imgproxy output format suffix: if_jpg, if_png, if_webp, if_gif, if_avif
        local map = { jpeg = "if_jpg", png = "if_png", webp = "if_webp", gif = "if_gif", avif = "if_avif" }
        local p = map[f]
        if p then parts[#parts + 1] = p end
    elseif op.type == "quality" then
        parts[#parts + 1] = "q" .. op.value
    elseif op.type == "crop" then
        local t = op.value and op.value or "center"
        -- imgproxy crop type param: "ct_center" etc.
        if op.value then parts[#parts + 1] = "ct_" .. op.value end
    elseif op.type == "rotate" then
        parts[#parts + 1] = "rotate_" .. op.value
    elseif op.type == "sharpen" then
        parts[#parts + 1] = "sharpen_" .. op.value
    elseif op.type == "blur" then
        parts[#parts + 1] = "blur_" .. op.value
    elseif op.type == "watermark" then
        if op.text then parts[#parts + 1] = "wm_text_" .. op.text end
    elseif op.type == "background" then
        parts[#parts + 1] = "bg_" .. op.value
    elseif op.type == "strip_metadata" then
        if op.value == "true" then parts[#parts + 1] = "strip_meta" end
    end
    return table.concat(parts, "/")
end

-- Validate the whole operations list and concatenate their imgproxy params.
-- Returns (imgproxy_params, error). imgproxy_params may be empty string.
function M.build(imgproxy_params_base, operations)
    if not operations then return imgproxy_params_base, nil end
    if type(operations) ~= "table" then return nil, "operations must be an array" end
    local all_params = {}
    if imgproxy_params_base and imgproxy_params_base ~= "" then
        all_params[#all_params + 1] = imgproxy_params_base
    end
    for i, op in ipairs(operations) do
        local ok, err = validate_op(op)
        if not ok then
            return nil, string.format("operation[%d]: %s", i, err)
        end
        local p = to_imgproxy_params(op)
        if p and p ~= "" then
            all_params[#all_params + 1] = p
        end
    end
    return table.concat(all_params, "/")
end

-- Build a default resize+format operation set for preset styles.
function M.preset(style_name)
    local styles = {
        avatar    = { { type = "resize", width = 128, height = 128, fit = "cover" }, { type = "format", output_format = "webp" } },
        thumbnail = { { type = "resize", width = 320, height = 240, fit = "cover" }, { type = "format", output_format = "webp" } },
        product   = { { type = "resize", width = 800, height = 800, fit = "contain" }, { type = "background", value = "ffffff" }, { type = "format", output_format = "webp" } },
        article   = { { type = "resize", width = 1200, height = 0, fit = "contain" }, { type = "quality", value = 82 } },
        original  = {},
    }
    return styles[style_name]
end

return M
