# Music Time 2.10.0 — Fila inteligente e Smart Flow

O botão existente de Play contínuo agora abre um painel com dois recursos independentes. As mesmas preferências estão em Configurações → Controles e reprodução.

## Fila inteligente

Continua a reprodução ao terminar a fila. Os modos são Gênero, Artista, Era e Aleatório, com quantidade configurável por rodada. A seleção considera toda a fila: artistas, gêneros e décadas predominantes, com mais peso para escolhas manuais e músicas mais recentes. Sugestões automáticas têm peso menor para preservar a intenção da seleção original.

Gênero mantém a variedade da seleção; Artista busca outras faixas dos artistas presentes; Era usa a década das faixas e prioriza similaridade entre artistas; Aleatório usa a biblioteca disponível sem repetir faixas que já estão na fila. Ao esgotar as candidatas, a reprodução termina normalmente.

## Smart Flow

Insere sugestões entre as faixas escolhidas, preservando sua ordem. Aleatório intercala músicas variadas; Dose dupla forma pares do mesmo artista e respeita pares existentes; Fã do artista prioriza os artistas presentes e artistas semelhantes; Da era intercala músicas da mesma década com prioridade para artistas semelhantes.

As sugestões são preparadas em segundo plano, em grupos limitados de até 12 espaços. Faixas automáticas não geram novas inserções. A fila mostra a origem das sugestões; mover uma sugestão manualmente a transforma em uma escolha explícita. Ao desligar o Smart Flow ou trocar seu modo, apenas suas sugestões futuras são retiradas; a faixa atual e escolhas manuais permanecem.

Os dois recursos podem ser usados juntos. A playlist salva não é alterada. As sugestões respeitam disponibilidade/offline e evitam duplicatas na fila. Repetir faixa ou fila suspende novas recomendações; ativar repetição remove as inserções futuras do Smart Flow. Shuffle reorganiza a sequência e permite reconstruir os espaços. A origem das sugestões e a fila são restauradas ao reabrir, com reprodução pausada.

## Similaridade e compatibilidade

Usa a integração Last.fm existente, com cache e fallback local por artista/gênero/ano. As consultas consideram até quatro artistas de maior peso por preparação; o trabalho opcional de rede é limitado e falhas não impedem a reprodução. O Last.fm fornece referências, não arquivos de áudio: todas as músicas vêm da biblioteca disponível.

Instalações anteriores preservam a ativação do Play contínuo como Fila inteligente. O antigo modo Dose dupla de continuação passa a Artista; o Smart Flow começa desligado. As opções de ícones, equalização e transições permanecem disponíveis.

Windows e Ubuntu 24.04 x64 são distribuídos separadamente. Consulte os manifestos de cada pacote para as verificações concluídas. O aceite de áudio, bandeja e contas reais na VM/partição Ubuntu continua separado dos testes automatizados.
