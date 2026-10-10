# Type B — Windows AI Workstation Offline ISO

**4.1 codebase — 2026-10-10:** Qsync, VMware, WSL və VSIX recovery düzəlişləri
normal build axınına daxil edilib. Beş runtime faylının yeganə mənbəyi runtime/
qovluğudur; builder onları hər ISO-ya məcburi yerləşdirir və hash-lərini qeyd edir.
**4.1 ISO 2026-10-10 tarixində yaradılıb.** Build, asset/security yoxlamaları və
ISO daxilində 84 faylın SHA-256 yoxlaması keçib. Təmiz VM quraşdırması və fiziki
noutbukda USB boot/qəbul testi hələ gözlənilir; bu versiya sınaq namizədidir.
GitHub yalnız kod və metadata saxlayır; böyük asset-lər və ISO daxil deyil.
[ISO yoxlama nəticələri](validation/MEDIA-VALIDATION.md).
[Düzəlişlər, build və qəbul ardıcıllığı](BUILD-NOTES.md).

Bu layihə yalnız **Type B** üçündür: Windows 11 x64, WSL2 üzərində Ubuntu
22.04 LTS, Docker Engine və ayrıca hazır Ubuntu 22.04 LTS VMware VM.

Proqramların installer-ləri, Office mənbələri, VSIX-lər, WSL obrazı və hazır VM
ISO-ya əvvəlcədən daxil edilir. Windows proqramları normal Windows Setup-un
`specialize` mərhələsində lokal mənbədən qurulur; istifadəçi masaüstünə daxil
olandan sonra internetdən EXE yükləyən və proqram quran provisioning yoxdur.
Bu üsul proqramların birbaşa `install.wim` daxilində capture edildiyi image deyil;
proqramlar Windows quraşdırılması zamanı, OOBE-dən əvvəl qurulur.

Windows username, şifrə, LocalAccounts və AutoLogon unattended fayla yazılmır.
OOBE-də hesab seçimi/yaradılması normal Windows axınında qalır. Windows
buraxılışının hesab və internet tələbləri bu layihə tərəfindən dəyişdirilmir.

## GitHub-dan clone etdikdən sonra cari layihəni necə hazırlamaq olar?

Repo: [optim00s/iso-test](https://github.com/optim00s/iso-test).
Git-də scriptlər, konfiqurasiya, təlimatlar və SHA-256 manifestləri saxlanılır.
ISO, EXE/MSI/MSIX, Office data, VSIX, WSL TAR və VMware diskləri `.gitignore`
ilə kənarda qalır. `git clone` bu böyük faylları avtomatik yükləmir.
Hazırda repo daxilində onlar üçün ayrıca public download hosting-i yoxdur.

Windows build kompüterində PowerShell aç:

```powershell
git clone https://github.com/optim00s/iso-test.git
cd iso-test
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\Initialize-ProjectFolders.ps1
```

Son command mövcud faylları silmədən və installer işlətmədən boş asset/build
qovluqlarını yaradır. Tam hazırlıqdan sonra əsas struktur belə olacaq:

```text
iso-test/
  Build-TypeB-ISO.ps1
  README.md
  config/                  apps.json, vsix.json, build.json, assets.lock.json
  scripts/                 acquisition, provisioning, restore və build yoxlamaları
  runtime/                 beş canonical target runtime faylı
  overlay/                 Autounattend.xml və SetupComplete fallback
  tests/                   VMware təlimatı və versiya command-ları
  source/
    Windows11-x64.iso       original Microsoft Windows ISO; ayrıca əldə edilir
  assets/
    windows/               cari EXE/MSI/ZIP/MSIX paketləri
      TerminalDependencies/
      OpenSSH-FoD/         yalnız source Windows-da OpenSSH yoxdursa uyğun FoD
    office/
      setup.exe
      configuration.xml
      SHA256SUMS
      Office/Data/         Word/Excel/PowerPoint/OneNote/Outlook offline mənbələri
    vsix/                  altı extension paketi
    linux/
      ubuntu-22.04.5-desktop-amd64.iso
      TypeB-Ubuntu-22.04-WSL-Docker.tar
      TypeB-Ubuntu-22.04-WSL-Docker.tar.sha256
      TypeB-Ubuntu-22.04-WSL-Docker.tar.baseline.json
      Ubuntu-22.04-VM/      hazırlanmış VMX/VMDK və baseline.json
      baseline/            sıfırdan Linux hazırlamaq üçün; acquisition yaradır
    updates/               varsa təşkilatın təsdiqlədiyi CAB/MSU paketləri
  vm-source/               VM-i sıfırdan qurmaq üçün yerli source qovluğu
  work/                    build zamanı yaranır
  output/                  yeni ISO və manifestlər build zamanı yaranır
```

### Yol A — məhz cari build-in asset-lərini bərpa et

Cari installer-ləri, **eyni Office data-nı**, VSIX-ləri və hazır Ubuntu
WSL/VM-ni olduğu kimi geri gətirmək üçün layihə sahibindən yekun
`TypeB-Windows-AI-Workstation-v4.0.iso` faylını ayrıca transfer/storage vasitəsilə
əldə et. Bu 51.12 GB-lıq fayl GitHub reposunda deyil; avtomatik download linki
hələ verilmir. ISO ZIP kimi paylaşılıbsa, əvvəl ZIP-dən ISO-nu çıxart.

Həmin ISO-nun SHA256-sı:
`3d2c371aecccde68f9beaf3029d76d01da45461155fd1ae1c7b7a126ad95db7d`.
Yalnız asset bərpası üçün ISO saxlandıqdan sonra clone diskində əlavə
təxminən **42 GiB boş yer** tələb olunur. ISO-nu və bərpa fayllarını eyni diskdə
saxlayacaqsansa onların cəmi üçün daha çox yer ayır.

Administrator PowerShell-də layihə kökündən, nümunə yolu öz ISO yoluna dəyiş:

```powershell
.\scripts\Restore-TypeBAssets.ps1 -SourceIso "E:\Transfer\TypeB-Windows-AI-Workstation-v4.0.iso"
.\scripts\Prepare-OfficeOffline.ps1 -VerifyOnly
.\scripts\Test-BuildSecurity.ps1
```

Restore scripti əvvəl yekun ISO hash-ini yoxlayır, ISO-nu read-only mount edir,
sonra **75 locked faylı** `config/assets.lock.json`-dakı ölçü və SHA256-larla
bərpa edir. Windows/Office/VSIX payload-u ISO-nun
`sources/$OEM$/$1/TypeB-Offline/Packages` qovluğundan, hazır Linux asset-ləri
isə `sources/$OEM$/$1/TypeB-Assets/Ubuntu` qovluğundan götürülür.
Fərqli mövcud asset-in üzərinə yazılmır; düzgün mövcud fayllar saxlanılır.
Script heç bir EXE qurmur, distro import etmir və VM-i işə salmır.

Bu yol `assets/windows`, `assets/office/Office/Data`, `assets/vsix` və hazır
`assets/linux/Ubuntu-22.04-VM`/WSL TAR-nı cari build ilə eyni hala gətirir.
Hazır VM-ni yenidən provision etməyə ehtiyac yoxdur. `baseline/`, original
WSL rootfs və `vm-source/Prepared-Ubuntu-22.04` yalnız sıfırdan hazırlama üçün
lazımdır; cari build-in həmin müvəqqəti source-ları arxivə daxil deyil.
`work/iso` və `output/` daxilindəki build/test faylları da Git backup-u deyil.

Yenidən Windows ISO build etmək istəyirsənsə, **original Microsoft ISO-nu**
ayrıca `source/Windows11-x64.iso` kimi yerləşdir. Hazır Type B ISO-nu bu adla
dəyişib source kimi istifadə etmə. Cari source üçün gözlənilən SHA256:
`bd4307df32bc8af33b39ccecb1174aeb345386630f89a2b86c7a4e36b55ea650`.
[Microsoft Windows 11 download](https://www.microsoft.com/en-us/software-download/windows11).
Microsoft-un gələcək download-u başqa hash verərsə, cari source-un eynisi deyil;
yeni təsdiqlənmiş source üçün `-SourceIsoSha256` parametrini ayrıca ver.

### Yol B — asset-ləri vendor mənbələrindən sıfırdan hazırla

Hazır yekun ISO yoxdursa aşağıdakı paketləri build kompüterində əldə et və
göstərilən adlarla saxla. Bütün yükləmələr BUILD mərhələsində edilir.
`config/assets.lock.json` cari faylların hash-lərini saxlayır: yalnız adın eyni
olması faylın eyni olduğu demək deyil. Vendor-un yeni versiyası və yenidən
provision edilmiş Linux obrazı əvvəlki hash-i verməyə bilər. Bu, yeni build
olacaq; paketləri təsdiqlədikdən sonra `Lock-Assets.ps1` ilə yeni lock yarat.

Windows download xəritəsi — bütün yollar `assets/windows/` altındadır:

| Saxlanacaq fayl | Mənbə və düzgün paket seçimi |
|---|---|
| `VSCodeSetup-x64.exe` | [VS Code](https://code.visualstudio.com/download), **System Installer x64**; cari paket 1.141.0. |
| `Git-64-bit.exe` | [Git for Windows releases](https://github.com/git-for-windows/git/releases), x64 installer; cari paket 2.56.0.2, Git LFS onun daxilindədir. |
| `7z-x64.exe` | [7-Zip 26.04 x64](https://github.com/ip7z/7zip/releases/download/26.04/7z2604-x64.exe); `apps.json`-dakı publisher hash pin-i ilə eyni olmalıdır. |
| `winrar-x64.exe` | [RARLAB](https://www.rarlab.com/download.htm), Windows x64; cari faylın ProductVersion-u 7.30.1-dir. |
| `Nextcloud-x64.msi` | [Nextcloud Desktop](https://nextcloud.com/install/), Windows x64 **MSI**. |
| `Qsync-x64.exe` | [QNAP Utilities](https://www.qnap.com/en/utilities/essentials), Qsync Windows x64 EXE; cari paket 6.1.0.0831. MSI seçilərsə `apps.json` method/file/args da uyğun dəyişməlidir. |
| `python-3.13-amd64.exe` | [Python Windows releases](https://www.python.org/downloads/windows/), Python **3.13** Windows installer 64-bit; cari paket 3.13.16. |
| `Anaconda3-Windows-x86_64.exe` | [Anaconda archive](https://repo.anaconda.com/archive/), Windows x86_64 installer; cari paket 2026.07-1. |
| `cmake-x64.msi` | [CMake](https://cmake.org/download/), Windows x86_64 MSI. |
| `uv-x86_64-pc-windows-msvc.zip` | [uv releases](https://github.com/astral-sh/uv/releases), məhz Windows MSVC x86_64 ZIP. |
| `ffmpeg-win64.zip` | [FFmpeg Windows builds](https://www.gyan.dev/ffmpeg/builds/), daxilində `bin/ffmpeg.exe` və `bin/ffprobe.exe` olan x64 ZIP; tək top-level qovluq olmalıdır. |
| `wget.exe` | [wget-on-windows](https://github.com/KnugiHK/wget-on-windows/releases/tag/v1.25.0-20260517), x64 static OpenSSL build; cari fayl 1.25.0-dır. |
| `teamsbootstrapper.exe`, `MSTeams-x64.msix` | [Microsoft Teams bulk deployment](https://learn.microsoft.com/en-us/microsoftteams/teams-client-bulk-install), həm bootstrapper, həm **x64 offline MSIX**. |
| `wsl-x64.msi` | [Microsoft WSL 3.0.1](https://github.com/microsoft/WSL/releases/tag/3.0.1), `wsl.3.0.1.0.x64.msi` faylını bu adla saxla. |
| `Microsoft.WindowsTerminal.msixbundle` | [Microsoft Terminal releases](https://github.com/microsoft/terminal/releases), cari konfiqurasiya **Terminal Preview** identity-si üçün hazırlanıb. Stable seçsən `apps.json` detection identity-sini də dəyiş. |
| `TerminalDependencies/Microsoft.UI.Xaml.2.8.x64.appx` | [Microsoft.UI.Xaml NuGet 2.8.7](https://www.nuget.org/packages/Microsoft.UI.Xaml/2.8.7) içindəki `tools/AppX/x64/Release/Microsoft.UI.Xaml.2.8.appx`-i bu adla saxla. Digər dependency-ləri seçdiyin Terminal manifestinə uyğun əldə et. |
| `VMware-workstation-full.exe` | [VMware Workstation Pro](https://www.vmware.com/products/desktop-hypervisor/workstation-and-fusion), Broadcom download portalı; login tələb oluna bilər. Cari paket 26.0.0. |
| `LM-Studio-Setup.exe` | [LM Studio](https://lmstudio.ai/download), Windows x64 installer; cari paket 0.4.25+1. `/S /allusers` davranışı ayrıca VM testində yoxlanmalıdır. |

İmzalı EXE/MSI-lər üçün nümunə yoxlama:

```powershell
Get-AuthenticodeSignature .\assets\windows\VSCodeSetup-x64.exe
Get-FileHash .\assets\windows\VSCodeSetup-x64.exe -Algorithm SHA256
```

7-Zip-in bu buraxılışı unsigned olduğu üçün onun etibarı ayrıca sabitlənmiş
publisher SHA256 ilə yoxlanılır; bütün paketlər üçün signature tələbini söndürmə.
`OpenSSH-FoD` və `updates` faylları yalnız uyğun source Windows build-i və
təşkilatın təsdiqlədiyi offline paketlər olduqda əlavə edilməlidir.

**Office data-nı yarat:** [Microsoft Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117)
yüklə və ODT EXE-ni `assets/office/setup.exe` kimi saxla. Script self-extracting
paketdirsə real deployment tool-u çıxarır. Git-dəki `configuration.xml`
Microsoft 365 x64, Current channel, `en-us` və offline source path-ni müəyyən edir.

```powershell
.\scripts\Prepare-OfficeOffline.ps1
.\scripts\Prepare-OfficeOffline.ps1 -VerifyOnly
```

Nəticə `assets/office/Office/Data` və Office SHA256 manifestidir. Current channel
yenilənən kanaldır: yenidən download cari **16.0.20430.20146** Office data-sının
eynisi olmaya bilər. Eyni data üçün Yol A-dakı hazır ISO və ya eyni binary backup
lazımdır. Office hesab/lisenziya aktivləşdirməsi payload download-dan ayrıdır.

**VSIX-ləri əldə et:** build kompüterində VS Code → Extensions (`Ctrl+Shift+X`)
aç, ID-ni axtar, nəticəyə sağ klik → **Download Specific Version VSIX**.
Platform seçimi çıxarsa cədvəldəki platformu seç və faylı `assets/vsix/`-ə
göstərilən adla saxla. [VS Code-un rəsmi VSIX download təlimatı](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#can-i-download-an-extension-directly-from-the-marketplace).

| Fayl / extension ID | Cari versiya | Platform |
|---|---|---|
| `ms-python.python.vsix` | 2026.8.0 | win32-x64 |
| `ms-python.vscode-pylance.vsix` | 2026.4.1 | universal |
| `ms-toolsai.jupyter.vsix` | 2025.9.1 | win32-x64 |
| `charliermarsh.ruff.vsix` | 2026.84.0 | win32-x64 |
| `ms-vscode-remote.remote-ssh.vsix` | 0.128.0 | universal |
| `ms-vscode-remote.remote-wsl.vsix` | 0.104.3 | universal |

Bu versiyalar Marketplace-də artıq yoxdursa eyni faylı oradan bərpa etmək mümkün
olmaya bilər; Yol A və ya saxlanmış eyni VSIX backup-u istifadə et. Yalnız build
kompüterində `code --install-extension` işlətmək ISO üçün `.vsix` asset-i yaratmır.

**Ubuntu/WSL və Linux konfiqurasiyasını hazırla:**

```powershell
.\scripts\Acquire-UbuntuAssets.ps1
.\scripts\Acquire-LinuxBaseline.ps1
.\scripts\Build-DockerReady-UbuntuWSL.ps1
```

İlk iki script Canonical Ubuntu 22.04.5 Desktop ISO/22.04 WSL rootfs və
`config/linux-baseline.json`-dakı uv **0.11.19**, Linux Anaconda
**2025.12-1** installer-lərini SHA256 ilə əldə edir. Üçüncünü Administrator
PowerShell-də, host WSL2 işləyən halda çağır. O, Docker-ready WSL TAR, SHA256
və baseline report yaradır. Host hypervisor-u VMware nested testi üçün
söndürmüsənsə, Linux image build-dən əvvəl host WSL2-ni bərpa et və restart et.

Linux konfiqurasiyası Git-də [Provision-TypeB-Ubuntu.sh](scripts/linux/Provision-TypeB-Ubuntu.sh)
və [linux-baseline.json](config/linux-baseline.json) daxilindədir: Ubuntu 22.04,
Docker Engine/Compose, Git/LFS, GCC/G++/make, CMake, uv ilə Python 3.13,
Anaconda, systemd və `/etc/profile.d/typeb-engineering.sh` PATH siyasəti.
APT paketləri və Python patch versiyası build vaxtı dəyişə bildiyi üçün
sıfırdan qurulmuş TAR/VM-in əvvəlki hash-i verməsi gözlənilmir.

**Ayrıca hazır Ubuntu VM yarat:**

1. VMware-də Ubuntu **64-bit**, Location `vm-source/Prepared-Ubuntu-22.04` seç.
2. `assets/linux/ubuntu-22.04.5-desktop-amd64.iso` ilə Ubuntu-nu quraşdır.
3. `assets/linux/baseline` və `scripts/linux/Provision-TypeB-Ubuntu.sh`-ı VM-ə
   köçür. VM terminalında öz real baseline yolunu yaz:

   ```bash
   sudo bash Provision-TypeB-Ubuntu.sh /path/to/baseline 3.13 vm
   ```

4. `Type B Ubuntu baseline: PASS` al. VM-dəki
   `/usr/local/share/typeb/baseline.json`-u Windows-dakı
   `vm-source/Prepared-Ubuntu-22.04/baseline.json` yoluna köçür.
5. VM-i tam söndür; suspend/snapshot vəziyyətində staging etmə. Windows-da:

   ```powershell
   .\scripts\Prepare-UbuntuVM.ps1 -SourceVmDirectory ".\vm-source\Prepared-Ubuntu-22.04"
   ```

Bu addım hazır VM-ni `assets/linux/Ubuntu-22.04-VM`-ə yerləşdirir. WSL TAR
ayrıca hazırlanır; Desktop ISO və təkcə VMware proqramının olması hazır VM deyil.

### Hazırlıqdan sonra build

**Yol A** ilə bərpa edəndə əvvəlki `config/assets.lock.json` saxlanılır;
`Test-BuildSecurity.ps1` həmin 75 faylı yoxlayır. **Yol B** ilə yeni paketlər
hazırlayanda əvvəl çatışmayanları yoxla, sonra təsdiqlənmiş yeni asset-ləri lock et:

```powershell
.\scripts\Test-BuildAssets.ps1 -ReportOnly
# Yalnız yeni paketlər üçün (Yol B):
.\scripts\Lock-Assets.ps1
.\scripts\Test-BuildSecurity.ps1
```

Original Windows ISO `source/Windows11-x64.iso` yolunda olmalı, Windows ADK-nın
**Deployment Tools** komponenti (`oscdimg.exe`) quraşdırılmalı və asset-lər hazır
olduqdan sonra build diskində ən az **100 GB əlavə boş yer** qalmalıdır.
Administrator PowerShell-də:

```powershell
.\Build-TypeB-ISO.ps1 -SourceIso ".\source\Windows11-x64.iso"
```

Çıxış `output/TypeB-Windows-AI-Workstation-v4.0.iso`, onun `.sha256` faylı və
`build-manifest.json` olacaq. Təzə build əvvəlki ISO-nun hash-i ilə eyni olmaq
məcburiyyətində deyil. Qəbul üçün aşağıdakı VMware/Rufus yoxlamalarını apar.

## ISO ilə quraşdırma zamanı istifadəçi nə görəcək?

Aşağıdakı cədvəl **bütün tələb olunan asset-lər hazırlanıb build və qəbul testləri
keçdikdən sonra gözlənilən davranışı** göstərir. Hazırda yekun ISO və Rufus
testinin keçdiyi iddia edilmir.

| Mərhələ / komponent | İstifadəçi nə görəcək? | Avtomatik baş verən iş |
|---|---|---|
| Rufus ilə hazırlanmış USB-dən boot | Adi Windows 11 quraşdırma ekranı | ISO USB-dən başlayır; tətbiq yükləməsi üçün internet istifadə edilmir. |
| Windows Setup | Dil, klaviatura, Windows edition/lisenziya və disk seçiminin adi ekranları | Bu seçimlər əvvəlcədən zorla təyin edilmir. |
| OOBE-dən əvvəl | Quraşdırmanın davam etdiyini göstərən ekran və əlavə restart | Lokal installer-lər qurulur; WSL xüsusiyyətlərini aktivləşdirmək üçün restartı Windows Setup idarə edir. |
| OOBE və Windows hesabı | Adi region və hesab yaratma/seçmə axını | ISO əvvəlcədən username və şifrə yaratmır. |
| İlk Windows girişi | Profil hazırlanarkən əlavə gözləmə ola bilər | Hazır WSL TAR lokal olaraq həmin istifadəçiyə import edilir; hazır VM profilə köçürülür. Yeni proqram və Linux paketləri yüklənmir. |
| Quraşdırma nəticəsi | Public Desktop-da `TypeB-Setup-STATUS.txt`, şəxsi Desktop-da `TypeB-User-STATUS.txt` | Windows proqramları və istifadəçi üçün WSL/VM hazırlığı ayrı yoxlanılır; xəta PASS kimi göstərilmir. |
| Visual Studio Code | Start menyusunda hazır VS Code | System Installer OOBE-dən əvvəl qurulur. |
| VS Code extensionları | Python, Pylance, Jupyter, Ruff, Remote SSH və Remote WSL quraşdırılmış görünür | ISO-dakı bütün `.vsix` faylları Default profile-a yerləşdirilir; yeni profil onları miras alır. Avtomatik extension update yoxlaması söndürülür. |
| Windows Terminal | Hazır Terminal tətbiqi | Hazırda `assets` daxilindəki paket **Terminal Preview**-dur; dependency-ləri offline provision edilməlidir. |
| Git / Git LFS | Windows terminalında `git` və `git lfs` işləyir | Git for Windows və onun daxilindəki Git LFS qurulur; LFS system konfiqurasiyası edilir. |
| OpenSSH / curl | Windows terminalında `ssh` və `curl` işləyir | Mənbə Windows-da olmayan OpenSSH üçün uyğun offline FoD paketləri tələb olunur. |
| 7-Zip / WinRAR | Start menyusunda qurulmuş tətbiqlər | ISO-dakı lokal installer-lər OOBE-dən əvvəl qurulur. |
| Microsoft 365 / Outlook | Word, Excel, PowerPoint, OneNote və Outlook hazır görünür | Tam Office offline mənbəsi istifadə olunur. Tətbiqin qurulması lisenziya aktivləşdirilməsi və hesab login-i ilə eyni deyil. |
| Microsoft Teams | Teams Start menyusunda görünür | Lokal MSIX bütün yeni istifadəçilər üçün provision edilir; istifadəçi Teams hesabına özü daxil olur. |
| LM Studio | Program Files-da və Start menyusunda hazır tətbiq | Installer bütün istifadəçilər üçün qurulmalıdır; bu build-in davranışı test edilir. Model faylları ayrıca asset kimi verilməyibsə, model əvvəlcədən daxil deyil. |
| Nextcloud / QNAP Qsync | Qurulmuş desktop client-lər | Client-lər lokal paketdən qurulur; server/hesab bağlantısı istifadəçi və ya IT tərəfindən edilir. |
| Windows Python / Anaconda / uv | Python 3.13, conda və uv terminaldan açılır | Machine-wide paketlər və PATH konfiqurasiyası hazırlanır. |
| CMake / FFmpeg / wget | Windows terminalında alətlər işləyir | Lokal MSI, ZIP və EXE asset-lərindən qurulur. |
| WSL2 + Ubuntu 22.04 LTS | Start → Type B → Ubuntu 22.04 WSL; `wsl -l -v` siyahısında distro WSL **2** kimi görünür | İstifadəçi profili yaranandan sonra hazır obraz import edilir; ad Windows hesabından həmin vaxt törədilir, əvvəlcədən Windows username yazılmır. |
| Docker Engine | WSL daxilində `docker info` və `docker compose version` işləyir | Docker Ubuntu obrazında əvvəlcədən qurulub; systemd xidməti başlanır. Docker Desktop tələb olunmur. |
| Linux engineering baseline | WSL-də Git, Git LFS, OpenSSH, curl, wget, tmux, FFmpeg/ffprobe, GCC/G++/make, CMake, uv və conda mövcuddur | Linux paketləri yalnız obrazın BUILD mərhələsində qurulur. |
| Python 3.13 — əsas Linux mühiti | `python --version` 3.13 göstərir; `uv python find --python-preference only-managed 3.13` işləyir | Python uv tərəfindən əvvəlcədən idarə olunan runtime kimi qurulur. Ubuntu-nun sistem Python-u saxlanılır. |
| VMware Workstation Pro | Qurulmuş VMware və Start → Type B → Ubuntu 22.04 VM shortcut-u | Hazır VM diski və VMX istifadəçi profilinə köçürülür; ilk girişdə Ubuntu Setup aparılmır. |
| Ubuntu 22.04 LTS Desktop ISO | `C:\TypeB-Assets\Ubuntu\ubuntu-22.04.5-desktop-amd64.iso` | VM üçün original ISO ayrıca saxlanılır; tək ISO hazır VM əvəzi sayılmır. |

İlk girişdə WSL importu və böyük VM diskinin köçürülməsi vaxt aparır. Masaüstünün
hazırlanma vaxtını real hardware-də yoxlamaq lazımdır. WSL-də yaradılan lokal
hesabın əvvəlcədən şifrəsi yoxdur; sudo həmin WSL hesabı üçün NOPASSWD siyasəti
ilə işləyir. Bu siyasət [Linux provisioning skriptində](scripts/linux/Provision-TypeB-Ubuntu.sh)
görünür və təşkilatın tələbinə uyğun nəzərdən keçirilə bilər.

## Build üçün hazırlıq

Administrator PowerShell-də layihə qovluğundan:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Asset-lərin cari vəziyyəti; bütün çatışmayanları birlikdə göstərir.
.\scripts\Test-BuildAssets.ps1 -ReportOnly

# BUILD maşınında internetlə hazırlama:
.\scripts\Prepare-OfficeOffline.ps1
.\scripts\Acquire-UbuntuAssets.ps1
.\scripts\Acquire-LinuxBaseline.ps1
.\scripts\Build-DockerReady-UbuntuWSL.ps1
```

`assets\windows\wsl-x64.msi` və Terminal-ın uyğun dependency Appx/MSIX-lərini
`assets\windows\TerminalDependencies` daxilinə əlavə et. WSL offline quraşdırma
paketi üçün [Microsoft-un offline install sənədi](https://learn.microsoft.com/en-us/windows/wsl/install#offline-install)
istifadə olunur. Windows paketlərinin adları və qurma üsulları [apps.json](config/apps.json)
daxilindədir. LM Studio bu build üçün `/S /allusers` ilə machine-wide qurulmalıdır;
yalnız SYSTEM profilinə qurulma uğurlu qəbul edilmir.

Hazır VM yoxdursa, BUILD mərhələsində Ubuntu 22.04 Desktop ISO ilə VMware-da VM
qur. Hazırlanmış `assets/linux/baseline` qovluğunu və
`scripts/linux/Provision-TypeB-Ubuntu.sh` faylını VM-ə ver, sonra VM-də işlət:

```bash
sudo bash Provision-TypeB-Ubuntu.sh /path/to/baseline 3.13 vm
```

VM-dən `/usr/local/share/typeb/baseline.json` faylını VM-in Windows-da yerləşən
qovluğuna `baseline.json` adı ilə köçür. VM-i tam söndür və staging et:

```powershell
.\scripts\Prepare-UbuntuVM.ps1 -SourceVmDirectory "D:\VMs\Prepared-Ubuntu-22.04"
.\scripts\Lock-Assets.ps1
.\scripts\Test-BuildSecurity.ps1

# Windows ISO yüklənəndən və bütün yoxlamalar keçəndən sonra:
.\Build-TypeB-ISO.ps1 -SourceIso ".\source\Windows11-x64.iso"
```

Çıxış: `output\TypeB-Windows-AI-Workstation-v4.1.iso`, onun `.sha256` faylı və
`build-manifest.json`. Rufus həmin **yekun Type B ISO** ilə hazırlanmalıdır.

## Qəbul yoxlaması

[Başqa kompüterdə VMware setup ardıcıllığı](tests/VMWARE-TEST-STEPS.md) və sadə
versiya scriptləri: [Windows + WSL](tests/Show-TypeB-WindowsVersions.ps1),
[Ubuntu Linux](tests/Show-TypeB-LinuxVersions.sh). Bunlar `python --version`,
`uv --version`, `docker version` kimi command-ları göstərir; paket yükləmir.

[Quraşdırma checklist-i](tests/VMWARE-FIRST-CHECKLIST.md) və
[Windows/WSL yoxlaması](tests/QUICK-VALIDATE-TARGET.ps1) istifadə edilir.
VMware-da ilkin test faydalıdır; Rufus ilə fiziki cihazda USB boot yoxlaması
ayrıca tələb olunur. Hər iki status PASS olmalı, WSL2/Docker və hazır VM
internetdən installer/paket yükləmədən işləməlidir. Virtualizasiya BIOS/UEFI-də
aktiv olmalıdır; VMware içində WSL2 testi üçün nested virtualization lazımdır.

Repo səviyyəsində simulyasiya yoxlamaları:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SHA256Workflows.ps1
```

Bu yoxlamalar real Windows Setup, app installer-ləri, WSL kernel-i və Rufus
boot testinin əvəzi deyil.
