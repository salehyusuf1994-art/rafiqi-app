import pickle,re,os,collections
code,strs=pickle.load(open('/tmp/lexed.pkl','rb'))
R='/home/claude/rafiqi-app'
def load(p):
    d={}
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";',open(p).read(),re.M):
        if m.group(1) in d: print('DUPKEY',p,m.group(1))
        d[m.group(1)]=m.group(2)
    return d
A=load(R+'/App/en.lproj/Localizable.strings'); W=load(R+'/Widgets/en.lproj/Localizable.strings')
print('app keys',len(A),'widget keys',len(W),'identical',A==W)
for k in set(A)|set(W):
    if A.get(k)!=W.get(k): print('DIFF',k,A.get(k),W.get(k))
# specifier consistency
def specs(s): return sorted(re.findall(r'%(?:\d\$)?(?:ll|l)?[@dfs]|%lld',s))
for k,v in A.items():
    if specs(k)!=specs(v): print('SPEC MISMATCH',repr(k),repr(v))
arab=re.compile('[\u0600-\u06FF]')
miss=collections.defaultdict(list)
for f,st in strs.items():
    for ln,t,ctx in st:
        if not arab.search(t): continue
        key=t.replace('\\"','"').replace('\\n','\n')
        if '\x00' in key: 
            miss['INTERP'].append((os.path.basename(f),ln,key.replace('\x00','⟨⟩'),ctx[-25:].replace('\n',' ')))
            continue
        if key not in A:
            miss['MISSING'].append((os.path.basename(f),ln,key,ctx[-25:].replace('\n',' ')))
for k in miss:
    print('====',k,len(miss[k]))
    for x in miss[k]: print(' ',x)

print('######## FILTERED')
for k in ('MISSING','INTERP'):
    for f,ln,key,ctx in miss[k]:
        c=ctx.rstrip()
        if re.search(r'isEN \? "[^"]*" :$',c): continue
        if not re.search(r'(\(|: |return|= |\?|:)$',c): continue
        if re.search(r'(\[|", |\), \()$',ctx): continue
        print(k,f,ln,repr(key)[:80],'|',c[-32:])
