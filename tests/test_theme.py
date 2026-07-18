"""Light mode is the default theme."""
import re

def test_default_theme_is_light():
    css = open('styles.css').read()
    # --bg should be light (high L > 0.80)
    bg_match = re.search(r'--bg:\s*(oklch\([^)]+\))', css)
    assert bg_match, '--bg not found in :root'
    val = bg_match.group(1)
    # Extract L value from oklch
    l_val = float(val.split()[0].replace('oklch(',''))
    assert l_val > 0.80, f'default --bg is dark ({l_val}), expected light'

def test_light_ink_is_dark():
    # Light mode means dark text (low L < 0.30)
    css = open('styles.css').read()
    ink_match = re.search(r'--ink:\s*(oklch\([^)]+\))', css)
    assert ink_match, '--ink not found'
    val = ink_match.group(1)
    l_val = float(val.split()[0].replace('oklch(',''))
    assert l_val < 0.30, f'--ink is light ({l_val}), expected dark for readability'
