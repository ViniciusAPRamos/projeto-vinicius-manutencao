@echo off
title Otimizador Vinicius - inventario
rem Uso: Inventario-PC.bat \\servidor\pasta
rem Grava NOME-DO-PC.json na pasta, sem janela e sem pedir administrador.
rem Bom para o script de logon ou o Agendador de Tarefas dos PCs da empresa.
if "%~1"=="" (
  echo Uso: %~nx0 pasta
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Otimizador-Vinicius-GUI.ps1" -Inventario "%~1"
