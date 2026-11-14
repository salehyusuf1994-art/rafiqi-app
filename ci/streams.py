"""يستخرج روابط الإذاعات (الأساسية والرسمية والاحتياطية) من Media.swift ويطبع قائمة: الاسم<TAB>الرابط"""
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
consts = dict(re.findall(r'private static let (\w+) = "([^"]+)"', src))
def expand(expr):
    expr = expr.strip()
    m = re.fullmatch(r'(\w+)\s*\+\s*"([^"]*)"', expr)
    if m and m.group(1) in consts: return consts[m.group(1)] + m.group(2)
    m = re.fullmatch(r'"([^"]+)"', expr)
    return m.group(1) if m else None
out = []
# Station(name: "...", url: "...")
for name, url in re.findall(r'Station\(name: "([^"]+)", url: "([^"]+)"', src):
    out.append((name, url))
# s("name", "CC", primary, [alts])
for m in re.finditer(r's\("([^"]+)", "([A-Z]{2})", ([^,\n]+?)(?:,\s*\[(.*?)\])?\)', src, re.S):
    name, cc, prim, alts = m.groups()
    p = expand(prim)
    if p: out.append((f"{cc} {name}", p))
    for a in re.split(r',\s*(?=(?:\w+\s*\+\s*)?")', alts or ""):
        u = expand(a.replace("\n", " "))
        if u: out.append((f"{cc} {name} (احتياطي)", u))
seen = set()
for n, u in out:
    if u not in seen:
        seen.add(u); print(f"{n}\t{u}")
