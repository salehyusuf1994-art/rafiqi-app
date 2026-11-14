"""Tiny Swift lexer: strips comments and string contents, keeps interpolations as code."""
import re
def strip(src):
    out=[];i=0;n=len(src);strings=[]  # strings: (line, text)
    line=1
    def emit(c):
        nonlocal line
        out.append(c)
    stack=[]  # for interpolation: track paren depth
    while i<n:
        c=src[i]
        if src.startswith('//',i):
            j=src.find('\n',i); j=n if j<0 else j; out.append(' '*(j-i)); i=j; continue
        if src.startswith('/*',i):
            d=0;j=i
            while j<n:
                if src.startswith('/*',j): d+=1;j+=2;continue
                if src.startswith('*/',j):
                    d-=1;j+=2
                    if d==0: break
                    continue
                j+=1
            out.append(re.sub(r'[^\n]',' ',src[i:j])); i=j; continue
        if c=='"' or (c=='#' and re.match(r'#+"',src[i:])):
            m=re.match(r'(#*)("""|")',src[i:]); hashes=m.group(1); q=m.group(2)
            start=i; i+=len(m.group(0)); buf=[]; parts=[]
            close=q+hashes
            esc='\\'+hashes
            while i<n:
                if src.startswith(close,i): i+=len(close); break
                if src.startswith(esc+'(',i):
                    # interpolation: find matching paren, recursively strip
                    j=i+len(esc)+1; d=1
                    while j<n and d:
                        if src[j]=='"':
                            # nested string inside interpolation: skip it
                            k=j+1
                            while k<n and src[k]!='"':
                                if src[k]=='\\': k+=1
                                k+=1
                            j=k+1; continue
                        if src[j]=='(': d+=1
                        elif src[j]==')': d-=1
                        j+=1
                    parts.append(src[i+len(esc)+1:j-1]); buf.append('\x00'); i=j; continue
                if src.startswith(esc,i) and hashes=='' and src[i]=='\\': buf.append(src[i:i+2]); i+=2; continue
                if q=='"' and src[i]=='\n': break
                buf.append(src[i]); i+=1
            text=''.join(buf)
            strings.append((src.count('\n',0,start)+1,text,src[start-40:start]))
            seg=src[start:i]
            # keep newlines, replace with placeholder string token
            out.append('""'+'\n'*seg.count('\n')+' '*0)
            for p in parts: out.append(' ('+strip(p)[0].replace('\n',' ')+') ')
            continue
        out.append(c); i+=1
    return ''.join(out), strings
