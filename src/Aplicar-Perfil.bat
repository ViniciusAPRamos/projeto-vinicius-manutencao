@echo off
title Otimizador Vinicius - aplicar perfil
rem Uso: Aplicar-Perfil.bat basico^|trabalho^|gamer^|leve^|caminho\perfil.json
rem Aplica sem abrir a janela. Bom para padronizar varios PCs da empresa.
if "%~1"=="" (
  echo Uso: %~nx0 basico^|trabalho^|gamer^|leve^|arquivo.json
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Otimizador-Vinicius-GUI.ps1" -Perfil "%~1"
