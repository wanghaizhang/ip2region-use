-- ============================================================================
-- image_meta.lua : image format detection & metadata helpers
-- ============================================================================
-- Detects image format from magic bytes (never trusts the client-declared MIME).
-- Provides a supported-format check and a minimal JPEG/PNG dimension reader so
-- the /info endpoint can work without a heavy dependency.
-- ----------------------------------------------------------------------------

local M = {}

-- Map magic bytes to MIME type.
local function detect_magic(bytes)
    -- PNG: 89 50 4E 47 0D 0A 1A 0A
    if #bytes >= 8 and
        string.byte(bytes, 1) == 0x89 and string.byte(bytes, 2) == 0x50 and
        string.byte(bytes, 3) == 0x4E and string.byte(bytes, 4) == 0x47 and
        string.byte(bytes, 5) == 0x0D and string.byte(bytes, 6) == 0x0A and
        string.byte(bytes, 7) == 0x1A and string.byte(bytes, 8) == 0x0A then
        return "png"
    end
    -- JPEG: FF D8 FF
    if #bytes >= 3 and string.byte(bytes, 1) == 0xFF and string.byte(bytes, 2) == 0xD8 then
        return "jpeg"
    end
    -- GIF: "GIF87a" or "GIF89a"
    if #bytes >= 6 and string.sub(bytes, 1, 6) == "GIF87a" or string.sub(bytes, 1, 6) == "GIF89a" then
        return "gif"
    end
    -- WebP: "RIFF....WEBP" at bytes 0-7 and 8-11
    if #bytes >= 12 and
        string.sub(bytes, 1, 4) == "RIFF" and
        string.sub(bytes, 9, 12) == "WEBP" then
        return "webp"
    end
    -- AVIF/HEIF: Ftyp box with avif/heif brand
    if #bytes >= 12 and
        string.sub(bytes, 4, 8) == "Ftyp" then
        local brand = string.sub(bytes, 12, 15)
        if brand == "avif" or brand == "heix" or brand == "heic" then
            return "avif"
        end
    end
    return nil
end

-- Detect format from raw bytes. Returns (mime, error).
function M.detect_format(bytes)
    local fmt = detect_magic(bytes)
    if not fmt then return nil, "unrecognized image format (magic bytes not matched)" end
    return fmt
end

-- Supported output/input formats.
local SUPPORTED = { jpeg = true, png = true, webp = true, gif = true, avif = true }

function M.is_supported_format(mime)
    return not not SUPPORTED[mime]
end

-- Minimal dimension reader for JPEG (SOF markers).
-- Returns (width, height, error).
function M.jpeg_dimensions(bytes)
    -- skip SOI (FF D8) and any APPn/JFIF/EXIF segments
    local i = 3
    local n = #bytes
    while i < n - 1 do
        if string.byte(bytes, i) ~= 0xFF then break end
        local marker = string.byte(bytes, i + 1)
        if marker == 0xC0 or marker == 0xC1 or marker == 0xC2 then
            -- SOF: FF C0 LEN YX YH XX XY
            local height = string.byte(bytes, i + 5) * 256 + string.byte(bytes, i + 6)
            local width = string.byte(bytes, i + 7) * 256 + string.byte(bytes, i + 8)
            return width, height
        elseif marker == 0xD9 then -- EOI
            break
        elseif marker == 0xDA then -- SOS, stop (headers done)
            break
        else
            local slen = string.byte(bytes, i + 2) * 256 + string.byte(bytes, i + 3)
            if slen < 2 then break end
            i = i + 2 + slen
        end
    end
    return nil, nil, "cannot parse JPEG dimensions"
end

-- Minimal dimension reader for PNG (IHDR).
-- Returns (width, height, error).
function M.png_dimensions(bytes)
    if #bytes < 24 then return nil, nil, "truncated PNG" end
    local w = (string.byte(bytes, 16) * 16777216) +
        (string.byte(bytes, 17) * 65536) +
        (string.byte(bytes, 18) * 256) + string.byte(bytes, 19)
    local h = (string.byte(bytes, 20) * 16777216) +
        (string.byte(bytes, 21) * 65536) +
        (string.byte(bytes, 22) * 256) + string.byte(bytes, 23)
    return w, h
end

return M
