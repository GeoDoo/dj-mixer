"""Verify HTML DJ mixer has mp4/m4a support wired up."""
import re

def test_accept_attr_includes_mp4():
    html = open('index.html').read()
    matches = re.findall(r'accept="([^"]+)"', html)
    for m in matches:
        assert '.mp4' in m, f'missing .mp4 in accept="{m}"'
        assert '.m4a' in m, f'missing .m4a in accept="{m}"'
        assert 'video/' not in m, f'video/* still in accept="{m}" — music mixer'

def test_drop_handler_accepts_audio_and_video():
    html = open('index.html').read()
    assert "f.type.startsWith('audio/')||f.type.startsWith('video/')" in html

def test_each_deck_has_mp4_accept():
    html = open('index.html').read()
    deck_a = re.search(r'id="file-a"[^>]+accept="([^"]+)"', html)
    deck_b = re.search(r'id="file-b"[^>]+accept="([^"]+)"', html)
    assert deck_a and deck_b, 'missing file inputs'
    for d in [deck_a, deck_b]:
        assert '.mp4' in d.group(1)
        assert 'video/' not in d.group(1)

if __name__ == '__main__':
    test_accept_attr_includes_mp4()
    test_drop_handler_accepts_audio_and_video()
    test_each_deck_has_mp4_accept()
    print('PASS — all 3 tests')
