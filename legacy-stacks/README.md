# Stacks legadas — histórico (NÃO versionar)

Compose das 11 stacks `sittax-*` que existiam no Portainer antigo
(`portainerdev.sittax.com.br`) e **não foram migradas** para o Portainer novo
(`infra.sittax.com.br`), por decisão do Leonardo em 2026-08-06.

Estão aqui só como histórico. Foram substituídas pelos monolitos por ambiente
(`dev`, `qa-01`, `qa-02`, `qa-03`, `sittax-stage`) — o produto `simples-hml`.

## Por que não migrar

Confirmado pelo `docker stack ls` no `.116` (fonte autoritativa, não o campo
`Status` do Portainer): **nenhuma das 11 está implantada no swarm**.

```
sittax-api            sittax-ecac-transmissao   sittax-rt
sittax-app            sittax-gerar-integracao   sittax-upload
sittax-apuracao       sittax-gerar-livros       sittax-worker-services
sittax-autenticacao   sittax-ecac-consulta
```

## ⚠️ Contêm credenciais

Cada arquivo tem entre 6 e 8 valores sensíveis embutidos no próprio compose
(connection strings de SQL Server, `JWT_SECRET`, senhas de RabbitMQ/Redis).
Por isso a pasta está no `.gitignore` — **não commitar como está**.

Para versionar, é preciso antes trocar os literais por referências
(`${VAR}` + `.env` fora do git, ou Docker secrets).
