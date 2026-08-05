#!/bin/bash
# 进程检查脚本 - 在 Ephemeral Container 中运行（需 --share-processes）
# 用法：kubectl debug -it <pod> --image=ubuntu --target=<container> --share-processes
#       然后粘贴此脚本内容执行

set -e

echo "=== Kubernetes Ephemeral Container 进程诊断 ==="
echo "时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 查找目标容器的主进程 PID（通常是 PID 1 之外的第一个进程）
TARGET_PID=$(ps aux | grep -v "PID\|grep\|bash\|sh" | awk '{print $2}' | head -1)

if [ -z "$TARGET_PID" ]; then
    echo "未找到目标进程"
    exit 1
fi

echo "目标进程 PID: $TARGET_PID"
echo ""

# 1. 进程树
echo "=== 1. 进程树 ==="
ps auxf
echo ""

# 2. 进程详情
echo "=== 2. 进程详情 (PID: $TARGET_PID) ==="
ps -p $TARGET_PID -o pid,ppid,user,%cpu,%mem,vsz,rss,stat,start,time,comm
echo ""

# 3. 打开的文件描述符
echo "=== 3. 打开的文件描述符 ==="
ls -la /proc/$TARGET_PID/fd/ 2>/dev/null || echo "无法访问文件描述符"
echo ""

# 4. 内存映射
echo "=== 4. 内存映射 (前 20 行) ==="
cat /proc/$TARGET_PID/maps 2>/dev/null | head -20 || echo "无法访问内存映射"
echo ""

# 5. 环境变量
echo "=== 5. 环境变量 ==="
cat /proc/$TARGET_PID/environ 2>/dev/null | tr '\0' '\n' | head -20 || echo "无法访问环境变量"
echo ""

# 6. 当前工作目录
echo "=== 6. 当前工作目录 ==="
ls -la /proc/$TARGET_PID/cwd 2>/dev/null || echo "无法访问工作目录"
echo ""

# 7. 资源限制
echo "=== 7. 资源限制 ==="
cat /proc/$TARGET_PID/limits 2>/dev/null || echo "无法访问资源限制"
echo ""

echo "=== 诊断完成 ==="
