"""Read a narrow, explicit subset of actual Phase 1 Luau config tables.

This is data extraction, NOT executing Luau or Roblox services. Raises on missing fields.
"""
from __future__ import annotations
from pathlib import Path
import re
import json

ROOT = Path(__file__).resolve().parents[1]


def _strip_comments(code: str) -> str:
    return '\n'.join(row.split('--', 1)[0] for row in code.splitlines())


def _subtable(code: str, key: str) -> str:
    match = re.search(r'(?<![\w.])' + re.escape(key) + r'\s*=\s*\{', code)
    if not match:
        raise ValueError(f'Cannot find Luau table: {key}')
    start = match.end()
    depth = 1
    for i in range(start, len(code)):
        if code[i] == '{': depth += 1
        elif code[i] == '}':
            depth -= 1
            if depth == 0: return code[start:i]
    raise ValueError(f'Unclosed Luau table {key}')


def _number(code: str, key: str) -> float:
    match = re.search(r'(?<![\w.])' + re.escape(key) + r'\s*=\s*(-?\d+(?:\.\d+)?)\b', code)
    if not match: raise ValueError(f'Missing Luau numeric key: {key}')
    return float(match.group(1))


def _entries(code: str, keys: tuple[str, ...], prefix: str) -> list[dict]:
    for key in keys: code = _subtable(code, key)
    result = []
    for found in re.finditer(r'\{\s*id\s*=\s*"([^"]+)"\s*,([^{}]*)\}', code):
        vals = {'id': found.group(1)}
        for k in ('x','z','y','sx','sz','sy'):
            m = re.search(r'\b'+k+r'\s*=\s*(-?\d+(?:\.\d+)?)', found.group(2))
            if m: vals[k]=float(m.group(1))
        result.append(vals)
    if not result: raise ValueError(f'Cannot parse {prefix} entries')
    return result


def load_rules(root: Path = ROOT) -> dict:
    shared = root/'src/shared'
    cfg = _strip_comments((shared/'Config.luau').read_text(encoding='utf-8'))
    chars = _strip_comments((shared/'Data/Characters.luau').read_text(encoding='utf-8'))
    map_src = _strip_comments((root/'src/map/BrickyardConfig.luau').read_text(encoding='utf-8'))
    move = _subtable(cfg, 'Movement')
    dodge = _subtable(cfg, 'Dodge')
    combat = _subtable(cfg, 'Combat')
    match = _subtable(cfg, 'Match')
    sword = _subtable(chars, 'Characters.SWORD')
    paint = _subtable(chars, 'Characters.PAINTBALL')
    sword_primary = _subtable(sword, 'primary')
    sword_parry = _subtable(sword, 'secondary')
    paint_primary = _subtable(paint, 'primary')
    paint_ball = _subtable(paint_primary, 'projectile')
    paint_ammo = _subtable(paint, 'ammo')
    return {
        'provenance':'READ_FROM_PHASE1_LUAU_SOURCE_NOT_EXECUTED',
        'movement':{'walk':_number(move,'WalkSpeed'), 'run':_number(move,'RunSpeed')},
        'combat':{'health':_number(combat,'MaxHealth'), 'hit_radius':_number(combat,'HitRadius')},
        'dodge':{k:_number(dodge,v) for k,v in {'distance':'Distance','duration':'Duration','iframes':'InvulnSeconds','charges':'MaxCharges','recharge':'RechargeSeconds'}.items()},
        'respawn':{'seconds':_number(match,'RespawnSeconds'), 'protection':_number(match,'RespawnProtectionSeconds')},
        'sword':{'damage':_number(sword_primary,'damage'),'interval':_number(sword_primary,'cooldown'), 'range':_number(sword_primary,'range'),'arc':_number(sword_primary,'arcDegrees'), 'move_mult':_number(sword_primary,'moveSpeedMult'),
          'parry':{'cooldown':_number(sword_parry,'cooldown'),'window':_number(sword_parry,'windowSeconds'),'arc':_number(sword_parry,'frontArcDegrees'),'counter':_number(sword_parry,'counterDamage'),'range':_number(sword_parry,'counterRange')}},
        'paintball':{'damage':_number(paint_primary,'damage'),'interval':_number(paint_primary,'fireInterval'), 'move_mult':_number(paint_primary,'moveSpeedMult'), 'magazine':_number(paint_ammo,'magazine'),'reload':_number(paint_ammo,'reloadSeconds'), 'speed':_number(paint_ball,'speed'),'lifetime':_number(paint_ball,'lifetime'),'range':_number(paint_ball,'maxRange'),'radius':_number(_subtable(paint_ball,'collision'),'radius')},
        'map':{'size':_number(map_src,'MapSize'), 'cover':_entries(map_src, ('PlazaCover',), 'plaza cover'), 'spawns':_entries(map_src, ('Spawns','Ground'), 'ground spawns')},
        'approx':{'tick':0.05,'think_interval':0.15,'actor_radius_2d':1.65,'firing_error':'synthetic per bot', 'cover':'plaza-only 2D projection of config (no buildings/roofs)', 'parry_prediction':'synthetic AI'}
    }


if __name__=='__main__':
    print(json.dumps(load_rules(), indent=2))
