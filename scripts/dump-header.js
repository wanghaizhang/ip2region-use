/**
 * 诊断脚本：打印 ip2region_v4.xdb 的头部原始字节
 * 用于确认 xdb 格式的具体结构
 * 
 * 运行：node scripts/dump-header.js
 */

const fs = require("fs");
const path = require("path");

const dbPath = path.join(__dirname, "..", "data", "ip2region_v4.xdb");
const buffer = fs.readFileSync(dbPath);

console.log("文件总大小:", buffer.length, "bytes");
console.log("");

// 打印前 256 字节的十六进制
const hexDump = [];
for (let i = 0; i < Math.min(256, buffer.length); i++) {
    hexDump.push(buffer[i].toString(16).padStart(2, "0"));
}
console.log("前 256 字节 hex:");
console.log(hexDump.join(" "));
console.log("");

// 解析前 56 字节（假设的 header 大小）
console.log("头部解析（假说）:");
console.log("  XDB_MAGIC (0-31):", buffer.slice(0, 32));
console.log("  IndexBlockPtr (32-35):", buffer.readUInt32LE(32));
console.log("  LastIndexBlockPtr (36-39):", buffer.readUInt32LE(36));
console.log("  TotalBlocks (40-43):", buffer.readUInt32LE(40));
console.log("  DataBlockIndexBlockPtr (44-47):", buffer.readUInt32LE(44));
console.log("  IndexBlockPtr2 (48-51):", buffer.readUInt32LE(48));
console.log("  DataIndexBlockPtr (52-55):", buffer.readUInt32LE(52));
console.log("");

// 尝试解析索引块
const totalBlocks = buffer.readUInt32LE(40);
const indexBlockPtr = buffer.readUInt32LE(32);
console.log(`TotalBlocks: ${totalBlocks}, IndexBlockPtr: ${indexBlockPtr}`);

console.log("索引块 0 (前 12 字节):");
console.log("  sip (offset 0):", buffer.readUInt32LE(indexBlockPtr));
console.log("  eip (offset 4):", buffer.readUInt32LE(indexBlockPtr + 4));
console.log("  data offset (offset 8):", buffer.readUInt32LE(indexBlockPtr + 8));
