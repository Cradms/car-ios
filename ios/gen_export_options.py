#!/usr/bin/env python3
"""生成 ExportOptions.plist
用法: python3 gen_export_options.py <bundle_id> <team_id> [method] [profile_name]
"""
import plistlib
import sys

bundle = sys.argv[1] if len(sys.argv) > 1 else "com.yg.carapp"
team = sys.argv[2] if len(sys.argv) > 2 else ""
method = sys.argv[3] if len(sys.argv) > 3 else "ad-hoc"
prof = sys.argv[4] if len(sys.argv) > 4 else ""

d = {
    "method": method,
    "teamID": team,
    "signingStyle": "manual",
    "stripSwiftSymbols": True,
    "compileBitcode": False,
}
if prof:
    d["provisioningProfiles"] = {bundle: prof}

with open("ExportOptions.plist", "wb") as f:
    plistlib.dump(d, f)
print("已生成 ExportOptions.plist")
