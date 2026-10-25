"""Current-baseline rules for the approximate simulator (Phase 2, 5-character combat).

Reads Config / Characters / BrickyardConfig Luau source text (NOT executed). Differences from the preserved Phase 1
loader (sim_rules.py): per-character maxHealth (SWORD 110 / PAINTBALL 95 / ...), and numeric literals written as
`a / b` (e.g. PAINTBALL fireInterval = 1 / 3) are evaluated. The Phase 1 loader would read that as 1.0 — see
docs/SIM_BASELINES.md. Raises on missing fields.
"""
from __future__ import annotations
import json
import re
from pathlib import Path
import sim_rules as legacy
from sim_rules import _strip_comments, _subtable

ROOT = legacy.ROOT
CHARACTER_IDS = ("SWORD", "PAINTBALL", "SUPERBALL", "TIMEBOMB", "SLINGSHOT")
_NUM = r'(-?\d+(?:\.\d+)?)(?:\s*/\s*(-?\d+(?:\.\d+)?))?'


def _number(code: str, key: str) -> float:
    m = re.search(r'(?<![\w.])' + re.escape(key) + r'\s*=\s*' + _NUM + r'(?![\w.])', code)
    if not m:
        raise ValueError(f'Missing Luau numeric key: {key}')
    a = float(m.group(1))
    return a / float(m.group(2)) if m.group(2) else a


def _max_health(chars: str, cid: str) -> float:
    m = re.search(r'Characters\.' + cid + r'\.maxHealth\s*=\s*(\d+(?:\.\d+)?)', chars)  # SWORD assigns it after the table
    if m:
        return float(m.group(1))
    return _number(_subtable(chars, 'Characters.' + cid), 'maxHealth')


def load_rules(root: Path = ROOT) -> dict:
    shared = root / 'src/shared'
    cfg = _strip_comments((shared / 'Config.luau').read_text(encoding='utf-8'))
    chars = _strip_comments((shared / 'Data/Characters.luau').read_text(encoding='utf-8'))
    map_src = _strip_comments((root / 'src/map/BrickyardConfig.luau').read_text(encoding='utf-8'))
    move = _subtable(cfg, 'Movement'); dodge = _subtable(cfg, 'Dodge'); match = _subtable(cfg, 'Match')
    sword = _subtable(chars, 'Characters.SWORD'); paint = _subtable(chars, 'Characters.PAINTBALL')
    sp = _subtable(sword, 'primary'); sparry = _subtable(sword, 'secondary')
    pp = _subtable(paint, 'primary'); pball = _subtable(pp, 'projectile'); pammo = _subtable(paint, 'ammo')
    hp = {cid: _max_health(chars, cid) for cid in CHARACTER_IDS}
    return {
        'provenance': 'READ_FROM_CURRENT_LUAU_SOURCE_NOT_EXECUTED',
        'movement': {'walk': _number(move, 'WalkSpeed'), 'run': _number(move, 'RunSpeed')},
        'hp': hp,
        'combat': {'health': hp['SWORD'], 'hit_radius': _number(_subtable(cfg, 'Combat'), 'HitRadius')},
        'dodge': {k: _number(dodge, v) for k, v in {'distance': 'Distance', 'duration': 'Duration', 'iframes': 'InvulnSeconds', 'charges': 'MaxCharges', 'recharge': 'RechargeSeconds'}.items()},
        'respawn': {'seconds': _number(match, 'RespawnSeconds'), 'protection': _number(match, 'RespawnProtectionSeconds')},
        'sword': {'damage': _number(sp, 'damage'), 'interval': _number(sp, 'cooldown'), 'range': _number(sp, 'range'), 'arc': _number(sp, 'arcDegrees'), 'move_mult': _number(sp, 'moveSpeedMult'),
                  'parry': {'cooldown': _number(sparry, 'cooldown'), 'window': _number(sparry, 'windowSeconds'), 'arc': _number(sparry, 'frontArcDegrees'), 'counter': _number(sparry, 'counterDamage'), 'range': _number(sparry, 'counterRange')}},
        'paintball': {'damage': _number(pp, 'damage'), 'interval': _number(pp, 'fireInterval'), 'move_mult': _number(pp, 'moveSpeedMult'), 'magazine': _number(pammo, 'magazine'), 'reload': _number(pammo, 'reloadSeconds'),
                      'speed': _number(pball, 'speed'), 'lifetime': _number(pball, 'lifetime'), 'range': _number(pball, 'maxRange'), 'radius': _number(_subtable(pball, 'collision'), 'radius')},
        'map': {'size': _number(map_src, 'MapSize'), 'cover': legacy._entries(map_src, ('PlazaCover',), 'plaza cover'), 'spawns': legacy._entries(map_src, ('Spawns', 'Ground'), 'ground spawns')},
        'approx': {'tick': 0.05, 'think_interval': 0.15, 'actor_radius_2d': 1.65, 'firing_error': 'synthetic per bot', 'cover': 'plaza-only 2D projection of config (no buildings/roofs)', 'parry_prediction': 'synthetic AI',
                   'scope': 'SWORD basic+parry and PAINTBALL primary only; skills/ultimates/other characters are NOT simulated'},
    }


if __name__ == '__main__':
    print(json.dumps(load_rules(), indent=2))
