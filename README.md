# 🛠️ Windows Maintenance Suite Pro

Um script de nível Enterprise (SysAdmin) escrito em PowerShell para manutenção, otimização e diagnóstico avançado do Windows 10 e 11. 

Diferente da maioria dos "otimizadores" encontrados na internet, este script possui uma **filosofia de segurança**. Ele foca em estabilidade, observabilidade e não realiza "tweaks" mágicos destrutivos no registro ou apaga arquivos vitais do sistema.

## ✨ Funcionalidades

- **Limpeza Segura:** Apaga apenas arquivos temporários com mais de 48 horas (evitando quebrar instalações em andamento).
- **Otimização Inteligente de Disco:** Detecta automaticamente se a unidade é NVMe/SSD ou HDD e aplica o comando de TRIM/Otimização nativo mais adequado.
- **Saúde do Hardware (SMART):** Consulta o desgaste do SSD (Wear) e a temperatura da placa de vídeo (suporte nativo via `nvidia-smi` para placas RTX).
- **Diagnóstico de Estabilidade:** Filtra os eventos críticos do Windows das últimas horas para detectar quedas de energia (Erro 41) ou falhas no boot.
- **Reparo Profundo:** Utiliza comandos nativos da Microsoft (`DISM` e `SFC`) na ordem correta para reparar imagens do Windows corrompidas.

## 🚀 Como usar

1. Faça o download do arquivo `Manutencao.ps1`.
2. Salve no seu computador (Ex: `C:\Scripts\Manutencao.ps1`).
3. Clique com o botão direito no arquivo e execute com o PowerShell como **Administrador**.

### Atalho de Área de Trabalho (Recomendado)
Para rodar com dois cliques:
1. Crie um novo atalho na sua área de trabalho.
2. Cole o destino: `powershell.exe -ExecutionPolicy Bypass -File "C:\Caminho\Manutencao.ps1"`
3. Nas propriedades do atalho > Avançados > Marque "Executar como administrador".

## 🤖 Automação (Agendador de Tarefas)
O script aceita os parâmetros `-Auto`, `-Advanced` e `-ExportReport`. Para rodar a limpeza leve de forma 100% invisível em segundo plano toda semana, adicione isso ao Agendador de Tarefas do Windows:
`powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Caminho\Manutencao.ps1" -Auto`
