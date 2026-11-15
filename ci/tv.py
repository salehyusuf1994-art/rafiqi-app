"""يستخرج روابط القنوات من TV.swift: الاسم<TAB>الرابط (كل الروابط)"""
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r'TVChannel\(id: "[^"]+", name: "([^"]+)",.*?urls: \[(.*?)\]', src):
    name, urls = m.groups()
    for i, u in enumerate(re.findall(r'"([^"]+)"', urls)):
        print(f"{name}{' #'+str(i+1) if i else ''}\t{u}")
