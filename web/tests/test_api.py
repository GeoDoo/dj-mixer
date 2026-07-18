"""Backend API tests — upload, list, stream, delete."""
import subprocess, time, json, os, wave, struct, tempfile, urllib.request

BASE = 'http://localhost:8765'

def _serve():
    srv = subprocess.Popen(['python3','backend.py'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    return srv

def _wav():
    f = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    with wave.open(f.name, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
        for i in range(44100): w.writeframes(struct.pack('<h', int(16000*(i%44100)/44100)))
    return f.name

def test_upload_then_list_then_stream():
    srv = _serve()
    try:
        # upload
        wav = _wav()
        import urllib.request
        import io
        boundary = '----testboundary'
        body = []
        body.append(f'--{boundary}'.encode())
        body.append(b'Content-Disposition: form-data; name="file"; filename="test.wav"')
        body.append(b'Content-Type: audio/wav')
        body.append(b'')
        with open(wav, 'rb') as f:
            body.append(f.read())
        body.append(f'--{boundary}--'.encode())
        data = b'\r\n'.join(body)

        req = urllib.request.Request(f'{BASE}/api/upload', data=data,
            headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
        resp = urllib.request.urlopen(req)
        assert resp.status == 200, f'upload status {resp.status}'
        result = json.loads(resp.read())
        track_id = result['id']
        assert result['name'] == 'test.wav'
        assert result['duration'] >= 0
        print(f'uploaded: {track_id}')

        # list
        resp = urllib.request.urlopen(f'{BASE}/api/tracks')
        tracks = json.loads(resp.read())
        ids = [t['id'] for t in tracks]
        assert track_id in ids, f'{track_id} not in {ids}'
        print(f'found in track list')

        # stream
        resp = urllib.request.urlopen(f'{BASE}/api/tracks/stream/{track_id}')
        assert resp.status == 200
        data = resp.read()
        assert len(data) > 1000, f'stream too short: {len(data)}'
        print(f'streamed {len(data)} bytes')

        # delete
        req = urllib.request.Request(f'{BASE}/api/tracks/{track_id}', method='DELETE')
        resp = urllib.request.urlopen(req)
        assert resp.status == 200

        # verify gone
        resp = urllib.request.urlopen(f'{BASE}/api/tracks')
        tracks = json.loads(resp.read())
        assert track_id not in [t['id'] for t in tracks], 'track still in list after delete'
        print(f'deleted and verified gone')

    finally:
        try: os.unlink(wav)
        except: pass
        srv.terminate()

def test_playlist_crud():
    srv = _serve()
    try:
        # create playlist
        req = urllib.request.Request(f'{BASE}/api/playlists',
            data=json.dumps({'name':'Test'}).encode(),
            headers={'Content-Type':'application/json'})
        resp = urllib.request.urlopen(req)
        pl = json.loads(resp.read())
        pl_id = pl['id']
        assert pl['name'] == 'Test'

        # list playlists
        resp = urllib.request.urlopen(f'{BASE}/api/playlists')
        pls = json.loads(resp.read())
        assert pl_id in [p['id'] for p in pls]
        print(f'playlist created: {pl_id}')
    finally:
        srv.terminate()

if __name__ == '__main__':
    test_upload_then_list_then_stream()
    test_playlist_crud()
    print('ALL PASS')
