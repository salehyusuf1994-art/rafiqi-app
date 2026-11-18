"""يختار محاكي آيفون لكل خطوات CI (مكان واحد بدل نسخ متفرقة): iPhone 17 Pro Max إن وُجد، ثم أي Pro Max، ثم أي آيفون."""
import json, subprocess, sys
d = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
c = [x for k, v in d.items() if "iOS" in k for x in v if "iPhone" in x["name"]]
p = [x for x in c if x["name"] == "iPhone 17 Pro Max"] or [x for x in c if "Pro Max" in x["name"]] or c
if not p:
    sys.exit("no iPhone simulator available")
print(p[-1]["udid"])
