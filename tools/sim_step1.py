"""RoBattles! Phase 1 source-driven approximate combat simulator.
Data comes from Config, Characters and BrickyardConfig Luau files at runtime.
Combat/AI/physics are Python approximations; Roblox Luau server code is NOT executed.
"""
from __future__ import annotations
import argparse
import collections
import dataclasses
import json
import math
import random
from pathlib import Path
from typing import Optional
from sim_rules import load_rules

RULES = load_rules()

DT = 0.05
THINK_DT = 0.15
ARENA = RULES["map"]["size"]/2  # Real map bound; 2D geometry is approximate
RESPAWN = RULES["respawn"]["seconds"]
PROTECTION = RULES["respawn"]["protection"]
SPEED = RULES["movement"]["walk"]
SPRINT = RULES["movement"]["run"]
DODGE_DIST = RULES["dodge"]["distance"]
DODGE_IFRAME = RULES["dodge"]["iframes"]
DODGE_RECHARGE = RULES["dodge"]["recharge"]
RADIUS = RULES["approx"]["actor_radius_2d"]
LOS_LIMIT = 90.0  # APPROX visibility
STYLES = ('rusher', 'kiter', 'controller', 'adaptive')
# Real plaza cover projected into 2D; no actual Roblox colliders/buildings/roofs.
PLAZA_COVER = tuple((c["x"]-c["sx"]/2,c["z"]-c["sz"]/2, c["x"]+c["sx"]/2,c["z"]+c["sz"]/2) for c in RULES["map"]["cover"])

@dataclasses.dataclass(frozen=True)
class V:
    x: float
    y: float
    def __add__(self, other: V) -> V: return V(self.x+other.x, self.y+other.y)
    def __sub__(self, other: V) -> V: return V(self.x-other.x, self.y-other.y)
    def __mul__(self, factor: float) -> V: return V(self.x*factor, self.y*factor)
    def dot(self, other: V) -> float: return self.x*other.x+self.y*other.y
    def length(self) -> float: return math.hypot(self.x,self.y)
    def norm(self) -> V:
        d = self.length()
        return V(self.x/d,self.y/d) if d>1e-9 else V(1.,0.)
    def distance(self, other: V) -> float: return (self-other).length()

def rotate(v: V, radians: float) -> V:
    c,s=math.cos(radians),math.sin(radians)
    return V(v.x*c-v.y*s, v.x*s+v.y*c)

def segment_circle(a: V,b: V,center: V, radius: float) -> Optional[float]:
    d=b-a
    mag2=d.dot(d)
    if mag2<1e-12:
        return 0. if a.distance(center)<=radius else None
    t=max(0.,min(1.,(center-a).dot(d)/mag2))
    return t if (a+d*t).distance(center)<=radius else None

def segment_rect(a: V,b: V,rect: tuple[float,float,float,float]) -> Optional[float]:
    """Liang-Barsky segment/AABB; t of first obstruction intersection."""
    xmin,ymin,xmax,ymax=rect
    dx,dy=b.x-a.x,b.y-a.y
    p=(-dx,dx,-dy,dy)
    q=(a.x-xmin,xmax-a.x,a.y-ymin,ymax-a.y)
    lo,hi=0.,1.
    for pi,qi in zip(p,q):
        if abs(pi)<1e-12:
            if qi<0: return None
        else:
            t=qi/pi
            if pi<0: lo=max(lo,t)
            else: hi=min(hi,t)
            if lo>hi: return None
    return lo

@dataclasses.dataclass
class Fighter:
    id: int
    character: str
    style: str
    pos: V
    rng: random.Random
    hp: float=0.
    alive: bool=True
    facing: V=dataclasses.field(default_factory=lambda:V(1,0))
    next_think: float=0.
    next_attack: float=0.
    desired: V=dataclasses.field(default_factory=lambda:V(0,0))
    sprint: bool=False
    target_id: Optional[int]=None
    respawn_at: float=0.
    shield_until: float=2.
    iframe_until: float=0.
    dodge_ready: list=dataclasses.field(default_factory=lambda:[0.,0.])
    parry_until: float=0.
    parry_ready: float=0.
    parry_countered: set=dataclasses.field(default_factory=set)
    ammo: int=0
    reload_end: Optional[float]=None
    score: int=0
    kills: int=0
    assists: int=0
    deaths: int=0
    damage: float=0.
    taken: float=0.
    shots: int=0
    hits: int=0
    rejects: int=0
    parries: int=0
    parry_blocks: int=0
    reloads: int=0
    dodges: int=0
    protected_rejects: int=0
    lifetimes: float=0.
    death_sources: dict=dataclasses.field(default_factory=dict)

    @property
    def max_hp(self): return RULES["combat"]["health"]  # Phase 1 uses common 100 HP
    def is_protected(self,t: float): return self.alive and t+1e-9<self.shield_until
    def approve_attack(self,t: float):
        if self.is_protected(t): self.shield_until=t

@dataclasses.dataclass
class Bullet:
    owner: int
    pos: V
    direction: V
    remaining: float=0.
    ttl: float=0.

class Sim:
    def __init__(self,mode='1v1',seed=1,duration=420.,cover='plaza',bot_style='mix'):
        if mode not in ('1v1','ffa12'): raise ValueError('Unknown mode')
        if cover not in ('none','plaza'): raise ValueError('Unknown cover')
        if bot_style!='mix' and bot_style not in STYLES: raise ValueError('Unknown bot style')
        self.mode,self.seed,self.duration,self.cover=mode,seed,duration,cover
        self.walls=PLAZA_COVER if cover=='plaza' else ()
        self.t=0.
        self.tick=0
        self.seed_rng=random.Random(seed)
        self.fighters=[]
        self.bullets=[]
        self.events=collections.Counter()
        self._setup(bot_style)

    def _setup(self,style):
        n=2 if self.mode=='1v1' else 12
        order=['SWORD','PAINTBALL'] if n==2 else ['SWORD','PAINTBALL']*6
        # Alternate assigned starting side with seed; no seat fixed to a character.
        if n==2 and self.seed%2: order.reverse()
        theta=self.seed_rng.random()*math.tau
        for i in range(n):
            # Start at actual BRICKYARD ground spawn coordinates; rooftops excluded.
            choices=RULES["map"]["spawns"]
            site=choices[1 if i==0 else 7] if n==2 else choices[(i*5+int(self.seed%len(choices)))%len(choices)]
            xy=V(site["x"],site["z"])
            botstyle=STYLES[i%len(STYLES)] if style=='mix' else style
            fighter=Fighter(i,order[i],botstyle,xy,random.Random(self.seed*1000003+i*8191+31))
            fighter.hp=fighter.max_hp
            fighter.ammo=int(RULES["paintball"]["magazine"]) if fighter.character=="PAINTBALL" else 0
            fighter.facing=(V(0,0)-xy).norm()
            self.fighters.append(fighter)

    def blocked(self,a: V,b: V) -> bool:
        return any(segment_rect(a,b,r) is not None for r in self.walls)

    def place(self,p: V) -> V:
        p=V(min(ARENA-2,max(-ARENA+2,p.x)),min(ARENA-2,max(-ARENA+2,p.y)))
        # Block movement if center is inside/too close to a wall; caller can keep previous position.
        return p

    def walk(self,f: Fighter,velocity: V,dt: float):
        if velocity.length()<1e-7: return
        destination=self.place(f.pos+velocity*dt)
        # Conservative expanded-wall collision for player radius.
        inflated=((r[0]-RADIUS,r[1]-RADIUS,r[2]+RADIUS,r[3]+RADIUS) for r in self.walls)
        walls=tuple(inflated)
        def free(dest): return all(segment_rect(f.pos,dest,rect) is None for rect in walls)
        if free(destination):
            f.pos=destination
            return
        # APPROX 2D local obstacle detour. Deterministic; NOT Roblox pathfinding.
        # Keep a side preference to prevent jitter at symmetric cover corners.
        direction=velocity.norm()
        turn=1 if f.id%2 else -1
        for deg in (20,40,60,85,110,135,160,180):
            for sign in (turn,-turn):
                option=self.place(f.pos+rotate(direction, math.radians(deg*sign))*velocity.length()*dt)
                if free(option):
                    f.pos=option
                    return

    def perceived(self,f: Fighter) -> list[Fighter]:
        return [p for p in self.fighters if p.id!=f.id and p.alive
                and f.pos.distance(p.pos)<=LOS_LIMIT and not self.blocked(f.pos,p.pos)]

    def think(self,f: Fighter):
        enemies=self.perceived(f)
        f.target_id=None
        if not enemies:
            # Search route to center with randomized orbit; no enemy wallhack.
            center=V(0,0)-f.pos
            drift=rotate(center.norm(),math.sin(self.t*0.5+f.id)*0.65)
            f.desired=drift.norm()
            f.sprint=True
            return
        # Simple utility score combines distance, vulnerability, and current health.
        target=max(enemies,key=lambda p:(2.5/(1+f.pos.distance(p.pos)*0.04)
                    + .35*(1-p.hp/p.max_hp),-p.id))
        f.target_id=target.id
        delta=target.pos-f.pos
        dist=delta.length()
        f.facing=delta.norm()
        desired_range=RULES['sword']['range']-1 if f.character=='SWORD' else 26.0
        if f.style=='rusher': desired_range=4.7 if f.character=='SWORD' else 13.
        if f.style=='kiter': desired_range=9. if f.character=='SWORD' else 36.
        if f.style=='controller': desired_range=7. if f.character=='SWORD' else 31.
        if f.style=='adaptive' and f.hp/f.max_hp<.35: desired_range+=17
        if dist>desired_range+2: movement=delta.norm()
        elif dist<desired_range-2: movement=delta.norm()*-1
        else: movement=V(-delta.y,delta.x).norm()*(1 if f.id%2 else -1)
        if f.style=='controller' and not self.blocked(f.pos,f.pos+movement*9):
            movement=rotate(movement,math.sin(self.t*0.3+f.id)*0.3)
        f.desired=movement.norm()
        f.sprint=dist>desired_range+10
        # Parry based on visible imminent threat; normal ranged projectile blocked.
        if f.character=='SWORD' and self.t+1e-9>=f.parry_ready:
            danger=any(b.owner!=f.id and b.pos.distance(f.pos)<17
                       and (f.pos-b.pos).dot(b.direction)>0 for b in self.bullets)
            danger=danger or (dist<8 and target.character=='SWORD')
            if danger and f.rng.random()<(.42 if f.style=='adaptive' else .30):
                f.parry_until=self.t+RULES["sword"]["parry"]["window"];f.parry_ready=self.t+RULES["sword"]["parry"]["cooldown"];f.parries+=1;f.parry_countered.clear()
                f.sprint=False
        # Dodge has two independently recharging charges.
        if (f.hp/f.max_hp<.55 or (target.character=='SWORD' and dist<9)) \
                and f.rng.random()<.035:
            slots=[idx for idx,ready in enumerate(f.dodge_ready) if ready<=self.t+1e-9]
            if slots:
                idx=slots[0];f.dodge_ready[idx]=self.t+DODGE_RECHARGE
                side=V(-delta.y,delta.x).norm()*(1 if f.rng.random()<.5 else -1)
                self.walk(f,side,DODGE_DIST)  # 9 stud positional displacement; model simplification
                f.iframe_until=self.t+DODGE_IFRAME
                f.dodges+=1

    def shoot(self,f: Fighter):
        if not f.alive or self.t+1e-9<f.next_attack:return
        if f.target_id is None: return
        target=self.fighters[f.target_id]
        if not target.alive or self.blocked(f.pos,target.pos):return
        distance=f.pos.distance(target.pos)
        if f.character=='SWORD':
            if distance>RULES["sword"]["range"]+RADIUS:return
            f.approve_attack(self.t);f.sprint=False
            damage=RULES["sword"]["damage"]
            f.next_attack=self.t+RULES["sword"]["interval"]
            f.shots+=1
            # Actual Phase 1 constant damage frontal cleave, unique hit per enemy.
            for enemy in self.fighters:
                if enemy.id==f.id or not enemy.alive:continue
                ray=(enemy.pos-f.pos)
                if ray.length()>RULES["sword"]["range"]+RADIUS or f.facing.dot(ray.norm())<math.cos(math.radians(RULES["sword"]["arc"]/2)):
                    continue
                if self.blocked(f.pos,enemy.pos):continue
                self.apply_hit(f,enemy,damage,'melee')
        else:
            if distance>RULES["paintball"]["range"]:return
            if f.reload_end is not None:return
            if f.ammo<=0:
                f.reload_end=self.t+RULES["paintball"]["reload"];f.reloads+=1
                return
            f.approve_attack(self.t);f.sprint=False
            f.next_attack=self.t+RULES["paintball"]["interval"]
            f.shots+=1;f.ammo-=1
            # Shot error, no instant hit. Errors are per-bot seeded.
            error=math.radians({'rusher':9,'kiter':7,'controller':6,'adaptive':7}[f.style])
            aim=rotate((target.pos-f.pos).norm(),f.rng.gauss(0,error))
            self.bullets.append(Bullet(f.id,f.pos,aim,RULES["paintball"]["range"],RULES["paintball"]["lifetime"]))
            if f.ammo==0:
                f.reload_end=self.t+RULES["paintball"]["reload"];f.reloads+=1

    def apply_hit(self,src: Fighter,dst: Fighter,damage: float,kind: str):
        if not dst.alive or src.id==dst.id or (kind!='paint' and not src.alive):return 'invalid'
        # Fired projectiles survive owner death, following Phase 1 ownerDied handling.
        if dst.is_protected(self.t):
            dst.protected_rejects+=1;self.events['spawn_protected']+=1
            return 'protected'
        if self.t+1e-9<dst.iframe_until:
            self.events['dodge_immune']+=1
            return 'dodged'
        if dst.character=='SWORD' and self.t+1e-9<dst.parry_until and dst.facing.dot((src.pos-dst.pos).norm())>=math.cos(math.radians(RULES["sword"]["parry"]["arc"]/2)):
            dst.parry_blocks+=1
            self.events['parry_block']+=1
            if src.id not in dst.parry_countered and src.pos.distance(dst.pos)<=RULES["sword"]["parry"]["range"]+RADIUS and src.alive:
                self._damage(dst,src,RULES["sword"]["parry"]["counter"],'parry_counter')
                dst.parry_countered.add(src.id)
            return 'parried'
        self._damage(src,dst,damage,kind)
        return 'hit'

    def _damage(self,src:Fighter,dst:Fighter,damage:float,kind:str):
        if not dst.alive or dst.is_protected(self.t):return
        actual=min(dst.hp,damage)
        dst.hp-=actual;dst.taken+=actual;src.damage+=actual;src.hits+=1
        dst.death_sources[src.id]=self.t
        if dst.hp<=1e-9:
            dst.hp=0;dst.alive=False;dst.deaths+=1
            dst.respawn_at=self.t+RESPAWN
            src.kills+=1;src.score+=1  # Phase 1 ScoreboardService sorts by kills, no KO point currency
            # Assist points are not implemented in Phase 1 ScoreboardService.
            dst.death_sources={}
            self.events['kill_'+kind]+=1

    def bullets_step(self):
        updated=[]
        for b in self.bullets:
            step=min(RULES["paintball"]["speed"]*DT,b.remaining)
            endpoint=b.pos+b.direction*step
            wall_t=min((t for rect in self.walls if (t:=segment_rect(b.pos,endpoint,rect)) is not None),default=2.)
            hit=None
            hit_t=wall_t
            for target in self.fighters:
                if target.id==b.owner or not target.alive:continue
                t=segment_circle(b.pos,endpoint,target.pos,RADIUS)
                if t is not None and t<=hit_t:
                    if (hit is None or t<hit_t or (t==hit_t and target.id<hit.id)):
                        hit,target_id=target,target.id
                        hit_t=t
            if hit is not None:
                result=self.apply_hit(self.fighters[b.owner],hit,RULES["paintball"]["damage"],'paint')
                # Protected and invulnerable targets let projectile pass.
                if result not in ('protected','dodged'):
                    continue
            if wall_t<=1.:continue
            b.pos=endpoint;b.remaining-=step;b.ttl-=DT
            if b.remaining>0.001 and b.ttl>0:updated.append(b)
        self.bullets=updated

    def respawn_step(self):
        for f in self.fighters:
            if not f.alive and self.t+1e-9>=f.respawn_at:
                # fixed deterministic respawn sites; abstract surrogate only
                alive=[e for e in self.fighters if e.id!=f.id and e.alive]
                sites=RULES["map"]["spawns"]
                site=max(sites, key=lambda s: (min((math.hypot(s["x"]-e.pos.x,s["z"]-e.pos.y) for e in alive), default=1000), -int(s["id"][1:])))
                f.pos=V(site["x"],site["z"])
                f.hp=f.max_hp;f.alive=True;f.shield_until=self.t+PROTECTION
                f.next_attack=self.t;f.next_think=self.t
                f.reload_end=None;f.ammo=int(RULES["paintball"]["magazine"]) if f.character=="PAINTBALL" else 0;f.target_id=None
                f.iframe_until=0;f.parry_until=0;f.parry_countered.clear()
                f.dodge_ready=[self.t,self.t]
                f.death_sources={}
                f.desired=V(0,0);f.sprint=False
                self.events['respawn']+=1

    def step(self):
        self.t=round(self.tick*DT,9)
        self.respawn_step()
        # Stable id ordering: reload, decision, shoot, movement, projectile resolution.
        for f in self.fighters:
            if not f.alive:continue
            f.lifetimes+=DT
            if f.reload_end is not None and self.t+1e-9>=f.reload_end:
                f.ammo=int(RULES["paintball"]["magazine"]);f.reload_end=None
            if self.t+1e-9>=f.next_think:
                self.think(f)
                f.next_think=self.t+THINK_DT
            self.shoot(f)
        for f in self.fighters:
            if f.alive:
                self.walk(f,f.desired*(SPRINT if f.sprint else SPEED),DT)
        self.bullets_step()
        self.tick+=1

    def run(self):
        for _ in range(math.ceil(self.duration/DT)):
            self.step()
        ranked=sorted(self.fighters,key=lambda f:(-f.score,-f.kills,-round(f.damage,6),f.id))
        result={
          'model':'phase1_source_data_python_approximation_not_roblox','mode':self.mode,'seed':self.seed,
          'duration':self.duration,'tick':DT,'cover':self.cover,'rule_source':RULES['provenance'],
          'winner':ranked[0].id,'winner_character':ranked[0].character,
          'events':dict(sorted(self.events.items())),
          'players':[
           {k:getattr(f,k) for k in ('id','character','style','score','kills','assists','deaths',
                  'damage','taken','shots','hits','parries','parry_blocks','reloads',
                  'dodges','protected_rejects')}
           for f in sorted(self.fighters,key=lambda f:f.id)
          ],
          'omissions':['Character skills 1/2/3 and ultimates','Character-specific passives and future design-only changes',
             'Roblox Humanoid and physics','exact BRICKYARD geometry and vertical travel',
             'character-specific projectile geometry','network latency'],
        }
        return result

def batch(mode:str,matches:int,seed:int,duration:float,cover:str='abstract',style:str='mix'):
    if matches<1:raise ValueError('matches must be positive')
    games=[Sim(mode,seed+i,duration,cover,style).run() for i in range(matches)]
    totals=collections.defaultdict(lambda:collections.defaultdict(float))
    winners=collections.Counter(g['winner_character'] for g in games)
    for game in games:
        for p in game['players']:
            t=totals[p['character']]
            for key in ('kills','assists','deaths','damage','taken','shots','hits','parries','parry_blocks','reloads','dodges','protected_rejects','score'):
                t[key]+=p[key]
            t['participations']+=1
    summary={
       'model':'phase1_source_data_python_approximation_not_roblox',
       'mode':mode,'matches':matches,'base_seed':seed,'duration':duration,'cover':cover,'rules':RULES,
       'winners':dict(sorted(winners.items())),
       'by_character':{
           name:{k:round(v/t['participations'],3) if k!='participations' else int(v)
               for k,v in sorted(t.items())} for name,t in sorted(totals.items())
       },
       'games':games
    }
    return summary

def markdown_report(res:dict)->str:
    lines=['# RoBattles! Step 1 — Phase 1 Source-Driven Simulation', '',
      '**Phase 1 Luau source-driven data; Python combat AI/physics approximation, NOT Roblox Studio or actual server code.**',
      f"Mode: `{res['mode']}` · Matches: {res['matches']} · Duration: {res['duration']} s · Seed: {res['base_seed']} · Cover: {res['cover']}",
      '', '## Model winners', '', '| Character | Wins | Win share |', '|---|---:|---:|']
    for ch in sorted(res['by_character']):
        wins=res['winners'].get(ch,0)
        lines.append(f'| {ch} | {wins} | {wins/res["matches"]*100:.1f}% |')
    lines+=['','## Mean statistics per player per match','','| Character | KO | Deaths | Effective damage | Shots | Hits |','|---|---:|---:|---:|---:|---:|']
    for ch,v in sorted(res['by_character'].items()):
        lines.append(f'| {ch} | {v["kills"]:.2f} | {v["deaths"]:.2f} | {v["damage"]:.1f} | {v["shots"]:.1f} | {v["hits"]:.1f} |')
    lines+=['','## Important model limitations', '',
      '- SWORD base attack 14 at 0.55s, PAINTBALL 4 at 0.12s / 30 rounds / 1.8s reload, both with 100 HP in Phase 1 source. These differ from future approved character design specs.',
      '- Spawn positions and 9 plaza covers are loaded from BRICKYARD source, but 2D collider projection omits buildings, roof terrain, stairs and Roblox Studio physics.',
      '- AI profiles and accuracy are provisional and can materially change results.',
      '- Winner is ranked by kills (Phase 1 scoreboard); any future points/assists system is omitted.',
      '- Results are **NOT** evidence of true character balance, Studio integration, or player win rates.', '']
    return '\n'.join(lines)

def main():
    p=argparse.ArgumentParser(description='RoBattles independent Step 1 simulator')
    p.add_argument('--mode',choices=['1v1','ffa12'],default='1v1')
    p.add_argument('--matches',type=int,default=10)
    p.add_argument('--seed',type=int,default=20261025)
    p.add_argument('--duration',type=float,default=420.)
    p.add_argument('--cover',choices=['none','plaza'],default='plaza')
    p.add_argument('--style',choices=['mix',*STYLES],default='mix')
    p.add_argument('--output',type=Path,default=Path('results'))
    args=p.parse_args()
    if args.duration<=0: p.error('duration must be >0')
    result=batch(args.mode,args.matches,args.seed,args.duration,args.cover,args.style)
    args.output.mkdir(parents=True,exist_ok=True)
    basename=f'{args.mode}_seed{args.seed}_n{args.matches}'
    (args.output/(basename+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    report=markdown_report(result)
    (args.output/(basename+'.md')).write_text(report,encoding='utf-8')
    print(report)
    print('Output:',args.output/(basename+'.json'))

if __name__=='__main__':main()
