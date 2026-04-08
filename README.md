# NitroSense Win10 BYOI

This repo recreates a working Windows 10 NitroSense setup without redistributing Acer's files.

`BYOI` means `bring your own installer`: you supply Acer's official `NitroSense_5.1.385` package locally, and the scripts patch/build everything on your machine.

## What this does

- installs the working Win10 backend stack
- patches the Nitro/monitor extension INF for Win10 binding
- installs only the backend pieces that mattered in testing:
  - core Nitro backend
  - Quick Access
  - Care Center
- leaves Device Info out by default
- builds a portable NitroSense frontend from the official UWP/AppX package
- removes the Store startup dependency with local shims
- neutralizes the packaged Store-version path and removes the Live Update widget from the user config
- keeps the generated frontend on a clean renderer baseline to avoid the orange-screen regression

## What this does not ship

This repo intentionally does **not** include:

- Acer installers
- Acer AppX packages
- extracted Acer app files
- patched Acer binaries
- rebuilt Acer packages

Keep generated outputs out of Git.

This project is an unofficial compatibility workflow. It is not affiliated with or endorsed by Acer.

## Prereqs

- Windows 10 x64
- the original Acer NitroSense zip
- PowerShell 5+
- `tar.exe` available in `PATH`

## End-user flow

1. Put exactly one original Acer NitroSense zip into [input](C:/Users/noah/Desktop/nitrosense-win10-byoi/input).
2. Double-click [patch.bat](C:/Users/noah/Desktop/nitrosense-win10-byoi/patch.bat).
3. Wait for patching to finish.
4. Open [output](C:/Users/noah/Desktop/nitrosense-win10-byoi/output).

The patcher builds:

- `output\NitroSense_portable`
- `output\Backend`
- `output\tools`

## After patching

If you want to install the backend on a Windows 10 machine:

1. Reboot once with `Disable driver signature enforcement`.
2. Open an elevated PowerShell in `output\tools`.
3. Run:

```powershell
.\Install-Backend.ps1 -PackageRoot ..\Backend
```

Then optionally run:

```powershell
.\Register-NitroLauncher.ps1 -PortableRoot ..\NitroSense_portable
.\Create-DesktopShortcut.ps1 -PortableRoot ..\NitroSense_portable
.\Tidy-NitroConfig.ps1
```

Or use the repo-level installer after patching:

1. Double-click [install.bat](C:/Users/noah/Desktop/nitrosense-win10-byoi/install.bat).
2. Let it copy NitroSense into `C:\Program Files\NitroSense`.
3. It will install the backend, register the launcher task, create the desktop shortcut, and apply the Nitro-key launcher wrapper.

## Notes

- The backend install patches unsigned INF files on purpose. Windows 10 will reject those unless you install during a signature-enforcement-disabled boot.
- The portable build uses an unpacked `resources\app` folder instead of a repacked `app.asar`.
- Device Info was tested as optional and is omitted by default.
- Quick Access and Care Center stay in because they were needed for mode and battery features.
- The patcher/install flow neutralizes NitroSense's packaged Store-version path and removes the Live Update widget. I did not find a separate Acer NitroSense updater service/task that also needed disabling on the test machine.

## Output

The one-click patcher writes its results to:

`.\output`
