"""Harmless native-process fixtures; never install any software."""
import json,os,subprocess,sys,time
from pathlib import Path
mode= sys.argv[1]
folder=Path(sys.argv[2])
with (folder/'attempts.txt').open('a') as f: f.write('attempt\n')
(folder/'parent.json').write_text(json.dumps({'parent':os.getpid()}))
if mode in ('child','failed-child'):
    child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(12)'],creationflags=subprocess.CREATE_NO_WINDOW)
    (folder/'child.json').write_text(json.dumps({'parent':os.getpid(),'child':child.pid}))
    sys.exit(7 if mode=='failed-child' else 0)
if mode=='hang': time.sleep(60)
if mode=='fail': sys.exit(7)
if mode=='retry':
    sys.exit(7 if len((folder/'attempts.txt').read_text().splitlines())==1 else 0)
if mode=='reboot': sys.exit(3010)
sys.exit(0)
