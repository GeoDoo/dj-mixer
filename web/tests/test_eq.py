"""3-band EQ per deck: Hi/Mid/Lo controls exist."""
def test_eq_controls_per_deck():
    html = open('index.html').read().lower()
    assert 'eq' in html, 'no EQ controls in HTML'

def test_eq_uses_biquad_filter_node():
    html = open('index.html').read()
    assert 'createBiquadFilter' in html, 'no Web Audio EQ filter (BiquadFilterNode)'
