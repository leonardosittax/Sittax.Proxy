# Lições da migração de homologação — ler antes de repetir em produção

Registro do que deu errado (e do que deu certo) na noite de **05→06/08/2026**,
migrando homologação para acesso só-VPN e trocando o Portainer.

O próximo alvo é **mais crítico, com arquitetura mais simples**: menos ambientes
e sem cluster de nós. Boa parte da complexidade daqui some — mas as armadilhas
abaixo **não dependem de swarm** e vão aparecer igual.

Cada item tem o sintoma que a gente viu de verdade, não teoria.

---

## As três que causaram incidente

### 1. `docker service ls` mostrando `1/1` NÃO é saúde

Foi o ponto cego que mais custou. Durante horas o painel mostrou tudo verde
enquanto **sete serviços do stage não consumiam fila nenhuma**. O container
sobe, responde health check de processo, e a aplicação por dentro está sem
conexão com o broker.

Também mascarou task presa em `Pending` com `host-mode port already in use`: o
serviço aparecia `1/1` pela task **antiga**, enquanto a nova nunca escalonava.

**Verificação que vale**, por dependência e não por réplica:

| dependência | o que contar |
|---|---|
| RabbitMQ | conexões e filas **no broker**, não réplicas |
| banco | query real, não porta aberta |
| HTTP | status code do domínio real, não `docker ps` |

```bash
# o que realmente responde
docker exec <rabbit> rabbitmqctl list_connections client_properties
docker exec <rabbit> rabbitmqctl list_queues name messages consumers

# task nova vs task velha — o ls esconde isso
docker service ps <svc> --no-trunc --format '{{.CurrentState}}|{{.Error}}'
```

### 2. O compose guardado no Portainer NÃO é o que roda

**59 de 71 serviços** rodavam imagem diferente da que estava no compose. O CI
atualiza a imagem direto (`docker service update`) e nunca volta ao Portainer.

Redeployar do compose armazenado teria **revertido 59 serviços para builds
antigos**. Num caso o `IMAGE` do `qa-03` apontava para uma versão de **dois
meses** antes da que rodava.

E não era só a tag: o `sittax-autenticacao-st` tinha `image:
sittax-autenticacao:latest` no compose enquanto rodava `sittax:2.20260713.1` —
**repositório diferente**. O `recupera-spa` apontava para `recupera-spa` e rodava
`recupera-spa-homolog`.

> **Antes de qualquer redeploy: reconciliar.** Compare imagem do compose com a
> que roda, serviço a serviço. Só depois mexa em outra coisa.

Se o compose já for parametrizado (`image: ${IMAGE}`), a reconciliação é só
corrigir a variável — não precisa tocar no compose.

### 3. `${VAR}` e injeção de env do produto são coisas DIFERENTES

Essa derrubou a mensageria dos **5 ambientes** de uma vez.

- `${RABBIT_USUARIO}` no compose é substituído **no render**, a partir da Env
  da stack, **antes** do deploy.
- A env do produto (F3 do fork) é injetada **no container**, no deploy.

Elas não se substituem. O compose tinha:

```yaml
RABBITMQ_DEFAULT_USER: ${RABBIT_USUARIO}
```

Ao mover `RABBIT_USUARIO` para o produto, a linha renderizou **vazia**. O
RabbitMQ subiu sem usuário definido, o volume inicializou só com `guest`, e
todos os serviços passaram a levar `ACCESS_REFUSED`.

> **Regra:** variável usada como fonte de `${}` em qualquer lugar do compose
> **fica na stack**. Só sobe para o produto o que é consumido apenas como env
> de container.

Para descobrir quais são, antes de mover:

```bash
# toda variavel referenciada FORA de blocos environment:
grep -oE '\$\{[A-Z_]+\}' compose.yml | sort -u
```

---

## Armadilhas de ferramenta

### RabbitMQ

- **`RABBITMQ_DEFAULT_USER` só age no primeiro boot com data dir vazio.** Se o
  volume já existe, ele é ignorado. Corrigir a variável depois **não recria o
  usuário** — tem que criar na mão:
  ```bash
  rabbitmqctl add_user admin <senha>
  rabbitmqctl set_user_tags admin administrator
  rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
  ```
- **MassTransit não se recupera** de um broker que recusou login. Ele desiste do
  bus, o serviço fica de pé, sem erro novo no log, e nunca mais consome.
  **Só volta com restart do serviço.**
- Log de erro some rápido: procure `ACCESS_REFUSED` com `--since`, não com
  `--tail`, para separar histórico de problema atual.

### dnsmasq

- **`systemctl reload` NÃO relê o arquivo de configuração** — só limpa cache.
  Mudou `address=`? É `restart`.
- **Carrega TODOS os arquivos de `/etc/dnsmasq.d/`**, não só `.conf`. Um backup
  deixado ali vira configuração ativa. Aconteceu: o `db.dev` antigo do
  `.bak-20260806` venceu o novo. Backups vão para **fora** do diretório.
- Não tem split-horizon (views): uma instância responde o mesmo IP para todos.
  Se LAN e VPN precisam de respostas diferentes, ou são duas instâncias, ou
  resolve-se com rota.

### nginx

- **`map_hash_bucket_size` tem que vir ANTES do primeiro `map` do bloco.** A
  diretiva `map` preenche o default quando ainda está vazio, e a partir daí o
  nginx recusa qualquer `map_hash_bucket_size` com `"directive is duplicate"` —
  mensagem que não ajuda nada a achar a causa.
- **Certificado por variável (`ssl_certificate $var.crt`) é lido pelo WORKER**,
  não pelo master. Chave `600 root:root` dá `Permission denied` no handshake.
  Precisa de `640 root:www-data` e diretório `750`.
- **TLS passthrough (`ssl_preread`) não consegue devolver HTML.** Para mostrar
  página de bloqueio é obrigatório terminar TLS, e portanto ter certificado
  válido daquele hostname.
- `nginx -t` escreve em **stderr**. Função de sudo que descarta stderr esconde
  o erro e você fica olhando para "test failed" sem motivo.

### Docker Swarm

*(A maior parte disto some no próximo servidor, que não tem nós.)*

- **Muitos redeploys em sequência travam o alocador de rede.** Depois de dezenas
  de updates, 25 tasks ficaram presas em `New` sem erro, e o log do daemon
  mostrava `initialized VXLAN UDP port` em loop a cada 5s. Não havia interface
  órfã para remover — o estado ruim estava **dentro do daemon**. Só resolveu com
  `systemctl restart docker` no nó.
- **Porta em `mode: host` + `update_order: start-first` = deadlock.** A task nova
  não sobe porque a antiga ainda segura a porta. Nesses serviços use
  `stop-first`.
- `docker stack deploy` resolve digest no registry por padrão. Para imagem que
  só existe local, use `--resolve-image=never`. Para registry privado,
  `--with-registry-auth`.
- `docker stack config` **não lê `.env`** (isso é do `docker compose`). Para
  validar com variáveis, exporte no shell antes.

### Portainer

- **O agent confia na primeira chave que receber** (trust on first use).
  Reiniciou o agent? Ele reaprende com quem falar primeiro. Com dois Portainers
  apontando para o mesmo agent, um deles fica de fora com
  `Invalid request signature` — que parece erro de rede e não é.
- **Não deixe dois Portainers no mesmo agent.** Foi o que aconteceu aqui: o
  antigo e o novo disputando.
- A API recusa criar stack com nome que já existe no swarm
  (`checkUniqueStackNameInDocker`), **sem flag de bypass**. Para trazer stack já
  rodando para outro Portainer sem downtime foi preciso criar um endpoint de
  adoção no fork (`POST /stacks/adopt/swarm`) — ver `vpn-block/`.
- `DELETE /stacks/{id}` **remove o stack do swarm**, não só o registro.

### Cloudflare

- **Bloqueia o User-Agent padrão do `urllib`.** Script Python contra API atrás
  da Cloudflare retorna `403` enquanto o mesmo `curl` retorna `200`. Mandar um
  `User-Agent` qualquer resolve. Perdi tempo achando que era o token.

### NetBird

- **Colide com Tailscale.** Os dois usam a faixa CGNAT `100.64.0.0/10`. Máquina
  com os dois instalados: o Tailscale toma a tabela NRPT inteira e o split-DNS
  do NetBird nunca é aplicado. Diagnóstico em
  `vpn-block/diagnostico-dns.ps1`.
- Rota e nameserver são distribuídos **por grupo**. Peer fora dos grupos
  configurados não recebe nada e o sintoma é "não resolve" — parece problema de
  DNS e é de permissão.

---

## O que fazer diferente no próximo

Sem nós e com menos ambientes, o roteiro encurta muito:

1. **Reconciliar imagem antes de tudo.** Compose × realidade, serviço a serviço.
   É o passo que evita o incidente maior.
2. **Snapshot do estado antes**, e não só de réplica: imagem de cada serviço,
   conexões no broker, status HTTP de cada domínio. É contra isso que se compara.
3. **Mudar uma coisa por vez, verificando pela dependência.** Cada redeploy em
   lote foi onde os problemas se acumularam.
4. **Nunca mover para o produto variável usada como `${}`.**
5. **Backup do volume antes de recriar** qualquer container com estado
   (RabbitMQ, banco, Portainer). O volume do Rabbit reinicializou e as mensagens
   em fila se perderam.
6. **Sem swap em host de control plane é risco.** Defina limite de memória em
   todo container: quem vazar morre sozinho em vez de o OOM killer escolher a
   vítima.

## O que funcionou bem e vale repetir

- **Branch de rollback no próprio servidor.** O clone git em
  `/home/nginx/.nginx` com commits separados permitiu voltar cada etapa
  isoladamente. Rollback = `git checkout <branch anterior>` + `update.sh`.
- **Provar que a mudança não teve efeito**, em vez de assumir. Na adoção dos
  stacks, comparar `Version.Index` do serviço antes e depois provou que o Docker
  não encostou em nada.
- **Sonda descartável antes de remover coisa crítica.** Antes de tirar
  `JWT_SECRET` do compose, gravei um `F3_PROBE=injecao-ok` no produto e conferi
  que chegava no container. Só então removi o que importava.
- **Ponto de vista externo real.** Testar o bloqueio da própria máquina não
  serve — de dentro do escritório você é "interno". Um host remoto batendo no IP
  público é o único teste honesto.
