using System;
using System.Diagnostics;
using System.IO;

internal static class Program
{
    private static int Main()
    {
        try
        {
            var baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
            var logPath = GetLogPath();
            var target = ResolveTarget(baseDirectory);

            if (string.IsNullOrWhiteSpace(target) || !File.Exists(target))
            {
                Log(logPath, "Target not found.");
                return 2;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = target,
                Arguments = "xsense:gotoPage=MainPage",
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(target) ?? baseDirectory
            };

            Process.Start(startInfo);
            Log(logPath, "Launched " + target);
            return 0;
        }
        catch (Exception ex)
        {
            try
            {
                Log(GetLogPath(), ex.ToString());
            }
            catch
            {
            }

            return 1;
        }
    }

    private static string ResolveTarget(string baseDirectory)
    {
        var configuredPath = Path.Combine(baseDirectory, "LauncherTarget.txt");
        if (File.Exists(configuredPath))
        {
            var target = File.ReadAllText(configuredPath).Trim();
            if (!string.IsNullOrWhiteSpace(target))
            {
                return target;
            }
        }

        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        var desktopPortable = Path.Combine(desktop, "NitroSense_portable_test", "NitroSense.exe");
        if (File.Exists(desktopPortable))
        {
            return desktopPortable;
        }

        var installedPortable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "NitroSense", "NitroSense.exe");
        if (File.Exists(installedPortable))
        {
            return installedPortable;
        }

        return string.Empty;
    }

    private static string GetLogPath()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "NitroSenseLauncherWrapper");
        Directory.CreateDirectory(root);
        return Path.Combine(root, "launcher-wrapper.log");
    }

    private static void Log(string logPath, string message)
    {
        File.AppendAllText(
            logPath,
            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message + Environment.NewLine);
    }
}
