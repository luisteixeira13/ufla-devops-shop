# Checkpoint 1 — Entrega Contínua (CI/CD + Staging + Rollback)

## 1. Visão geral da esteira (`.github/workflows/cd.yml`)

A esteira é acionada automaticamente a cada `git push` e executa três jobs encadeados sem intervenção manual:

1. **Gate (`ci`)**: Executa lint (`ruff check .`) e testes automatizados com cobertura (`pytest --cov=app --cov-report=term-missing`) em matriz Python `3.11` e `3.12`.
2. **Publicação e Release (`publicar`)**:
   - Deriva automaticamente a versão **SemVer** a partir dos *Conventional Commits* usando `paulhatch/semantic-version@v5.4.0`.
   - Constrói a imagem uma única vez (`docker/build-push-action@v6`) injetando `APP_VERSION` e publica no GitHub Container Registry (`ghcr.io/luisteixeira13/ufla-shop`) usando o `GITHUB_TOKEN` efêmero do próprio job.
   - Publica tags imutáveis: SemVer (`1.0.1`) e SHA do commit (`sha-efad33e`).
   - Cria automaticamente a GitHub Release (`v1.0.1-efad33e`) com notas geradas.
3. **Implantação em Staging (`staging`)**:
   - Executa `./scripts/deploy.sh <versao>` no ambiente `staging`, subindo a stack completa (`banco`, `cache`, `api`, `nginx`) com `docker compose up -d --wait` e validando `/health`, `/ready` e `/api/info`.

## 2. Artefatos publicados

- **Pacote no GHCR:** https://github.com/users/luisteixeira13/packages/container/package/ufla-shop
- **Tags imutáveis geradas pelo pipeline:**
  - `ghcr.io/luisteixeira13/ufla-shop:1.0.1`
  - `ghcr.io/luisteixeira13/ufla-shop:sha-efad33e`
  - `ghcr.io/luisteixeira13/ufla-shop:1.0.0` (versão anterior usada para rollback)

## 3. Evidência do Deploy (`1.0.1`) e Rollback (`1.0.0`)

Log completo da execução de `./scripts/deploy.sh 1.0.1` seguido do rollback imediato com `./scripts/deploy.sh 1.0.0` e verificação de persistência dos dados no PostgreSQL:

```text
$ ./scripts/deploy.sh 1.0.1
===== IMPLANTANDO ghcr.io/luisteixeira13/ufla-shop:1.0.1 =====
[+] pull 8/8
 ✔ Image ghcr.io/luisteixeira13/ufla-shop:1.0.1 Pulled                                                                                                     2.2s
[+] up 4/4
 ✔ Container ufla-devops-shop-cache-1 Healthy                                                                                                              7.9s
 ✔ Container ufla-devops-shop-nginx-1 Healthy                                                                                                              7.9s
 ✔ Container ufla-devops-shop-banco-1 Healthy                                                                                                              7.9s
 ✔ Container ufla-devops-shop-api-1   Healthy                                                                                                              7.9s
===== STATUS DOS CONTAINERS =====
NAME                       IMAGE                                    COMMAND                  SERVICE   CREATED          STATUS                    PORTS
ufla-devops-shop-api-1     ghcr.io/luisteixeira13/ufla-shop:1.0.1   "uvicorn app:api --h…"   api       8 seconds ago    Up 6 seconds (healthy)    8000/tcp
ufla-devops-shop-banco-1   postgres:16-alpine                       "docker-entrypoint.s…"   banco     34 minutes ago   Up 34 minutes (healthy)   5432/tcp
ufla-devops-shop-cache-1   redis:7-alpine                           "docker-entrypoint.s…"   cache     34 minutes ago   Up 34 minutes (healthy)   6379/tcp
ufla-devops-shop-nginx-1   nginx:1.27-alpine                        "/docker-entrypoint.…"   nginx     34 minutes ago   Up 34 minutes             0.0.0.0:80->80/tcp, [::]:80->80/tcp
===== VALIDANDO HEALTHCHECKS HTTP =====
{"status":"ok","versao":"1.0.1"}
{"status":"ok","banco":"ok","cache":"ok"}
{"aplicacao":"ufla-devops-shop","versao":"1.0.1","banco":"postgresql","cache":"redis","instancia":"e06b64be911c"}

$ ./scripts/deploy.sh 1.0.0
===== IMPLANTANDO ghcr.io/luisteixeira13/ufla-shop:1.0.0 =====
[+] pull 1/1
 ✔ Image ghcr.io/luisteixeira13/ufla-shop:1.0.0 Pulled                                                                                                     0.5s
[+] up 4/4
 ✔ Container ufla-devops-shop-cache-1 Healthy                                                                                                              7.8s
 ✔ Container ufla-devops-shop-nginx-1 Healthy                                                                                                              7.8s
 ✔ Container ufla-devops-shop-banco-1 Healthy                                                                                                              7.8s
 ✔ Container ufla-devops-shop-api-1   Healthy                                                                                                              7.8s
===== STATUS DOS CONTAINERS =====
NAME                       IMAGE                                    COMMAND                  SERVICE   CREATED          STATUS                    PORTS
ufla-devops-shop-api-1     ghcr.io/luisteixeira13/ufla-shop:1.0.0   "uvicorn app:api --h…"   api       8 seconds ago    Up 6 seconds (healthy)    8000/tcp
ufla-devops-shop-banco-1   postgres:16-alpine                       "docker-entrypoint.s…"   banco     35 minutes ago   Up 35 minutes (healthy)   5432/tcp
ufla-devops-shop-cache-1   redis:7-alpine                           "docker-entrypoint.s…"   cache     35 minutes ago   Up 35 minutes (healthy)   6379/tcp
ufla-devops-shop-nginx-1   nginx:1.27-alpine                        "/docker-entrypoint.…"   nginx     35 minutes ago   Up 34 minutes             0.0.0.0:80->80/tcp, [::]:80->80/tcp
===== VALIDANDO HEALTHCHECKS HTTP =====
{"status":"ok","versao":"1.0.0"}
{"status":"ok","banco":"ok","cache":"ok"}
{"aplicacao":"ufla-devops-shop","versao":"1.0.0","banco":"postgresql","cache":"redis","instancia":"bbabe78704d6"}

$ curl -s 'http://localhost/api/busca?q=persistencia'
{"termo":"persistencia","total":1,"resultados":[{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-27T22:50:28.787248+00:00"}]}
```
