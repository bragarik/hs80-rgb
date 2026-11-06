# HS80 RGB

Apague os LEDs laterais do **Corsair HS80 RGB USB com fio** sem instalar o iCUE. O programa envia os comandos USB e encerra: nenhum servico ou aplicativo fica aberto.

Tambem permite escolher uma cor estatica e ajustar sua intensidade.

## Compatibilidade

- Windows 11, usando o Windows PowerShell 5.1 incluido no sistema.
- Modelo USB com **VID `1B1C`, PID `0A88`**.
- Nao exige Python, drivers adicionais, bibliotecas externas ou privilegios de administrador em uma instalacao normal do Windows.
- Nao cobre HS80 Wireless, HS80 MAX nem outros headsets Corsair.

O comando para apagar foi confirmado por um usuario com esse modelo. As opcoes de cor, brilho e inicializacao automatica ainda precisam de validacao nesse hardware. Os testes automatizados verificam a compilacao, os parametros e a montagem dos comandos, sem acessar um headset.

## Uso

Baixe o ZIP do repositorio e extraia todos os arquivos. Feche o iCUE e outros aplicativos que controlem a iluminacao do fone.

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

`Color` aceita seis digitos hexadecimais, com ou sem `#`. `Brightness` aceita um inteiro de 0 a 100; o padrao e 100. O brilho e calculado multiplicando os canais RGB pela porcentagem, sem alterar uma configuracao separada de brilho do firmware. A percepcao visual nao e necessariamente linear.

Para executar pelo PowerShell sem o `.bat`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hs80-rgb.ps1 -Color "0080FF" -Brightness 50
```

O `Bypass` vale apenas para esse processo, sem mudar a politica de execucao configurada no Windows. Politicas da organizacao podem impedir a execucao.

## Aplicar ao entrar no Windows

```powershell
# Apagar em cada login do usuario atual
.\hs80-rgb.bat -InstallStartup

# Ou salvar uma cor e intensidade para cada login
.\hs80-rgb.bat -InstallStartup -Color "0080FF" -Brightness 25

# Remover a inicializacao automatica
.\hs80-rgb.bat -UninstallStartup
```

A instalacao copia o script para `%LOCALAPPDATA%\HS80-RGB\hs80-rgb.ps1` e cria o atalho `HS80 RGB.lnk` na pasta de inicializacao do usuario. Nao aplica a cor imediatamente: use tambem o comando normal para isso. Para mudar a cor salva ou atualizar o script instalado, execute `-InstallStartup` novamente.

A remocao exclui somente o atalho. Voce pode excluir manualmente a pasta `%LOCALAPPDATA%\HS80-RGB` depois. Se criou o atalho antigo `HS80 RGB apagado` durante um teste manual, remova-o em `Win + R` → `shell:startup` para evitar duas execucoes.

O script roda uma vez por login e encerra. O fone deve estar conectado nesse momento. Se for reconectado, perder a alimentacao USB ou tiver sua cor alterada por outro programa, execute o `.bat` novamente. Nao ha monitoramento de reconexao ou reaplicacao continua.

## Diagnostico

```powershell
# Listar as interfaces do modelo, sem enviar comandos de iluminacao
.\hs80-rgb.bat -ListDevices

# Conferir a cor efetiva e os pacotes, sem acessar USB
.\hs80-rgb.bat -Color "0080FF" -Brightness 50 -Preview
```

O script aceita apenas `1B1C:0A88` e uma unica interface HID com relatorios de saida de 16 bytes. Se encontrar mais de uma interface compativel, interrompe sem enviar comandos. Desconecte headsets duplicados e consulte `-ListDevices`.

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

## Creditos e licenca

Protocolo e sequencia de inicializacao baseados no controlador [OpenLinkHub / hs80rgb](https://github.com/jurkovic-nikola/OpenLinkHub/blob/main/src/devices/hs80rgb/hs80rgb.go), de Nikola Jurkovic, distribuido sob GPL-3.0-or-later. Este projeto tambem e distribuido sob **GPL-3.0-or-later**; consulte [LICENSE](LICENSE).

Projeto independente, sem afiliacao com a Corsair.
