from fastapi import Depends, FastAPI, HTTPException

from app.auth import require_api_key
from app.db import all_shipments, get_shipment
from app.pagination import paginate

app = FastAPI(title="Shipwave API")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/shipments", dependencies=[Depends(require_api_key)])
def list_shipments(page: int = 1, size: int = 10):
    try:
        return paginate(all_shipments(), page, size)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.get("/shipments/{shipment_id}", dependencies=[Depends(require_api_key)])
def read_shipment(shipment_id: int):
    shipment = get_shipment(shipment_id)
    if shipment is None:
        raise HTTPException(status_code=404, detail="shipment not found")
    return shipment
