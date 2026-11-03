#!/usr/bin/env python3
"""StudsRNG progression simulator: python3 tools/simulate.py [hours]

Plays the game second by second as a sensible, active player and prints
when each zone, rebirth and stud milestone happens. It reads the real data
straight from the Lua files (zone prices and multipliers, studs, upgrades,
Config numbers), so after a balance change just run it again.

The player:
  - walks the keys of their best zone: PRESSES presses a second, keeping a
    combo going; Lucky Keys crits; enemies add ENEMY_SHARE on top
  - rolls with Auto Roll as soon as it's bought (free rolls first, then
    paid while Clacks allow), else by hand at half the speed
  - equips their best studs; every stud found counts towards the index
  - buys the next zone the moment they can, then the cheapest upgrade they
    can afford without delaying the next zone much
  - rebirths when it's affordable and the next zone is far off
  - earns Zone Mastery stars (Shared/Mastery: zone studs found + KILLS_PER_MIN
    enemies a minute in the zone they play), which add Clacks everywhere and
    pay more on that zone's keys; gets the Zone Set bonus when 3 of the
    equipped studs share a zone; plays the Favoured / Vintage rotation at its
    average odds (it never moves to a weaker zone for it)
  - skips: variants, fusing, quests, Focus, daily rewards, events, boosts,
    Stud Memories, squad roles / squad combo, Robux (they all only make
    progress faster)

Targets (an active player, hours of play): zone 2 in ~2 min, zone 5 in
~20 min, zone 10 in ~2 h, zone 20 in ~15 h, the last zone in ~80 h.
"""
import math, random, re, sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src" / "ReplicatedStorage" / "Shared"
random.seed(7)

PRESSES = 3.5          # keys a second while walking the board
COMBO = 0.4            # average combo bonus while pressing (Config.Combo caps it)
ENEMY_SHARE = 0.15     # Clacks from fights on top of keys
KILLS_PER_MIN = 4      # enemies defeated a minute in the zone being played
MANUAL_ROLL_SPEED = 0.5  # rolls a second before Auto Roll (by hand)
ROLL_BUDGET = 0.35     # share of income spent on paid rolls (Auto Roll on)

def lua_number(text):
    return float(text.replace("_", ""))

# --- Config ------------------------------------------------------------------
config = (SRC / "Config.lua").read_text()
def config_value(block, key):
    m = re.search(rf"Config\.{block}\s*=\s*\{{(.*?)\n\}}", config, re.S)
    v = re.search(rf"\b{key}\s*=\s*([\d_.]+)", m.group(1))
    return lua_number(v.group(1))

ROLL_COST = config_value("Rolls", "ClackCost")
ZONE_COST_POWER = config_value("Rolls", "ZoneCostPower")
ROLL_COOLDOWN = config_value("Rolls", "Cooldown")
MIN_COST_FRACTION = config_value("Rolls", "MinCostFraction")
BASE_SLOTS = config_value("Inventory", "BaseSlots")
MAX_SLOTS = config_value("Inventory", "MaxSlots")
PRESSES_PER_FREE = config_value("Economy", "PressesPerFreeRoll")
MIN_PRESSES_PER_FREE = config_value("Economy", "MinPressesPerFreeRoll")
REBIRTH_BASE = config_value("Rebirth", "BaseCost")
REBIRTH_GROWTH = config_value("Rebirth", "CostGrowth")
REBIRTH_CLACKS = config_value("Rebirth", "ClacksPerRebirth")
REBIRTH_LUCK = config_value("Rebirth", "LuckPerRebirth")
LUCKY_ROLLS = config_value("LuckyMeter", "Rolls")
LUCKY_LUCK = config_value("LuckyMeter", "Luck")
_rush = re.search(r"Rush = \{ Every = ([\d_]+), Seconds = ([\d.]+) \}", config)
RUSH_SHARE = float(_rush.group(2)) * PRESSES / lua_number(_rush.group(1))  # extra x1 Clacks this share of the time
RESET_ZONES = re.search(r"ResetZones\s*=\s*(true|false)", config).group(1) == "true"
MASTERY_KILLS = config_value("Mastery", "Kills")
MASTERY_GLOBAL = config_value("Mastery", "GlobalClacks")
_kb = re.search(r"KeyBonus = \{ \[2\] = ([\d.]+), \[3\] = ([\d.]+) \}", config)
MASTERY_KEY = {2: float(_kb.group(1)), 3: float(_kb.group(2))}
_zs = re.search(r"ZoneSet = \{ SetSize = (\d+), Clacks = ([\d.]+) \}", config)
SET_SIZE, SET_CLACKS = int(_zs.group(1)), float(_zs.group(2))
EARLY_MAX = config_value("ZoneRotation", "EarlyMax")
_fav = re.search(r"Favoured = \{ Luck = ([\d.]+), Clacks = ([\d.]+) \}", config)
_vin = re.search(r"Vintage = \{ Luck = ([\d.]+), Clacks = ([\d.]+), Count = (\d+) \}", config)
FAV_LUCK, FAV_CLACKS = float(_fav.group(1)), float(_fav.group(2))
VIN_LUCK, VIN_CLACKS, VIN_COUNT = float(_vin.group(1)), float(_vin.group(2)), int(_vin.group(3))
milestones = [
    {k: lua_number(v) for k, v in re.findall(r"(\w+)\s*=\s*([\d_.]+)", m)}
    for m in re.findall(r"\{\s*(Count[^}]*)\}", re.search(r"local milestones.*?\n\}", config, re.S).group(0))
]

# --- Zones -------------------------------------------------------------------
zones_lua = (SRC / "Zones.lua").read_text()
COUNT = int(re.search(r"local COUNT = (\d+)", zones_lua).group(1))
HAND_PRICES = [lua_number(x) for x in re.search(r"HAND_PRICES = \{([^}]*)\}", zones_lua).group(1).split(",")]
HAND_MULTS = [lua_number(x) for x in re.search(r"HAND_MULTIPLIERS = \{([^}]*)\}", zones_lua).group(1).split(",")]
PRICE_GROWTH = lua_number(re.search(r"PRICE_GROWTH = ([\d.]+)", zones_lua).group(1))
PRICE_GROWTH_END = lua_number(re.search(r"PRICE_GROWTH_END = ([\d.]+)", zones_lua).group(1))
MULT_GROWTH = lua_number(re.search(r"MULTIPLIER_GROWTH = ([\d.]+)", zones_lua).group(1))

def round2(v):
    s = 10 ** max(0, math.floor(math.log10(v)) - 1)
    return math.floor(v / s + 0.5) * s

zones = []
for n in range(COUNT):
    if n < len(HAND_PRICES):
        zones.append((HAND_PRICES[n], HAND_MULTS[n]))
    else:
        p, m = zones[-1]
        order = n + 1
        growth = PRICE_GROWTH + (PRICE_GROWTH_END - PRICE_GROWTH) * (order - len(HAND_PRICES)) / max(COUNT - len(HAND_PRICES), 1)
        zones.append((round2(p * growth), math.floor(m * MULT_GROWTH + 0.5)))

# Chance a zone is Favoured today / Vintage this week (Shared/ZoneRotation).
def rotation_odds(n):
    early = min(EARLY_MAX, COUNT)
    fav = 1 / early if n <= early else 1 / max(COUNT - early, 1)
    vin = (1 - fav) * VIN_COUNT / COUNT
    return fav, vin

# --- Studs ---------------------------------------------------------------------
studs_lua = (SRC / "Studs.lua").read_text()
studs = []
for m in re.finditer(r'Id = "(\w+)".*?Rarity = "(\w+)", OneIn = ([\d_]+), Multiplier = ([\d.]+), World = "(\w+)"(, Drop = true)?', studs_lua):
    if m.group(6):
        continue
    world = m.group(5)
    if not world.isdigit():
        continue
    studs.append({"id": m.group(1), "rarity": m.group(2), "one_in": lua_number(m.group(3)),
                  "mult": lua_number(m.group(4)), "zone": int(world)})
studs.sort(key=lambda s: -s["one_in"])
# Mastery counts each zone's non-Secret studs.
zone_studs = {}
for st in studs:
    if st["rarity"] != "Secret":
        zone_studs.setdefault(st["zone"], set()).add(st["id"])

# --- Upgrades ------------------------------------------------------------------
up_lua = (SRC / "Upgrades.lua").read_text()
upgrades = []
for m in re.finditer(r'\{\s*Id = "(\w+)".*?Stat = "(\w+)", PerLevel = ([\d.]+), MaxLevel = (\d+), BaseCost = ([\d_]+), CostGrowth = ([\d.]+)', up_lua, re.S):
    upgrades.append({"id": m.group(1), "stat": m.group(2), "per": float(m.group(3)), "max": int(m.group(4)),
                     "base": lua_number(m.group(5)), "growth": float(m.group(6))})

def upgrade_cost(u, level):
    v = u["base"] * u["growth"] ** level
    s = 10 ** max(0, math.floor(math.log10(v)) - 1)
    return math.floor(v / s + 0.5) * s

# --- Player --------------------------------------------------------------------
class Player:
    def __init__(self):
        self.clacks = 0.0
        self.zone = 1
        self.rebirths = 0
        self.levels = {u["id"]: 0 for u in upgrades}
        self.owned = {}          # stud id -> count
        self.found = set()
        self.meter = 0.0
        self.free = 0
        self.rolls = 0
        self.cached = None
        self.kills = {}          # zone -> enemies defeated there

    def stat(self, name):
        return sum(u["per"] * self.levels[u["id"]] for u in upgrades if u["stat"] == name)

    def bonuses(self):
        slots = luck = clacks = 0
        for m in milestones:
            if len(self.found) >= m["Count"]:
                slots += m.get("Slots", 0); luck += m.get("Luck", 0); clacks += m.get("Clacks", 0)
        return slots, luck, clacks

    def slots(self):
        s, _, _ = self.bonuses()
        return int(min(MAX_SLOTS, BASE_SLOTS + s + self.stat("Slots")))

    def equipped(self):
        picks = []
        for st in studs:
            picks += [st] * min(self.owned.get(st["id"], 0), 12)
        picks.sort(key=lambda st: -st["mult"])
        return picks[: self.slots()]

    def stud_bonus(self):
        return sum(st["mult"] - 1 for st in self.equipped())

    def zone_set(self):
        counts = {}
        for st in self.equipped():
            counts[st["zone"]] = counts.get(st["zone"], 0) + 1
        return any(c >= SET_SIZE for c in counts.values())

    def stars(self, n):
        if n > self.zone:
            return 0
        ids = zone_studs.get(n, set())
        have = len(ids & self.found)
        if not ids or have < len(ids) - 1:
            return 1
        if have < len(ids):
            return 2
        return 3 if self.kills.get(n, 0) >= MASTERY_KILLS else 2

    def total_stars(self):
        return sum(self.stars(n) for n in range(1, self.zone + 1))

    def clack_mult(self):
        if self.cached is None:
            self.cached = self._clack_mult()
        return self.cached

    def _clack_mult(self):
        _, _, bonus = self.bonuses()
        lasting = self.total_stars() * MASTERY_GLOBAL + (SET_CLACKS if self.zone_set() else 0)
        return ((1 + self.stud_bonus()) * (1 + bonus + lasting)
                * (1 + REBIRTH_CLACKS + self.stat("RebirthBonus")) ** self.rebirths
                * (1 + self.stat("ClacksPct")))

    def luck(self):
        _, bonus, _ = self.bonuses()
        fav, vin = rotation_odds(self.zone)
        rotation = 1 + fav * (FAV_LUCK - 1) + vin * (VIN_LUCK - 1)  # on average
        return (1 + bonus) * (1 + self.rebirths * REBIRTH_LUCK) * (1 + self.stat("LuckPct")) * rotation

    def roll(self):
        luck = self.luck()
        self.rolls += 1
        self.meter_lucky = getattr(self, "meter_lucky", 0) + 1
        if self.meter_lucky >= LUCKY_ROLLS:
            self.meter_lucky = 0
            luck *= LUCKY_LUCK
        hit = None
        for st in studs:
            if st["zone"] <= self.zone and random.random() < luck / st["one_in"]:
                hit = st
                break
        if hit is None:
            hit = studs[-1]
        if hit["id"] not in self.found or self.owned.get(hit["id"], 0) < 12:
            self.cached = None
        self.owned[hit["id"]] = self.owned.get(hit["id"], 0) + 1
        self.found.add(hit["id"])
        return hit

    def key_scale(self):
        fav, vin = rotation_odds(self.zone)
        rotation = 1 + fav * (FAV_CLACKS - 1) + vin * (VIN_CLACKS - 1)  # on average
        return rotation * (1 + MASTERY_KEY.get(self.stars(self.zone), 0))

    def per_second(self):
        _, key_mult = zones[self.zone - 1]
        key_mult *= self.key_scale()
        crit = 1 + self.stat("CritChance")
        speed = 1 + self.stat("WalkSpeed") / 16
        return PRESSES * speed * key_mult * self.clack_mult() * (1 + COMBO) * crit * (1 + ENEMY_SHARE) * (1 + RUSH_SHARE)

    def zone_price(self, n):
        return zones[n - 1][0] * (1 - min(0.5, self.stat("ZoneDiscountPct")))

def simulate(hours):
    p = Player()
    t = 0
    zone_at = {1: 0}
    rebirth_at = []
    stud_milestones = []
    best_one_in = 0
    report_every = 3600
    timeline = []
    while t < hours * 3600:
        t += 1
        if t % 60 == 0:
            before = p.stars(p.zone)
            p.kills[p.zone] = p.kills.get(p.zone, 0) + KILLS_PER_MIN
            if p.stars(p.zone) != before:
                p.cached = None
        gain = p.per_second()
        p.clacks += gain
        # Free rolls from presses
        presses = PRESSES * (1 + p.stat("WalkSpeed") / 16)
        per_free = max(MIN_PRESSES_PER_FREE, PRESSES_PER_FREE * (1 - p.stat("MeterPct")))
        p.meter += presses
        while p.meter >= per_free:
            p.meter -= per_free
            p.free += 1
        # Rolling
        auto = p.levels.get("AutoRoll", 0) > 0
        speed = (1 + p.stat("RollSpeedPct")) / ROLL_COOLDOWN if auto else MANUAL_ROLL_SPEED
        rolls_now = speed
        whole = int(rolls_now) + (1 if random.random() < rolls_now - int(rolls_now) else 0)
        cost = ROLL_COST * max(MIN_COST_FRACTION, 1 - p.stat("RollCostPct")) * zones[p.zone - 1][1] ** ZONE_COST_POWER
        p.budget = getattr(p, "budget", 0.0) + gain * ROLL_BUDGET if auto else 0.0
        for _ in range(whole):
            if p.free > 0:
                p.free -= 1
            elif auto and p.budget >= cost and p.clacks >= cost:
                p.budget -= cost
                p.clacks -= cost
            else:
                break
            hit = p.roll()
            extra = p.stat("ExtraRollChance")
            if random.random() < extra:
                p.roll()
            if hit["one_in"] > best_one_in:
                best_one_in = hit["one_in"]
                stud_milestones.append((t, hit["id"], hit["rarity"], hit["one_in"]))
        # Zones
        while p.zone < COUNT and p.clacks >= p.zone_price(p.zone + 1):
            p.clacks -= p.zone_price(p.zone + 1)
            p.zone += 1
            p.cached = None
            zone_at.setdefault(p.zone, t)
        # Upgrades: cheapest affordable that keeps most of the next zone's savings
        next_price = p.zone_price(p.zone + 1) if p.zone < COUNT else math.inf
        options = [(upgrade_cost(u, p.levels[u["id"]]), u) for u in upgrades if p.levels[u["id"]] < u["max"]]
        options.sort(key=lambda x: x[0])
        for cost_u, u in options:
            if cost_u <= p.clacks and (cost_u <= 0.25 * p.clacks or cost_u < 0.1 * next_price):
                p.clacks -= cost_u
                p.levels[u["id"]] += 1
                p.cached = None
            else:
                break
        # Rebirth: when zones are kept, as soon as it's no dearer than the next
        # zone (or that zone is far off); when they reset, only when stuck.
        rebirth_cost = REBIRTH_BASE * REBIRTH_GROWTH ** p.rebirths
        eta = (next_price - p.clacks) / gain if gain > 0 else math.inf
        wants = (rebirth_cost <= next_price or eta > 10 * 60) if not RESET_ZONES else eta > 15 * 60
        if p.clacks >= rebirth_cost and wants:
            p.rebirths += 1
            rebirth_at.append((t, p.rebirths, p.zone))
            p.clacks = 0
            if RESET_ZONES:
                p.zone = 1
            p.cached = None
        if t % report_every == 0:
            timeline.append((t / 3600, p.zone, max(zone_at), p.rebirths, p.clack_mult(), p.luck(), best_one_in, len(p.found), p.rolls, p.total_stars()))
    return zone_at, rebirth_at, stud_milestones, timeline

def fmt_time(seconds):
    if seconds < 3600:
        return f"{seconds / 60:5.1f} min"
    return f"{seconds / 3600:5.1f} h  "

def main():
    hours = float(sys.argv[1]) if len(sys.argv) > 1 else 100
    zone_at, rebirth_at, stud_milestones, timeline = simulate(hours)
    print(f"{len(studs)} rollable studs, {len(upgrades)} upgrades, {COUNT} zones; {hours:g} h simulated\n")
    print("First reached (play time):")
    for n in sorted(zone_at):
        price, mult = zones[n - 1]
        print(f"  zone {n:2d}  {fmt_time(zone_at[n])}   price {price:<10.3g} keys x{mult:g}")
    print(f"\nRebirths: {len(rebirth_at)}" + "".join(f"\n  #{r:<2d} at {fmt_time(t)} (was in zone {z})" for t, r, z in rebirth_at[:12]))
    print("\nBest stud so far:")
    for t, sid, rarity, one_in in stud_milestones[-12:]:
        print(f"  {fmt_time(t)}  {sid} ({rarity}, 1 in {one_in:,.0f})")
    print("\n hour  zone  best  rebirths  clack x     luck   best 1-in   found  rolls  stars")
    for row in timeline[:: max(1, len(timeline) // 20)]:
        h, z, bz, r, cm, lk, bo, f, rl, stars = row
        print(f" {h:5.0f}  {z:4d}  {bz:4d}  {r:8d}  {cm:9.3g}  {lk:6.2f}  {bo:10,.0f}  {f:5d}  {rl:6d}  {stars:5d}")

if __name__ == "__main__":
    main()
