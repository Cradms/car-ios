# 复刻版生产镜像（纯标准库，无需 requirements）
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    REPLICA_ENV=prod \
    HOST=0.0.0.0 \
    DATA_FILE=/data/data.json \
    LOG_FILE=/data/requests.log

WORKDIR /app

COPY . /app
# 构建时组装 site/（含卡密清理），随后删掉原始抓取包减小体积
RUN python build.py && rm -rf /app/_dump /app/_test /app/shots /app/data.json /app/requests.log

RUN useradd -m -u 10001 app && mkdir -p /data && chown -R app /data
USER app

VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/',timeout=2)"

CMD ["python", "server.py", "8080"]
