# Trainer builds and pushes this once: <ACR>/shared/shipwave-worker:1.0
FROM python:3.12-slim
RUN useradd --uid 10001 --no-create-home worker
WORKDIR /app
COPY worker.py .
USER 10001
CMD ["python", "-u", "worker.py"]
