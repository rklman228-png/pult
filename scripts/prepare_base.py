#!/usr/bin/env python3
"""Build an unsigned IPA from the official RUTUBE iOS .xcarchive ZIP."""
import pathlib, sys, zipfile

if len(sys.argv) != 3:
    sys.exit("usage: prepare_base.py official.zip output.ipa")
source, target = map(pathlib.Path, sys.argv[1:])
target.parent.mkdir(parents=True, exist_ok=True)
needle="/Products/Applications/Rutube.app/"
count=0
with zipfile.ZipFile(source) as archive, zipfile.ZipFile(target,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=7) as out:
    for info in archive.infolist():
        if needle not in info.filename or info.is_dir():
            continue
        rel=info.filename.split(needle,1)[1]
        if rel.startswith("/") or ".." in pathlib.PurePosixPath(rel).parts:
            raise ValueError("unsafe path: "+rel)
        out.writestr("Payload/Rutube.app/"+rel,archive.read(info),compress_type=zipfile.ZIP_DEFLATED)
        count+=1
with zipfile.ZipFile(target) as check:
    assert "Payload/Rutube.app/Rutube" in check.namelist()
    assert "Payload/Rutube.app/Info.plist" in check.namelist()
    assert check.testzip() is None
print("Base IPA prepared:",target,"files:",count)
