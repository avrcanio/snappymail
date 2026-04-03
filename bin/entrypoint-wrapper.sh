#!/bin/sh
set -eu

APP_ROOT=/var/lib/snappymail/_data_/_default_
APP_INI="${APP_ROOT}/configs/application.ini"
DOMAIN_JSON="${APP_ROOT}/domains/default.json"
ADMIN_PASSWORD_FILE="${APP_ROOT}/admin_password.txt"
INDEX_TEMPLATE="$(find /snappymail -path '*/app/templates/Index.html' | head -n 1)"

sed_escape() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

ini_bool() {
  case "${1:-false}" in
    1|true|TRUE|yes|YES|on|ON) printf 'On' ;;
    *) printf 'Off' ;;
  esac
}

json_bool() {
  case "${1:-false}" in
    1|true|TRUE|yes|YES|on|ON) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

security_type() {
  case "${1:-none}" in
    ssl|SSL|tls|TLS) printf '1' ;;
    starttls|STARTTLS) printf '2' ;;
    *) printf '0' ;;
  esac
}

forward_signal() {
  if [ -n "${main_pid:-}" ] && kill -0 "${main_pid}" 2>/dev/null; then
    kill -TERM "${main_pid}" 2>/dev/null || true
  fi
}

trap forward_signal INT TERM

if [ -n "${INDEX_TEMPLATE}" ] && grep -q 'apple-mobile-web-app-capable' "${INDEX_TEMPLATE}"; then
  sed -i 's#<meta name="apple-mobile-web-app-capable" content="yes">#<meta name="mobile-web-app-capable" content="yes">#' "${INDEX_TEMPLATE}"
  rm -rf "${APP_ROOT}/cache"/*
fi

/entrypoint.sh &
main_pid=$!

for _ in $(seq 1 60); do
  if [ -f "${APP_INI}" ]; then
    break
  fi
  sleep 1
done

if [ ! -f "${APP_INI}" ]; then
  echo "[ERROR] SnappyMail configuration was not created in time" >&2
  wait "${main_pid}"
  exit 1
fi

if [ -n "${SNAPPYMAIL_ADMIN_PASSWORD:-}" ]; then
  admin_hash="$(php -r 'echo password_hash(getenv("SNAPPYMAIL_ADMIN_PASSWORD"), PASSWORD_BCRYPT), PHP_EOL;')"
  sed -i "s/^admin_password = .*/admin_password = \"$(sed_escape "${admin_hash}")\"/" "${APP_INI}"
  printf '%s\n' "${SNAPPYMAIL_ADMIN_PASSWORD}" > "${ADMIN_PASSWORD_FILE}"
fi

sed -i "s/^title = .*/title = \"$(sed_escape "${WEBMAIL_TITLE:-SnappyMail Webmail}")\"/" "${APP_INI}"
sed -i "s/^force_https = .*/force_https = $(ini_bool "${SNAPPYMAIL_FORCE_HTTPS:-true}")/" "${APP_INI}"
sed -i "/^\\[contacts\\]/,/^\\[/ s/^enable = .*/enable = $(ini_bool "${SNAPPYMAIL_CONTACTS_ENABLE:-true}")/" "${APP_INI}"
sed -i "/^\\[contacts\\]/,/^\\[/ s/^type = .*/type = \"pgsql\"/" "${APP_INI}"
sed -i "/^\\[contacts\\]/,/^\\[/ s|^pdo_dsn = .*|pdo_dsn = \"$(sed_escape "pgsql:host=${SNAPPYMAIL_DB_HOST:-postgis};port=${SNAPPYMAIL_DB_PORT:-5432};dbname=${SNAPPYMAIL_DB_NAME:-snappymail}")\"|" "${APP_INI}"
sed -i "/^\\[contacts\\]/,/^\\[/ s/^pdo_user = .*/pdo_user = \"$(sed_escape "${SNAPPYMAIL_DB_USER:-snappymail}")\"/" "${APP_INI}"
sed -i "/^\\[contacts\\]/,/^\\[/ s/^pdo_password = .*/pdo_password = \"$(sed_escape "${SNAPPYMAIL_DB_PASSWORD:-}")\"/" "${APP_INI}"
sed -i 's/^default_domain = .*/default_domain = ""/' "${APP_INI}"
sed -i 's/^determine_user_domain = .*/determine_user_domain = Off/' "${APP_INI}"

cat > "${DOMAIN_JSON}" <<EOF
{
    "IMAP": {
        "host": "${MAIL_IMAP_HOST:-mail.finestar.hr}",
        "port": ${MAIL_IMAP_PORT:-993},
        "type": $(security_type "${MAIL_IMAP_SECURITY:-ssl}"),
        "timeout": 300,
        "shortLogin": false,
        "lowerLogin": true,
        "ssl": {
            "verify_peer": true,
            "verify_peer_name": true,
            "allow_self_signed": $(json_bool "${MAIL_ALLOW_SELF_SIGNED:-false}"),
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        }
    },
    "SMTP": {
        "host": "${MAIL_SMTP_HOST:-mail.finestar.hr}",
        "port": ${MAIL_SMTP_PORT:-587},
        "type": $(security_type "${MAIL_SMTP_SECURITY:-starttls}"),
        "timeout": 60,
        "shortLogin": false,
        "lowerLogin": true,
        "ssl": {
            "verify_peer": true,
            "verify_peer_name": true,
            "allow_self_signed": $(json_bool "${MAIL_ALLOW_SELF_SIGNED:-false}"),
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        },
        "useAuth": $(json_bool "${MAIL_SMTP_AUTH:-true}"),
        "setSender": false,
        "usePhpMail": false
    },
    "Sieve": {
        "host": "${MAIL_SIEVE_HOST:-mail.finestar.hr}",
        "port": ${MAIL_SIEVE_PORT:-4190},
        "type": $(security_type "${MAIL_SIEVE_SECURITY:-starttls}"),
        "timeout": 10,
        "shortLogin": false,
        "lowerLogin": true,
        "ssl": {
            "verify_peer": true,
            "verify_peer_name": true,
            "allow_self_signed": $(json_bool "${MAIL_ALLOW_SELF_SIGNED:-false}"),
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        },
        "enabled": $(json_bool "${MAIL_SIEVE_ENABLED:-false}")
    },
    "whiteList": ""
}
EOF

chown -R www-data:www-data /var/lib/snappymail

wait "${main_pid}"
