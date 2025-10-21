#!/usr/bin/env bash
# recon.sh - Recon automation minimal, modular and conservative.
# Uso: ./recon.sh example.com
# Autor: (você) - adaptado por ChatGPT
# IMPORTANTE: execute somente contra alvos autorizados.

set -euo pipefail
IFS=$'\n\t'

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Uso: $0 dominio.tld"
  exit 2
fi

OUTDIR="./recon_${DOMAIN}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUTDIR}"
echo "[*] Output em ${OUTDIR}"

# Config
CRT_SH_URL="https://crt.sh/?q=%25.${DOMAIN}&output=json"
USER_AGENT="Mozilla/5.0 (recon-script/1.0)"
NMAP_TOPPORTS="-F"            # -F = fast (top ports). Alterar se quiser scans mais completos
NMAP_EXTRA_ARGS="-sV -Pn --open --min-rate 1000"  # cuidado com min-rate; ajuste conforme necessário
MAX_CONCURRENT_RESOLVERS=25
TIMEOUT_CURL=20

log() { echo "[$(date +'%H:%M:%S')] $*"; }

################################
# Funções utilitárias
################################
safe_curl() {
  # $1 = url, $2 = out file
  curl -sS -m "${TIMEOUT_CURL}" -A "${USER_AGENT}" "$1" -o "$2" || return $?
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

################################
# 1) Passive: crt.sh
################################
log "1) Passive: consultando crt.sh..."
TMP_CRT="${OUTDIR}/crt_raw.json"
safe_curl "${CRT_SH_URL}" "${TMP_CRT}" || log "curl falhou ao baixar crt.sh (ok, continuando)"
# limpa garbage e extrai name_value / common_name
if [ -s "${TMP_CRT}" ]; then
  # tenta jq
  if command_exists jq; then
    # Extrai campos e normaliza
    jq -r '.[]?.name_value? // .[]?.common_name? // empty' "${TMP_CRT}" \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/\*\.//g' \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
      | sort -u > "${OUTDIR}/subdomains_crt.txt" || true
    log "crt.sh salvo em ${OUTDIR}/subdomains_crt.txt"
  else
    log "jq não instalado — salvando resposta bruta em ${TMP_CRT}"
  fi
else
  log "crt.sh não retornou conteúdo."
fi

################################
# 2) Passive: other tools if installed (amass/subfinder)
################################
if command_exists amass; then
  log "2) Rodando amass (passive)..."
  amass enum -passive -d "${DOMAIN}" -o "${OUTDIR}/subdomains_amass.txt" || log "amass encerrou com erro"
fi

if command_exists subfinder; then
  log "2) Rodando subfinder (passive)..."
  subfinder -d "${DOMAIN}" -silent -o "${OUTDIR}/subfinder.txt" || log "subfinder erro"
fi

################################
# 3) Consolidar subdomínios
################################
log "3) Consolidando fontes de subdomínios..."
cat ${OUTDIR}/subdomains_crt.txt 2>/dev/null || true \
  > "${OUTDIR}/all_subs_raw.txt"

for f in "${OUTDIR}"/subdomains_* 2>/dev/null; do
  if [ -f "$f" ]; then
    cat "$f" >> "${OUTDIR}/all_subs_raw.txt"
  fi
done

# fallback: se vazio, usa o dominio raiz
if [ ! -s "${OUTDIR}/all_subs_raw.txt" ]; then
  echo "${DOMAIN}" > "${OUTDIR}/all_subs_raw.txt"
fi

# normalizar e deduplicar
cat "${OUTDIR}/all_subs_raw.txt" \
  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/\*\.//g' \
  | sort -u > "${OUTDIR}/subdomains_all.txt"

log "Total subdomínios agregados: $(wc -l < "${OUTDIR}/subdomains_all.txt")"

################################
# 4) Resolver subdomínios (DNS) - paralelo leve
################################
log "4) Resolvendo subdomínios (DNS)..."
RESOLVED="${OUTDIR}/resolved.txt"
> "${RESOLVED}"

resolve_one() {
  host="$1"
  # tenta dig + short; se não instalado, usa getent
  if command_exists dig; then
    ips=$(dig +short "$host" A)
    if [ -z "$ips" ]; then
      ips=$(dig +short "$host" AAAA)
    fi
  elif command_exists getent; then
    ips=$(getent hosts "$host" | awk '{print $1}')
  else
    # fallback ping (não ideal)
    ips=""
  fi
  if [ -n "$ips" ]; then
    echo "${host} ${ips}" >> "${RESOLVED}"
  fi
}

export -f resolve_one
export RESOLVED
export -f log

# concurrency control using xargs -P
cat "${OUTDIR}/subdomains_all.txt" | xargs -I{} -n1 -P ${MAX_CONCURRENT_RESOLVERS} bash -c 'resolve_one "$@"' _ {}

log "Resolução completa. Salvo em ${RESOLVED} (linhas: $(wc -l < "${RESOLVED}" || echo 0))"

################################
# 5) HTTP probing (httpx if presente) and collecting alive hosts
################################
log "5) HTTP probing..."
ALIVE="${OUTDIR}/alive_http.txt"
> "${ALIVE}"

if command_exists httpx; then
  # httpx melhor porque detecta TLS e retorna status
  httpx -l "${OUTDIR}/subdomains_all.txt" -silent -timeout 10 -o "${ALIVE}" || true
  log "httpx completou, arquivo: ${ALIVE}"
else
  # fallback simples: curl head
  while read -r host; do
    for scheme in http https; do
      url="${scheme}://${host}"
      if curl -sS -I --max-time 8 -A "${USER_AGENT}" "${url}" >/dev/null 2>&1; then
        echo "${url}" >> "${ALIVE}"
        break
      fi
    done
  done < "${OUTDIR}/subdomains_all.txt"
  log "Probe HTTP simples completo, arquivo: ${ALIVE}"
fi

################################
# 6) Port scan (nmap) - opcional e controlado
################################
log "6) Port scan (nmap) para hosts vivos (modo rápido)."
NMAP_OUT="${OUTDIR}/nmap"
mkdir -p "${NMAP_OUT}"

if command_exists nmap; then
  # pegar IPs únicos dos resolved ou hosts vivos
  cut -d' ' -f2- "${RESOLVED}" 2>/dev/null | tr ' ' '\n' | sort -u > "${OUTDIR}/ips_all.txt" || true
  # fallback: se empty, tenta extrair do alive_http
  if [ ! -s "${OUTDIR}/ips_all.txt" ] && [ -s "${ALIVE}" ]; then
    awk -F/ '{print $3}' "${ALIVE}" | sed 's/:.*$//' | sort -u > "${OUTDIR}/ips_all.txt"
  fi

  if [ -s "${OUTDIR}/ips_all.txt" ]; then
    log "IPs para scan: $(wc -l < "${OUTDIR}/ips_all.txt")"
    # varrer cada IP em modo rápido
    while read -r ip; do
      safe_out="${NMAP_OUT}/${ip}.nmap"
      log "nmap ${ip} -> ${safe_out}"
      nmap ${NMAP_TOPPORTS} ${NMAP_EXTRA_ARGS} -oN "${safe_out}" "${ip}" || log "nmap erro em ${ip}"
    done < "${OUTDIR}/ips_all.txt"
  else
    log "Nenhum IP encontrado para scannear."
  fi
else
  log "nmap não está instalado — pulando etapa de port-scan."
fi

################################
# 7) Web enumeration: robots, headers, title snapshot (simples)
################################
log "7) Web enum básica (robots, headers, titles) para hosts HTTP vivos"
WEB_ENUM_DIR="${OUTDIR}/web_enum"
mkdir -p "${WEB_ENUM_DIR}"
if [ -s "${ALIVE}" ]; then
  while read -r url; do
    hostsafe=$(echo "$url" | sed 's/[^a-zA-Z0-9._-]/_/g')
    # robots
    curl -sS --max-time 8 -A "${USER_AGENT}" "${url%/}/robots.txt" -o "${WEB_ENUM_DIR}/${hostsafe}_robots.txt" || true
    # headers
    curl -sSI --max-time 8 -A "${USER_AGENT}" "${url}" -o "${WEB_ENUM_DIR}/${hostsafe}_headers.txt" || true
    # title
    curl -sS --max-time 8 -A "${USER_AGENT}" "${url}" | sed -n '1,300p' | grep -i -m1 "<title" > "${WEB_ENUM_DIR}/${hostsafe}_title.html" || true
  done < "${ALIVE}"
  log "Web enum salva em ${WEB_ENUM_DIR}"
else
  log "Nenhum host HTTP vivo detectado, pulando web enum."
fi

################################
# 8) Relatório simples
################################
REPORT="${OUTDIR}/report_summary.txt"
echo "Recon report - ${DOMAIN}" > "${REPORT"
echo "Generated: $(date -u)" >> "${REPORT}"
echo "" >> "${REPORT}"
echo "Subdomínios agregados: $(wc -l < "${OUTDIR}/subdomains_all.txt")" >> "${REPORT}"
echo "Subdomínios resolvidos: $(wc -l < "${RESOLVED}" || echo 0)" >> "${REPORT}"
echo "Hosts HTTP vivos: $(wc -l < "${ALIVE}" || echo 0)" >> "${REPORT}"
echo "IPs listados: $(wc -l < "${OUTDIR}/ips_all.txt" 2>/dev/null || echo 0)" >> "${REPORT}"
echo "" >> "${REPORT}"
echo "Arquivos gerados:" >> "${REPORT}"
ls -1 "${OUTDIR}" | sed 's/^/ - /' >> "${REPORT}"

log "Relatório resumido gerado em ${REPORT}"
log "Recon concluído. Diretório: ${OUTDIR}"
