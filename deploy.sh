#!/bin/bash
# Sube archivos a GitHub por la API de Contents. Falla con exit!=0 si algo no subió.
# Usa HTTPS directo: `gh api -X PUT` se rompe con payloads grandes ("unexpected end of JSON input").
# git push tampoco sirve en este repo: GitHub responde "fatal error in commit_refs".
set -o pipefail
cd "$(dirname "$0")"
GH_TOKEN_VALUE="$(gh auth token)" python3 - "$@" <<'PY'
import base64, json, os, sys, time, urllib.request, urllib.error

REPO  = 'marialuisa-melonn/liviana'
TOKEN = os.environ['GH_TOKEN_VALUE']
files = sys.argv[1:] or ['index.html','sw.js','manifest.json','README.md','deploy.sh',
                         'icon-180.png','icon-192.png','icon-512.png']

def api(url, method='GET', body=None):
    req = urllib.request.Request(url, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={'Authorization':'Bearer '+TOKEN, 'Accept':'application/vnd.github+json',
                 'Content-Type':'application/json', 'User-Agent':'liviana-deploy',
                 'X-GitHub-Api-Version':'2022-11-28'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')

fallos = 0
for f in files:
    if not os.path.exists(f):
        print('NO EXISTE  ' + f); fallos += 1; continue
    url = f'https://api.github.com/repos/{REPO}/contents/{f}'
    st, cur = api(url)
    body = {'message': f'Actualizar {f}', 'branch': 'main',
            'content': base64.b64encode(open(f,'rb').read()).decode()}
    if st == 200 and cur.get('sha'):
        body['sha'] = cur['sha']
    # GitHub devuelve 500 de forma intermitente en este repo: reintentar
    for intento in range(1, 6):
        st, res = api(url, 'PUT', body)
        if st in (200, 201):
            print('subido     ' + f + '  ' + (res.get('commit',{}).get('sha','')[:8]))
            break
        if st >= 500 and intento < 5:
            print('  reintento ' + str(intento) + ' (' + f + ' dio HTTP ' + str(st) + ')')
            time.sleep(4 * intento)
            st2, cur2 = api(url)          # el sha pudo cambiar
            if st2 == 200 and cur2.get('sha'): body['sha'] = cur2['sha']
            continue
        print('FALLO      ' + f + '  HTTP ' + str(st) + '  ' + str(res.get('message',''))[:160])
        fallos += 1
        break
sys.exit(1 if fallos else 0)
PY
