# Music Time 3.0.6 — Reprodução e verificação de atualizações

## Mudanças

- Eventos de posição atualizam somente progresso, tempo e letras. A biblioteca continua reagindo às mudanças reais de estado, metadados, fila e preferências.
- Pré-carregamento de letras e áudio deixa de verificar a fila a cada posição. Smart Flow não é consultado pelo temporizador, nem encadeia consultas após inserir suas próprias sugestões; mantém um look-ahead limitado.
- A assinatura da capa usada pelo Windows é reutilizada enquanto os mesmos bytes permanecem ativos. O progresso do sistema continua atualizado por segundo; mudanças de estado e comandos de busca continuam imediatos.
- Fundo desfocado e disco giratório usam limites de pintura próprios. Contagem de escuta é mantida sem reconstrução periódica da tela; durante crossfade, registro de escuta da faixa anterior ocorre por segundo e ao finalizar.
- A análise WAV dos Smart fades executa fora do ambiente da interface. A próxima faixa pode ser preparada três segundos antes da janela de transição, sem antecipar o início da sobreposição escolhida. Falhas continuam permitindo avanço normal.
- Cache nativo do libmpv permanece em memória, sem a segunda cópia temporária em disco. Cache persistente do Music Time, leitura antecipada e qualidade do áudio são preservados. Runtime libmpv LGPL permanece o mesmo, conferido por SHA256. O buffer de saída observado continua em 0,2 s; não foi aumentado sem evidência de necessidade.
- Preferências de automação não são regravadas quando permanecem iguais. Rotinas de retomada da sessão, sincronização de scrobbles e detecção da saída de áudio foram preservadas.
- Sobre obtém versão e número de compilação pelo package_info_plus. O botão Verificar atualização consulta as últimas 100 releases públicas do projeto apenas ao ser acionado, ignora rascunhos/pré-releases/versões sem pacote compatível e compara versões numericamente. Falhas de rede têm mensagem e nova tentativa; não são tratadas como ausência de atualização.
- A ação Abrir download e notas leva à release oficial no navegador. Download e instalação são manuais. Não há atualização silenciosa nem envio de dados da biblioteca. Versões instaladas mais novas que a release pública não recebem oferta de downgrade.

## Validação e limites

Análise completa sem problemas e 31 testes direcionados aprovados: seleção de releases/falhas, versão instalada e responsividade do Sobre, progresso/letras sem reconstruir a página, cache de letras, Smart Flow limitado, fila inteligente, quatro modos de crossfade, equalização, reprodução de arquivo concluído em cache e cache offline real. Os primeiros testes encontraram um import ausente no teste legado do Sobre, corrigido antes da rodada final. Os avisos de WAV das fixtures de transição não foram tratados como evidência de reprodução da falha do usuário.

Build Windows concluído após disponibilizar os headers/bibliotecas ATL da instalação Community 2022 ao compilador Build Tools, ambos MSVC 14.44.35207. Integração nativa aprovada: capa, play/pause, troca de estilos sem reiniciar sessão, bandeja, posição da janela e saída limpa. O novo teste de cache observou 20 segundos sem buffering, desvio máximo de 77 ms; os testes usam arquivos fictícios e não medem o sinal analógico.

A comparação curta do mesmo perfil fictício registrou CPU média de 1,36% na 3.0.5 e 1,77% na 3.0.6, memória de 307 e 306 MB. A linha do tempo avançou 10,95/11,01 s durante 12 amostras. Não há redução de CPU comprovada por essa amostra. O relato de pausas menores que um segundo no meio de faixas já em cache não foi reproduzido; a carga repetida da interface foi removida, mas confirmação na coleção/dispositivo real continua pendente. Não foi feita captura ETW/DPC do driver nem validação auditiva pelo usuário.

Instalação local 3.0.6+71: binários conferidos e três arquivos do perfil preservados por hash; backup privado pré-instalação. App deixado fechado. Projetos pessoal e público atualizados; não foram criadas novas releases de instaladores Windows/Ubuntu, que continuam 3.0.3.

SHA256 do instalador: 9A06242D5D6A69DDE921F8548F8047850BE2CD7CF064C5B1F1E08962F1E7A372
