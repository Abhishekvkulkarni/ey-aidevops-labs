"""Shipwave rate engine: price a parcel quote.  Rules are written in rates-spec.md (R1-R8)."""
import math
from decimal import Decimal, ROUND_HALF_EVEN

ZONES = {"metro": Decimal("1.0"), "regional": Decimal("1.2"), "remote": Decimal("1.5")}
SERVICES = {"standard": Decimal("1.0"), "express": Decimal("1.6")}
TIER_DISCOUNT = {"none": Decimal("0"), "silver": Decimal("0.05"), "gold": Decimal("0.10")}
DISCOUNT_CAP = Decimal("150.00")
MIN_CHARGE = Decimal("45.00")
FUEL = Decimal("0.08")
VOLUMETRIC_DIVISOR = 5000


def chargeable_weight(weight_kg, dims_cm=None):
    """The larger of the real weight and the volumetric weight (length x width x height / 5000)."""
    w = Decimal(str(weight_kg))
    if dims_cm:
        l, wd, h = (Decimal(str(d)) for d in dims_cm)
        vol = l * wd * h / VOLUMETRIC_DIVISOR
        return max(w, vol)
    return w


def weight_charge(w):
    """Base price for a chargeable weight in kg."""
    if w <= 0 or w > 70:
        raise ValueError("weight must be above 0 and at most 70 kg")
    if w < Decimal("0.5"):
        return Decimal("40.00")
    elif w <= 2:
        return Decimal("70.00")
    elif w <= 10:
        return Decimal("70.00") + Decimal("15.00") * math.ceil(w - 2)
    return Decimal("190.00") + Decimal("12.00") * math.ceil(w - 10)


def quote(weight_kg, zone, service="standard", tier="none", dims_cm=None):
    """Total price in rupees as a Decimal with 2 places."""
    if zone not in ZONES:
        raise ValueError(f"unknown zone: {zone}")
    if service not in SERVICES:
        raise ValueError(f"unknown service: {service}")
    if tier not in TIER_DISCOUNT:
        raise ValueError(f"unknown tier: {tier}")
    w = chargeable_weight(weight_kg, dims_cm)
    subtotal = weight_charge(w) * ZONES[zone] * SERVICES[service]
    discount = min(subtotal * TIER_DISCOUNT[tier], DISCOUNT_CAP)
    after_discount = subtotal - discount
    subtotal = max(after_discount, MIN_CHARGE)
    total = subtotal + subtotal * FUEL
    return total.quantize(Decimal("0.01"), rounding=ROUND_HALF_EVEN)
