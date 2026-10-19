#!/usr/bin/env node
/**
 * 下载 ip2region 数据库文件到 data 目录
 * 
 * 下载源：https://github.com/lionsoul2014/ip2region
 * 下载后手动放到 data 目录，或运行本脚本
 */

const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");

const dataDir = path.join(__dirname, "data");
const dbPath = path.join(dataDir, "ip2region_v4.xdb");
const dbUrl = "https://gitee.com/lionsoul/ip2region/raw/v3.18.0/data/ip2region_v4.xdb";

// 检查是否需要下载
if (fs.existsSync(dbPath)) {
  const stats = fs.statSync(dbPath);
  console.log("✓ xdb 文件已存在:", dbPath);
  console.log(`  大小：${(stats.size / 1024 / 1024).toFixed(2)} MB`);
} else {
  console.log("✗ xdb 文件不存在，开始下载...");

  const request = https.get(dbUrl, (res) => {
    if (res.statusCode !== 200) {
      console.error(`下载失败，状态码：${res.statusCode}`);
      process.exit(1);
    }

    console.log(`正在下载，服务器返回 ${res.headers['content-length']} 字节...`);

    const chunks = [];
    res.on("data", (chunk) => chunks.push(chunk));
    res.on("end", () => {
      const buffer = Buffer.concat(chunks);
      if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
      }
      fs.writeFileSync(dbPath, buffer);
      console.log("✓ 下载完成:", dbPath);
      console.log(`  大小：${(buffer.length / 1024 / 1024).toFixed(2)} MB`);
    });
  });

  request.on("error", (err) => {
    console.error("下载失败:", err.message);
    process.exit(1);
  });

  request.setTimeout(30000, () => {
    request.destroy();
    console.error("下载超时");
    process.exit(1);
  });
}

console.log("");
console.log("使用方法:");
console.log("  npm run prepare-xdb    # 下载或检查 xdb 文件");
console.log("  npm run start          # 启动本地测试服务");
