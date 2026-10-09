@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo ================================================
echo    CHAT DE RELATORIO NEVES - ENVIAR AO GITHUB
echo ================================================
echo.
echo Crie primeiro um repositorio VAZIO no GitHub.
echo Nao marque README, .gitignore nem License.
echo Copie a URL HTTPS dele, terminada em .git.
echo.
set /p "REPO=URL do repositorio (https://github.com/usuario/repositorio.git): "
if "%REPO%"=="" goto :falha
where git >nul 2>&1
if errorlevel 1 (
 echo Git nao encontrado. Instale Git for Windows.
 goto :falha
)
if not exist ".github\workflows\build-apk.yml" (
 echo ERRO: Workflow do GitHub nao encontrado.
 goto :falha
)
git init || goto :falha
git checkout -B main || goto :falha
git add . || goto :falha
git -c user.name="Chat de Relatorio Neves" -c user.email="neves-app@users.noreply.github.com" commit -m "Adicionar app Flutter e compilacao APK" || goto :falha
git remote remove origin >nul 2>&1
git remote add origin "%REPO%" || goto :falha
git push -u origin main || goto :falha
echo.
echo ENVIADO! Entre em GitHub, repositorio, Actions.
echo Selecione "Gerar APK" e depois o arquivo em Artifacts.
pause
exit /b 0
:falha
echo.
echo Nao foi possivel concluir. Copie a mensagem de erro para corrigirmos.
pause
exit /b 1
