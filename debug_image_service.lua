-- debug_image_service.lua : load each image_service module under resty and print errors
local stdout = io.stdout
local function log(...)
    local parts = {}
    for _, v in ipairs({...}) do parts[#parts+1] = tostring(v) end
    stdout:write(table.concat(parts, " ") .. "\n")
end

local function try_load(modname)
    local ok, err = pcall(require, modname)
    if ok then
        log("OK   ", modname)
    else
        log("FAIL ", modname, " ::", err)
    end
end

-- base modules first
try_load("resty.core")
try_load("resty.random")
try_load("resty.openssl.hmac")
try_load("cjson")

-- image_service modules
try_load("image_service.config")
try_load("image_service.security")
try_load("image_service.http_client")
try_load("image_service.imgproxy")
try_load("image_service.input")
try_load("image_service.operations")
try_load("image_service.output")
try_load("image_service.image_meta")
try_load("image_service.image_api")

log("DONE")
