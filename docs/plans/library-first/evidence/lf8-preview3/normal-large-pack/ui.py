import sys
import io
import time
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(OUT.parent / 'native'))
import driver
import ui_driver

driver.OUT = ui_driver.OUT = OUT


def photo(name, page):
    deadline = time.monotonic() + 45
    while True:
        raw = driver.device('exec-out', 'screencap', '-p')
        image = Image.open(io.BytesIO(raw)).convert('RGB').crop((60, 350, 1110, 1900))
        colors = len(image.getcolors(image.width * image.height) or [])
        if colors > 15000:
            break
        assert time.monotonic() < deadline, ('No photograph pixels', name, colors)
        time.sleep(.5)
    nodes = driver.snap(name)
    assert page in driver.text(nodes), (name, page, driver.text(nodes))
    driver.save(name + '-pixel-check.json', {'central_unique_colors': colors, 'page': page, 'normal_apk': True, 'note': 'Pixel diversity is a readiness check only; saved screenshot inspected separately'})
    return nodes
