# HS80 RGB

Controle os LEDs laterais do **Corsair HS80 RGB USB com fio** no Windows 11 sem instalar o iCUE. O mesmo `.bat` pode apagar, definir uma cor ou executar seis animações. Revisão atual: **`0.2.0+startup.3`**.

| Modo | Comportamento |
| --- | --- |
| Apagar ou cor estática | Envia a configuração e encerra |
| Qualquer animação | Mantém um processo ativo atualizando a cor |

## Download

[**Baixar HS80 RGB v0.2.0 para Windows (.zip)**](https://github.com/bragarik/hs80-rgb/releases/download/v0.2.0/hs80-rgb-v0.2.0.zip)

[Todas as versões](https://github.com/bragarik/hs80-rgb/releases) · [Testes automatizados](https://github.com/bragarik/hs80-rgb/actions)

Extraia **todo o ZIP** antes de executar. Mantenha `hs80-rgb.bat` e `hs80-rgb.ps1` na mesma pasta. Não precisa instalar Git, Python ou bibliotecas externas.

Esta versão é uma **prévia das animações**. Apagar, cor estática e brilho foram confirmados no headset na v0.1.0. Os novos efeitos, parada por Ctrl+C, troca de efeito e execução no login ainda precisam de confirmação física no Windows com o fone.

## Compatibilidade

- Windows 11 e Windows PowerShell 5.1, incluído no sistema.
- Corsair HS80 **USB com fio**, identificador **`1B1C:0A88`**.
- Não cobre HS80 Wireless, HS80 MAX nem outros headsets.
- Não exige privilégios de administrador em uma instalação normal do Windows.
- Feche o iCUE e outros programas que controlem a iluminação do headset.

Os dois logos são tratados como uma única zona. O projeto não ajusta separadamente o indicador do microfone, áudio ou equalizador.

### Controle por lado

Não foi encontrado um comando verificável para controlar os lados separadamente no modelo USB `1B1C:0A88`. A [página oficial da Corsair](https://www.corsair.com/ww/en/p/gaming-headsets/ca-9011237-na/hs80-rgb-usb-wired-gaming-headset-carbon-ca-9011237-na) descreve iluminação RGB, mas não informa comandos para cada lado. O [controlador OpenLinkHub para esse modelo](https://github.com/jurkovic-nikola/OpenLinkHub/blob/main/src/devices/hs80rgb/hs80rgb.go) implementa uma única zona chamada Logo. Isso não prova uma limitação física; nesta versão, os efeitos usam apenas o controle conjunto confirmado, sem comandos experimentais para lados independentes.

## Apagar e escolher uma cor

Dois cliques em `hs80-rgb.bat` apagam os LEDs. Para outras opções, abra o PowerShell na pasta extraída:

```powershell
# Apagar: preto, brilho 0%; encerra depois do envio
.\hs80-rgb.bat

# Roxo a 30%; encerra depois do envio
.\hs80-rgb.bat -Color "AA00FF" -Brightness 30

# Azul: sem brilho informado, usa 100%
.\hs80-rgb.bat -Color "0080FF"
```

`-Color` aceita seis dígitos hexadecimais, com ou sem `#`. `-Brightness` aceita um inteiro de 0 a 100. O brilho multiplica os canais RGB; não altera um ajuste separado de brilho no firmware. Um brilho explícito é sempre respeitado, inclusive zero.

## Animações

```powershell
# Arco-íris, uma volta completa a cada 10 segundos
.\hs80-rgb.bat -Effect Rainbow -Brightness 30 -Period 10

# Respiração roxa, um ciclo completo a cada 4 segundos
.\hs80-rgb.bat -Effect Breathe -Color "AA00FF" -Brightness 30 -Period 4

# Transição suave por uma paleta; 12 segundos para percorrer toda a lista
.\hs80-rgb.bat -Effect Cycle -Colors "FF0000,00FF00,0000FF" -Brightness 30 -Period 12

# Piscar: metade do ciclo aceso, metade apagado
.\hs80-rgb.bat -Effect Blink -Color "0080FF" -Brightness 30 -Period 2

# Batimento: dois pulsos, o segundo mais fraco, seguidos de uma pausa
.\hs80-rgb.bat -Effect Heartbeat -Color "FF0000" -Brightness 30 -Period 2

# Cores aleatórias com transições suaves de 4 segundos
.\hs80-rgb.bat -Effect Random -Brightness 30 -Period 4

# Repetir a mesma sequência aleatória com uma semente explícita
.\hs80-rgb.bat -Effect Random -Brightness 30 -Period 4 -Seed 42
```

Sem `-InstallStartup`, o efeito começa agora e não modifica a configuração salva para o login. O terminal fica ocupado enquanto a animação executa.

| Opção | Padrão |
| --- | --- |
| `-Effect` | `Static`; também aceita `Rainbow`, `Breathe`, `Cycle`, `Blink`, `Heartbeat` e `Random` |
| `-Period` | Segundos inteiros de 1 a 3600; `Rainbow` e `Cycle`: 10; `Breathe` e `Random`: 4; `Blink` e `Heartbeat`: 2 |
| `-Color` em `Breathe`, `Blink` e `Heartbeat` | Branco quando omitido; preto explícito continua apagado |
| `-Colors`, apenas em `Cycle` | De 2 a 16 cores hexadecimais separadas por vírgula; padrão: vermelho, verde e azul |
| `-Seed`, apenas em `Random` | Inteiro de 0 a 2147483647; quando omitido, uma nova semente é escolhida para a execução/configuração |
| `-Brightness` nas animações | 100% quando omitido, exceto efeitos de uma cor com preto explícito |

Em `Cycle`, `-Period` é o tempo para percorrer a paleta inteira e voltar à primeira cor. Em `Random`, é o tempo de cada transição para a próxima cor; a sequência não reinicia a cada período. Nos demais efeitos, é a duração do ciclo completo. `Rainbow`, `Cycle` e `Random` não usam `-Color`.

As animações mantêm a conexão USB aberta, inicializam o controle uma única vez e enviam novas cores em intervalos de aproximadamente 50 ms. Paletas e sementes são preparadas uma vez por execução, sem sorteio a cada quadro. O aleatório é reproduzível com a mesma semente e permanece contínuo entre transições.

### Parar e trocar de modo

Use **Ctrl+C** no terminal da animação, ou abra outro terminal na pasta e execute:

```powershell
.\hs80-rgb.bat -Stop
```

A parada normal apaga os LEDs e encerra o processo da animação. `-Stop` sem animação ativa não altera uma cor estática nem precisa de um headset conectado.

Executar outra cor, apagar ou escolher outro efeito pede a parada da animação anterior, aguarda que ela apague e feche a conexão, e então aplica a nova escolha. A coordenação vale na **mesma sessão do Windows**, mesmo entre cópias do programa em pastas diferentes. Não são encerrados processos por nome ou PID. Se o controlador anterior não liberar o acesso em cinco segundos, a nova execução falha sem iniciar outro controlador USB.

Fechar o terminal à força ou encerrar o processo no Gerenciador de Tarefas pode impedir a limpeza final. Se o USB for desconectado, a animação encerra com erro; reconecte e execute o comando novamente. Não há reconexão automática nesta versão.

## Iniciar com o Windows

```powershell
# Apagar uma vez no próximo login e encerrar
.\hs80-rgb.bat -InstallStartup

# Cor estática no login: aplica e encerra
.\hs80-rgb.bat -InstallStartup -Color "AA00FF" -Brightness 30

# Animação no login: permanece executando sem janela
.\hs80-rgb.bat -InstallStartup -Effect Rainbow -Brightness 30 -Period 10

# Respiração roxa no login, sem janela
.\hs80-rgb.bat -InstallStartup -Effect Breathe -Color "AA00FF" -Brightness 30 -Period 4

# Paleta personalizada no login
.\hs80-rgb.bat -InstallStartup -Effect Cycle -Colors "AA00FF,0080FF,00FF80" -Brightness 30 -Period 12

# Aleatório: a semente salva permite repetir a sequência em cada login
.\hs80-rgb.bat -InstallStartup -Effect Random -Brightness 30 -Period 4 -Seed 42

# Remover a execução nos próximos logins
.\hs80-rgb.bat -UninstallStartup
```

Configurar a inicialização **não aplica nem interrompe o efeito atual**. A escolha é salva para o próximo login. Execute também o comando sem `-InstallStartup` se quiser aplicar agora.

A instalação cria estes arquivos para o usuário atual:

| Arquivo | Finalidade |
| --- | --- |
| `%LOCALAPPDATA%\HS80-RGB\hs80-rgb.ps1` | Cópia do controlador |
| `%LOCALAPPDATA%\HS80-RGB\HS80Rgb.Startup-<identificador>.exe` | Pequeno iniciador sem console, compilado localmente a partir do código C# incluído no script |
| `HS80 RGB.lnk`, na pasta de inicialização do usuário | Atalho para o iniciador, com cor, brilho, efeito, período e paleta/semente quando aplicável |
| `%LOCALAPPDATA%\HS80-RGB\startup.log` | Diagnóstico e tempos da execução no login; criado quando o iniciador executa |

O iniciador cria o PowerShell sem janela de console e encerra imediatamente. Em uma animação, somente o controlador PowerShell continua ativo; no modo estático, ele também encerra após aplicar a cor. Não instala serviço nem exige VBScript. Os comandos manuais pelo `.bat` continuam visíveis no terminal, permitindo Ctrl+C.

Use o `.bat` para configurar a inicialização: ele chama o Windows PowerShell 5.1, necessário para compilar o iniciador. A compilação ocorre durante a instalação, não a cada login. O controlador C# dos comandos USB ainda é compilado pelo script a cada processo; o modo silencioso não promete reduzir o tempo até aplicar a cor.

Execute `-InstallStartup` novamente para mudar a escolha salva ou atualizar uma instalação anterior. A atualização do download não altera o atalho nem a cópia já instalada. Se ainda houver um atalho antigo chamado `HS80 RGB apagado`, remova-o em `Win + R` → `shell:startup` para evitar execuções duplicadas.

`-Stop` e alterações manuais preservam o atalho. `-UninstallStartup` remove apenas o atalho: a cópia local permanece, e uma animação ativa continua até `-Stop`, Ctrl+C ou substituição por outro modo. O headset deve estar conectado no login; não há monitoramento de novas conexões.

Depois de atualizar para esta revisão, execute `-InstallStartup` novamente para substituir o alvo antigo do atalho pelo iniciador sem console, informando a cor/efeito que deseja salvar. A atualização do ZIP sozinha não altera uma instalação existente.

## Versão e diagnóstico

```powershell
# Deve mostrar HS80 RGB 0.2.0+startup.3
.\hs80-rgb.bat -Version

# Interfaces HID, sem enviar comandos de iluminação
.\hs80-rgb.bat -ListDevices

# Prévia estática sem acessar USB nem parar uma animação ativa
.\hs80-rgb.bat -Color "0080FF" -Brightness 50 -Preview

# Amostras de um ciclo e parâmetros salvos no atalho, sem acessar USB
.\hs80-rgb.bat -Effect Breathe -Color "AA00FF" -Brightness 30 -Period 4 -Preview

# Tempos da última execução no login, quando houver
Get-Content "$env:LOCALAPPDATA\HS80-RGB\startup.log" -Tail 30
```

O controlador seleciona `1B1C:0A88`, interface `MI_03`, com `UsagePage=0xFFC5`, `Usage=0x0001`, saída de 16 bytes e relatório `C8`. Esses dados foram confirmados no headset testado. `Col01` e `Col02` podem pertencer a um único fone; a seleção não depende da ordem ou de um número de coleção fixo. Mais de uma coleção de controle elegível interrompe a operação.

O sucesso do envio significa que o Windows aceitou os comandos; o programa não lê uma confirmação da cor. Confira visualmente a iluminação e o indicador vermelho do microfone mutado. O `.bat` pausa quando ocorre erro. Para diagnosticar uma configuração de login, execute manualmente o comando correspondente no terminal.

O log de inicialização registra o início do script, compilação do controlador, espera de acesso exclusivo, detecção/inicialização USB e aplicação da cor ou início do efeito. Não registra cada quadro animado. O iniciador limita o arquivo a aproximadamente 256 KiB entre execuções; falhas de gravação do diagnóstico não impedem o controle do fone. O log mede as etapas depois de iniciar o programa, não o tempo que o Windows demorou para executar a entrada de inicialização.

## Desenvolvimento

O `.bat` inicia o PowerShell. O `.ps1` contém um controlador C# compilado em memória, que utiliza as APIs HID do Windows. O modo estático conserva a cor ao fechar a conexão; as animações apagam no encerramento normal. A coordenação usa mutex e evento nomeados na sessão do Windows. Os cálculos dos efeitos usam tempo decorrido, sem acumular atrasos entre ciclos.

Sequência USB, com relatórios de 16 bytes:

| Comando | Dados | Uso |
| --- | --- | --- |
| `C8` | `00`, depois `01`, em envios separados | Ativar controle por software |
| `C9` | `64`, depois `66`, em envios separados | Inicializar iluminação |
| `CB` | `03 1C RR 16 GG 17 BB` | Aplicar uma cor; repetido nos quadros animados |

O descritor observado anuncia `C8`, mas não `C9`/`CB`; estes continuam na sequência de comandos confirmada no teste inicial. Não há gravação de firmware ou perfil permanente.

No clone do repositório, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Lifecycle.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Startup.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Release.Tests.ps1
```

Os testes não precisam de um headset. Cobrem quadros e limites dos seis efeitos, paletas, sementes, continuidade do aleatório, brilho, parâmetros de inicialização, pacotes, seleção de coleção, parada e substituição entre processos, tempo limite, recuperação após falha e integridade do ZIP. O teste de inicialização usa pastas temporárias, verifica o subsistema GUI do executável e confirma que o PowerShell filho não tem console/janela, sem alterar a pasta de inicialização real. Os testes entre processos usam nomes exclusivos e não param animações do usuário. GitHub Actions executa no Windows PowerShell 5.1 e PowerShell 7; a compilação do iniciador GUI é testada no Windows PowerShell 5.1. Em Linux, os cálculos e o empacotamento podem ser testados no PowerShell 7; as verificações que exigem Windows são ignoradas.

### Publicação

Crie `releases/vX.Y.Z.md`, atualize a versão no script, os testes e o link de download, faça um commit e envie uma tag nova:

```bash
git push origin main
git tag -a vX.Y.Z -m "HS80 RGB vX.Y.Z"
git push origin vX.Y.Z
```

O workflow Release testa, monta o ZIP e publica notas e checksum SHA-256. `v0.2.0` é uma prévia das animações; versões com sufixo, como `v0.3.0-beta.1`, também são prévias. Somente as prévias `v0.1.0` e `v0.2.0` podem ter seus arquivos substituídos quando a tag é atualizada. Durante essa troca, a Release vira rascunho até o upload do ZIP e do checksum terminar. Releases estáveis e outras versões existentes não são sobrescritas.

Para montar um pacote local sem publicar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Version v0.2.0
```

O resultado fica em `dist/`. O ZIP inclui os scripts, instruções, licença, notas e testes necessários para conferir a distribuição.

## Créditos e licença

Protocolo baseado no controlador [OpenLinkHub / hs80rgb](https://github.com/jurkovic-nikola/OpenLinkHub/blob/main/src/devices/hs80rgb/hs80rgb.go), de Nikola Jurkovic, distribuído sob GPL-3.0-or-later. Este projeto também é distribuído sob **GPL-3.0-or-later**; consulte [LICENSE](LICENSE).

Projeto independente, sem afiliação com a Corsair.
