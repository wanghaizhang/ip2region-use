"use strict";

// 异步日志模块：缓冲写入 + 防抖落盘，避免每次 console 都触发磁盘 IO。
// 用法：
//   const logger = require("./logger");
//   logger.info("message"); logger.warn(...); logger.error(...); logger.debug(...);
//   logger.access(req, res);  // 记录一次 HTTP 请求（状态码 + 耗时）

const fs = require("fs");
const path = require("path");

// 日志级别映射
const LEVELS = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

const LOG_DIR = process.env.LOG_DIR || path.join(__dirname, "logs");
const LEVEL = process.env.LOG_LEVEL || "info";
const MIN_LEVEL = LEVELS[LEVEL] || LEVELS.info;
const DATE = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
const FILE = path.join(LOG_DIR, `ip2region-${DATE}.log`);

// 时间戳前缀
const ts = () => new Date().toISOString();

// 按级别格式化一行
function format(level, args) {
  const time = ts();
  const msg = args
    .map((a) => (typeof a === "string" ? a : safeStringify(a)))
    .join(" ");
  return `${time} [${level.toUpperCase()}] ${msg}`;
}

function safeStringify(value) {
  try {
    return JSON.stringify(value);
  } catch (err) {
    return String(value);
  }
}

// 环形缓冲：最多缓存 128 行，超过就提前落盘
const BUFFER_MAX = 128;
let buffer = [];
let flushTimer = null;
const FLUSH_DELAY = 200; // 防抖延迟（毫秒）

// 立即落盘（不经过防抖）
function flushSync() {
  if (buffer.length === 0) return;
  const lines = buffer.splice(0, buffer.length).join("\n") + "\n";
  try {
    // 确保日志目录存在
    if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
    fs.appendFileSync(FILE, lines);
  } catch (err) {
    // 兜底：落盘失败时直接打印到 stdout，避免完全丢日志
    process.stdout.write(err.message + "\n");
  }
}

// 异步防抖落盘
function flushAsync() {
  if (flushTimer) return; // 已有待执行的 flush，忽略
  flushTimer = setTimeout(() => {
    flushTimer = null;
    flushSync();
  }, FLUSH_DELAY);
}

// 写入一条日志
function write(level, args) {
  if (LEVELS[level] < MIN_LEVEL) return;
  const line = format(level, args);
  buffer.push(line);

  // 同时输出到 stdout（便于 PM2 / 日志平台采集）
  const out = level === "error" || level === "warn"
    ? process.stderr
    : process.stdout;
  out.write(line + "\n");

  // 错误级别立即落盘；否则缓冲防抖
  if (level === "error") {
    flushSync();
  } else {
    flushAsync();
  }
}

// 访问日志：记录一次 HTTP 请求
function access(req, res, durationMs) {
  const method = req.method || "GET";
  const url = (req && req.url) || "-";
  const ip = (req && req.socket && req.socket.remoteAddress) || "-";
  const status = res && res.statusCode ? res.statusCode : "-";
  const line = format("info", [
    `access ${method} ${url} ${status} ${durationMs}ms client=${ip}`,
  ]);

  const out = process.stdout;
  out.write(line + "\n");

  buffer.push(line);
  flushSync(); // 访问日志每条都落盘，保证可追溯
}

// 优雅关闭：退出前确保缓冲落盘
function close() {
  if (flushTimer) {
    clearTimeout(flushTimer);
    flushTimer = null;
  }
  flushSync();
}

// 对外暴露的方法
const logger = {
  debug: (...args) => write("debug", args),
  info: (...args) => write("info", args),
  warn: (...args) => write("warn", args),
  error: (...args) => write("error", args),
  access,
  close,
};

module.exports = logger;
