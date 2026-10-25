"""Shipwave worker. Pre-built image: learners deploy it, they do not change it."""
import time

print("shipwave-worker started", flush=True)
while True:
    print("worker heartbeat: no jobs queued", flush=True)
    time.sleep(30)
