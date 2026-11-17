#!/usr/bin/env python3
"""Embed RTUIFix.framework into the original ARM64 iOS app without recompiling Rutube."""
import argparse
import pathlib
import plistlib
import struct
import zipfile

APP="Payload/Rutube.app/"
BIN=APP+"Rutube"
LIB=b"@executable_path/Frameworks/RTUIFix.framework/RTUIFix"
MAGIC=0xFEEDFACF
ARM64=0x0100000C

def commands(data):
    if len(data)<32 or struct.unpack_from("<I",data)[0]!=MAGIC:
        raise ValueError("Expected ARM64 Mach-O, not a zip or Android APK")
    if struct.unpack_from("<I",data,4)[0]!=ARM64:
        raise ValueError("Not ARM64")
    count,size=struct.unpack_from("<II",data,16)
    pos,end=32,32+size
    result=[]
    for i in range(count):
        if pos+8>end: raise ValueError("Broken Mach-O load command header")
        cmd,n=struct.unpack_from("<II",data,pos)
        if n<8 or n%8 or pos+n>end: raise ValueError("Broken Mach-O load command")
        result.append((cmd,pos,n))
        pos+=n
    if pos!=end: raise ValueError("Mach-O load command size mismatch")
    return result,count,size,end

def inject(original):
    cmds,count,size,end=commands(original)
    if any(LIB in original[p:p+n] for _,p,n in cmds): return original
    cmdlen=(24+len(LIB)+1+7)//8*8
    if end+cmdlen>0x4000 or any(original[end:end+cmdlen]):
        raise ValueError("Not enough safe Mach-O header padding; do not shift code")
    patched=bytearray(original)
    raw=struct.pack("<IIIIII",0xC,cmdlen,24,0,0x10000,0x10000)+LIB+b"\0"
    patched[end:end+cmdlen]=raw.ljust(cmdlen,b"\0")
    struct.pack_into("<II",patched,16,count+1,size+cmdlen)
    if not any(LIB in patched[p:p+n] for _,p,n in commands(patched)[0]):
        raise ValueError("Library injection validation failed")
    return bytes(patched)

def build(base,framework,out):
    if not (framework/"RTUIFix").is_file(): raise FileNotFoundError("Framework not compiled")
    if not (framework/"Info.plist").is_file(): raise FileNotFoundError("Framework plist not found")
    out.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(base) as z, zipfile.ZipFile(out,"w",compression=zipfile.ZIP_DEFLATED) as dest:
        if BIN not in z.namelist(): raise ValueError("Missing iOS executable")
        for info in z.infolist():
            name=info.filename
            if ("/_CodeSignature/" in name or
                name.endswith("/embedded.mobileprovision") or
                name.startswith(APP+"Frameworks/RTUIFix.framework/")):
                continue
            data=z.read(info)
            if name==BIN: data=inject(data)
            if name==APP+"Info.plist":
                plist=plistlib.loads(data)
                plist["CFBundleDisplayName"]="Rutube"
                plist["CFBundleName"]="Rutube"
                plist["UIDesignRequiresCompatibility"]=True
                data=plistlib.dumps(plist,fmt=plistlib.FMT_BINARY)
            dest.writestr(info,data,compress_type=zipfile.ZIP_DEFLATED)
        for file in framework.rglob("*"):
            if file.is_file():
                path=APP+"Frameworks/"+file.relative_to(framework.parent).as_posix()
                dest.write(file,path)
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None
        assert APP+"Frameworks/RTUIFix.framework/RTUIFix" in z.namelist()
        plist=plistlib.loads(z.read(APP+"Info.plist"))
        assert plist["CFBundleDisplayName"]=="Rutube"
        assert any(LIB in z.read(BIN)[p:p+n] for _,p,n in commands(z.read(BIN))[0])
    print("SUCCESS: unsigned iOS IPA with embedded UI framework:",out)
    print("Display name: Rutube. Re-sign the app, its extensions, and RTUIFix.framework before installing.")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--base",type=pathlib.Path,required=True)
    p.add_argument("--framework",type=pathlib.Path,required=True)
    p.add_argument("--output",type=pathlib.Path,required=True)
    a=p.parse_args()
    build(a.base,a.framework,a.output)
