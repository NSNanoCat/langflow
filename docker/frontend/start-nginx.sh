#!/bin/sh
set -e

# 中文：定义最终 nginx 配置使用的可写目录。
# English: Define the writable directory used by the final nginx config.
CONFIG_DIR="/tmp/nginx"
mkdir -p $CONFIG_DIR

# 中文：检查并设置运行时环境变量。
# English: Check and set runtime environment variables.
if [ -z "$BACKEND_URL" ]; then
  BACKEND_URL="$1"
fi
if [ -z "$FRONTEND_PORT" ]; then
  FRONTEND_PORT="$2"
fi
if [ -z "$FRONTEND_PORT" ]; then
  # 中文：修复 Railway 只注入 PORT 时前端 nginx 仍监听 80 导致服务不可达的问题。
  # English: Fix Railway deployments where nginx keeps listening on 80 when only PORT is injected.
  FRONTEND_PORT="$PORT"
fi
if [ -z "$FRONTEND_PORT" ]; then
  FRONTEND_PORT="80"
fi
if [ -z "$LANGFLOW_MAX_FILE_SIZE_UPLOAD" ]; then
  LANGFLOW_MAX_FILE_SIZE_UPLOAD="1"
fi
if [ -z "$NGINX_RESOLVER" ]; then
  # 中文：修复 Railway 私网 DNS 变化后 nginx 缺少运行时 resolver 导致代理卡住的问题。
  # English: Fix Railway private DNS changes causing stuck nginx proxying when no runtime resolver is configured.
  NGINX_RESOLVER="$(awk '/^nameserver / { printf "%s ", $2 }' /etc/resolv.conf | sed 's/[[:space:]]*$//')"
fi
if [ -z "$NGINX_RESOLVER" ]; then
  NGINX_RESOLVER="127.0.0.11"
fi
if [ -z "$BACKEND_URL" ]; then
  echo "BACKEND_URL must be set as an environment variable or as first parameter. (e.g. http://localhost:7860)"
  exit 1
fi

# 中文：导出 envsubst 需要替换的变量。
# English: Export variables required by envsubst.
export BACKEND_URL FRONTEND_PORT LANGFLOW_MAX_FILE_SIZE_UPLOAD NGINX_RESOLVER

# 中文：使用 envsubst 将环境变量替换到模板中。
# English: Use envsubst to substitute environment variables into the template.
envsubst '${BACKEND_URL} ${FRONTEND_PORT} ${LANGFLOW_MAX_FILE_SIZE_UPLOAD} ${NGINX_RESOLVER}' < /etc/nginx/conf.d/default.conf.template > $CONFIG_DIR/default.conf

# 中文：使用生成后的配置启动 nginx。
# English: Start nginx with the generated configuration.
exec nginx -c $CONFIG_DIR/default.conf -g 'daemon off;'
