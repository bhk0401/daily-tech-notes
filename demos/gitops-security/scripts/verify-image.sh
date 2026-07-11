#!/bin/bash
# 镜像签名验证脚本
# 用法：./verify-image.sh <image-name>

set -e

IMAGE=$1

if [ -z "$IMAGE" ]; then
    echo "用法：$0 <image-name>"
    echo "示例：$0 ghcr.io/your-org/your-app:v1.0.0"
    exit 1
fi

echo "🔍 验证镜像签名：$IMAGE"
echo ""

# 检查 cosign 是否安装
if ! command -v cosign &> /dev/null; then
    echo "❌ cosign 未安装，请先安装：https://docs.sigstore.dev/"
    exit 1
fi

# 验证签名
echo "执行 cosign verify..."
cosign verify "$IMAGE" \
    --certificate-identity-regexp=https://github.com/your-org/.* \
    --certificate-oidc-issuer=https://token.actions.githubusercontent.com

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 签名验证通过！"
else
    echo ""
    echo "❌ 签名验证失败！"
    exit 1
fi
