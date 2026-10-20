# OpenResty ip2region 服务

基于 OpenResty（LuaJIT / Lua 5.1）的 IP 地理位置查询 API，使用 `lua/ip2region.lua`（已改写为 `bit.*` 兼容 LuaJIT）。

## 目录结构

```
D:\demo\openresty\
├── nginx.exe
├── nginx.conf
├── lua/
│   ├── ip2region.lua
│   └── ip2region_api.lua
└── data/
    └── ip2region_v4.xdb
```

## 关键配置：lua_package_path

```nginx
lua_package_path "./lua/?.lua;;";
```

- `./lua/?.lua`：`?` 通配模块名，让 `require("ip2region")` 找到 `lua/ip2region.lua`，`require("ip2region_api")` 找到 `lua/ip2region_api.lua`。
- `;;`：保留 Lua 默认的模块搜索路径。

> ⚠️ 不要用 `lua_package_path "lua/ip2region.lua;lua/ip2region_api.lua;"` 这种逐模块列举的写法——它会导致请求失败。统一用 `./lua/?.lua;;`。

## 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | 服务信息 |
| GET | `/ip2region/api/ip` | 查询客户端 IP |
| GET | `/ip2region/api/ip/{IP}` | 查询指定 IP（正则捕获组用命名变量 `ngx.var.query_ip`） |

## 启动 / 重载

```powershell
cd D:\demo\openresty
.\nginx.exe -t          # 校验配置
.\nginx.exe -s reload   # 重载（或 .\nginx.exe 首次启动）
```

## 文件

- `lua/ip2region.lua`：ip2region xdb 解析器（LuaJIT 兼容，`bit.*`）。
- `lua/ip2region_api.lua`：region 字符串转 JSON 响应。
