"""يولّد قوائم «الويدجت» في «تعديل الأداة» من Catalog.swift: الاسم = القسم ورقمه، والوصف = اسم الويدجت."""
import re, collections
R = '/home/claude/rafiqi-app/'
cat = open(R + 'Widgets/Catalog.swift').read()
items = re.findall(r'w\("([\w.]+)", "([^"]+)", "([^"]+)", "[^"]*", \[([^\]]*)\]', cat)
prefix = {"التاريخ": "التاريخ", "الصلاة": "الصلاة", "الساعة": "الساعة", "الطقس": "الطقس", "القرآن والأذكار": "القرآن",
          "الوسائط": "الوسائط", "القنوات": "القنوات", "الأدوات": "الأدوات", "شاشة القفل": "القفل"}
def ar(n): return str(n).translate(str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩'))
cnt = collections.Counter(); num = {}
for i, g, n, f in items:
    cnt[g] += 1; num[i] = f"{prefix[g]} {ar(cnt[g])}"
def case(i): return i.replace('hilal.', '').replace('.', '_')
def enum(name, fam, typ):
    rows = [(i, g, n) for i, g, n, f in items if fam in f]
    out = [f'enum {name}: String, AppEnum {{']
    out += [f'    case {case(i)} = "{i}"' for i, g, n in rows]
    out += ['    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"',
            f'    static let caseDisplayRepresentations: [{name}: DisplayRepresentation] = [']
    out += [f'        .{case(i)}: DisplayRepresentation(title: "{num[i]}", subtitle: "{n}"),' for i, g, n in rows]
    out += ['    ]', '}', '']
    return '\n'.join(out), rows
d = open(R + 'Widgets/Designs.swift').read()
start = d.index('enum DesignSmall'); end = d.index('struct RafiqiLargeIntent')
blocks = []
for nm, fam in [('DesignSmall', '.systemSmall'), ('DesignMedium', '.systemMedium'), ('DesignLarge', '.systemLarge')]:
    b, rows = enum(nm, fam, None); blocks.append(b); print(nm, len(rows))
d = d[:start] + '\n'.join(blocks) + '\n' + d[end:]
open(R + 'Widgets/Designs.swift', 'w').write(d)
# أسماء للترجمة الإنجليزية
en = {"التاريخ": "Date", "الصلاة": "Prayer", "الساعة": "Clock", "الطقس": "Weather", "القرآن": "Quran", "الوسائط": "Media",
      "القنوات": "Channels", "الأدوات": "Tools", "القفل": "Lock"}
pairs = {}
for i, v in num.items():
    p, n = v.rsplit(' ', 1)
    pairs[v] = en[p] + ' ' + n.translate(str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789'))
open('/tmp/en_numbers.py', 'w').write('T.update(' + repr(pairs) + ')\n')
