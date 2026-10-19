# ip2region API（HTTP 服务）

## 项目概述
基于 Node.js 的 IP 归属地查询 HTTP API。使用 ip2region npm 包解析 ip2region xdb 数据库，支持 IPv4 查询。自带**异步日志**模块（缓冲写入 + 防抖落盘），请求日志落盘到 `logs/` 目录。

## 项目结构
```
huaweicloud-ip2region/
├── index.js          # HTTP 服务和查询接口
├── logger.js         # 异步日志模块（缓冲 + 防抖落盘）
├── bootstrap         # 华为云 FunctionGraph 启动脚本
├── package.json      # Node.js 依赖
├── package-lock.json # 依赖锁文件
├── data/
│   └── ip2region_v4.xdb  # ip2region IPv4 数据库 (需下载)
├── scripts/
│   └── download-xdb.js # 下载 xdb 数据库脚本
├── logs/             # 运行期日志输出目录（自动生成）
└── README.md         # 本文件
```

## 日志说明
`logger.js` 提供异步日志，避免每次 `console` 都触发磁盘 IO：

| 方法 | 说明 |
|------|------|
| `logger.debug/warn/info/error(...)` | 按级别记录日志 |
| `logger.access(req, res, durationMs)` | 记录一次 HTTP 请求（方法、URL、状态码、耗时、客户端 IP） |
| `logger.close()` | 退出前强制落盘缓冲 |

**工作机制：**
- 普通日志（info/warn/debug）先写入内存缓冲（最多 128 行），200ms 防抖后批量落盘
- `error` 级别立即落盘，保证关键错误不丢失
- `access` 访问日志每条立即落盘，保证可追溯
- 同时输出到 stdout，便于 PM2 / 日志平台采集
- 按日期生成文件：`logs/ip2region-YYYY-MM-DD.log`

**环境变量：**
| 变量 | 默认值 | 说明 |
|------|--------|------|
| `LOG_LEVEL` | `info` | 日志级别：debug / info / warn / error |
| `LOG_DIR` | `./logs` | 日志输出目录 |

**示例访问日志：**
```
2026-10-19T10:30:15.123Z [INFO] access GET /ip2region/api/ip/8.8.8.8 200 12ms client=::ffff:127.0.0.1
```

## 前置准备

### 1. 下载 ip2region 数据库
项目使用官方 ip2region IPv4 数据库 (ip2region_v4.xdb)。请执行以下任一步骤：

**方法 A：使用下载脚本**
```powershell
cd D:\demo\huaweicloud-ip2region
node scripts/download-xdb.js
```
此脚本会从 Gitee 仓库下载指定版本 v3.18.0 的 ip2region_v4.xdb 并保存到 data 目录。

**方法 B：手动下载**
1. 访问 Gitee：https://gitee.com/lionsoul/ip2region
2. 下载 `ip2region_v4.xdb` 文件 (v3.18.0 版本)
3. 将其放入 `data/` 目录

### 2. 本地验证 (可选)
在部署前，建议先在本地验证代码与数据库是否正常工作：
```powershell
cd D:\demo\huaweicloud-ip2region
npm install            # 安装依赖
node test-local.js     # 运行本地测试
```

## 部署步骤

### 方式 A：自托管 HTTP 服务（推荐，本机服务器 / 云服务器）

服务监听 `127.0.0.1:8000`，配合 Nginx 反向代理对外提供服务。

**1. 上传部署包**
```bash
scp ip2region-api-deploy.zip root@服务器IP:/home/project/
```

**2. 解压并安装依赖**
```bash
ssh root@服务器IP
cd /home/project
mkdir -p ip2region
unzip -o ip2region-api-deploy.zip -d ip2region/
cd ip2region
npm install --production
```

**3. 启动服务（PM2 守护 + 开机自启）**
```bash
npm install -g pm2
pm2 start index.js --name "ip2region-api"
pm2 startup        # 注册开机自启（systemd）
pm2 save           # 保存进程列表，重启后自动恢复
```

**4. 本地测试**
```bash
curl http://127.0.0.1:8000/ip2region/api/ip/8.8.8.8
# {"success":true,"ip":"8.8.8.8","country":"United States",...}
```

**5. Nginx 反向代理（对外提供 80 端口）**
```bash
cat > /etc/nginx/conf.d/ip2region.conf << 'EOF'
server {
    listen 80;
    server_name _;
    location /ip2region/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
nginx -t
systemctl restart nginx
firewall-cmd --permanent --add-service=http
firewall-cmd --reload
```

**6. 公网测试**
```bash
curl http://服务器IP/ip2region/api/ip/114.114.114.114
```

### 方式 B：华为云 FunctionGraph（Serverless）

1. 登录华为云控制台，进入 FunctionGraph 服务
2. 创建空白函数，函数类型选择 **HTTP 函数**
3. 运行环境选择 **Node.js 22.18**
   - 若该版本不可用，选择区域支持的 Node.js 版本
   - 同步修改 bootstrap 中的路径 `/opt/function/runtime/nodejs22.18/rtsp/nodejs/bin/node`
4. 上传 `function.zip`
5. 设置：内存 512 MB、超时 10 秒
6. 配置 API 网关触发器，发布 API，复制调用 URL

> 注意：FunctionGraph 环境下 `logger.js` 的落盘路径受运行时限制，建议设置环境变量 `LOG_DIR=/tmp/logs`，日志主要通过 stdout 输出供云平台采集。

## 测试接口

部署完成后，使用以下 URL 进行测试：

| 请求 | 示例 | 预期结果 |
|------|------|----------|
| `GET /` | https://your-api-url/ | 返回服务信息 JSON |
| `GET /api/ip` | https://your-api-url/api/ip | 返回当前客户端 IP 的归属地 |
| `GET /api/ip/8.8.8.8` | https://your-api-url/api/ip/8.8.8.8 | 返回 8.8.8.8 的归属地 |
| `GET /api/ip/114.114.114.114` | https://your-api-url/api/ip/114.114.114.114 | 返回中国 IP 归属地 |
| `GET /api/ip/999.1.1.1` | https://your-api-url/api/ip/999.1.1.1 | 返回 400 错误 (无效 IP) |

### 示例响应
```json
{
  "success": true,
  "ip": "8.8.8.8",
  "country": "美国",
  "province": "加利福尼亚州",
  "city": "山景城",
  "isp": "Google LLC"
}
```

## 免费额度与费用

| 项目 | 说明 |
|------|------|
| FunctionGraph | 每月 100 万次请求 + 400,000 GB·秒执行时间免费额度 |
| API 网关 | 可能有独立的请求或实例费用，请确认套餐详情 |
| 日志 | 日志存储与保留时间可能产生额外费用 |
| OBS | 若使用远程存储，会产生存储和流出费用 |

建议设置费用告警，避免超额产生费用。

## 注意事项

1. **IPv4 仅**：当前实现仅支持 IPv4 查询，IPv6 需额外配置
2. **客户端 IP**：在 `/api/ip` 接口，`req.socket.remoteAddress` 获取的可能是代理/负载均衡的 IP，不应直接信任公网用户提供的 `X-Forwarded-For`
3. **数据库大小**：官方 ip2region IPv4 数据库约 11MB，打包后 function.zip 约 15-20MB
4. **首次冷启动**：函数首次调用可能有 1-3 秒的延迟（包初始化时间）
5. **内存使用**：ip2region 数据库在内存中的占用约为文件大小的 2-3 倍，512 MB 内存足以支持单实例

## 许可证
基于 MIT 许可证，详见 LICENSE 文件（如果有）。