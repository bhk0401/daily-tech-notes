# mTLS Demo Project

## 快速开始
1. 安装 Istio: `istioctl install --set profile=demo`
2. 启用 mTLS: `kubectl apply -f mtls-strict.yaml`
3. 部署服务：`kubectl apply -f services.yaml`
4. 验证：`./verify-mtls.sh`

## 文件说明
- mtls-strict.yaml: mTLS 严格模式配置
- services.yaml: 示例服务定义
- verify-mtls.sh: 验证脚本
