"""Bir klasörü zip arşivine koyar (yollar her zaman "/" ile, sıra her derlemede aynı).

Kullanım: python zip_dir.py <klasör> <çıktı.zip>
"""
import os
import sys
import zipfile


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    count = 0
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for root, dirs, files in os.walk(src):
            dirs.sort()
            for name in sorted(files):
                path = os.path.join(root, name)
                z.write(path, os.path.relpath(path, src).replace(os.sep, '/'))
                count += 1
    print(f'{out}: {count} dosya, {os.path.getsize(out) // 1024} KB')


if __name__ == '__main__':
    main()
