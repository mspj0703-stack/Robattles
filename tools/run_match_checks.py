#!/usr/bin/env python3
"""Run every inherited suite plus match tests. Preserved Phase 1 simulation results are reported separately (sim_legacy*) and never hidden.
Usage: python3 tools/run_match_checks.py --luau /path/luau --compiler /path/luau-compile
Exit 1 when ANY group fails, including inherited immutable-source checks.
"""
import argparse,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--luau',required=True);p.add_argument('--compiler',required=True);p.add_argument('--log-dir',default='docs/match-check-logs');a=p.parse_args()
    target=ROOT/a.log_dir;target.mkdir(parents=True,exist_ok=True)
    groups=[
        ('combat_and_match',[sys.executable,str(ROOT/'tools/run_tests.py'),'--luau',a.luau]),
        ('map',[sys.executable,str(ROOT/'tools/run_map_tests.py'),'--luau',a.luau]),
        ('ui_state',[a.luau,str(ROOT/'tests_ui/state.spec.luau')]),
        ('ui_mock',[sys.executable,str(ROOT/'tools/run_ui_smoke.py'),'--luau',a.luau]),
        ('sim_current',[sys.executable,str(ROOT/'tools/run_sim.py'),'current']),
        ('sim_legacy',[sys.executable,str(ROOT/'tools/run_sim.py'),'legacy']),
        ('sim_legacy_at_d1f03e6',[sys.executable,str(ROOT/'tools/run_sim.py'),'legacy','--at','d1f03e6']),
        ('projects',[sys.executable,str(ROOT/'tools/check_projects.py')]),
        ('remotes',[sys.executable,str(ROOT/'tools/check_remotes.py')]),
    ]
    failures=[]
    for name,cmd in groups:
        result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
        (target/(name+'.txt')).write_text(result.stdout+result.stderr)
        label='PASS' if result.returncode==0 else 'FAIL'
        if name.startswith('sim_legacy') and result.returncode==0 and 'failed 0 ' not in result.stdout: label='NO-NEW-FAILURES (preserved suite still has known stale failures)'
        print(name,label,flush=True)
        if name.startswith('sim_legacy'):  # never hide the preserved suite's real failures: print its own summary lines
            print('   '+'\n   '.join(l for l in result.stdout.splitlines() if l.startswith(('SIM LEGACY','  known stale'))),flush=True)
        if result.returncode:failures.append(name)
    sources=[]
    for tree in ['src','tests','tests_ui','tests_map']:sources.extend((ROOT/tree).rglob('*.luau'))
    errors=[]
    for source in sources:
        result=subprocess.run([a.compiler,'--null',str(source)],capture_output=True)
        if result.returncode:errors.append(str(source)+'\n'+result.stderr.decode('utf-8','replace'))
    (target/'compile.txt').write_text(f'{len(sources)-len(errors)}/{len(sources)} compiled\n'+'\n'.join(errors))
    if errors:failures.append('compile')
    print('Failed groups:',', '.join(failures) or 'none')
    return int(bool(failures))
if __name__=='__main__':sys.exit(main())
