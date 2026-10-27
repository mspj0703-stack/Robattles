#!/usr/bin/env python3
"""Execute view construction/callback tests with a restricted mock, NOT Roblox."""
import argparse,pathlib,re,shutil,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def convert(source):
    def repl(m):
        parts=m.group(1).split('.')
        ups=0
        while parts and parts[0]=='Parent': ups+=1;parts.pop(0)
        prefix='../'*max(0,ups-1) or './'
        return 'require("'+prefix+'/'.join(parts)+'")'
    return re.sub(r'require\(script\.([\w.]+)\)',repl,source)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--luau',required=True);a=ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        tmp=pathlib.Path(tmp)
        for folder in ['client','shared']:
            for p in (ROOT/'src'/folder).rglob('*.luau'):
                out=tmp/folder/p.relative_to(ROOT/'src'/folder);out.parent.mkdir(parents=True,exist_ok=True)
                text=convert(p.read_text())
                if folder=='client':
                    mock='../'*(len(p.relative_to(ROOT/'src').parts)-1)+'tests_ui/RobloxMock'
                    text='local Mock=require("'+mock+'")\n'+''.join('local '+k+'=Mock.'+k+'\n' for k in ['game','workspace','Instance','Enum','Color3','Vector2','Vector3','UDim','UDim2','CFrame','TweenInfo'])+text
                out.write_text(text)
        (tmp/'client/Link.luau').write_text('return {shared=function(path) return require("../shared/"..path) end}')
        shutil.copytree(ROOT/'tests_ui',tmp/'tests_ui')
        return subprocess.run([a.luau,str(tmp/'tests_ui/views.spec.luau')]).returncode
if __name__=='__main__':raise SystemExit(main())
