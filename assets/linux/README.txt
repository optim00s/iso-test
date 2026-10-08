Use README.md for the complete Type B build flow.
Acquire-UbuntuAssets.ps1 prepares the Desktop ISO and WSL source.
Acquire-LinuxBaseline.ps1 prepares uv and Anaconda build inputs.
Build-DockerReady-UbuntuWSL.ps1 prepares and verifies the full engineering image.
Prepare-UbuntuVM.ps1 stages a shut-down, already provisioned Ubuntu 22.04 VM.
A Desktop ISO alone does not satisfy the prepared-VM requirement.
