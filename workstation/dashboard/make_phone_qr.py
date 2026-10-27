"""Write a phone QR PNG from a URL file. Exit 2 if no QR library is installed."""
from pathlib import Path
import sys

def main() -> int:
    if len(sys.argv) != 3:
        return 2
    link = Path(sys.argv[1])
    out = Path(sys.argv[2])
    url = link.read_text(encoding="ascii").strip()
    if not url.startswith("https://"):
        return 2
    try:
        import segno
        segno.make(url, error="m").save(str(out), scale=10, border=2)
        return 0
    except Exception:
        pass
    try:
        import qrcode
        qrcode.make(url).save(str(out))
        return 0
    except Exception:
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
