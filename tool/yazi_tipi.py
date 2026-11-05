"""Rakamlar için Manrope yazı tipini (SIL Open Font License) hazırlar.

Google Fonts deposundaki değişken Manrope dosyası indirilir ve uygulamanın kullandığı kalınlıklar
(400, 500, 600, 700, 800) ayrı dosyalar olarak çıkarılır; lisans metni de yanına konur.

Kullanım: python3 tool/yazi_tipi.py app/assets/fonts
Dosyalar zaten varsa hiçbir şey yapmaz.
"""
import os
import subprocess
import sys
import urllib.request

WEIGHTS = {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold'}
SOURCE = 'https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/'


def main() -> None:
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    targets = {w: os.path.join(out, f'Manrope-{name}.ttf') for w, name in WEIGHTS.items()}
    license_path = os.path.join(out, 'OFL-Manrope.txt')
    if all(os.path.exists(p) for p in targets.values()) and os.path.exists(license_path):
        print('Manrope hazır')
        return
    subprocess.run([sys.executable, '-m', 'pip', 'install', '--quiet', 'fonttools'], check=True)
    from fontTools.ttLib import TTFont  # noqa: E402 (fonttools yeni kuruldu)
    from fontTools.varLib import instancer  # noqa: E402

    variable = os.path.join(out, '_Manrope-degisken.ttf')
    urllib.request.urlretrieve(SOURCE + 'Manrope%5Bwght%5D.ttf', variable)
    urllib.request.urlretrieve(SOURCE + 'OFL.txt', license_path)
    for weight, path in targets.items():
        font = TTFont(variable)
        instance = instancer.instantiateVariableFont(font, {'wght': weight})
        instance.save(path)
        print(f'{os.path.basename(path)}: {os.path.getsize(path)} bayt')
    os.remove(variable)


if __name__ == '__main__':
    main()
