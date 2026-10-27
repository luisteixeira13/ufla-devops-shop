# Atividade 5 — A stack completa

## (a) Status dos serviços (docker compose ps)

```text
NAME                       IMAGE                                    COMMAND                  SERVICE   CREATED          STATUS                    PORTS
ufla-devops-shop-api-1     ghcr.io/luisteixeira13/ufla-shop:1.0.0   "uvicorn app:api --h…"   api       13 seconds ago   Up 7 seconds (healthy)    8000/tcp
ufla-devops-shop-banco-1   postgres:16-alpine                       "docker-entrypoint.s…"   banco     13 seconds ago   Up 12 seconds (healthy)   5432/tcp
ufla-devops-shop-cache-1   redis:7-alpine                           "docker-entrypoint.s…"   cache     13 seconds ago   Up 12 seconds (healthy)   6379/tcp
ufla-devops-shop-nginx-1   nginx:1.27-alpine                        "/docker-entrypoint.…"   nginx     13 seconds ago   Up Less than a second     0.0.0.0:80->80/tcp, [::]:80->80/tcp
```

## (b) Roteiro de validação e persistência

### Verificação inicial dos endpoints (/, /api/info e /health)

```text
$ curl -i http://localhost/
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Tue, 27 Oct 2026 22:46:35 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 1262
Connection: keep-alive

$ curl -s http://localhost/api/info
{"aplicacao":"ufla-devops-shop","versao":"1.0.0","banco":"postgresql","cache":"redis","instancia":"706c9ef27281"}

$ curl -s http://localhost/health
{"status":"ok","versao":"1.0.0"}
```

### Teste de persistência (POST, down, up --wait e busca)

```text
$ curl -s -X POST http://localhost/api/produtos \
  -H 'Content-Type: application/json' \
  -d '{"nome":"Prova de persistencia","preco":9.9,"estoque":1}'
{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-27T22:50:28.787248+00:00"}

$ docker compose down
[+] down 5/5
 ✔ Container ufla-devops-shop-nginx-1 Removed                                                                                                               0.2s
 ✔ Container ufla-devops-shop-api-1   Removed                                                                                                               0.5s
 ✔ Container ufla-devops-shop-banco-1 Removed                                                                                                               0.3s
 ✔ Container ufla-devops-shop-cache-1 Removed                                                                                                               0.3s
 ✔ Network ufla-devops-shop_default   Removed                                                                                                               0.1s

$ docker compose up -d --wait
[+] up 5/5
 ✔ Network ufla-devops-shop_default   Created                                                                                                               0.1s
 ✔ Container ufla-devops-shop-cache-1 Healthy                                                                                                              13.0s
 ✔ Container ufla-devops-shop-banco-1 Healthy                                                                                                              13.0s
 ✔ Container ufla-devops-shop-api-1   Healthy                                                                                                              12.8s
 ✔ Container ufla-devops-shop-nginx-1 Healthy                                                                                                              12.8s

$ curl -s 'http://localhost/api/busca?q=persistencia'
{"termo":"persistencia","total":1,"resultados":[{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-27T22:50:28.787248+00:00"}]}
```

## (c) Endereço público da imagem no GHCR

- Imagem utilizada no `compose.yaml`: `ghcr.io/luisteixeira13/ufla-shop:1.0.0`
- Página pública do pacote: https://github.com/users/luisteixeira13/packages/container/package/ufla-shop

## (d) Pergunta conceitual: depends_on vs. service_healthy

O `depends_on` sozinho apenas garante a ordem em que os containers são iniciados pelo Docker, mas não espera que o processo interno (como o PostgreSQL ou o Redis) termine sua inicialização e esteja efetivamente pronto para aceitar conexões TCP, o que pode causar erros de `connection refused` na subida da API. Ao adicionar `condition: service_healthy`, o Docker Compose aguarda que os comandos de `healthcheck` (`pg_isready` no banco e `redis-cli ping` no cache) retornem sucesso antes de iniciar o container da API, garantindo que as dependências estejam operacionais.
