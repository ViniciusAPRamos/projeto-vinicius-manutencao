// TechPulse.exe: abre a interface (src\Otimizador-Vinicius-GUI.ps1) sem console.
// O manifesto pede administrador já no clique; os argumentos são repassados ao script
// (ex.: TechPulse.exe -Perfil gamer). Compilado pelo tools\build.ps1 com o csc do .NET Framework.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("TechPulse")]
[assembly: System.Reflection.AssemblyProduct("TechPulse")]
[assembly: System.Reflection.AssemblyCompany("Vinícius")]

static class Programa
{
    [STAThread]
    static int Main(string[] args)
    {
        string pasta = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(pasta, "src", "Otimizador-Vinicius-GUI.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Arquivo não encontrado:\n" + script + "\n\nReinstale o TechPulse.", "TechPulse", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        string extras = string.Join(" ", args.Select(a => a.Contains(" ") ? "\"" + a + "\"" : a));
        var info = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" " + extras,
            UseShellExecute = false,
            CreateNoWindow = args.Length == 0,
            WorkingDirectory = pasta
        };
        try { Process.Start(info); return 0; }
        catch (Exception e)
        {
            MessageBox.Show("Não foi possível abrir o TechPulse:\n" + e.Message, "TechPulse", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
