@echo off
title Otimizador Vinicius
rem Abre a interface grafica (v2.0). O script pede permissao de administrador sozinho.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Otimizador-Vinicius-GUI.ps1"
