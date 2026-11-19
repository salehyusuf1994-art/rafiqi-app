import sys
sys.path.insert(0,'.')
exec(open('en_tr.py').read())
# مفتاح مكرر بترجمتين مختلفتين = خطأ صامت (الأخيرة تغلب): يوقف التوليد
import re as _re, collections as _c
_d=_c.defaultdict(set)
for _k,_v in _re.findall(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"', open('en_tr.py',encoding='utf-8').read()): _d[_k].add(_v)
_bad={k:v for k,v in _d.items() if len(v)>1}
if _bad:
    print('DUPLICATE KEYS WITH DIFFERENT TRANSLATIONS:', _bad); sys.exit(1)
def esc(s): return s.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')
# فاصلة عليا موحّدة في الإنجليزية: ’ بدل ' داخل الكلمات (Today’s، don’t)
import re as _re2
def tidy(v): return _re2.sub(r"(?<=\w)'(?=\w)", "\u2019", v)
out='/* English — keys are the Arabic source strings */\n'+''.join(f'"{esc(k)}" = "{esc(tidy(v))}";\n' for k,v in T.items())
for p in ['../../App/en.lproj/Localizable.strings','../../Widgets/en.lproj/Localizable.strings']:
    if len(sys.argv)>1: open(p,'w').write(out)
    else: print(p, open(p).read()==out, len(T))
