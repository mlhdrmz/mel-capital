"""Web önizlemesinin ekran görüntülerini alır (tasarımı derleme sunucusunda kontrol etmek için).

Kullanım: python screenshots.py <web klasörü> <çıktı klasörü>
Uygulama web'de ?sekme=<ad>&dil=<tr|en> parametreleriyle istenen ekranı açar.
"""
import functools
import http.server
import os
import sys
import threading

from playwright.sync_api import sync_playwright

TARGETS = [
    ('ozet', 'tr'), ('harcamalar', 'tr'), ('borclar', 'tr'), ('bankalar', 'tr'),
    ('plan', 'tr'), ('alisveris', 'tr'), ('ayarlar', 'tr'), ('plan', 'en'),
]


def main() -> None:
    web, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=web)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    report = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(args=['--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
        for tab, lang in TARGETS:
            page = browser.new_page(viewport={'width': 1600, 'height': 900})
            logs = []
            page.on('console', lambda m, logs=logs: logs.append(f'{m.type}: {m.text}'))
            page.on('pageerror', lambda e, logs=logs: logs.append(f'pageerror: {e}'))
            page.goto(f'http://127.0.0.1:{port}/?sekme={tab}&dil={lang}')
            try:
                page.wait_for_selector('flutter-view, flt-glass-pane', timeout=60000)
            except Exception as error:  # noqa: BLE001
                logs.append(f'bekleme: {error}')
            page.wait_for_timeout(5000)
            name = f'{tab}_{lang}.png'
            page.screenshot(path=os.path.join(out, name))
            problems = [line for line in logs if line.startswith(('error', 'pageerror', 'bekleme'))]
            report.append(f'{name}: ' + ('sorun yok' if not problems else ' | '.join(problems)[:600]))
            page.close()
        browser.close()
    server.shutdown()
    with open(os.path.join(out, 'rapor.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(report) + '\n')
    print('\n'.join(report))


if __name__ == '__main__':
    main()
