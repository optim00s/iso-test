# Type B ISO — başqa kompüterdə VMware testi

Bu addımlar yekun Windows ISO-nun quraşdırılmasını yoxlamaq üçündür. Scriptlər
`python --version`, `uv --version`, `docker version` kimi mövcud alətləri çağırır;
paket və ya installer yükləmir. Real Windows/WSL/VM nəticəsi testdən sonra məlum olacaq.

## 1. Faylları test kompüterinə köçür

- `output/TypeB-Windows-AI-Workstation-v4.0.iso`
- `output/TypeB-Windows-AI-Workstation-v4.0.iso.sha256`
- `tests/Show-TypeB-WindowsVersions.ps1`
- `tests/Show-TypeB-LinuxVersions.sh`

İki versiya scripti və bu təlimat birlikdə `output/TypeB-Version-Checks.zip`
arxivində də verilir. Arxivi test Windows VM-inin Desktop-undakı
`TypeB-Checks` qovluğuna açmaq kifayətdir.

Yekun Windows ISO 51.12 GB-dır (47.61 GiB). Ubuntu Desktop ISO-nu seçmə.
Köçürdükdən sonra PowerShell-də hash-i yoxla; yol nümunəsini öz yoluna dəyiş:

```powershell
Get-FileHash "E:\TypeB\TypeB-Windows-AI-Workstation-v4.0.iso" -Algorithm SHA256
```

Gözlənilən SHA256:
`3d2c371aecccde68f9beaf3029d76d01da45461155fd1ae1c7b7a126ad95db7d`.

## 2. Yeni Windows VM yarat

1. VMware Workstation Pro → **File → New Virtual Machine**.
2. **Typical (Recommended)** → **I will install the operating system later**.
   Bu seçim VMware Easy Install-un hesab/OOBE ayarlarını dəyişməsinin qarşısını alır.
3. Guest operating system: **Microsoft Windows**; Version: **Windows 11 x64**.
4. Name: `TypeB-Windows11-Test`; Location: kifayət qədər boş yeri olan diskdə yeni qovluq.
5. Virtual disk üçün **200 GB** seç. Disk böyüdükcə yer tutmalıdır;
   **Allocate all disk space now** seçmə. Test kompüterində ISO-dan əlavə
   təxminən **150 GB boş yer** planlaşdır; faktiki istifadə quraşdırmaya görə dəyişəcək.
6. **Customize Hardware**: RAM **8 GB** (hazır Ubuntu VM-ni də açmaq üçün
   **12–16 GB** daha rahatdır; host RAM-a uyğun seç), CPU **1 processor / 4 cores**.
7. **Processors → Virtualize Intel VT-x/EPT or AMD-V/RVI** seç.
8. **Options → Advanced → Firmware type: UEFI**, **Secure Boot** aktiv olsun.
   Windows 11 üçün **TPM** əlavə et; VMware tələb edərsə VM encryption-u
   aktivləşdir və şifrəsini saxla. TPM artıq varsa təkrar əlavə etmə.
9. **CD/DVD → Use ISO image file**: yekun `TypeB-Windows-AI-Workstation-v4.0.iso`.
   **Connect at power on** aktiv olsun.
10. **Network Adapter → NAT**, ilkin offline yoxlama üçün **Connected** və
    **Connect at power on** seçimlərini söndür. Sonra **Finish → Power on**.

Windows 11 üçün UEFI/Secure Boot/vTPM ayarları
[Broadcom-un Windows 11 quraşdırma sənədinə](https://knowledge.broadcom.com/external/article/315650)
uyğundur. BIOS/UEFI-də fiziki kompüterin Intel VT-x / AMD SVM ayarı da aktiv olmalıdır.

**WSL2 üçün host şərti:** VMware test kompüterinin özündə Hyper-V/VBS aktivdirsə,
nested virtualization işləməyə bilər. Broadcom bu halda host Hyper-V ilə VM daxilində
WSL2-nin birlikdə işləmədiyini bildirir. VM açılarkən `Virtualized Intel VT-x/EPT is
not supported` çıxarsa, davam edib WSL2-ni uğurlu sayma; uyğun host virtualizasiya
konfiqurasiyası və ya fiziki test lazımdır.
[Broadcom nested virtualization məhdudiyyətləri](https://knowledge.broadcom.com/external/article?articleNumber=313547).

## 3. Windows quraşdırmasını tamamla

1. CD-dən boot üçün istənərsə bir düymə bas.
2. Windows Setup dil/klaviatura və edition seçimlərini et. ISO-nu öz lisenziyana
   uyğun edition ilə yoxla; product key istənərsə uyğun seçim et.
3. Quraşdırma növü soruşularsa **Custom: Install Windows only** seç.
4. Yalnız yeni VM-in boş virtual diskini seç → **Next**.
5. Faylların köçürülməsi və lokal proqramların qurulması bitsin. Avtomatik restart
   zamanı yenidən CD boot düyməsini basma. Böyük payload səbəbindən müddət dəyişir.
6. OOBE-də region/klaviatura və öz test istifadəçi hesabını tamamla.
   Windows edition-u hesab üçün internet tələb edərsə NAT bağlantısını həmin
   mərhələdə aç; sonra offline yoxlamadan əvvəl yenidən söndür.
7. İlk masaüstündə WSL importu və hazır VM-in köçürülməsini gözlə.
   `TypeB-Setup-STATUS.txt` və `TypeB-User-STATUS.txt` fayllarının hər ikisində
   **PASSED** olmalıdır. İkincisi tamamlanmadan WSL yoxlamasını başlatma.
8. Xəta varsa machine logları: `C:\ProgramData\TypeB\Logs`;
   user logu: `%LOCALAPPDATA%\TypeB\first-logon.log`.

## 4. Sadə versiya command-larını işlət

VM-dəki Windows istifadəçisinin Desktop-unda `TypeB-Checks` qovluğu yarat və
iki `Show-TypeB-*` scriptini ora köçür. USB/network transfer və ya VMware Shared
Folder istifadə edə bilərsən; paylaşım üçün lazım olsa VMware Tools-u quraşdır.
Scriptlər yekun ISO ayrıca yenidən build olunmadan işləyir.

**VM daxilindəki Windows PowerShell-də**, eyni istifadəçi ilə:

```powershell
Set-Location "$env:USERPROFILE\Desktop\TypeB-Checks"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-TypeB-WindowsVersions.ps1 -IncludeWsl
```

Yalnız Windows command-ları üçün `-IncludeWsl` parametrini çıxart.
Linux scripti PowerShell scriptinin yanında saxlanmalıdır.

Əl ilə Windows-da minimum command-lar:

```powershell
python --version
uv --version
conda --version
git --version
git lfs version
code --version
code --list-extensions --show-versions
wsl --version
wsl -l -v
wsl -d TypeB-Ubuntu-22.04
```

Son command Ubuntu WSL terminalını açır. **Həmin Linux terminalında**:

```bash
cat /etc/os-release
python --version
uv --version
uv python find --python-preference only-managed 3.13
conda --version
git --version
git lfs version
ssh -V
curl --version
wget --version
tmux -V
ffmpeg -version
ffprobe -version
gcc --version
g++ --version
make --version
cmake --version
docker version
docker compose version
```

Ubuntu **22.04**, əsas `python` **3.13**, `wsl -l -v`-də
`TypeB-Ubuntu-22.04` üçün **VERSION 2** gözlənilir. `docker version` həm
**Client**, həm də **Server** göstərməlidir; tək CLI versiyası daemon-un
işlədiyini təsdiqləmir. Offline yoxlamada `docker run hello-world` işlətmə:
image əvvəlcədən yoxdursa internetdən pull tələb edir.

VS Code siyahısında bu altı extension olmalıdır:

```text
charliermarsh.ruff
ms-python.python
ms-python.vscode-pylance
ms-toolsai.jupyter
ms-vscode-remote.remote-ssh
ms-vscode-remote.remote-wsl
```

## 5. Hazır Ubuntu VM və GUI proqramlarını aç

Windows VM daxilində **Start → Type B → Ubuntu 22.04 VM** aç. İlk açılışda
VMware soruşarsa **I copied it** seç. Ubuntu quraşdırma wizard-ı əvəzinə
hazır Ubuntu açılmalıdır. Ubuntu terminalında yuxarıdakı Linux command-larını
işlət; Docker socket üçün icazə xətası varsa `sudo docker version` işlət.
Linux scriptini Ubuntu-ya köçürmüsənsə:

```bash
sudo bash /path/to/Show-TypeB-LinuxVersions.sh
```

Windows test VM-i daxilində ayrıca Ubuntu VM açmaq əlavə nested virtualization
tələb edir və host imkanlarından asılıdır. Belə açılış uğursuz olsa, hazır
Ubuntu VM-in fiziki Windows cihazında yoxlanması da tələb olunur.

Windows-da ayrıca VS Code, Terminal, 7-Zip, WinRAR, Word, Excel, PowerPoint,
OneNote, Outlook, Teams, LM Studio, Nextcloud, Qsync və VMware-i aç.
Office aktivləşdirməsi, Teams/cloud hesabları və LM Studio modelləri ayrıca
istifadəçi ayarlarıdır. Versiya scriptləri GUI tətbiqlərinin hamısını yoxlamır.

Sonda çıxış edib yenidən daxil ol: import/copy/setup təkrarlanmamalıdır.
VMware testi Rufus ilə fiziki USB boot yoxlamasını əvəz etmir.
