import sys, urllib.request, urllib.parse
UA = {"User-Agent": "VLC/3.0.20 LibVLC/3.0.20"}
def get(u, n=4096):
    try:
        r = urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=10)
        return r.status, r.read(n)
    except Exception as e:
        return getattr(e, "code", 0) or str(e)[:40], b""
for u in sys.argv[1:]:
    code, body = get(u)
    line = f"{code} {len(body)} {u}"
    depth = 0
    while body.startswith(b"#EXTM3U") and depth < 3:
        uris = [l for l in body.decode(errors="ignore").splitlines() if l and not l.startswith("#")]
        if not uris: line += " | empty"; break
        nxt = urllib.parse.urljoin(u, uris[0]); u = nxt
        code, body = get(nxt, 20000)
        line += f" -> {code} {len(body)}"
        depth += 1
    print(line)
