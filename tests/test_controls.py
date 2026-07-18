import subprocess, time, sys, json
from playwright.sync_api import sync_playwright

def test_controls_work():
    srv = subprocess.Popen(['python3','-m','http.server','8765'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)

    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.on('console', lambda msg: (
            errors.append({'type': msg.type, 'text': msg.text})
        if msg.type == 'error' else None))
        page.on('pageerror', lambda e: errors.append({'type': 'exception', 'text': str(e)}))

        page.goto('http://localhost:8765/index.html')
        page.wait_for_load_state('networkidle')
        time.sleep(0.5)

        assert not errors, f'Console errors: {errors}'

        page.click('label[for="file-a"]')

        for deck in ['a','b']:
            for band in ['vol','hi','mid','lo']:
                fader = page.locator(f'#eq-{deck}-{band}')
                box = fader.bounding_box()
                page.mouse.move(box['x'] + box['width']/2, box['y'] + box['height']/2)
                page.mouse.down()
                page.mouse.move(box['x'] + box['width']*0.8, box['y'] + box['height']/2, steps=5)
                page.mouse.up()

        xf = page.locator('#fader-track')
        box = xf.bounding_box()
        page.mouse.move(box['x'] + box['width']/2, box['y'] + box['height']*0.8)
        page.mouse.down()
        page.mouse.move(box['x'] + box['width']/2, box['y'] + box['height']*0.2, steps=5)
        page.mouse.up()

        page.keyboard.press('Space')
        page.keyboard.press('2')
        page.keyboard.press('Space')
        page.keyboard.press('ArrowLeft')
        page.keyboard.press('1')
        page.keyboard.press('q')
        page.keyboard.press('w')
        page.keyboard.press('a')
        page.keyboard.press('z')

        page.click('#play-a')
        browser.close()

    srv.terminate()
    assert not errors, f'Errors during interaction: {errors}'
