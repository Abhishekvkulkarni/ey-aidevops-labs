FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
	PYTHONUNBUFFERED=1 \
	PATH=/home/appuser/.local/bin:$PATH

WORKDIR /app

COPY --from=builder /install /usr/local
COPY . .

RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin appuser \
	&& mkdir -p /tmp \
	&& chown -R 10001:10001 /app /tmp

USER 10001

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]