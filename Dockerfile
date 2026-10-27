FROM python:3.12-alpine AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

COPY requirements.txt .

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


FROM python:3.12-alpine AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SQLITE_PATH=/data/loja.db

WORKDIR /app

RUN addgroup -S appgroup \
    && adduser -S -u 10001 -G appgroup appuser \
    && mkdir -p /data \
    && chown appuser:appgroup /data

COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appgroup app/ ./app/
COPY --chown=appuser:appgroup static/ ./static/

USER 10001:appgroup

EXPOSE 8000

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
