# Atividade 3 — Automatizar de verdade

## 1. Objetivo

O objetivo desta atividade foi automatizar a implantação e a operação da aplicação UFLA DevOps Shop em um servidor Linux, utilizando serviços gerenciados pelo `systemd`, backup do PostgreSQL, agendamento automático e Nginx como proxy reverso com HTTPS.

A aplicação foi implantada em uma instância AWS com Ubuntu 26.04.1 LTS e Python 3.14.4.

## 2. Aplicação e testes

Antes da implantação, a aplicação foi validada em ambiente virtual Python, utilizando os testes automatizados e o Ruff.

Resultados obtidos:

- **Testes automatizados:** 21 aprovados.
- **Cobertura de código:** 82%.
- **Análise estática com Ruff:** todos os testes de lint aprovados.

Comandos utilizados:

```bash
env -u DATABASE_URL -u REDIS_URL \
    .venv/bin/python -m pytest --cov=app --cov-report=term

.venv/bin/ruff check .
```

## 3. Automação da implantação

Foi criado o script `scripts/deploy.sh` para automatizar a implantação da aplicação.

O script executa as seguintes tarefas:

- Verifica os comandos e arquivos necessários.
- Cria o usuário de sistema `ufla-shop`, caso ainda não exista.
- Copia os arquivos da aplicação para `/opt/ufla-shop`.
- Cria ou reutiliza o ambiente virtual Python e instala as dependências.
- Instala as unidades do `systemd`.
- Gera um certificado TLS autoassinado quando necessário.
- Configura e valida o Nginx.
- Habilita os serviços e o timer de backup.
- Verifica a disponibilidade da aplicação por meio do endpoint `/ready`.

Comando executado:

```bash
sudo ./scripts/deploy.sh
```

Resultado observado:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

Deploy concluído. Healthcheck HTTP 200:
{"status":"ok","banco":"ok","cache":"ok"}
```

A resposta confirma que a aplicação iniciou corretamente e que o PostgreSQL e o Redis estavam acessíveis.

## 4. Serviço systemd e recuperação automática

Foi criada a unidade `systemd/ufla-shop.service`, responsável por iniciar e supervisionar a API.

O serviço utiliza o usuário de sistema `ufla-shop`, executa a aplicação em `/opt/ufla-shop` e utiliza a configuração protegida localizada em `/etc/ufla-shop.env`.

As verificações realizadas mostraram:

```text
ufla-shop.service: active
ufla-shop.service: enabled
```

Também foi realizado um teste de recuperação, encerrando abruptamente o processo Uvicorn:

```bash
sudo kill -9 "$(pgrep -xo uvicorn)"
sleep 5
sudo systemctl status ufla-shop --no-pager
curl -sS http://127.0.0.1:8000/ready
```

Após a interrupção, o `systemd` iniciou um novo processo. O serviço voltou a ficar ativo, e o endpoint `/ready` retornou:

```json
{
  "status": "ok",
  "banco": "ok",
  "cache": "ok"
}
```

Esse resultado demonstra o funcionamento da política de reinício automático configurada com `Restart=on-failure`.

## 5. Nginx e HTTPS

Foi configurado o Nginx como proxy reverso da aplicação, encaminhando as requisições para `127.0.0.1:8000`.

A configuração inclui:

- Redirecionamento de HTTP para HTTPS.
- Certificado TLS autoassinado.
- Encaminhamento dos cabeçalhos `Host`, `X-Real-IP`, `X-Forwarded-For` e `X-Forwarded-Proto`.

Comandos utilizados:

```bash
curl -kI https://localhost
curl -I http://localhost
curl -ksS https://localhost/ready
```

O redirecionamento HTTP apresentou o resultado:

```text
HTTP/1.1 301 Moved Permanently
Location: https://localhost/
```

A consulta HTTPS com `curl -kI https://localhost` retornou `405 Method Not Allowed`, pois o comando utiliza o método HTTP HEAD e a rota principal da aplicação permite GET.

Para validar a aplicação efetivamente pelo HTTPS, foi realizada a consulta GET ao endpoint `/ready`, que retornou:

```json
{"status":"ok","banco":"ok","cache":"ok"}
```

## 6. Backup do PostgreSQL

Foi criado o script `scripts/backup.sh` para gerar backups comprimidos do banco PostgreSQL.

O script:

- Obtém a configuração do banco a partir de `/etc/ufla-shop.env`.
- Gera o backup utilizando `pg_dump` e compactação Gzip.
- Valida o arquivo compactado.
- Registra o arquivo em `/var/backups/ufla-shop`.
- Mantém os sete backups mais recentes.
- Registra a execução no log do sistema usando `logger -t backup`.

Comando utilizado:

```bash
sudo /opt/ufla-shop/scripts/backup.sh
```

Arquivos observados durante os testes:

```text
loja-2026-10-26-2141.sql.gz
loja-2026-10-26-2143.sql.gz
loja-2026-10-27-0247.sql.gz
```

Ambos foram gerados com sucesso, com tamanho aproximado de 1,6 KB cada.

O log do sistema registrou a conclusão do backup:

```text
backup: backup gerado: /var/backups/ufla-shop/loja-2026-10-26-2141.sql.gz
```

**Evidência complementar:** o enunciado solicita três execuções do backup. Até a coleta destas evidências, foram registrados dois arquivos; a terceira execução deverá ser adicionada após sua realização.

## 7. Agendamento automático do backup

Foram criadas as unidades:

- `systemd/ufla-shop-backup.service`
- `systemd/ufla-shop-backup.timer`

O serviço de backup é do tipo `oneshot`, enquanto o timer agenda a execução diária às 03:00, com `Persistent=true`.

O estado observado foi:

```text
ufla-shop-backup.timer
Loaded: loaded
Active: active (waiting)
```

A próxima execução estava programada para 27 de outubro de 2026, às 03:00 UTC.

## 8. Idempotência do deploy

O script de implantação foi executado duas vezes consecutivas:

```bash
sudo ./scripts/deploy.sh
sudo ./scripts/deploy.sh
```

As duas execuções terminaram com sucesso, retornando:

```text
Deploy concluído. Healthcheck HTTP 200:
{"status":"ok","banco":"ok","cache":"ok"}
```

Na segunda execução, as dependências já instaladas foram reconhecidas pelo `pip`, e a configuração do Nginx continuou válida.

Esse comportamento demonstra que o script pode ser executado novamente sem precisar recriar manualmente toda a infraestrutura da aplicação.

## 9. Segurança e organização

As credenciais da aplicação foram mantidas fora do repositório, no arquivo `/etc/ufla-shop.env`, com acesso restrito ao usuário root.

O certificado e a chave privada TLS são mantidos no sistema de arquivos do servidor, fora da árvore do projeto. O repositório possui regras no `.gitignore` para impedir que arquivos de ambiente, certificados e chaves sejam versionados.

A aplicação é executada por um usuário de sistema dedicado, e não diretamente pelo usuário root.

## 10. Conclusão

A implantação automatizada da UFLA DevOps Shop foi realizada com sucesso na AWS. A aplicação iniciou com PostgreSQL e Redis operacionais, o Nginx passou a encaminhar as requisições por HTTPS e o `systemd` demonstrou capacidade de recuperar o serviço após a interrupção abrupta do processo.

Os testes automatizados apresentaram 21 aprovações, com 82% de cobertura, e o Ruff não identificou problemas.

O backup PostgreSQL também foi validado, e seu agendamento diário foi habilitado. Para completar as evidências da atividade, falta registrar a terceira execução do backup e anexar sua saída à documentação.
