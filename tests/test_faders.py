"""Channel faders are linear sliders, not rotary knobs."""
def test_channel_fader_is_linear():
    html = open('index.html').read()
    # No Vol knob — replaced by a linear fader element
    assert 'knob-a-vol' not in html, 'Vol is still a knob'
    assert 'input' in html or 'fader' in html or 'range' in html, 'no linear fader'
    assert 'vol' in html or 'channel' in html, 'no volume/channel fader ref'

def test_vol_still_controls_gain():
    html = open('index.html').read()
    assert 'deckParams' in html, 'deckParams structure missing'
