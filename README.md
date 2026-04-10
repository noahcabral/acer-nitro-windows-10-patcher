# NitroSense Win10 BYOI

This repo recreates a working Windows 10 NitroSense setup without redistributing Acer's files.

`BYOI` means `bring your own installer`: you supply Acer's official `NitroSense_5.1.385` package locally, and the scripts patch/build everything on your machine.

## Community

Discord: [https://discord.gg/v7nG4SgNYr](https://discord.gg/v7nG4SgNYr)

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
- includes a built-in custom fan curve UI in `Scenario > Fan Control > Custom`
- installs a background fan controller automatically so custom curves keep working after NitroSense is closed

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

1. Put exactly one original Acer NitroSense zip or one extracted NitroSense folder into [input](C:/Users/noah/Desktop/nitrosense-win10-byoi/input).
2. Double-click [patch.bat](C:/Users/noah/Desktop/nitrosense-win10-byoi/patch.bat).
3. Wait for patching to finish.
4. Open [output](C:/Users/noah/Desktop/nitrosense-win10-byoi/output).

The patcher builds:

- `output\NitroSense_portable`
- `output\Backend`
- `output\tools`

## After patching

If you want the simplest normal-user setup after patching:

1. Double-click [install.bat](C:/Users/noah/Desktop/nitrosense-win10-byoi/install.bat).
2. Let it copy NitroSense into `C:\Program Files\NitroSense`.
3. It will install the backend, register the launcher task, create the desktop shortcut, apply the Nitro-key launcher wrapper, and install the background fan controller.

If you only want to install the backend manually on a Windows 10 machine:

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

## Optional background fan controller

The main installer now installs the background fan controller automatically.

If you ever need to reinstall it manually:

```powershell
.\output\tools\Install-BackgroundFanController.ps1 -InstallRoot "$env:ProgramFiles\NitroSense"
```

This installs a hidden autostarting controller that:

- reads temperatures directly from Acer System Monitor Service on `127.0.0.1:46753`
- sends `FAN_CONTROL` updates directly to Acer Agent Service on `127.0.0.1:46933`
- keeps working after NitroSense is closed
- follows the NitroSense scenario config and built-in custom fan curve editor

Config:

`C:\ProgramData\NitroSense\FanController\config.json`

Log:

`C:\ProgramData\NitroSense\FanController\controller.log`

Current tradeoff:

- while it is running, it owns custom fan mode and will take fan control back on the next polling cycle if NitroSense changes it

## Custom fan curves

The patched NitroSense UI adds a custom curve editor to:

`Scenario > Fan Control > Custom`

That editor:

- exposes separate CPU and GPU curves
- supports linking both fans with `Sync`
- writes to `C:\ProgramData\NitroSense\FanController\config.json`
- is backed by the installed background controller, so the curve keeps applying after the UI closes

## Notes

- The backend install patches unsigned INF files on purpose. Windows 10 will reject those unless you install during a signature-enforcement-disabled boot.
- The portable build uses an unpacked `resources\app` folder instead of a repacked `app.asar`.
- Device Info was tested as optional and is omitted by default.
- Quick Access and Care Center stay in because they were needed for mode and battery features.
- The patcher/install flow neutralizes NitroSense's packaged Store-version path and removes the Live Update widget. I did not find a separate Acer NitroSense updater service/task that also needed disabling on the test machine.

## Output

The one-click patcher writes its results to:

`.\output`
