#!/usr/bin/env python3
"""Descarga un paquete de Termux (aarch64) y todas sus dependencias y los
extrae en DEST/usr, sin necesitar dpkg. Uso: termux_fetch.py DEST pkg..."""
import gzip, io, lzma, os, sys, tarfile, urllib.request

REPO = "https://packages.termux.dev/apt/termux-main"
ARCH = os.environ.get("TERMUX_ARCH", "aarch64")
PREFIX = "./data/data/com.termux/files/usr/"


def get(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


def index():
    raw = None
    for name in ("Packages.gz", "Packages"):
        try:
            raw = get(f"{REPO}/dists/stable/main/binary-{ARCH}/{name}")
            if name.endswith(".gz"):
                raw = gzip.decompress(raw)
            break
        except Exception as e:  # noqa
            last = e
    if raw is None:
        raise last
    pkgs, cur, key = {}, {}, None
    for line in raw.decode().splitlines() + [""]:
        if not line:
            if "Package" in cur:
                pkgs[cur["Package"]] = cur
                for p in cur.get("Provides", "").split(","):
                    p = p.strip().split(" ")[0]
                    if p:
                        pkgs.setdefault(p, cur)
            cur = {}
            continue
        if line[0] in " \t" and key:
            cur[key] += "\n" + line.strip()
            continue
        key, _, val = line.partition(":")
        cur[key] = val.strip()
    return pkgs


def deps(p):
    out = []
    for field in ("Depends", "Pre-Depends"):
        for d in p.get(field, "").split(","):
            d = d.strip()
            if not d:
                continue
            alt = d.split("|")[0].strip()
            out.append(alt.split(" ")[0].split("(")[0].strip())
    return out


def extract_deb(data, dest):
    assert data[:8] == b"!<arch>\n", "no es un .deb"
    pos = 8
    while pos < len(data):
        hdr = data[pos:pos + 60]
        name = hdr[:16].decode().strip().rstrip("/")
        size = int(hdr[48:58].decode().strip())
        body = data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size & 1)
        if not name.startswith("data.tar"):
            continue
        if name.endswith(".xz"):
            body = lzma.decompress(body)
        elif name.endswith(".gz"):
            body = gzip.decompress(body)
        elif name.endswith(".zst"):
            import zstandard  # type: ignore
            body = zstandard.ZstdDecompressor().decompressobj().decompress(body)
        with tarfile.open(fileobj=io.BytesIO(body)) as t:
            for m in t.getmembers():
                if not m.name.startswith(PREFIX):
                    continue
                rel = m.name[len(PREFIX):]
                if not rel or ".." in rel.split("/"):
                    continue
                m.name = "usr/" + rel
                ABS = "/data/data/com.termux/files/usr/"
                if m.issym() and m.linkname.startswith(ABS):
                    m.linkname = os.path.relpath("usr/" + m.linkname[len(ABS):], os.path.dirname(m.name))
                if m.islnk():
                    m.linkname = "usr/" + m.linkname[len(PREFIX):] if m.linkname.startswith(PREFIX) else m.linkname
                t.extract(m, dest, set_attrs=True, filter="fully_trusted") if sys.version_info >= (3, 12) else t.extract(m, dest)


def main():
    dest, wanted = sys.argv[1], sys.argv[2:]
    pkgs = index()
    seen, order, stack = set(), [], list(wanted)
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        p = pkgs.get(n)
        if p is None:
            print("aviso: no encuentro", n, file=sys.stderr)
            continue
        order.append(p)
        stack.extend(deps(p))
    os.makedirs(dest, exist_ok=True)
    done = set()
    for p in order:
        if p["Package"] in done:
            continue
        done.add(p["Package"])
        print("termux:", p["Package"], p["Version"])
        extract_deb(get(f"{REPO}/{p['Filename']}"), dest)
    with open(os.path.join(dest, "PACKAGES.txt"), "w") as f:
        for p in order:
            f.write(f"{p['Package']} {p['Version']}\n")


if __name__ == "__main__":
    main()
