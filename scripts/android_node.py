#!/usr/bin/env python3
"""Prepara Node.js de Termux para ir dentro del APK de Herrero.

Uso: android_node.py <carpeta termux (con usr/)> <jniLibs/ABI>
     android_node.py --pack <bundle freellmapi> <cert.pem> <jniLibs/ABI/libfreellmapi_app.so>

Android (targetSdk 29+) solo deja ejecutar ficheros que el instalador extrae
de lib/<abi>/ y cuyo nombre es lib*.so. Así que:
  - usr/bin/node            -> libnode.so
  - cada biblioteca que pide (DT_NEEDED, transitivo) -> lib*.so; las de nombre
    con versión (libssl.so.3) pasan a libssl3.so, cambiando el nombre dentro del
    ELF en el mismo sitio (el nombre nuevo siempre es más corto: no se mueve nada).
  - FreeLLMAPI (app/ del bundle) y los certificados -> libfreellmapi_app.so (tar.gz)
"""
import os
import struct
import sys
import tarfile

# nombres que ya existen en el APK o en el sistema: se renombran igualmente
CLASH = {"libc++_shared.so": "libcxxtermux.so"}


def new_name(n):
    if n in CLASH:
        return CLASH[n]
    if n.endswith(".so"):
        return n
    stem, _, ver = n.partition(".so.")
    out = stem + ver.replace(".", "") + ".so"
    assert len(out) <= len(n), (n, out)
    return out


class Elf:
    def __init__(self, path):
        self.path = path
        self.b = bytearray(open(path, "rb").read())
        assert self.b[:4] == b"\x7fELF" and self.b[4] == 2 and self.b[5] == 1, f"{path}: no es ELF64 LE"
        (self.phoff,) = struct.unpack_from("<Q", self.b, 0x20)
        self.phentsize, self.phnum = struct.unpack_from("<HH", self.b, 0x36)
        self.loads = []
        dyn = None
        for i in range(self.phnum):
            o = self.phoff + i * self.phentsize
            p_type, _, p_offset, p_vaddr, _, p_filesz, _, _ = struct.unpack_from("<IIQQQQQQ", self.b, o)
            if p_type == 1:
                self.loads.append((p_vaddr, p_offset, p_filesz))
            elif p_type == 2:
                dyn = (p_offset, p_filesz)
        assert dyn, f"{path}: sin PT_DYNAMIC"
        self.dyn = []
        off, size = dyn
        for j in range(0, size, 16):
            tag, val = struct.unpack_from("<qQ", self.b, off + j)
            if tag == 0:
                break
            self.dyn.append((tag, val))
        strtab = next(v for t, v in self.dyn if t == 5)
        self.strtab = self.v2o(strtab)

    def v2o(self, v):
        for vaddr, off, sz in self.loads:
            if vaddr <= v < vaddr + sz:
                return v - vaddr + off
        raise ValueError(hex(v))

    def s(self, o):
        a = self.strtab + o
        return self.b[a:self.b.index(0, a)].decode()

    def needed(self):
        return [self.s(v) for t, v in self.dyn if t == 1]

    def rename(self, mapping):
        for t, v in self.dyn:
            if t not in (1, 14):  # DT_NEEDED, DT_SONAME
                continue
            old = self.s(v)
            new = mapping.get(old)
            if not new or new == old:
                continue
            a = self.strtab + v
            enc = new.encode() + b"\0" * (len(old) - len(new) + 1)
            self.b[a:a + len(old) + 1] = enc

    def save(self, path):
        open(path, "wb").write(self.b)
        os.chmod(path, 0o755)


def main():
    termux, jni = sys.argv[1:3]
    pack = "libfreellmapi_app.so"
    usr = os.path.join(termux, "usr")
    libdir = os.path.join(usr, "lib")
    os.makedirs(jni, exist_ok=True)
    node = os.path.join(usr, "bin", "node")
    todo, seen, libs = [node], set(), {}
    while todo:
        f = todo.pop()
        for n in Elf(f).needed():
            if n in seen:
                continue
            seen.add(n)
            p = os.path.join(libdir, n)
            if os.path.exists(p):
                libs[n] = os.path.realpath(p)
                todo.append(libs[n])
            # si no está en Termux es del sistema (libc, libm, libdl, liblog…)
    mapping = {n: new_name(n) for n in libs}
    print("bibliotecas:", ", ".join(f"{a}->{b}" for a, b in sorted(mapping.items())))
    e = Elf(node)
    e.rename(mapping)
    e.save(os.path.join(jni, "libnode.so"))
    for n, p in libs.items():
        e = Elf(p)
        e.rename(mapping)
        e.save(os.path.join(jni, mapping[n]))
    # comprobación: ningún DT_NEEDED queda sin resolver dentro de jniLibs (salvo el sistema)
    system = {"libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so", "libz.so"}
    names = set(os.listdir(jni))
    for f in sorted(names):
        if not f.endswith(".so") or f == os.path.basename(pack):
            continue
        try:
            nd = Elf(os.path.join(jni, f)).needed()
        except AssertionError:
            continue
        missing = [n for n in nd if n not in names and n not in system]
        if missing:
            print(f"aviso: {f} pide {missing}", file=sys.stderr)
    print("listo:", len(libs) + 1, "ficheros en", jni)


def pack_app(bundle, cert, out):
    """tar.gz con app/ de FreeLLMAPI y cert.pem (se guarda como libfreellmapi_app.so)."""
    with tarfile.open(out, "w:gz", compresslevel=9) as t:
        t.add(os.path.join(bundle, "app"), arcname="app")
        t.add(os.path.join(bundle, "pack.json"), arcname="pack.json")
        if cert and os.path.exists(cert):
            t.add(cert, arcname="cert.pem")


if __name__ == "__main__":
    if sys.argv[1] == "--pack":
        pack_app(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        main()
