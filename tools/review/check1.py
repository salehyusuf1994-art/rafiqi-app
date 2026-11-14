import sys,os,re,glob,collections
sys.path.insert(0,os.path.dirname(__file__))
from lex import strip
R='/home/claude/hilal-widgets'
files=sorted(glob.glob(R+'/App/*.swift')+glob.glob(R+'/Shared/*.swift')+glob.glob(R+'/Widgets/*.swift'))
code={};strs={}
for f in files:
    s=open(f).read(); c,st=strip(s); code[f]=c; strs[f]=st
    # bracket balance with positions
    stack=[]
    for ln,l in enumerate(c.split('\n'),1):
        for ch in l:
            if ch in '([{': stack.append((ch,ln))
            elif ch in ')]}':
                if not stack or '([{'[')]}'.index(ch)]!=stack[-1][0]: print('BRACKET',f,ln,ch); stack=[]; break
                stack.pop()
    if stack: print('UNCLOSED',f,stack[-3:])
# top-level declarations per target
app=[f for f in files if not f.endswith(('/Widgets.swift','/MatchActivity.swift'))]
ext=[f for f in files if '/App/' not in f]
def decls(fs):
    d=collections.defaultdict(list)
    for f in fs:
        for ln,l in enumerate(code[f].split('\n'),1):
            m=re.match(r'(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |fileprivate |internal |final )*(struct|enum|class|actor|protocol|typealias|func|let|var)\s+([A-Za-z_]\w*)',l)
            if m:
                key=(m.group(1) in('func',) and m.group(2)) or m.group(2)
                if m.group(1)=='func':
                    # include labels for overload distinction
                    sig=re.match(r'.*?func\s+\w+\s*(<[^>]*>)?\(([^)]*)\)',l)
                    labels=tuple(re.findall(r'(?:^|,)\s*(\w+)(?:\s+\w+)?\s*:',sig.group(2))) if sig else ()
                    key=m.group(2)+str(labels)
                priv='private ' in l or 'fileprivate ' in l
                d[key].append((os.path.basename(f),ln,priv))
    return d
for name,fs in (('APP',app),('EXT',ext)):
    for k,v in decls(fs).items():
        nonpriv=[x for x in v if not x[2]]
        if len(nonpriv)>1: print('DUP',name,k,nonpriv)
import pickle; pickle.dump((code,strs),open('/tmp/lexed.pkl','wb'))
print('files',len(files))
