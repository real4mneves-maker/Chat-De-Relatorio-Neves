# Chat de Relatório Neves 🏥

Aplicativo Flutter para relatórios de maqueiros e equipes hospitalares. Inclui chat, modelos, ditado de voz, histórico local, PDF, CSV e IA opcional Gemini/OpenAI.

## GERAR APK NO GITHUB (sem Android Studio no seu PC)

1. Entre em https://github.com/new e crie um repositório **vazio** (por exemplo, `chat-de-relatorio-neves`). Se estiver usando o script .bat, **não** adicione README, .gitignore ou License durante a criação.
2. Extraia este ZIP no Windows. Abra a pasta `chat_de_relatorio_neves` e clique duas vezes em `ENVIAR_AO_GITHUB.bat`. Cole a URL HTTPS do novo repositório, ex.: `https://github.com/SEU-USUARIO/chat-de-relatorio-neves.git`.
3. Autorize o Git se o navegador solicitar. O arquivo `.github/workflows/build-apk.yml` executará uma compilação a cada push para `main` ou `master`.
4. Abra seu repositório no GitHub, clique **Actions**, abra **Gerar APK | Chat de Relatório Neves**, selecione o trabalho concluído com ✓.
5. Role até **Artifacts** e baixe **Chat-de-Relatorio-Neves-APK**. Extraia esse ZIP. Dentro dele estará `app-release.apk` para instalar no Android.
6. Em compilações seguintes, você pode acionar **Actions > Gerar APK | Chat de Relatório Neves > Run workflow**.

**Por que o workflow faz `flutter create`?** O projeto original foi entregue sem os arquivos Gradle e demais arquivos padrão Android. O GitHub Actions os gera automaticamente. O workflow restaura as permissões de microfone e internet do Manifest após a geração.

### Se preferir enviar arquivos pelo navegador

Você pode criar um repositório e fazer upload dos **arquivos extraídos**, não do ZIP fechado. O `pubspec.yaml` e as pastas `lib`, `test`, `android` e **`.github`** precisam estar na raiz do repositório. A pasta `.github` é oculta em alguns gerenciadores de arquivo.

## IA, funcionamento offline e privacidade

Em **Ajustes**, selecione Gemini ou OpenAI e adicione uma chave própria do provedor. O chat precisa de internet quando usa IA. Sem chave, a estruturação básica e a biblioteca de modelos funcionam offline. O reconhecimento de voz depende do mecanismo do Android e pode precisar de internet.

**Proteção de dados:** anonimizar relatos antes de enviar para qualquer IA. Não usar nome completo, CPF, prontuário ou outras informações identificáveis de pacientes sem autorização institucional. Nesta versão a chave da API fica salva em SharedPreferences sem criptografia de segredos, por isso o app é um protótipo pessoal e não está pronto para processamento institucional de dados identificáveis.

O APK é para instalação e testes. Para publicar na Play Store será necessário criar assinatura de produção, personalizar ícone e splash e revisar segurança/privacidade.

## Pastas

- `lib/main.dart`: interface do aplicativo e serviços
- `pubspec.yaml`: dependências do Flutter
- `android/app/src/main/AndroidManifest.xml`: permissões e nome do aplicativo
- `test/widget_test.dart`: verificações básicas de formatação offline
- `.github/workflows/build-apk.yml`: compilação automática em GitHub Actions
- `ENVIAR_AO_GITHUB.bat`: envia os arquivos para um repositório GitHub vazio a partir do Windows com Git instalado

**Observação:** ainda não compilamos este projeto no GitHub. A automação está configurada, mas os resultados dependem da primeira execução real.
