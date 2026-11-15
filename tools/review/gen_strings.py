import sys
sys.path.insert(0,'.')
exec(open('en_tr.py').read())
def esc(s): return s.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')
out='/* English — keys are the Arabic source strings */\n'+''.join(f'"{esc(k)}" = "{esc(v)}";\n' for k,v in T.items())
for p in ['../../App/en.lproj/Localizable.strings','../../Widgets/en.lproj/Localizable.strings']:
    if len(sys.argv)>1: open(p,'w').write(out)
    else: print(p, open(p).read()==out, len(T))
