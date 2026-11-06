# HS80 RGB

Apague os LEDs laterais do **Corsair HS80 RGB USB com fio** sem instalar o iCUE. O programa envia os comandos USB e encerra: nenhum servico ou aplicativo fica aberto.

Tambem permite escolher uma cor estatica e ajustar sua intensidade.

## Download

[**Baixar HS80 RGB v0.1.0 para Windows (.zip)**](https://github.com/bragarik/hs80-rgb/releases/download/v0.1.0/hs80-rgb-v0.1.0.zip)

Versao previa: apagar, cor e brilho foram confirmados no fone; a execucao no login ainda aguarda validacao no hardware. Extraia todo o ZIP antes de executar o `.bat`. Nao e necessario instalar Git ou clonar o repositorio.

[Todas as versoes e notas](https://github.com/bragarik/hs80-rgb/releases) · [Testes automatizados](https://github.com/bragarik/hs80-rgb/actions)

## Compatibilidade

- Windows 11, usando o Windows PowerShell 5.1 incluido no sistema.
- Modelo USB com **VID `1B1C`, PID `0A88`**.
- Nao exige Python, drivers adicionais, bibliotecas externas ou privilegios de administrador em uma instalacao normal do Windows.
- Nao cobre HS80 Wireless, HS80 MAX nem outros headsets Corsair.

Apagar os LEDs, escolher uma cor e ajustar o brilho foram confirmados por um usuario com esse modelo no Windows 11. A execucao automatica no login ainda precisa de validacao nesse hardware. Os testes automatizados verificam a compilacao, os parametros e a montagem dos comandos, sem acessar um headset.

## Uso

Baixe o ZIP na secao Download e extraia todos os arquivos. Feche o iCUE e outros aplicativos que controlem a iluminacao do fone.

De dois cliques em **`hs80-rgb.bat`** para apagar os LEDs. Mantenha `hs80-rgb.ps1` na mesma pasta do `.bat`.

Para outras opcoes, abra um terminal na pasta extraida:

```powershell
# Apagar (comportamento padrao)
.\hs80-rgb.bat

# Cor estatica azul
.\hs80-rgb.bat -Color "0080FF"

# Roxo com 30% de intensidade
.\hs80-rgb.bat -Color "AA00FF" -Brightness 30

# Branco com intensidade maxima
.\hs80-rgb.bat -Color "FFFFFF" -Brightness 100

# Intensidade zero tambem apaga
.\hs80-rgb.bat -Color "FFFFFF" -Brightness 0
```

`Color` aceita seis digitos hexadecimais, com ou sem `#`. `Brightness` aceita um inteiro de 0 a 100. Sem argumentos, o padrao e **preto (`000000`) e brilho 0%**. Ao informar uma cor diferente de preto sem informar brilho, o programa usa 100%, para que a cor apareca. Um brilho informado explicitamente sempre e respeitado, inclusive zero. O brilho e calculado multiplicando os canais RGB pela porcentagem, sem alterar uma configuracao separada de brilho do firmware. A percepcao visual nao e necessariamente linear.

Para executar pelo PowerShell sem o `.bat`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hs80-rgb.ps1 -Color "0080FF" -Brightness 50
```

O `Bypass` vale apenas para esse processo, sem mudar a politica de execucao configurada no Windows. Politicas da organizacao podem impedir a execucao.

## Aplicar ao entrar no Windows

```powershell
# Apagar em cada login do usuario atual (preto, brilho 0%)
.\hs80-rgb.bat -InstallStartup

# Ou salvar uma cor e intensidade para cada login
.\hs80-rgb.bat -InstallStartup -Color "0080FF" -Brightness 25

# Remover a inicializacao automatica
.\hs80-rgb.bat -UninstallStartup
```

A instalacao copia o script para `%LOCALAPPDATA%\HS80-RGB\hs80-rgb.ps1` e cria o atalho `HS80 RGB.lnk` na pasta de inicializacao do usuario. Sem argumentos de cor e brilho, salva `-Color 000000 -Brightness 0`. Nao aplica a cor imediatamente: use tambem o comando normal para isso. Para mudar a cor salva ou atualizar o script instalado, execute `-InstallStartup` novamente; atualizar o ZIP nao modifica atalhos ja instalados.

A remocao exclui somente o atalho. Voce pode excluir manualmente a pasta `%LOCALAPPDATA%\HS80-RGB` depois. Se criou o atalho antigo `HS80 RGB apagado` durante um teste manual, remova-o em `Win + R` → `shell:startup` para evitar duas execucoes.

O script roda uma vez por login e encerra. O fone deve estar conectado nesse momento. Se for reconectado, perder a alimentacao USB ou tiver sua cor alterada por outro programa, execute o `.bat` novamente. Nao ha monitoramento de reconexao ou reaplicacao continua.

## Diagnostico

```powershell
# Conferir a versao e a revisao do codigo, sem acessar USB
.\hs80-rgb.bat -Version

# Listar as interfaces do modelo, sem enviar comandos de iluminacao
.\hs80-rgb.bat -ListDevices

# Conferir a cor efetiva e os pacotes, sem acessar USB
.\hs80-rgb.bat -Color "0080FF" -Brightness 50 -Preview
```

O script aceita apenas `1B1C:0A88`, interface USB `MI_03`, e seleciona a colecao com `UsagePage=0xFFC5`, `Usage=0x0001`, saida de 16 bytes e relatorio `C8`. Esses valores foram observados no fone testado em Windows 11. Um unico fone pode apresentar `Col01` e `Col02`: elas nao sao dois headsets. A colecao `Col02` observada anuncia apenas `C8`; a selecao nao exige que `C9` e `CB` estejam no descritor, embora eles facam parte da sequencia de comandos que apagou os LEDs no teste inicial. A selecao nao depende da ordem de enumeracao ou de um numero de colecao fixo. Se ainda houver mais de uma colecao RGB elegivel, interrompe sem enviar comandos. Consulte `-ListDevices`, que mostra tambem UsagePage, Usage e RgbReports.

A revisao atual e identificada como `0.1.0+rev.4` e usa brilho 0% no preset apagado. Ela mantem a selecao de interface corrigida em `hid.3`. A revisao `hid.2` rejeitava o descritor que anuncia apenas `C8`; versoes anteriores ainda podiam confundir duas colecoes com dois headsets. Atualizar a branch no GitHub nao substitui automaticamente os ZIPs ja publicados em Releases.

Se falhar, feche o iCUE, confira a conexao e execute o `.bat` no terminal para ler a mensagem. O `.bat` pausa quando ocorre um erro. O atalho de inicializacao executa sem janela; para diagnostica-lo, rode o script instalado manualmente no terminal.

O sucesso informado significa que o Windows aceitou os comandos; o protocolo usado aqui nao faz leitura de confirmacao da cor. Confira visualmente os LEDs laterais e o indicador vermelho de microfone mutado. O projeto nao oferece controle separado do LED do microfone, audio ou equalizador. Nao grava firmware nem perfis permanentes. Para voltar a ter luz, envie outra cor; para retomar o comportamento padrao do dispositivo, desconecte e reconecte o USB.

## Desenvolvimento

O `.bat` apenas inicia o PowerShell. O `.ps1` compila em memoria um pequeno controlador C# que usa as APIs HID incluidas no Windows. A conexao USB e fechada ao terminar.

Sequencia enviada, com cada relatorio completado ate 16 bytes:

| Comando | Dados | Funcao |
| --- | --- | --- |
| `C8` | `00`, depois `01`, em relatorios separados | Modo de controle por software |
| `C9` | `64`, depois `66`, em relatorios separados | Inicializacao da iluminacao |
| `CB` | `03 1C RR 16 GG 17 BB` | Cor RGB |

Nao envia o comando de retorno ao modo de hardware no encerramento, para preservar a cor solicitada. A persistencia apos fechar foi observada no teste de apagar; nao significa que a configuracao sobrevive a perda de alimentacao.

Testes sem hardware:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke.Tests.ps1
```

O GitHub Actions executa os testes no Windows PowerShell 5.1 e no PowerShell 7. `-Preview` e os testes tambem funcionam no PowerShell 7 em Linux, mas nao verificam as chamadas nativas do Windows.

### Publicar uma versao

Crie as notas em `releases/vX.Y.Z.md`, atualize o link de download acima e envie os arquivos antes da tag:

```bash
git push origin main
git tag -a vX.Y.Z -m "HS80 RGB vX.Y.Z"
git push origin vX.Y.Z
```

O workflow Release testa no Windows PowerShell 5.1 e no PowerShell 7, monta o ZIP com finais de linha do Windows e publica a Release com checksum SHA-256. A versao `v0.1.0` e tags com sufixo, como `v0.2.0-beta.1`, sao publicadas como previas. Somente a previa inicial `v0.1.0` pode ter seus arquivos substituidos ao atualizar a tag: a Release fica como rascunho durante a troca e volta a ser publicada depois do upload dos dois arquivos. Outras releases existentes nao sao sobrescritas.

No clone do repositorio, para montar o pacote localmente sem publicar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Version v0.1.0
```

O resultado fica em `dist/`. O ZIP inclui scripts, instrucoes, licenca, notas e testes; nao inclui configuracoes locais do Git.

## Creditos e licenca

Protocolo e sequencia de inicializacao baseados no controlador [OpenLinkHub / hs80rgb](https://github.com/jurkovic-nikola/OpenLinkHub/blob/main/src/devices/hs80rgb/hs80rgb.go), de Nikola Jurkovic, distribuido sob GPL-3.0-or-later. Este projeto tambem e distribuido sob **GPL-3.0-or-later**; consulte [LICENSE](LICENSE).

Projeto independente, sem afiliacao com a Corsair.
