#!/bin/bash
# 手动生成自签名证书（适用于没有 cert-manager 的环境）
# 生产环境建议使用 cert-manager

set -e

NAMESPACE="webhook-system"
SERVICE_NAME="image-validator"
CERT_DIR="certs"

echo "=== 生成 Admission Webhook 自签名证书 ==="

# 创建证书目录
mkdir -p ${CERT_DIR}

# 生成 CA 私钥和证书
echo "[1/4] 生成 CA..."
openssl genrsa -out ${CERT_DIR}/ca.key 2048
openssl req -x509 -new -nodes -key ${CERT_DIR}/ca.key -days 365 \
    -subj "/CN=${SERVICE_NAME}-ca" \
    -out ${CERT_DIR}/ca.crt

# 生成服务器私钥
echo "[2/4] 生成服务器私钥..."
openssl genrsa -out ${CERT_DIR}/server.key 2048

# 生成 CSR
echo "[3/4] 生成证书签名请求..."
openssl req -new -key ${CERT_DIR}/server.key \
    -subj "/CN=${SERVICE_NAME}.${NAMESPACE}.svc" \
    -out ${CERT_DIR}/server.csr

# 生成服务器证书（使用 SAN 扩展）
echo "[4/4] 签发服务器证书..."
cat > ${CERT_DIR}/openssl.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = DNS:${SERVICE_NAME}.${NAMESPACE}.svc,DNS:${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
EOF

openssl x509 -req -in ${CERT_DIR}/server.csr \
    -CA ${CERT_DIR}/ca.crt -CAkey ${CERT_DIR}/ca.key \
    -CAcreateserial -out ${CERT_DIR}/server.crt \
    -days 365 \
    -extfile ${CERT_DIR}/openssl.cnf \
    -extensions v3_req

# 创建 Kubernetes Secret
echo "创建 TLS Secret..."
kubectl create secret tls ${SERVICE_NAME}-tls \
    --cert=${CERT_DIR}/server.crt \
    --key=${CERT_DIR}/server.key \
    -n ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== 证书生成完成 ==="
echo "CA 证书 Base64（用于 WebhookConfiguration 的 caBundle）:"
cat ${CERT_DIR}/ca.crt | base64 | tr -d '\n'
echo ""
echo ""
echo "将上述 Base64 字符串填入 validating-config.yaml 和 mutating-config.yaml 的 caBundle 字段"
