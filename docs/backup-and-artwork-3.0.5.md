# Music Time 3.0.5 — Backup e capas da reprodução

- Corrigida a rejeição da preferência Smart Flow na criação/restauração de backups.
- Novo formato MTBACKUP3 para exportações com capas. Grava e lê uma imagem por vez, inclui somente imagens referenciadas e preserva a qualidade original. Metadados e imagens são verificados antes da restauração; falhas durante a restauração revertem a transação.
- Backups com senha usam AES-256-GCM por registro e derivação PBKDF2-HMAC-SHA256; credenciais permanecem protegidas. O arquivo de destino só é substituído após a conclusão da escrita temporária.
- Exportação e leitura mostram a etapa atual e quantidade de capas processadas; restauração mostra sua etapa. Músicas e downloads físicos continuam fora do backup.
- Mantida a leitura dos formatos antigos. Backups novos **com capas exigem Music Time 3.0.5 ou posterior**. Sem capas, o formato anterior continua sendo usado.
- Limites de proteção: arquivo com capas até 16 GB, imagem individual até 32 MB, catálogo/preferências até 128 MB e até 500 mil registros de imagem. A leitura não mantém todas as capas na memória.
- Tamanho da capa aplicado em Somente capa e na composição com letras, além de Clássico, Vinil e Minimalista. A faixa completa do seletor acompanha o espaço disponível, sem atingir um teto antes do final. O seletor fica desativado em Somente letras.

Validação: sete cenários do novo backup, incluindo arquivo de 138 MB, criptografia/credenciais, senha errada, truncamento, preservação do destino, restauração seletiva e rollback após alteração do arquivo; teste de tamanho em cinco composições e janelas de 480/1400 px; quatro testes do arquivo anterior e três de dados aprovados. O teste antigo de redimensionamento também passou. Na rodada ampliada, um teste legado de sidebar ainda espera Biblioteca onde a navegação desde 3.0 usa Músicas; nenhum código de navegação foi alterado nesta entrega.

Código 3.0.5+70. Testes, análise estática e build Windows aprovados. Os instaladores publicados permanecem na 3.0.3; este envio atualiza o código-fonte e a documentação.
