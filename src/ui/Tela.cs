// Leitura e ajuste da taxa de atualização (Hz) dos monitores - API Win32 (user32)
// EnumDisplayDevices / EnumDisplaySettings / ChangeDisplaySettingsEx
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Otz
{
    public class Monitor
    {
        public string Dispositivo;   // \\.\DISPLAY1
        public string Nome;          // nome do adaptador
        public bool Principal;
        public int Largura;
        public int Altura;
        public int Hz;
        public int HzMaximo;         // maior Hz na MESMA resolução e cor
    }

    public static class Tela
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        const int ENUM_CURRENT_SETTINGS = -1;
        const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
        const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x4;
        const int DM_DISPLAYFREQUENCY = 0x400000;
        const uint CDS_UPDATEREGISTRY = 0x1;
        const uint CDS_TEST = 0x2;

        static DEVMODE NovoModo()
        {
            DEVMODE m = new DEVMODE();
            m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            return m;
        }

        public static Monitor[] Listar()
        {
            List<Monitor> lista = new List<Monitor>();
            DISPLAY_DEVICE d = new DISPLAY_DEVICE();
            d.cb = Marshal.SizeOf(d);
            for (uint i = 0; EnumDisplayDevices(null, i, ref d, 0); i++)
            {
                if ((d.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0)
                {
                    DEVMODE atual = NovoModo();
                    if (EnumDisplaySettings(d.DeviceName, ENUM_CURRENT_SETTINGS, ref atual))
                    {
                        Monitor m = new Monitor();
                        m.Dispositivo = d.DeviceName;
                        m.Nome = d.DeviceString;
                        m.Principal = (d.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
                        m.Largura = atual.dmPelsWidth;
                        m.Altura = atual.dmPelsHeight;
                        m.Hz = atual.dmDisplayFrequency;
                        m.HzMaximo = atual.dmDisplayFrequency;
                        DEVMODE modo = NovoModo();
                        for (int n = 0; EnumDisplaySettings(d.DeviceName, n, ref modo); n++)
                        {
                            if (modo.dmPelsWidth == atual.dmPelsWidth && modo.dmPelsHeight == atual.dmPelsHeight &&
                                modo.dmBitsPerPel == atual.dmBitsPerPel && modo.dmDisplayFrequency > m.HzMaximo)
                                m.HzMaximo = modo.dmDisplayFrequency;
                        }
                        lista.Add(m);
                    }
                }
                d = new DISPLAY_DEVICE();
                d.cb = Marshal.SizeOf(d);
            }
            return lista.ToArray();
        }

        // Retorna 0 = ok, 1 = precisa reiniciar, negativo = erro (DISP_CHANGE_*)
        public static int DefinirHz(string dispositivo, int hz)
        {
            DEVMODE m = NovoModo();
            if (!EnumDisplaySettings(dispositivo, ENUM_CURRENT_SETTINGS, ref m)) return -100;
            m.dmDisplayFrequency = hz;
            m.dmFields = DM_DISPLAYFREQUENCY;
            int teste = ChangeDisplaySettingsEx(dispositivo, ref m, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
            if (teste != 0) return teste;
            return ChangeDisplaySettingsEx(dispositivo, ref m, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
