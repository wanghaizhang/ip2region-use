# Image Service API 接口文档

> 基于 imgproxy v4 的图像处理服务。OpenResty 转发，签名校验，SSRF 防护。
> 服务地址：`http://127.0.0.1:8090`（对外端口见 nginx 配置）。

---

## 1. 通用说明

### 1.1 请求方式

| 接口 | 方法 | 路径 | 说明 |
|---|---|---|---|
| 图像处理 | GET | `/api/v1/image` | URL 输入，二进制输出 |
| 风格处理 | GET | `/api/v1/style/{style}` | 预设风格，二进制输出 |
| 图片信息 | GET | `/api/v1/info` | 返回图片信息（已废弃，imgproxy v4 无 info 端点） |
| 上传处理 | POST | `/api/v1/image:process` | base64 / multipart 输入，JSON 输出 |

### 1.2 通用参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `src` | string | 是 | 源图片地址，`http(s)://`。必须通过 SSRF 校验（仅允许白名单域名，见配置 `allowed_sources`） |
| `format_mode` | string | 否 | 源地址编码格式：`plain`（默认）输出明文 `http(s)://` 源（带 `/plain/` 前缀）；`base64` 输出 URL-safe base64 编码的源（去掉 `/plain/`）。imgproxy v4 两种格式都接受。 |

### 1.3 响应

- 成功：HTTP 200，`Content-Type` 为图片格式（`image/png` / `image/webp` / `image/avif` 等），body 为二进制图片数据。
- 失败：HTTP 4xx / 5xx，JSON 错误体 `{"success":false,"error":"..."}`。

---

## 2. 缩放 / 尺寸（resize）

| 参数 | 类型 | 范围 | 说明 |
|---|---|---|---|
| `w` | int | 1 ~ `max_output_dimension`（默认 4096） | 目标宽度 |
| `h` | int | 1 ~ `max_output_dimension` | 目标高度 |
| `fit` | string | `fill` / `contain` | 缩放模式，`contain` → `fit`（等比适配），默认 `fill`（填满） |
| `min_w` | int | 1 ~ `max_output_dimension` | 最小宽度 |
| `min_h` | int | 1 ~ `max_output_dimension` | 最小高度 |
| `dpr` | int | 1 ~ 8 | 设备像素比 |
| `gravity` | string | `ce`/`top`/`bottom`/`left`/`right`/`sm` | 重力定位点（默认 `ce` 居中） |

imgproxy v4 只接受 `fit` / `fill` / `fill-down` 三种 resizing_type（老的 `crop`/`contain` 已废除）。

**转发格式：** `rs:{type}:{w}:{h}:1`

**示例：**
```
GET /api/v1/image?src=https://example.com/a.jpg&w=800&h=600&fit=fill
→ 转发：/{sig}/rs:fill:800:600:1/plain/https://example.com/a.jpg
```

---

## 3. 裁剪（crop）

| 参数 | 类型 | 范围 | 说明 |
|---|---|---|---|
| `crop_w` | int | 1 ~ `max_output_dimension` | 裁剪宽度（必填） |
| `crop_h` | int | 1 ~ `max_output_dimension` | 裁剪高度（必填） |
| `crop_gravity` | string | 同 `gravity` | 裁剪定位点，默认 `ce`；未传则沿用 `gravity` |

**转发格式：** `crop:{w}:{h}:{gravity}`

**示例：**
```
GET /api/v1/image?src=https://example.com/a.jpg&crop_w=150&crop_h=150&gravity=ce
→ 转发：/{sig}/rs:0:0:1/crop:150:150:ce/plain/https://example.com/a.jpg
```

---

## 4. 输出格式 / 质量

| 参数 | 类型 | 范围 | 说明 |
|---|---|---|---|
| `format` | string | `jpg` / `jpeg` / `png` / `webp` / `gif` / `avif` | 输出格式 |
| `q` | int | 1 ~ 100 | 压缩质量（quality） |

**转发格式：** `format:{fmt}`、`quality:{q}`

**示例：**
```
GET /api/v1/image?src=https://example.com/a.jpg&format=webp&q=80
→ 转发：/{sig}/rs:0:0:1/quality:80/format:webp/plain/https://example.com/a.jpg
```

---

## 5. 图像调整（adjustments）

| 参数 | 类型 | 范围 | 说明 |
|---|---|---|---|
| `rotate` | int | 0 ~ 360 | 旋转角度 |
| `auto_rotate` | string | `1` | 按 EXIF 自动旋转 |
| `flip` | string | `1` | 水平翻转 |
| `flip_v` | string | `1` | 垂直翻转 |
| `blur` | int | 1 ~ 1000 | 模糊半径 |
| `sharpen` | int | 1 ~ 1000 | 锐化半径 |
| `pixelate` | int | 1 ~ 10000 | 像素化尺寸 |

**转发格式：** `rotate:{deg}`、`auto_rotate:1`、`flip:1`、`flip:0:1`、`blur:{r}`、`sharpen:{r}`、`pixelate:{n}`

**示例：**
```
GET /api/v1/image?src=https://example.com/a.jpg&rotate=90&format=webp
→ 转发：/{sig}/rs:0:0:1/rotate:90/format:webp/plain/https://example.com/a.jpg
```

---

## 6. 扩展 / 填充 / 抠边

| 参数 | 类型 | 范围 | 说明 |
|---|---|---|---|
| `background` | string | 十六进制 | 背景色，可带 `FF` 透明度前缀（如 `FF0000`） |
| `padding` | string | — | 内边距，`{n}` 或 `{top}:{right}:{bottom}:{left}` |
| `trim` | int | 0 ~ 255 | 抠同色边阈值 |
| `trim_color` | string | 十六进制 | 抠边目标颜色，默认透明 |

**转发格式：** `background:{hex}`、`padding:{...}`、`trim:{threshold}:{color}`

**示例：**
```
GET /api/v1/image?src=https://example.com/a.jpg&background=FFFFFF&padding=20
→ 转发：/{sig}/rs:0:0:1/background:FFFFFF/padding:20/plain/https://example.com/a.jpg
```

---

## 7. 水印 / 元数据 / 安全

| 参数 | 类型 | 范围 | 说明 |
|---|---|---|---|
| `watermark` | int | 0 ~ 100 | 水印不透明度（0.00 ~ 1.00） |
| `strip_metadata` | string | `1` | 去除元数据 |
| `keep_copyright` | string | `1` | 保留版权信息 |
| `preserve_hdr` | string | `1` | 保留 HDR |

**转发格式：** `watermark:0.{xx}`、`strip_metadata:1`、`keep_copyright:1`、`preserve_hdr:1`

> **⚠️ 水印图来源限制（已排查确认）**：imgproxy 显示水印需要 `watermark_url` 参数提供水印图。实测 `watermark_url`（含源图自身、外部 picsum、w3school gif）**全部返回 404**，而仅 `watermark:0.50`（无水印图）**返回 200**。结论：当前 imgproxy 部署**拒绝 `watermark_url` 操作**——imgproxy v4 默认仅允许 `WATERMARK_SOURCE_ADDRESSES_ALLOWED` 白名单内的水印源，未配置白名单时 `watermark_url` 直接 404。解决方向：①在 imgproxy 服务端配置 `WATERMARK_SOURCE_ADDRESSES_ALLOWED`（含水印图地址）；②或使用服务端允许访问的水印源。`watermark` 不透明度参数本身可用。

---

## 8. 组合示例

```
GET /api/v1/image?src=https://example.com/a.jpg\
  &w=300&h=150&fit=contain&format=webp&q=50\
  &rotate=90&auto_rotate=1&gravity=ce
→ 转发：/{sig}/rs:fit:300:150:1/quality:50/format:webp/rotate:90/auto_rotate:1/gravity:ce/plain/https://example.com/a.jpg
```

多个处理操作按固定顺序拼接，段间用 `/` 连接：
`resize → min-dim → gravity → crop → format/quality → adjustments → extend/trim → watermark/metadata`

---

## 9. 错误码

| HTTP 状态 | 说明 |
|---|---|
| 400 | 缺少 `src`、源 URL 非法、源域名不在白名单、SSRF 拦截、参数无效 |
| 404 | 未知接口 / 未知风格 |
| 502 | imgproxy 处理失败 / 转发失败 |

---

## 10. 配置项

见 `lua/image_service/config.lua`：

| 配置项 | 说明 |
|---|---|
| `imgproxy_host` / `imgproxy_port` | imgproxy 服务地址 |
| `max_output_dimension` | 最大输出尺寸（默认 4096） |
| `allowed_sources` | 源域名白名单（空=不限制） |
| `cors_allow_origin` | CORS 允许来源 |
| `process_timeout_ms` | imgproxy 请求超时（毫秒） |
| `secret_key` / `secret_salt` | imgproxy 签名用的 HMAC 密钥与 salt（hex 编码） |

---

## 11. 签名与转发路径

imgproxy v4 URL 结构：
```
/{signature}/{processed_options}/{source}
```

源地址有两种写法（两种可互换）：

- **格式 1（plain，当前使用）**：`/{processed_options}/plain/{source_url}`，源为明文 `http(s)://` 地址，无需编码。
- **格式 2（base64）**：`/{processed_options}/{base64_source}`，源为 URL-safe base64 编码的地址（去掉 `/plain/`）。编码方式：对 `http(s)://...` 做标准 base64 编码（URL-safe，无 padding）。

示例（同一请求两种写法）：
```
格式1：/{sig}/rs:fill:800:600:1/quality:80/format:webp/plain/https://example.com/a.jpg
格式2：/{sig}/rs:fill:800:600:1/quality:80/format:webp/aHR0cHM6Ly9leGFtcGxlLmNvbS9haWFmLmpwZw==
```

- **signature**：`hmac_sha256(secret_key, salt .. path)` 的 base64url 编码，首个路径段。
- **processed_options**：处理操作段，`key:value` 用 `/` 连接。
- 无处理参数时，`processed_options` 默认为 `rs:fill:100:100:1`。

> `format_mode` 切换说明：API 默认输出格式 1（plain）。请求加 `?format_mode=base64` 时，`imgproxy.build_url` 将源 URL 做 URL-safe base64 编码后作为 source 段（去掉 `/plain/`）。两种格式的签名公式完全一致（`hmac_sha256(key, salt + /{ops}/{source})`），imgproxy v4 均接受。实测两种格式输出字节数完全相同。
