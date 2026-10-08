# Ubuntu VM build source

Hazır Ubuntu VM-i sıfırdan hazırlayanda VMware Location üçün bu qovluğun
altında `Prepared-Ubuntu-22.04` yarat. VM-i provision et, `baseline.json`-u
VM fayllarının yanına köçür və tam söndür. Sonra layihə kökündən:

```powershell
.\scripts\Prepare-UbuntuVM.ps1 -SourceVmDirectory ".\vm-source\Prepared-Ubuntu-22.04"
```

VM faylları Git-də saxlanılmır. Cari yekun Type B ISO-dan asset-ləri bərpa
etmisənsə, hazır VM artıq `assets/linux/Ubuntu-22.04-VM` daxilindədir;
bu source qovluğunu yenidən yaratmaq lazım deyil. Əsas [README](../README.md)
clone-dan sonrakı hər iki yolu izah edir.
