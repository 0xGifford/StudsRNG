"""StudsRNG balance simulator: python3 tools/balance.py

Mirrors the formulas in Shared/Zones.lua, Shared/Enemies.lua and
Shared/Util/RollLogic.lua (statsOf) for an "on-level" player at each zone,
and prints how long the next zone takes and how fights go. Change the
constants here and in the Lua files together.

Assumptions about an on-level player (tune these to playtest data):
  - presses 4 keys a second
  - Clacks multiplier (studs, rebirths, upgrades) grows log-linearly from
    x1.5 at zone 1 to x50,000 at zone 50
  - rarest stud held grows log-linearly from 1 in 3 to 1 in 1,000,000
  - slots 3 + zone/6 (max 12), stud level 1 + zone*0.8 (max 50),
    variant stats 1 + zone*0.05
Targets: ~4 min per zone early -> ~45 near the end; ~4-7 s per kill;
team survives 2-4x the kill time.
"""
import math

# --- Shared/Zones.lua ---
HAND = [(0, 1), (1_400, 2), (3_700, 4), (9_700, 7), (22_000, 11), (45_000, 17), (91_000, 26)]
PRICE_GROWTH, MULTIPLIER_GROWTH = 1.95, 1.5
# --- Shared/Enemies.lua ---
def enemy_health(n): return math.floor(45 * 1.2 ** n)
def enemy_damage(n): return 4 * 1.16 ** n
# --- Shared/Util/RollLogic.lua statsOf ---
STRENGTH_BASE, HEALTH_BASE = 3, 14

PRESSES_PER_SEC = 4
def clack_mult(n): return math.exp(math.log(1.5) + (math.log(5e4) - math.log(1.5)) * (n - 1) / 49)
def onlevel_one_in(n): return math.exp(math.log(3) + (math.log(1e6) - math.log(3)) * (n - 1) / 49)
def slots(n): return min(12, 3 + n // 6)
def level_bonus(n): return 1 + (min(50, 1 + int(n * 0.8)) - 1) * 0.05
def variant_stats(n): return 1 + n * 0.05

def round2(v):
    s = 10 ** max(0, math.floor(math.log10(v)) - 1)
    return math.floor(v / s + 0.5) * s

def zones():
    z = list(HAND)
    while len(z) < 50:
        p, m = z[-1]
        z.append((round2(p * PRICE_GROWTH), math.floor(m * MULTIPLIER_GROWTH + 0.5)))
    return z

def main():
    z = zones()
    print(" zone  next price   key x    min to next | enemy HP   kill s  survive s")
    for n in [1, 2, 3, 4, 5, 7, 10, 15, 20, 25, 30, 35, 40, 45, 49]:
        price_next, _ = z[n]
        _, km = z[n - 1]
        minutes = price_next / (PRESSES_PER_SEC * km * clack_mult(n)) / 60
        o = onlevel_one_in(n)
        scale = variant_stats(n) * level_bonus(n) * slots(n)
        strength = STRENGTH_BASE * o ** 0.38 * scale
        health = HEALTH_BASE * o ** 0.36 * scale
        kill = max(1.5, enemy_health(n) / strength) + 0.7  # MinFightTime, ArriveTime
        print(f" {n:4d}  {price_next:<11.3g} {km:<8.3g} {minutes:8.1f}    | {enemy_health(n):<9d} {kill:6.1f} {health / enemy_damage(n):9.1f}")

if __name__ == "__main__":
    main()
