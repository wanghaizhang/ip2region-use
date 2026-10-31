-- probe all ngx crypto / hash functions
ngx.header["Content-Type"] = "text/plain"
local keys = {}
for k in pairs(ngx) do keys[#keys+1] = k end
table.sort(keys)
local found = {}
for _, k in ipairs(keys) do
    if type(ngx[k]) == "function" then
        found[#found+1] = k
    end
end
ngx.say("functions: " .. table.concat(found, ", "))
-- try md5
ngx.say("md5(abc) = " .. ngx.md5("abc"))
