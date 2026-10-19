const http = require("http");
const path = require("path");
const logger = require("./logger");

// ip2region 依赖（ESM 包，不能用 require，用动态 import）

const dbPath = path.join(
  process.env.RUNTIME_CODE_ROOT || __dirname,
  "data",
  "ip2region_v4.xdb"
);

let query = null;

async function initQuery() {
  try {
    // ip2region.js 是 ESM 包，CommonJS 里不能用 require，用动态 import
    const ip2region = await import("ip2region.js");
    // 使用官方 ip2region.js 包的正确 API
    query = ip2region.newWithFileOnly(ip2region.IPv4, dbPath);
    logger.info(`IP2Region database initialized from: ${dbPath}`);
  } catch (err) {
    logger.error("Failed to initialize IP2Region:", err);
    throw err;
  }
}

function json(res, status, data) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=UTF-8",
    "Access-Control-Allow-Origin": "*",
    "Cache-Control": "public, max-age=300"
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  const start = Date.now();

  try {
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type"
      });
      res.end();
      return;
    }

    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    let ip = null;

    if (url.pathname === "/") {
      return json(res, 200, {
        success: true,
        service: "ip2region-api",
        endpoints: [
          "/ip2region/api/ip",
          "/ip2region/api/ip/8.8.8.8",
          "/ip2region/api/ip/114.114.114.114"
        ]
      });
    }

    // 匹配 /ip2region/ 开头的 API 路由
    const apiMatch = url.pathname.match(/^\/ip2region\/(api\/ip)(?:\/([^/]+))?/);
    if (!apiMatch) {
      return json(res, 404, {
        success: false,
        error: "Not Found - 使用 /ip2region/api/ip 或 /ip2region/api/ip/{IP}"
      });
    }

    const pathSuffix = apiMatch[1];
    // 根据路径匹配 IP
    if (apiMatch[2]) {
      // /ip2region/api/ip/{IP} 格式
      ip = decodeURIComponent(apiMatch[2]);
    } else if (pathSuffix === "api/ip") {
      // /ip2region/api/ip (返回远程 IP)
      ip = req.socket.remoteAddress;
    }

    const ipv4Pattern = /^(?:\d{1,3}\.){3}\d{1,3}$/;
    if (!ipv4Pattern.test(ip) || 
        ip.split('.').some(octet => Number(octet) > 255)) {
      return json(res, 400, {
        success: false,
        error: "Invalid IPv4 address"
      });
    }

    if (!query) {
      return json(res, 503, {
        success: false,
        error: "Service not initialized. Please wait."
      });
    }

    try {
      const resultStr = await query.search(ip);
      // Parse the region string: "country|region|city|isp|country_code"
      const parts = resultStr.split('|');
      const [country, region, city, isp, countryCode] = parts;
      
      return json(res, 200, {
        success: true,
        ip,
        country,
        region,
        city,
        isp,
        countryCode,
        regionStr: resultStr
      });
    } catch (err) {
      logger.error("IP lookup failed:", err);
      return json(res, 500, {
        success: false,
        error: "IP lookup failed"
      });
    }
  } finally {
    // 访问日志：覆盖所有请求（根路径、404、400、查询等）
    logger.access(req, { statusCode: res.statusCode }, Date.now() - start);
  }
});

server.listen(8000, "127.0.0.1", async () => {
  logger.info("IP2Region API server listening on 127.0.0.1:8000");

  // 在服务器启动后初始化查询
  await initQuery();
});

// 优雅关闭处理
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  server.close(() => {
    logger.info('Server closed');
    logger.close();
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  server.close(() => {
    logger.info('Server closed');
    logger.close();
    process.exit(0);
  });
});