# image-service — OpenResty + imgproxy 图片处理平台

一个自建的通用图片处理服务，采用 **OpenResty（Lua）统一入口 + imgproxy（内网引擎）** 的架构。对外提供统一的图片处理 API，支持 URL / Base64 / Data URL / multipart 上传多种输入，输出二进制 / Base64 / URL 多种结果。imgproxy 仅在内网 Docker 网络中被 OpenResty 调用，**不向公网暴露端口**。

---

## 一、架构总览

```
客户端 ──► OpenResty (8090) ──► imgproxy (8080, 内网)
          │   Lua: 路由 / 校验 / 签名 / 限流 / 缓存
          │
          │   ① URL 输入 → 直接交给 imgproxy
          │   ② Base64/上传 → 解码写入临时文件 → 受控内网源 → imgproxy
```

| 组件 | 职责 |
|------|------|
| **OpenResty** | 公网入口、路由、参数校验、签名、限流、缓存、日志 |
| **imgproxy** | 实际图像处理引擎：缩放、裁剪、格式转换、质量调整、水印 |
| **临时文件源** | 存放解码后的 Base64/上传图，仅内网可访问，处理完即删 |

Lua 不重新实现任何底层图像算法，所有图像处理都交给 imgproxy（底层 libvips / ImageMagick）。

---

## 二、目录结构

```
image-service/
├── lua/image_service/
│   ├── config.lua        # 集中配置（端口、限制、密钥、白名单）
│   ├── security.lua      # 签名、限流、SSRF 防护、来源校验
│   ├── http_client.lua   # 无依赖 HTTP 客户端（ngx.socket.tcp 实现）
│   ├── input.lua         # 输入适配器：URL / Base64 / Data URL / multipart
│   ├── operations.lua    # 操作参数校验 + 转换为 imgproxy 参数
│   ├── imgproxy.lua      # 生成签名 URL 并调用 imgproxy
│   ├── output.lua        # 二进制 / Base64 / URL 输出
│   ├── image_meta.lua    # 图片格式识别（魔法字节）+ 尺寸读取
│   └── image_api.lua     # 统一入口与路由分发
├── tmp/                  # 临时图片文件（随机令牌，用完即删）
├── compose.yaml          # imgproxy Docker 部署
├── .env.example          # 环境变量模板（含签名密钥）
└── README.md
```

> 模块实际位于 `openresty\lua\image_service\`（去掉 `image-service\lua\` 这一层嵌套），nginx 配置里 `lua_package_path` 指向 `./lua/image_service/?.lua`。

nginx 配置：`conf/image-service.conf`（独立 server 块，不影响现有 ip2region 服务）

---

## 三、API 接口

### 3.1 URL 图片处理（GET）

```
GET /api/v1/image?src=<HTTPS_URL>&w=800&h=600&fit=cover&format=webp&q=80
```

| 参数 | 含义 | 可选值 |
|------|------|--------|
| `src` | 原图 HTTPS URL（必填） | — |
| `w` | 输出最大宽度（px） | 1–2560 |
| `h` | 输出最大高度（px） | 1–2560 |
| `fit` | 缩放策略 | `contain` / `cover` / `fill` |
| `format` | 输出格式 | `jpeg` / `png` / `webp` / `gif` / `avif` |
| `q` | 输出质量 | 1–100 |

返回处理后的图片二进制，响应头含 `Cache-Control: public, max-age=86400`。

**示例：**

```bash
curl "http://127.0.0.1:8090/api/v1/image?src=https%3A%2F%2Fexample.com%2Fa.jpg&w=800&format=webp&q=80"
```

### 3.2 预设样式（GET）

```
GET /api/v1/style/:style?src=<HTTPS_URL>
```

| 样式 | 规则 |
|------|------|
| `avatar` | 128×128 正方形裁剪 → WebP |
| `thumbnail` | 320×240 居中裁剪 → WebP |
| `product` | 800×800 保持比例 + 白色背景 → WebP |
| `article` | 最大宽度 1200 保持比例 |
| `original` | 保留原始尺寸 |

**示例：**

```bash
curl "http://127.0.0.1:8090/api/v1/style/avatar?src=https%3A%2F%2Fexample.com%2Fu.jpg"
```

### 3.3 统一处理（POST，支持 Base64 / multipart）

**Base64 输入：**

```http
POST /api/v1/image:process
Content-Type: application/json

{
  "input": { "type": "base64", "data": "iVBORw0KGgoAAAANSUhEUg..." },
  "operations": [
    { "type": "resize", "width": 800, "height": 600, "fit": "contain" },
    { "type": "format", "output_format": "webp" },
    { "type": "quality", "value": 80 }
  ],
  "output": { "type": "base64" }
}
```

**响应：**

```json
{
  "success": true,
  "image": { "format": "webp", "width": 800, "height": 600, "data": "UklGRiIA..." }
}
```

**操作类型白名单：**

| type | 字段 | 说明 |
|------|------|------|
| `resize` | `width` `height` `fit` | 缩放，`fit` = contain/cover/fill |
| `format` | `output_format` | 输出格式转换 |
| `quality` | `value` | 质量 1–100 |
| `crop` | `type` | 裁剪位置：center/left top/right top 等 |
| `rotate` | `value` | 旋转 0/90/180/270 |
| `sharpen` | `value` | 锐化强度 0–10 |
| `blur` | `value` | 模糊强度 0–100 |
| `watermark` | `text` | 文字水印 |
| `background` | `value` | 补边背景色 6 位十六进制 |
| `strip_metadata` | `value` | 是否去除元数据 |

**multipart 上传：**

```bash
curl -X POST "http://127.0.0.1:8090/api/v1/image:process" \
  -F "file=@photo.jpg" \
  -F 'operations=[{"type":"resize","width":800,"fit":"contain"}]' \
  -F "output=base64"
```

`output` 字段可选：`binary` / `base64` / `url`。

### 3.4 图片信息（GET）

```
GET /api/v1/info?src=<HTTPS_URL>
```

返回格式、宽高、像素数：

```json
{ "success": true, "format": "jpeg", "width": 2400, "height": 1600, "pixel_count": 3840000 }
```

### 3.5 健康检查

```
GET /api/v1/health
→ {"success":true,"service":"image-service"}
```

---

## 四、部署步骤

### 4.1 前置准备

确认本机已安装：

- **OpenResty**（位于 `D:\demo\openresty`，含 `nginx.exe`、`lualib/`）
- **Docker**（用于运行 imgproxy）

### 4.2 配置签名密钥

```bash
cd D:\demo\openresty\image-service
cp .env.example .env
# 编辑 .env，将 IMGPROXY_SECRET_KEY / IMGPROXY_SECRET_SALT 替换为强随机值
```

生成强随机密钥（PowerShell）：

```powershell
-join ((1..64) | ForEach-Object { [System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(1))[0] })
```

### 4.3 配置 imgproxy 可达地址

编辑 `lua/image_service/config.lua`：

```lua
M.imgproxy_host = "imgproxy"   -- Docker 容器名；宿主机直连改为 "127.0.0.1"
M.imgproxy_port = 8080
```

### 4.4 启动 imgproxy

```bash
cd D:\demo\openresty\image-service
docker network create image_backend 2>/dev/null || true
docker compose up -d
docker ps   # 确认 imgproxy 容器运行，未发布端口到宿主机
```

### 4.5 接入 OpenResty

将 image-service 的 server 块加载进主 nginx.conf。两种接入方式：

**方式 A（推荐，独立 server）：** 在 `conf/nginx.conf` 的 `http {}` 中添加：

```nginx
include conf/image-service.conf;
```

注意：image-service.conf 内已自带 `lua_package_path` 和独立 `server` 块，监听 **8090** 端口，与现有 ip2region 服务（8080）互不干扰。

**方式 B（容器网络打通）：** 若 OpenResty 运行在 Docker 中，需将其加入 `image_backend` 网络：

```bash
docker network connect image_backend <openresty-container-name>
```

### 4.6 验证

```bash
# 健康检查
curl http://127.0.0.1:8090/api/v1/health

# URL 处理
curl -o /dev/null -w "%{http_code}\n" \
  "http://127.0.0.1:8090/api/v1/image?src=https%3A%2F%2Fwww.example.com%2F.jpg&w=200&format=webp"

# Base64 处理
curl -X POST http://127.0.0.1:8090/api/v1/image:process \
  -H "Content-Type: application/json" \
  -d '{"input":{"type":"base64","data":"iVBORw0KGgo..."},"operations":[{"type":"resize","width":200}],"output":{"type":"base64"}}'
```

---

## 五、安全设计

| 风险 | 防护措施 |
|------|----------|
| **SSRF** | URL 输入只允许 http/HTTPS，拒绝 `file://`、`ftp://`；拒绝回环/私有/链路本地/云元数据地址；imgproxy 侧 `ALLOW_*_SOURCE_ADDRESSES=false` |
| **来源白名单** | `config.lua` `allowed_sources` 为空时启用域名白名单模式 |
| **签名篡改** | imgproxy 路径用 HMAC-SHA256 签名，客户端无法伪造 w/h/format/q 参数 |
| **临时文件泄露** | 随机令牌文件名，仅内网 `internal` location 可访问，处理完即删 |
| **资源耗尽** | 请求体 20MiB 上限、解码后大小限制、20MP 像素上限、处理超时 30s、每 IP 5r/s 限流 |
| **格式伪造** | 不信任客户端声明的 MIME，用魔法字节识别真实格式 |
| **密钥泄露** | 签名密钥仅存服务端 `.env`，不返回客户端、不提交 Git |

---

## 六、参数限制（可配置）

所有限制集中在 `config.lua`：

| 项目 | 默认值 | 配置项 |
|------|--------|--------|
| 请求体上限 | 20 MiB | `max_request_body_bytes` |
| 解码后大小 | 20 MiB | `max_base64_input_bytes` |
| 源图像素 | 20 MP | `max_pixels` |
| 输出单边最大 | 2560 px | `max_output_dimension` |
| 默认质量 | 80 | `default_quality` |
| 处理超时 | 30 s | `process_timeout_ms` |
| 每 IP 速率 | 5 r/s | `rate_limit_rps` |
| 突发上限 | 20 | `rate_limit_burst` |

---

## 七、回滚

1. 从 `nginx.conf` 移除 `include conf/image-service.conf;`
2. `nginx -t` 验证后 `nginx -s reload`
3. `docker compose down` 停止 imgproxy
4. 确认原业务正常后，再删除 `image_backend` 网络与缓存目录

---

## 八、后续扩展

- **第二阶段**：图片信息接口（`/api/v1/info` 已预留）、样式管理、API Key 配额、用量统计
- **第三阶段**：智能主体裁剪、感知质量优化、动图/视频预览、对象存储集成、异步批处理

> imgproxy 开源版已覆盖第一阶段全部能力（缩放、裁剪、旋转、格式转换、质量、元数据清理、模糊、锐化、补边、水印、预设样式）。智能处理、高级压缩等高级能力需额外引擎或商业版。
