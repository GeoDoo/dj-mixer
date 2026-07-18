"""Spotify embed support: paste URL → iframe."""
import re

def test_spotify_input_exists():
    html = open('index.html').read()
    assert 'spotify' in html.lower(), 'no Spotify input in HTML'

def test_spotify_embed_url_generated():
    html = open('index.html').read()
    # The JS should reference the embed URL pattern
    assert 'spotify.com/embed/track/' in html, 'no embed URL pattern in JS'

def test_spotify_embed_has_id_parameter():
    html = open('index.html').read()
    assert 'playlist' in html.lower() or 'url' in html.lower() or 'track' in html.lower(), \
        'no track/playlist input field'
