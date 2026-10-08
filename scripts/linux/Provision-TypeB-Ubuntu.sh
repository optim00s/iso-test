#!/usr/bin/env bash
# Build-machine / prepared-VM provisioning only. Never run on the deployed host.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ $# == 3 ]] || { echo 'Usage: script <baseline-assets-dir> <python-version> <wsl|vm>' >&2; exit 2; }
assets="$1"
python_version="$2"
mode="$3"
[[ "$mode" == wsl || "$mode" == vm ]] || exit 2
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 && $(uname -m) == x86_64 ]] || { echo 'Ubuntu 22.04 x64 is required.' >&2; exit 1; }
# Accept existing Windows CRLF manifests as well as newly generated LF manifests.
(cd "$assets" && sed 's/\r$//' SHA256SUMS | sha256sum --check -)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg wget tmux ffmpeg build-essential cmake git git-lfs openssh-client python3
git lfs install --system
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
arch=$(dpkg --print-architecture)
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: jammy
Components: stable
Architectures: $arch
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker.service containerd.service
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$assets/uv-x86_64-unknown-linux-gnu.tar.gz" -C "$tmp"
install -m 0755 "$tmp/uv-x86_64-unknown-linux-gnu/uv" /usr/local/bin/uv
install -m 0755 "$tmp/uv-x86_64-unknown-linux-gnu/uvx" /usr/local/bin/uvx
export UV_PYTHON_INSTALL_DIR=/opt/typeb/uv/python
export UV_PYTHON_BIN_DIR=/opt/typeb/bin
export UV_PYTHON_PREFERENCE=only-managed
mkdir -p "$UV_PYTHON_BIN_DIR"
uv python install "$python_version" --default
chmod -R a+rX /opt/typeb
installers=("$assets"/Anaconda3-*-Linux-x86_64.sh)
[[ ${#installers[@]} == 1 && -f "${installers[0]}" ]] || { echo 'Expected one Anaconda installer.' >&2; exit 1; }
[[ ! -e /opt/anaconda3 ]] || { echo '/opt/anaconda3 already exists; build from a clean source.' >&2; exit 1; }
bash "${installers[0]}" -b -p /opt/anaconda3
chmod -R a+rX /opt/anaconda3
# Keep the uv Python ahead of conda; conda is available without auto-activating base.
cat >/etc/profile.d/typeb-engineering.sh <<'EOF'
export UV_PYTHON_INSTALL_DIR=/opt/typeb/uv/python
export UV_PYTHON_BIN_DIR=/opt/typeb/bin
export UV_PYTHON_PREFERENCE=only-managed
export UV_PYTHON_DOWNLOADS=never
export PATH="/opt/typeb/bin:/opt/anaconda3/condabin:/usr/local/bin:$PATH"
EOF
# Ubuntu interactive non-login shells do not source /etc/profile.d.
echo '. /etc/profile.d/typeb-engineering.sh' >>/etc/bash.bashrc
if [[ "$mode" == wsl ]]; then
  printf '[boot]\nsystemd=true\n' >/etc/wsl.conf
  cat >/usr/local/sbin/typeb-initialize-user <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 && $# == 1 && "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || exit 2
u="$1"
id "$u" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$u"
usermod -aG sudo,docker "$u"
# WSL users already have root access via wsl -u root; no preset passwords.
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$u" >/etc/sudoers.d/typeb-user
chmod 0440 /etc/sudoers.d/typeb-user
visudo -cf /etc/sudoers.d/typeb-user
printf '[boot]\nsystemd=true\n[user]\ndefault=%s\n' "$u" >/etc/wsl.conf
EOF
  chmod 0755 /usr/local/sbin/typeb-initialize-user
fi
. /etc/profile.d/typeb-engineering.sh
for command in git git-lfs ssh curl wget tmux ffmpeg ffprobe gcc g++ make cmake uv conda python docker; do command -v "$command" >/dev/null; done
python -c 'import sys; assert sys.version_info[:2] == (3,13)'
uv python find --python-preference only-managed 3.13 >/dev/null
docker compose version
install -d /usr/local/share/typeb
python3 - "$mode" <<'PY'
import json,subprocess,sys,datetime
def version(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
report={'schemaVersion':1,'ubuntuVersion':'22.04','architecture':'x86_64','mode':sys.argv[1],
        'checkedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'python':version('python','--version'),'uv':version('uv','--version'),
        'conda':version('conda','--version'),'docker':version('docker','--version'),
        'compose':version('docker','compose','version'),
        'checks':{c:True for c in ['git','git-lfs','ssh','curl','wget','tmux','ffmpeg','ffprobe','gcc','g++','make','cmake','uv','conda','python3.13','docker','compose']}}
with open('/usr/local/share/typeb/baseline.json','w') as f: json.dump(report,f,indent=2)
PY
apt-get clean
rm -rf /var/lib/apt/lists/*
echo 'Type B Ubuntu baseline: PASS'
