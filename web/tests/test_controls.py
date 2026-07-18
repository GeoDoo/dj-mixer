import subprocess, time, sys, json, os
from playwright.sync_api import sync_playwright

def _serve():
    srv = subprocess.Popen(['python3','backend.py'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=os.path.dirname(__file__)+'/..')
    time.sleep(1.5)
    return srv

def test_controls_work():
    srv = _serve()
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

def test_cue_jumps_back():
    """Upload a WAV, set cue at 0s, seek to 1s, click Cue → jumps to 0 and plays."""
    import wave, struct, tempfile, os
    # generate a tiny valid WAV
    wav = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    with wave.open(wav.name, 'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100)
        for i in range(44100*2):  # 2 seconds
            f.writeframes(struct.pack('<h', int(16000 * ((i%44100)/44100))))
    wav.close()

    srv = _serve()
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto('http://localhost:8765/index.html')
        page.wait_for_load_state('networkidle')
        time.sleep(0.3)
        assert not errors, f'Errors on load: {errors}'

        # upload the WAV via file input
        page.locator('#file-a').set_input_files(wav.name)
        time.sleep(0.5)  # wait for decode

        # play for a moment then stop
        page.click('#play-a')
        time.sleep(0.3)
        page.click('#play-a')
        time.sleep(0.1)

        # Cue — marks current position
        page.click('#cue-a')
        time.sleep(0.1)
        cue_before = page.evaluate('() => a.cuePoint()')
        print(f'cuePoint set at: {cue_before}')

        # click canvas to seek forward
        canvas = page.locator('#wave-a')
        box = canvas.bounding_box()
        page.mouse.click(box['x'] + box['width'] * 0.7, box['y'] + box['height']/2)
        time.sleep(0.1)

        # click Cue again — should jump back to cuePoint and play
        page.click('#cue-a')
        time.sleep(0.2)

        playing = page.evaluate('() => a.playing')
        pos = page.evaluate('() => a.pausePos()')
        play_text = page.inner_text('#play-a')
        print(f'after cue jump: playing={playing}, pos={pos}, play_btn={play_text}')
        assert play_text == '❚❚', f'Play button should show pause, got {play_text}'
        assert pos is not None and pos < cue_before + 0.5, f'Cue should jump back near {cue_before}, got pos={pos}'

        browser.close()

    os.unlink(wav.name)
    srv.terminate()
    assert not errors, f'Errors: {errors}'

def test_loop_toggle():
    """Upload WAV, click ⟳, verify active class toggles on click."""
    import wave, struct, tempfile
    wav = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    with wave.open(wav.name, 'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100)
        for i in range(44100): f.writeframes(struct.pack('<h', int(16000*(i%44100)/44100)))
    wav.close()
    srv = _serve()
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto('http://localhost:8765/index.html')
        page.wait_for_load_state('networkidle')
        time.sleep(0.3)
        assert not errors, f'Errors on load: {errors}'
        page.locator('#file-a').set_input_files(wav.name)
        time.sleep(0.5)
        # click ⟳ — should get active class
        page.click('#loop-a')
        time.sleep(0.1)
        cls = page.evaluate('() => document.getElementById("loop-a").className')
        assert 'active' in cls, f'loop should have active class, got: {cls}'
        # click again — active should be removed
        page.click('#loop-a')
        time.sleep(0.1)
        cls2 = page.evaluate('() => document.getElementById("loop-a").className')
        assert 'active' not in cls2, f'loop should not have active class after second click, got: {cls2}'
        browser.close()
    os.unlink(wav.name)
    srv.terminate()
    assert not errors, f'Errors: {errors}'

def test_canvas_seek_changes_position():
    """Click on waveform at 80% — verify pausePos moved past halfway."""
    import wave, struct, tempfile
    wav = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    with wave.open(wav.name, 'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100)
        for i in range(44100*3): f.writeframes(struct.pack('<h', int(16000*(i%44100)/44100)))
    wav.close()
    srv = _serve()
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto('http://localhost:8765/index.html')
        page.wait_for_load_state('networkidle')
        time.sleep(0.3)
        assert not errors
        page.locator('#file-a').set_input_files(wav.name)
        time.sleep(0.5)
        # play briefly then stop
        page.click('#play-a')
        time.sleep(0.3)
        page.click('#play-a')
        time.sleep(0.1)
        pos_before = page.evaluate('() => a.pausePos()')
        # click canvas at 80%
        canvas = page.locator('#wave-a')
        box = canvas.bounding_box()
        page.mouse.click(box['x'] + box['width'] * 0.8, box['y'] + box['height']/2)
        time.sleep(0.1)
        pos_after = page.evaluate('() => a.pausePos()')
        print(f'seek: {pos_before} -> {pos_after}')
        assert pos_after > pos_before + 0.3, f'seek position should advance, was {pos_before} -> {pos_after}'
        browser.close()
    os.unlink(wav.name)
    srv.terminate()
    assert not errors, f'Errors: {errors}'
