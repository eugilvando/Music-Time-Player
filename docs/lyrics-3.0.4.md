# Music Time 3.0.4 — Letras

Código 3.0.4+69. Instalado e validado localmente no Windows; os instaladores públicos Windows e Ubuntu permanecem na 3.0.3.

- Prioridade para LRC/TXT ao lado do áudio, tags embutidas e áudios já baixados antes de consultar a nuvem.
- Antecipação da faixa atual e das próximas duas, seguindo a ordem da fila, sem bloquear a reprodução. Pular para uma faixa ainda não preparada pode exigir espera.
- Cache em memória de até 100 resultados, consultas simultâneas compartilhadas e intervalo de dois minutos para repetir buscas sem resultado.
- Cache em disco de até 100 letras, reutilizado entre sessões e offline, com compatibilidade com versões anteriores. Letras válidas não expiram diariamente; atualização manual disponível no painel.
- LRCLIB como fonte pública principal, com verificação de artista, título e duração; lyrics.ovh como alternativa de texto sem sincronização. Falhas, respostas vazias ou inválidas permitem tentar a próxima fonte.
- Modo offline e preferência de letras online respeitados. A busca pública envia metadados da música, não arquivos de áudio ou credenciais das contas.

Validação Windows: 26 testes de letras, análise estática, build release e integração nativa (abertura, capa, play/pause, bandeja e saída limpa) aprovados. Consulta real aos dois serviços aprovada com faixa pública de controle. A disponibilidade das letras depende da cobertura dos serviços. Esta entrega não inclui um novo pacote Ubuntu validado.

Documentação dos serviços: [LRCLIB](https://lrclib.net/docs) e [lyrics.ovh](https://github.com/NTag/lyrics.ovh#api).
