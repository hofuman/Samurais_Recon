# Recon Tool — `recon.sh`

> Ferramenta modular e prática para automação das etapas iniciais de reconnaissance em testes de penetração.

**Aviso legal:** execute esta ferramenta **somente** em alvos que você tem autorização explícita. Scans sem permissão são ilegais e podem causar danos.

---

## Sumário

* [O que é](#o-que-é)
* [Funcionalidades principais](#funcionalidades-principais)
* [Instalação rápida](#instalação-rápida)
* [Como usar](#como-usar)
* [Saída gerada](#saída-gerada)
* [Configuração e variáveis importantes](#configuração-e-variáveis-importantes)
* [Dependências recomendadas](#dependências-recomendadas)
* [Boas práticas](#boas-práticas)
* [Extensões e integração](#extensões-e-integração)
* [Contribuição e licença](#contribuição-e-licença)
* [Solução de problemas comuns](#solução-de-problemas-comuns)

---

## O que é

`recon.sh` é um **script Bash** que automatiza coleta passiva (certificados, ferramentas de subdomain discovery), validação/normalização de subdomínios, resolução DNS, probe HTTP e scans rápidos de portas. Foi projetado para ser:

* leve e portátil (um arquivo);
* seguro por padrão (timeouts, modo rápido);
* fácil de estender (hooks para APIs e ferramentas).

---

## Funcionalidades principais

* Coleta passiva via `crt.sh` (JSON) e integração opcional com `amass`/`subfinder`;
* Consolidação e deduplicação de subdomínios;
* Resolução DNS paralela (usando `dig`/`getent`);
* HTTP probing com `httpx` ou `curl` como fallback;
* Scan rápido com `nmap` (opcional e configurável);
* Enumeração web básica: `robots.txt`, headers e título das páginas;
* Relatório resumido e diretório de saída por execução.

---

## Instalação rápida

1. Copie `recon.sh` para sua máquina.
2. Dê permissão de execução:

```bash
chmod +x recon.sh
```

3. (Opcional) Instale dependências recomendadas (ex.: `jq`, `nmap`, `httpx`).

Instalação rápida em Debian/Ubuntu:

```bash
sudo apt update && sudo apt install -y curl jq dnsutils nmap
# Ferramentas adicionais via go (requer go instalado):
# go install github.com/projectdiscovery/httpx/cmd/httpx@latest
# go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
```

---

## Como usar

Execute contra um domínio autorizado:

```bash
./recon.sh example.com
```

O script criará um diretório `recon_example.com_YYYYMMDD_HHMMSS` com todos os artefatos.

---

## Saída gerada (exemplo)

* `subdomains_all.txt` — subdomínios agregados
* `resolved.txt` — subdomínios com IPs
* `alive_http.txt` — URLs HTTP(S) detectadas
* `nmap/` — saída do nmap por IP
* `web_enum/` — robots, headers, title snapshots
* `report_summary.txt` — resumo da execução

---

## Configuração e variáveis importantes

Edite o topo do script para ajustar comportamento:

* `NMAP_TOPPORTS` — parâmetros para nmap (`-F` é rápido)
* `NMAP_EXTRA_ARGS` — argumentos extras do nmap (ex.: `-sV -Pn`)
* `MAX_CONCURRENT_RESOLVERS` — concorrência de resolução DNS
* `TIMEOUT_CURL` — timeout do curl

Ajuste esses valores ao escopo e à sensibilidade da rede alvo.

---

## Dependências recomendadas

* `curl`, `jq`, `dig`/`dnsutils`
* `nmap` (scans)
* `httpx` (probe HTTP)
* `amass`, `subfinder` (descoberta passiva adicional)
* `waybackurls`, `gau` (enumeração de conteúdo histórico)

---

## Boas práticas

* Obtenha **autorização por escrito** (escopo, IPs/hosts permitidos).
* Priorize coleta passiva antes de qualquer scan ativo.
* Evite scans agressivos em horários de pico.
* Registre timestamps, comandos executados e evidências.
* Use uma máquina isolada e mantenha backups dos artefatos.

---

## Extensões e integração

Ideias de melhorias:

* Adicionar módulos para APIs (Censys, Shodan, VirusTotal, CertSpotter);
* Suporte a proxies/Tor e configuração via variáveis de ambiente;
* Portar para Python/async para melhor performance e controle;
* Produzir saída em JSON/CSV para integração com pipelines CI/ELK.

---

## Contribuição e licença

Contribuições são bem-vindas: abra *issues* e *pull requests*.
Recomenda-se usar MIT (ou outra licença permissiva). Inclua `LICENSE` no repositório.

---

## Solução de problemas comuns

* `jq: parse error` ao consultar `crt.sh`: verifique a saída bruta (`curl -s "https://crt.sh/?q=%25.example.com&output=json" | sed -n '1,40p'`) — pode ser HTML (captcha/rate limit). O script contém limpeza básica; em caso de persistência, cole as primeiras linhas para análise.
* `subdomains_all.txt` vazio: verifique se `amass`/`subfinder` estão instalados ou se o domínio possui dados públicos.
* `nmap` muito lento: use `-F` ou remova `--min-rate`/ajuste argumentos.

---

Se quiser, eu também:

* adiciono `CONTRIBUTING.md` e `CHANGELOG.md`;
* gero o arquivo `LICENSE` (MIT) pronto;
* traduzo o README para inglês;
* crio um `Makefile`/scripts para instalar dependências.

Me diga quais desses quer que eu gere agora.
