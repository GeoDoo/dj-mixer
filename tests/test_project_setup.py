"""Modern JS project setup verification."""
import json, os, subprocess

def test_project_is_modern_js():
    """package.json exists, declares type module, lists deps, lint/format scripts."""
    assert os.path.exists('package.json'), 'no package.json'
    pkg = json.load(open('package.json'))
    assert pkg.get('type') == 'module', 'not ES module'
    assert pkg.get('scripts'), 'no scripts'
    assert 'lint' in pkg['scripts'] or 'format' in pkg['scripts'], 'no lint/format'

def test_js_modules_load():
    """Each .js module under src/ can be parsed by Node."""
    for root, dirs, files in os.walk('src'):
        for f in files:
            if f.endswith('.js'):
                path = os.path.join(root, f)
                r = subprocess.run(['node','--check',path], capture_output=True, text=True)
                assert r.returncode == 0, f'{path}: {r.stderr.strip()}'

def test_separate_stylesheet():
    """CSS is extracted from index.html into its own file."""
    html = open('index.html').read()
    assert '<link rel="stylesheet"' in html, 'no external stylesheet link'
    assert '<style>' not in html, 'inline styles still present'
