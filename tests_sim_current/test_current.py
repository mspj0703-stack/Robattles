"""CURRENT-baseline approximation tests (Phase 2 data). Not Luau CLI tests or Roblox Studio tests.
Expected numbers are the confirmed values documented in src/shared/Data/Characters.luau comments / docs/ASSUMPTIONS.md,
written here independently of the parser so the loader itself is tested. Preserved Phase 1 tests: tests_sim/ (see docs/SIM_BASELINES.md)."""
import sys, unittest, hashlib, pathlib, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from sim_current import *
from sim_rules_current import load_rules, _subtable
import sim_rules as legacy_rules

class SourceRules(unittest.TestCase):
    def test_actual_current_numbers(self):
        r=load_rules()
        self.assertEqual(r['hp'],{'SWORD':110,'PAINTBALL':95,'SUPERBALL':100,'TIMEBOMB':105,'SLINGSHOT':100})
        self.assertEqual(r['sword']['damage'],14)
        self.assertEqual(r['sword']['interval'],.55)
        self.assertEqual(r['sword']['parry']['counter'],18)
        self.assertEqual(r['sword']['parry']['window'],.4)
        self.assertEqual(r['paintball']['damage'],7)
        self.assertAlmostEqual(r['paintball']['interval'],1/3)   # written `1 / 3` in Characters.luau
        self.assertEqual(r['paintball']['magazine'],16)
        self.assertEqual(r['paintball']['reload'],1.2)
        self.assertEqual(r['paintball']['speed'],220)
        self.assertEqual(r['dodge']['distance'],14)
        self.assertEqual(r['respawn'],{'seconds':4,'protection':2})
    def test_division_literal_regression(self):
        # The preserved Phase 1 loader reads `fireInterval = 1 / 3` as 1.0; the current loader must not.
        self.assertEqual(legacy_rules.load_rules()['paintball']['interval'],1.0)
        self.assertAlmostEqual(load_rules()['paintball']['interval'],1/3)
    def test_every_character_has_hp_in_source(self):
        self.assertEqual(sorted(load_rules()['hp']),sorted(['SWORD','PAINTBALL','SUPERBALL','TIMEBOMB','SLINGSHOT']))
    def test_map_read(self):
        self.assertEqual(load_rules()['map']['size'],180)
        self.assertEqual(len(load_rules()['map']['cover']),9)
        self.assertEqual(len(load_rules()['map']['spawns']),16)
    def test_missing_source_fails_closed(self):
        with self.assertRaises(ValueError):_subtable('x = 5','Missing')
    def test_rule_source_files_exist(self):
        for rel in ('src/shared/Config.luau','src/shared/Data/Characters.luau','src/map/BrickyardConfig.luau'):
            self.assertTrue((ROOT/rel).exists(),rel)

class Simulation(unittest.TestCase):
    def test_determinism_1v1(self):
        self.assertEqual(Sim('1v1',2026,10).run(),Sim('1v1',2026,10).run())
    def test_determinism_ffa12(self):
        self.assertEqual(Sim('ffa12',2026,5).run(),Sim('ffa12',2026,5).run())
    def test_actors_and_hp(self):
        s=Sim('ffa12',33,5)
        self.assertEqual(len(s.fighters),12)
        self.assertEqual([f.hp for f in s.fighters],[{'SWORD':110,'PAINTBALL':95}[f.character] for f in s.fighters])
        self.assertEqual([f.ammo for f in s.fighters if f.character=='PAINTBALL'],[16]*6)
    def test_attack_magnitude(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        a.shield_until=b.shield_until=0
        self.assertEqual(s.apply_hit(a,b,RULES['sword']['damage'],'melee'),'hit')
        self.assertEqual(b.hp,b.max_hp-14)
    def test_geometry(self):
        self.assertAlmostEqual(segment_circle(V(0,0),V(10,0),V(5,0),1),.5)
        self.assertIsNone(segment_circle(V(0,0),V(10,0),V(5,5),1))
        self.assertIsNotNone(segment_rect(V(0,0),V(10,0),(4,-1,6,1)))
    def test_map_cover_blocking(self):
        s=Sim('1v1',2,1)
        self.assertTrue(s.blocked(V(-7,0),V(7,0)))
        self.assertFalse(s.blocked(V(-9,-10),V(9,-10)))
    def test_spawn_protect_boundary(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        s.t=1.999
        self.assertEqual(s.apply_hit(a,b,20,'melee'),'protected')
        self.assertEqual(b.hp,b.max_hp)
        s.t=2.
        self.assertEqual(s.apply_hit(a,b,20,'melee'),'hit')
        self.assertEqual(b.hp,b.max_hp-20)
    def test_attack_breaks_protection(self):
        s=Sim('1v1',2,1,'none');a,_=s.fighters
        a.approve_attack(.1)
        self.assertFalse(a.is_protected(.1))
    def test_dodge(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        b.shield_until=0;b.iframe_until=4;s.t=3.999
        self.assertEqual(s.apply_hit(a,b,20,'melee'),'dodged')
        s.t=4.
        self.assertEqual(s.apply_hit(a,b,20,'melee'),'hit')
    def test_parry_front_back(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        b.character='SWORD';b.shield_until=0;b.parry_until=2;b.facing=V(-1,0)
        a.pos=V(-1,0);b.pos=V(0,0);s.t=1
        self.assertEqual(s.apply_hit(a,b,7,'paint'),'parried')
        a.pos=V(1,0)
        self.assertEqual(s.apply_hit(a,b,7,'paint'),'hit')
    def test_parry_counters_once_per_attacker(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        b.character='SWORD';b.shield_until=0;b.parry_until=3;b.facing=V(-1,0)
        a.pos=V(-1,0);b.pos=V(0,0);s.t=2
        self.assertEqual(s.apply_hit(a,b,7,'paint'),'parried')
        hp=a.hp
        self.assertEqual(s.apply_hit(a,b,7,'paint'),'parried')
        self.assertEqual(a.hp,hp)
    def test_projectiles_survive_shooter_death(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        a.alive=False;b.shield_until=0
        self.assertEqual(s.apply_hit(a,b,RULES['paintball']['damage'],'paint'),'hit')
        self.assertEqual(b.hp,b.max_hp-7)
    def test_non_sword_cannot_parry(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        b.character='PAINTBALL';b.shield_until=0;b.parry_until=3;b.facing=V(-1,0)
        a.pos=V(-1,0);b.pos=V(0,0);s.t=2
        self.assertEqual(s.apply_hit(a,b,7,'paint'),'hit')
    def test_reload_amount(self):
        s=Sim('1v1',2,2,'none')
        f=next(f for f in s.fighters if f.character=='PAINTBALL')
        f.ammo=0;f.reload_end=.9;f.next_attack=100
        s.tick=18;s.step()
        self.assertEqual(f.ammo,16)
        self.assertIsNone(f.reload_end)
    def test_projectile_pass_protected(self):
        s=Sim('1v1',2,1,'none');a,b=s.fighters
        a.pos=V(0,0);b.pos=V(4,0);b.shield_until=2;s.t=1
        s.bullets=[Bullet(a.id,V(0,0),V(1,0),300,2)]
        s.bullets_step()
        self.assertEqual(b.hp,b.max_hp)
        self.assertEqual(len(s.bullets),1)
    def test_kill_respawn(self):
        s=Sim('1v1',2,10,'none');a,b=s.fighters
        a.shield_until=b.shield_until=0;s.t=2
        s._damage(a,b,200,'test')
        self.assertFalse(b.alive)
        self.assertEqual(a.score,1)
        s.t=6;s.respawn_step()
        self.assertTrue(b.alive)
        self.assertEqual(b.hp,b.max_hp)
        self.assertTrue(b.is_protected(6))
    def test_actions_occur_1v1(self):
        r=Sim('1v1',20261025,40,'plaza').run()
        self.assertGreater(sum(p['shots'] for p in r['players']),1,
            'AI should navigate plaza cover and actually fight')
    def test_actions_occur_ffa12(self):
        r=Sim('ffa12',20261025,20,'plaza').run()
        self.assertGreater(sum(p['shots'] for p in r['players']),10)
    def test_all_styles_and_mode(self):
        for style in STYLES:
            r=Sim('1v1',5,4,'none',style).run()
            self.assertTrue(all(p['style']==style for p in r['players']))
    def test_batch_one_hundred(self):
        a=batch('1v1',100,9,.25,'none')
        b=batch('1v1',100,9,.25,'none')
        self.assertEqual(a,b)
        self.assertEqual(sum(a['winners'].values()),100)
    def test_invalid_args(self):
        with self.assertRaises(ValueError):Sim('bogus')
        with self.assertRaises(ValueError):Sim('1v1',cover='bogus')
        with self.assertRaises(ValueError):batch('1v1',0,1,1)

if __name__=='__main__': unittest.main(verbosity=2)
