# 🛠️ Windows Maintenance Suite Pro v3.2

Um script de nível Enterprise (SysAdmin) escrito em PowerShell para manutenção, otimização e diagnóstico avançado do Windows 10 e 11.

Diferente da maioria dos "otimizadores" duvidosos da internet, este script possui uma rigorosa **filosofia de segurança**. Ele foca em estabilidade, observabilidade e utiliza exclusivamente utilitários e APIs nativas da Microsoft, sem realizar tweaks destrutivos no registro.

---

## ✨ Principais Funcionalidades

### 🧹 Limpeza Segura com Contabilização
- **Contador em Tempo Real:** Mede e exibe a quantidade exata de MB ou GB liberados.
- **Temporários (> 48h):** Apaga arquivos temporários de usuário e sistema antigos o suficiente para não interferir em instalações ativas.
- **Cache do Windows Update:** Limpa a pasta `SoftwareDistribution\Download` (> 7 dias).
- **Dumps de Travamento & WER:** Remove logs de erro do Windows e relatórios arquivados de crash.
- **Otimização de Entrega & Lixeira:** Limpeza nativa via API sem gerar falsos avisos quando a lixeira está vazia.
- **Alerta Proativo de WinSxS\Temp:** Monitora acúmulo excessivo de dados em transição de componentes (> 2 GB) e orienta a execução da limpeza correspondente.

### ⚡ Otimização de Armazenamento
- **Detecção Inteligente NVMe / SSD:** Identifica com precisão unidades flash modernas (inclusive SSDs NVMe onde a controladora omite a flag padrão de mídia) e executa exclusivamente o comando nativo **TRIM (`-ReTrim`)**, prevenindo desgaste por desfragmentações desnecessárias.
- **Otimização Tradicional para HDDs:** Aplica desfragmentação padrão apenas em discos rígidos mecânicos.

### 🩺 Diagnósticos de Hardware & Notebook
- **Saúde da Bateria:** Identifica notebooks e calcula capacidade original de projeto, carga máxima atual, número de ciclos e nível de desgaste (*Wear Level*).
- **Suporte Multi-GPU:** Detecta placas dedicadas (ex: NVIDIA RTX) e gráficos integrados (AMD Radeon / Intel), exibindo versões de driver, memória VRAM e temperatura da GPU via `nvidia-smi`.
- **SMART & SSD Health:** Monitora desgaste do SSD e erros de leitura/gravação.
- **Detecção Inteligente de Reboot Pendente:** Distingue reinicializações reais do sistema operacional (Windows Update / CBS) de filas temporárias de renomeação de aplicativos (OneDrive/Edge), prevenindo falsos descontos na pontuação de saúde.

### 🛡️ Estabilidade, Eventos & Reparo Profundo
- **Filtro Unificado de Eventos:** Exclui ruídos cosméticos de DCOM (10005, 10010) e destaca quedas de energia anormais (`Kernel-Power 41`) e telas azuis (`BugCheck 1001`).
- **Reparo Profundo NATIVO:** Orquestra `DISM /RestoreHealth` e `SFC /scannow` com captura de codificação UTF-16LE corrigida (sem caracteres corrompidos no log).
- **Limpeza do Armazenamento de Componentes (WinSxS):** Executa `DISM /StartComponentCleanup` para recuperar espaço de atualizações substituídas, com tratamento resiliente para inconsistências de pacotes legados (código 1726/RPC).
- **Limpeza de Drivers Obsoletos (DriverStore):** Auditoria e remoção de drivers antigos e pacotes duplicados de GPU/sistema.
- **Varredura de Discos Virtuais & Caches (.vhdx / Dev):** Mapeia discos virtuais (WSL, Hyper-V) e grandes caches de desenvolvimento (`.cache`, `.gradle`, `pip`).
- **Ponto de Restauração:** Criação de pontos de proteção do sistema diretamente pelo menu.
- **Codificação UTF-8 com BOM:** Suporte nativo e à prova de falhas a caracteres em Português (PT-BR) no Windows PowerShell 5.1 e superiores.

### 📊 Relatório Visual em HTML
- Exporta tanto o tradicional `SystemReport.txt` quanto um moderno dashboard `SystemReport.html` em modo escuro, com barras de progresso, cartões de métricas e tabela de eventos críticos.

---

## 🚀 Como Usar

1. Baixe ou clone este repositório.
2. Clique com o botão direito em `Manutencao.ps1` e selecione **Executar com o PowerShell**.
   *(O script possui auto-elevação UAC integrada: caso não esteja em modo Administrador, ele solicitará a elevação automaticamente)*.

### 🤖 Automação & Agendamento de Tarefas
Você pode automatizar a manutenção semanal de duas formas simples:

1. **Pelo Menu do Script:** Escolha a opção `16 (Instalar tarefa semanal no Agendador)` para registrar a tarefa com 1 clique.
2. **Via Linha de Comando:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Caminho\Manutencao.ps1" -Auto -ExportReport -HtmlReport
   ```

### ⌨️ Parâmetros de Linha de Comando Suportados:
- `-Routine <1-21>`: Executa diretamente qualquer rotina do menu (ex: `-Routine 14` para manutenção leve, `-Routine 15` para diagnóstico avançado, `-Routine 20` para DriverStore ou `-Routine 21` para caches de desenvolvimento).
- `-PauseAtEnd`: Mantém o console aberto no final da execução até pressionar ENTER (ideal para atalhos personalizados de rotinas específicas).
- `-Auto`: Executa a rotina leve de manutenção sem intervenção interativa.
- `-Advanced`: Executa o diagnóstico avançado completo.
- `-ExportReport`: Gera o relatório técnico em texto (`SystemReport.txt`).
- `-HtmlReport`: Gera o dashboard interativo em HTML (`SystemReport.html`).
- `-InstallTask`: Instala a tarefa semanal no Agendador do Windows.
- `-RemoveTask`: Remove a tarefa do Agendador do Windows.
