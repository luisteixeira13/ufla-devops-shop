# Atividade 4 — Containerizar a aplicação

## 1. Objetivo

O objetivo desta atividade foi containerizar a aplicação UFLA DevOps Shop utilizando Docker, construindo uma imagem multi-stage otimizada, com usuário não-root, encerramento controlado e verificação automática de saúde.

A aplicação foi executada no modo autônomo, utilizando SQLite e cache em memória, sem depender de PostgreSQL ou Redis externos, conforme previsto no enunciado.

## 2. Primeira versão funcional

A primeira versão foi construída usando a imagem base `python:3.12-slim`, com instalação das dependências de execução e cópia dos diretórios `app/` e `static/`.

Comando utilizado:

```bash
docker build -t ufla-shop:antes .
```

Resultado medido:

```text
IMAGE             ID             DISK USAGE   CONTENT SIZE
ufla-shop:antes   eb992c196583   239MB        56.4MB
```

Medição adicional com `docker image inspect`:

```text
Tamanho em bytes: 56370186
Tamanho formatado: 57M
```

A primeira versão funcionou e atendeu aos testes funcionais. Entretanto, o uso de `python:3.12-slim` resultou em um consumo de disco de 239 MB, acima da meta de tamanho da atividade.

## 3. Otimização da imagem

A versão final foi construída utilizando um Dockerfile multi-stage com `python:3.12-alpine`.

O primeiro estágio, denominado `builder`, cria o ambiente virtual e instala as dependências definidas em `requirements.txt`. O segundo estágio, denominado `runtime`, recebe apenas o ambiente virtual e os arquivos necessários à execução da aplicação.

Outras medidas adotadas:

- Utilização de Alpine como imagem base do estágio final.
- Separação entre construção das dependências e ambiente de execução.
- Cópia seletiva dos diretórios `app/` e `static/`.
- Uso de `.dockerignore` para excluir o repositório Git, ambientes virtuais, testes, caches, bancos SQLite e arquivos de ambiente do contexto de build.
- Execução com usuário não-root, UID `10001`.
- Configuração de `PYTHONDONTWRITEBYTECODE=1` e `PIP_NO_CACHE_DIR=1`.
- Uso de `CMD` em formato exec e de `HEALTHCHECK` com Python, sem instalar `curl` na imagem.

A medição final apresentou:

```text
IMAGE             ID             DISK USAGE   CONTENT SIZE
ufla-shop:1.0     9c88ad81c693   148MB        34.2MB
```

Medição adicional com `docker image inspect`:

```text
Tamanho em bytes: 34195679
Tamanho formatado: 35M
```

### Comparação antes e depois

| Métrica | Primeira versão | Versão final |
|---|---:|---:|
| Docker Disk Usage | 239 MB | 148 MB |
| Docker Content Size | 56,4 MB | 34,2 MB |
| `docker image inspect .Size` | 56.370.186 bytes | 34.195.679 bytes |
| Saída de `numfmt --to=si` | 57M | 35M |

Considerando a coluna `DISK USAGE`, a redução foi de aproximadamente **91 MB**, equivalente a **38,1%**. Considerando o valor retornado por `docker image inspect`, a redução foi de 22.174.507 bytes, aproximadamente **39,3%**.

A meta de menos de 150 MB foi alcançada: a versão final apresentou 148 MB na coluna `DISK USAGE` e 35M na medição formatada exigida no enunciado.

A inspeção de `docker history` também mostrou a redução das camadas da imagem base. Na primeira versão, as principais camadas da base somavam aproximadamente 136,4 MB; na imagem Alpine final, as principais camadas da base somavam aproximadamente 56,0 MB. A diferença aproximada é de 80,4 MB nessas camadas.

Como a troca de base e a adoção do multi-stage foram feitas em conjunto, a redução total medida representa o efeito combinado das alterações, não uma medição isolada da economia de cada uma.

## 4. Validação funcional da primeira versão

A primeira versão foi executada com:

```bash
docker run -d --name loja -p 8000:8000 ufla-shop:antes
sleep 10
```

Resultados obtidos:

```text
Estado de saúde: healthy
UID do usuário: 10001
HTTP /health: 200
Resposta: {"status":"ok","versao":"1.0.0"}
Quantidade de produtos: 12
```

Os logs mostraram a inicialização da aplicação com SQLite e cache em memória, incluindo a carga inicial de 12 produtos.

O encerramento foi medido com:

```bash
time docker stop loja
```

Resultado:

```text
TEMPO_REAL=0.444 segundos
```

## 5. Validação da imagem final

A imagem final foi executada com:

```bash
docker run -d --name loja -p 8000:8000 ufla-shop:1.0
sleep 10
```

### Saúde do container

Comando:

```bash
docker inspect --format='{{.State.Health.Status}}' loja
```

Resultado:

```text
healthy
```

### Usuário não-root

Comando:

```bash
docker run --rm ufla-shop:1.0 id -u
```

Resultado:

```text
10001
```

O valor retornado é diferente de zero, confirmando que o processo do container não utiliza o usuário root.

### Endpoint `/health`

Comando:

```bash
curl -sS -o /tmp/atividade04-health-final.json \
  -w 'HTTP /health: %{http_code}\n' \
  http://localhost:8000/health

cat /tmp/atividade04-health-final.json
```

Resultado:

```text
HTTP /health: 200
{"status":"ok","versao":"1.0.0"}
```

### Catálogo de produtos

Comando:

```bash
curl -fsS http://localhost:8000/api/produtos \
  | python3 -c 'import json,sys; print("Produtos:", len(json.load(sys.stdin)))'
```

Resultado:

```text
Produtos: 12
```

### Arquivos presentes na imagem

Foi realizada uma inspeção do diretório `/app` dentro do container.

Resultado:

```text
/app
├── app/
└── static/

OK: arquivos desnecessarios ausentes
```

Os testes confirmaram que `.git`, `.env`, `tests/` e `.venv/` não estão presentes no diretório da aplicação dentro da imagem final.

### Comando de inicialização

A inspeção da configuração da imagem apresentou:

```text
USER=10001:appgroup
CMD=["uvicorn","app:api","--host","0.0.0.0","--port","8000"]
```

O `CMD` está em formato exec, com os argumentos separados em uma lista. Isso permite que o sinal de encerramento seja recebido diretamente pelo Uvicorn.

### Tempo de encerramento

Comando utilizado:

```bash
time docker stop loja
docker rm loja
```

Resultado:

```text
TEMPO_REAL=0.428 segundos
```

O tempo medido foi inferior ao limite de 2 segundos exigido no enunciado.

## 6. Por que o HEALTHCHECK usa `/health` em vez de `/ready`?

O endpoint `/health` verifica se o processo da aplicação está vivo sem consultar o banco de dados ou o cache, sendo adequado para a verificação de liveness do container. Já `/ready` verifica se o banco e o cache estão disponíveis e pode retornar HTTP 503 quando uma dependência falha, por isso é mais adequado para verificar prontidão do que vida do processo.

## 7. Conclusão

A aplicação foi containerizada com sucesso e a imagem final atingiu os requisitos técnicos medidos nesta atividade.

A versão final apresenta 148 MB de `DISK USAGE`, estado `healthy`, usuário não-root com UID `10001`, resposta HTTP 200 em `/health` e 12 produtos em `/api/produtos`. O tempo medido de encerramento foi de 0,428 segundos.

A adoção da imagem base Alpine e do build multi-stage reduziu o tamanho medido da imagem. A configuração também evita copiar arquivos de desenvolvimento e utiliza o formato exec para iniciar o Uvicorn, permitindo o encerramento rápido do container.
