import pickle,re,os,collections
code,strs=pickle.load(open('/tmp/lexed.pkl','rb'))
# members per type (indent 4 inside top-level struct/enum/class/extension)
mem=collections.defaultdict(list)
for f,c in code.items():
    cur=None
    for ln,l in enumerate(c.split('\n'),1):
        m=re.match(r'(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |fileprivate |final )*(?:struct|enum|class|extension|actor)\s+([\w.]+)',l)
        if m: cur=m.group(1); continue
        if cur and re.match(r'    (?! )',l):
            m=re.match(r'    (?:@\w+(?:\([^)]*\))?\s+)*((?:public |private |fileprivate |static |override |final |mutating |nonisolated |lazy )*)(func|var|let|case|struct|enum|class|typealias)\s+`?(\w+)`?(.*)',l)
            if m:
                mods,kind,name,rest=m.groups()
                if kind=='func':
                    sig=re.match(r'\s*(<[^>]*>)?\(([^)]*)\)',rest)
                    labels=tuple(re.findall(r'(?:^|,)\s*(\w+)(?:\s+\w+)?\s*:',sig.group(2))) if sig else ('?',)
                    name=name+str(labels)
                if kind=='case':
                    for nm in re.findall(r'(\w+)(?:\([^)]*\))?\s*(?:=\s*[^,]+)?',rest.split('//')[0]):
                        pass
                mem[(cur,name)].append((os.path.basename(f),ln,'static' in mods))
for (t,n),v in mem.items():
    if len(v)>1:
        # static vs instance can coexist
        if len(set(x[2] for x in v))==len(v): continue
        print('MEMBER DUP',t,n,v)
