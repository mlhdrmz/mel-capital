"""Bir çıktı dosyasının son satırlarını GitHub Actions notu (annotation) olarak yazar.

Kullanım: python annotate.py <error|warning|notice> "<başlık>" <dosya> [satır sayısı]

Notlar GitHub API'sinden okunabildiği için, derleme ya da test hatalarının ayrıntısı
çalışma günlüğünü indirmeden de görülebilir.
"""
import sys


def encode(text: str) -> str:
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def main() -> None:
    level = sys.argv[1] if len(sys.argv) > 1 else 'notice'
    title = sys.argv[2] if len(sys.argv) > 2 else 'Çıktı'
    path = sys.argv[3] if len(sys.argv) > 3 else ''
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            lines = [line.rstrip() for line in f.read().splitlines()]
    except OSError:
        lines = ['(çıktı dosyası yok)']
    lines = [line for line in lines if line.strip()] or ['(boş)']
    body = '\n'.join(lines[-count:])[-60000:]
    safe_title = title.replace('%', '%25').replace(',', '%2C').replace(':', '%3A')
    print(f'::{level} title={safe_title}::{encode(body)}')


if __name__ == '__main__':
    main()
