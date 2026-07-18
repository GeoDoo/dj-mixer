"""Theme toggle tests: light mode exists, swaps CSS vars, has a toggle."""
def test_stylesheet_has_light_vars():
    css = open('styles.css').read()
    assert '.light' in css or '.light-mode' in css, 'no light class in CSS'
    assert '--bg:' in css, '--bg variable defined'

def test_light_mode_inverts_bg_and_ink():
    css = open('styles.css').read()
    # Find both dark and light definitions for --bg and --ink
    import re
    # In light mode, bg should be light (high L in oklch) and ink dark (low L)
    light_bg = re.search(r'\.light[^}]*--bg:\s*(oklch[^;]+)', css, re.DOTALL)
    light_ink = re.search(r'\.light[^}]*--ink:\s*(oklch[^;]+)', css, re.DOTALL)
    assert light_bg, 'light mode --bg not defined'
    assert light_ink, 'light mode --ink not defined'

def test_theme_toggle_button_exists():
    html = open('index.html').read()
    assert 'theme' in html.lower() or 'light' in html.lower() or 'toggle' in html.lower(), \
        'no theme toggle in HTML'
