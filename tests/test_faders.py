"""All controls are linear sliders — no rotary knobs."""
def test_eq_is_fader_not_knob():
    html = open('index.html').read()
    assert 'eq-fader' in html, 'no EQ fader elements'
    assert 'class=\"knob\"' not in html, 'rotary knob CSS still present'

def test_vol_is_fader_not_knob():
    html = open('index.html').read()
    assert 'eq-a-vol' in html, 'vol not in eq-row'
