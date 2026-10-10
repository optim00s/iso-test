# Type B 4.1 — avtomatik quraşdırma

optim00s/iso-test reposunun c19f03f5d71df3b0b5b0d72969ccac135e898b18 commit-i əsasında hazırlanıb. GitHub origin: https://github.com/optim00s/iso-test. Məqsəd recovery CD-ləri olmadan avtomatik quraşdırılan yeni ISO yaratmaqdır. Mövcud Windows VM-in capture edilməsi bu yolun tələbi deyil.

## Birləşdirilən düzəlişlər

| Əvvəl istifadə olunan paket | Yeni ISO-da davranış |
| --- | --- |
| TypeB-Qsync-Recovery.iso | Installerin öz prosesi gözlənilir; davamlı child tətbiqi/service quraşdırmanı bloklamır. Registry, binary və service yolu təsdiqlənir. 600 saniyə limit, uyğun halda bir retry var. |
| TypeB-Recovery-v2.iso | VMware hər iki Program Files qovluğunda məhsul adı ilə aşkarlanır. Hazır Ubuntu VM qısayolu həmin executable-a yönəlir. |
| TypeB-WSL-Recovery.iso | Importdan əvvəl SID, TAR hash-i, boş hədəf, boot və cəhd qeydi saxlanır. Restartdan sonra yalnız installerə məxsus yarımçıq import bir dəfə, VHDX/registry backup-dan sonra bərpa edilir. Başqa distributiv sıfırlanmır. |
| TypeB-VSCode-Repair.iso | Altı yerli VSIX native VS Code CLI ilə real profilə quraşdırılır; ID@versiyalar yoxlanır. Xam extension qovluğunun kopyalanması uğur sayılmır. Optional pack download-u söndürülüb. |

Uzun hazırlıq sinxron Active Setup-dan çıxarılıb. HKLM Run launcher-i real istifadəçinin girişində fon hazırlığını başladır; profil üçün mutex və atomik completion JSON-u var. Bir girişdə ən çox üç cəhd edilir. Restart lazım olduqda növbəti girişdə davam edir. SYSTEM/Audit Administrator üçün profil hazırlığı başlamır.

Windows tətbiqləri specialize mərhələsində lokal payload-dan qurulur. Ubuntu WSL 2, Docker və Linux tool yoxlamaları, altı VSIX və hazır Ubuntu VM-in kopyalanması ilk real profil üçün avtomatik tamamlanır. Yarımçıq installer-owned VM copy davam etdirilir və hash-lə yoxlanır.

Bütün profil yoxlamaları keçmədən TYPE B USER SETUP: PASSED yazılmır. Maşın tətbiqlərinin PASSED nəticəsi təkbaşına WSL/VM/extension hazırlığını təsdiqləmir. App hesabına giriş hazırlığın şərti deyil; lisenziya/aktivasiya ayrıca qalır. OOBE normal yeni Windows istifadəçisi yaradır; ISO-da miki, sabit parol və AutoLogon yoxdur.

## İndi hazır olan

Codebase, runtime, məcburi build inteqrasiyası, kod testləri və təlimatlar hazırdır. Yerli build üçün flashkartdakı 4.0 ISO-dan 75 locked asset bərpa edilib və ayrıca təmiz Microsoft Windows ISO-su yoxlanıb. Yeni TypeB-Windows-AI-Workstation-v4.1.iso yaradılıb; 84 daxili faylın hash yoxlaması keçib. GitHub-a böyük ISO/EXE/MSI/Office Data/VSIX/WSL TAR/VMDK faylları daxil edilmir. Təmiz quraşdırma və fiziki USB boot testi gözlənilir: validation/MEDIA-VALIDATION.md.

Asset-free kod yoxlamaları üçün build kompüterində Python və ADK Deployment Tools lazımdır:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-CodeChecks.ps1 -PythonExe C:\Path\python.exe

Testlər WSL/download/ODT əməliyyatlarını mock edir, kiçik fixture və harmless proseslər yaradır. Oscdimg testi dummy boot images ilə yolların dırnaqlanmasını yoxlaya bilər; bu, həqiqi firmware boot sübutu deyil. Optional native VSIX testi:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-VSCodeProvisioning.ps1 -VsixPath .\assets\vsix\charliermarsh.ruff.vsix -Native

## Clone etdikdən sonra asset-lərin bərpası

Əvvəlki Type B 4.0 ISO flashkartdadırsa, locked asset-ləri oradan bərpa etmək olar. Yollar nümunədir:

    .\scripts\Initialize-ProjectFolders.ps1
    .\scripts\Restore-TypeBAssets.ps1 -SourceIso "E:\TypeB-Windows-AI-Workstation-v4.0.iso"
    .\scripts\Test-BuildAssets.ps1
    .\scripts\Lock-Assets.ps1
    .\scripts\Test-BuildSecurity.ps1

Restore gözlənilən köhnə ISO hash-ini və hər asset-i yoxlayır; fərqli yerli faylı əvəz etmir. README.md eyni Office Data, installer-lər, altı VSIX, WSL TAR və hazır Ubuntu VM strukturunu təsvir edir. İşlək Windows VM-i silməzdən əvvəl flashkartdakı ISO-nun bu lazımi asset-ləri həqiqətən saxladığını yoxlamaq lazımdır; codebase onların ehtiyat nüsxəsi deyil.

Build üçün ayrıca **təmiz Microsoft Windows x64 mənbə ISO-su** lazımdır. config/build.json əvvəlki stock ISO-nun hash-ini pin edir; başqa təsdiqlənmiş mənbə üçün etibarlı -SourceIsoSha256 verilir. Köhnə Type B ISO-sunu builder-ə SourceIso kimi vermə.

Əvvəl yazmadan plan:

    .\scripts\Get-TypeBBuildPlan.ps1 -SourceIso ".\source\Windows11-x64.iso"

Sonra Administrator PowerShell-də:

    .\Build-TypeB-ISO.ps1 -SourceIso ".\source\Windows11-x64.iso"

Stage/output başqa diskdə də saxlanıla bilər:

    .\Build-TypeB-ISO.ps1 -SourceIso "D:\Windows11-x64.iso" -WorkRoot "D:\TypeB-work" -OutputIso "D:\TypeB-Windows-AI-Workstation-v4.1.iso"

Builder asset mövcudluğunu, hash-ləri və stage + output üçün boş sahəni yoxlayır. Hər build unikal iş qovluğu yaradır; köhnə work/ISO silinmir, mövcud output əvəz edilmir. Beş runtime faylı/hash manifesti məcburi ISO-ya yerləşdirilir. BIOS/UEFI boot faylları stock mənbədən saxlanır; əvvəlki oscdimg dırnaq xətası düzəldilib.

## IT handoff üçün qəbul

1. Yeni 4.1 ISO ilə boş Windows VM qur; recovery CD-lərini qoşma.
2. OOBE-ni tamamla, yeni real profilə daxil ol; app hesablarına giriş etmə.
3. Lazım olan Windows restartlarını et və eyni profilə qayıt. Hazırlıq özü davam etməlidir; Desktop TypeB-User-STATUS.txt mərhələni göstərir.
4. 19 komponentin maşın hesabatı və profil hazırlığı PASSED olmalıdır.
5. Altı extensionı və Python/Jupyter istifadəsini yoxla. WSL VERSION 2, Ubuntu 22.04, python/uv/conda və Docker **serveri** cavab verməlidir.
6. Start → Type B → Ubuntu 22.04 VM ilə hazır VM-i aç, boot və Linux tools/Docker yoxlamalarını et. VM fayllarının hash yoxlaması boot testi deyil.
7. Rufus ilə yekun ISO-nu uyğun həcmli USB-yə yazıb fiziki noutbukda quraşdırmanı təkrarla. UEFI/TPM/Secure Boot tələblərini və virtualizasiyanı yoxla; VMware-də WSL 2 üçün nested virtualization lazımdır.

Qəbul testi bitənədək build-manifest.json acceptanceStatus=PENDING_CLEAN_INSTALL saxlayır. Kod testləri real installer, hardware və firmware testinin əvəzi deyil.
