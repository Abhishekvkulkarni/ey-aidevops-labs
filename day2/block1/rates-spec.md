# Spec: Shipwave rate engine (`src/rates.py`)

Function: `quote(weight_kg, zone, service="standard", tier="none", dims_cm=None)` returns the total price in rupees as a `Decimal` with 2 decimal places.

## Requirements

1. **R1 Weight bands** (chargeable weight in kg):
   up to **and including** 0.5 kg = 40.00;
   above 0.5 up to and including 2 kg = 70.00;
   above 2 up to and including 10 kg = 70.00 plus 15.00 for every *started* kg above 2;
   above 10 kg = 190.00 plus 12.00 for every *started* kg above 10.
   A weight of 0 or less, or above 70 kg, raises `ValueError`.
2. **R2 Chargeable weight.** When `dims_cm=(length, width, height)` is given, volumetric weight = length x width x height / 5000. The chargeable weight is the larger of the real weight and the volumetric weight.
3. **R3 Zone multiplier** on the weight charge: metro 1.0, regional 1.2, remote 1.5. An unknown zone raises `ValueError`.
4. **R4 Service multiplier**: standard 1.0, express 1.6. An unknown service raises `ValueError`.
5. **R5 Loyalty discount** taken off the amount after R3 and R4: none 0%, silver 5%, gold 10%. The discount is **never more than 150.00**. An unknown tier raises `ValueError`.
6. **R6 Minimum charge.** After the discount the amount is at least 45.00.
7. **R7 Fuel surcharge**: 8% of the amount after R6, added on top.
8. **R8 Rounding.** The total is rounded to 2 decimals, **half up** (0.005 rounds to 0.01). Not banker's rounding.

Order of calculation: R1 and R2, then R3 and R4, then R5, then R6, then R7, then R8.

## Worked examples (use these as test cases)

| Weight (kg) | Zone | Service | Tier | Dimensions (cm) | Total |
|---|---|---|---|---|---|
| 0.3 | metro | standard | none | - | 48.60 |
| 0.5 | metro | standard | none | - | 48.60 |
| 1.5 | regional | standard | none | - | 90.72 |
| 2 | metro | standard | none | - | 75.60 |
| 2.1 | metro | express | none | - | 146.88 |
| 5 | remote | standard | silver | - | 176.99 |
| 10 | metro | standard | gold | - | 184.68 |
| 10.5 | regional | express | silver | - | 397.92 |
| 3 | metro | standard | none | 50 x 40 x 30 | 231.12 |
| 60 | remote | express | gold | - | 1885.68 |
| 70 | metro | standard | none | - | 982.80 |
| 0.1 | metro | standard | silver | - | 48.60 |

## Edge cases worth a test of their own

Weights exactly on a band edge (0.5, 2, 10). A weight just above an edge. Weight 0, negative, 70 and 70.01. A volumetric weight that beats the real weight, and one that does not. A discount that hits the 150.00 cap. A discount that drops the amount under the 45.00 minimum. A total that ends exactly on a half-cent. Each of the three `ValueError` cases.
