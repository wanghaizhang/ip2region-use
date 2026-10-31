-- temp diagnostic: load each image_service module under resty, print real errors
package.path = "./lua/?.lua;./lua/image_service/?.lua;./lualib/?.lua;;" .. package.path

local mods = {"config","security","http_client","operations","input","output","image_meta","imgproxy","image_api"}
for _, m in ipairs(mods) do
    local ok, err = pcall(require, "image_service." .. m)
    if ok then print("OK   "..m) else print("ERR  "..m..": "..tostring(err)) end
end
