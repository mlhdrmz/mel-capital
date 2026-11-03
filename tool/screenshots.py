"""Web önizlemesinin ekran görüntülerini alır (tasarımı derleme sunucusunda kontrol etmek için).

Kullanım: python screenshots.py <web klasörü> <çıktı klasörü>
Uygulama web'de ?sekme=<ad>&dil=<tr|en>&banka=<anahtar>&ekran=<tanitim|baslangic|kurulum>&adim=<adım> parametreleriyle istenen ekranı açar.
"""
import functools
import http.server
import os
import sys
import threading

from playwright.sync_api import sync_playwright

TARGETS = [
    ('ozet_tr', 'sekme=ozet&dil=tr'),
    ('harcamalar_tr', 'sekme=harcamalar&dil=tr'),
    ('borclar_tr', 'sekme=borclar&dil=tr'),
    ('bankalar_tr', 'sekme=bankalar&dil=tr'),
    ('banka_akbank_tr', 'sekme=bankalar&dil=tr&banka=akbank'),
    ('plan_tr', 'sekme=plan&dil=tr'),
    ('alisveris_tr', 'sekme=alisveris&dil=tr'),
    ('ayarlar_tr', 'sekme=ayarlar&dil=tr'),
    ('ayarlar_guncelleme_tr', 'sekme=ayarlar&dil=tr&guncelleme=var'),
    ('tanitim1_tr', 'ekran=tanitim&dil=tr'),
    ('tanitim2_tr', 'ekran=tanitim&slayt=2&dil=tr'),
    ('tanitim3_tr', 'ekran=tanitim&slayt=3&dil=tr'),
    ('baslangic_tr', 'ekran=baslangic&dil=tr'),
    ('kurulum_ekstre_tr', 'ekran=kurulum&adim=ekstre&dil=tr'),
    ('kurulum_hesaplar_tr', 'ekran=kurulum&adim=hesaplar&dil=tr'),
    ('kurulum_kartlar_tr', 'ekran=kurulum&adim=kartlar&dil=tr'),
    ('kurulum_krediler_tr', 'ekran=kurulum&adim=krediler&dil=tr'),
    ('kurulum_giderler_tr', 'ekran=kurulum&adim=giderler&dil=tr'),
    ('kurulum_bitti_tr', 'ekran=kurulum&adim=bitti&dil=tr'),
    ('ipucu_ozet_tr', 'sekme=ozet&ipucu=1&dil=tr'),
    ('panel_harcama_tr', 'sekme=harcamalar&dil=tr&panel=harcama'),
    ('panel_borc_tr', 'sekme=borclar&dil=tr&panel=borc'),
    ('ozet_en', 'sekme=ozet&dil=en'),
    ('tanitim1_en', 'ekran=tanitim&dil=en'),
    ('plan_en', 'sekme=plan&dil=en'),
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
        for name, query in TARGETS:
            page = browser.new_page(viewport={'width': 1600, 'height': 900})
            logs = []
            page.on('console', lambda m, logs=logs: logs.append(f'{m.type}: {m.text}'))
            page.on('pageerror', lambda e, logs=logs: logs.append(f'pageerror: {e}'))
            page.goto(f'http://127.0.0.1:{port}/?{query}')
            try:
                page.wait_for_selector('flutter-view, flt-glass-pane', timeout=60000)
            except Exception as error:  # noqa: BLE001
                logs.append(f'bekleme: {error}')
            page.wait_for_timeout(5000)
            name = f'{name}.png'
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
