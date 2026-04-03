# SnappyMail stack for `webmail.finestar.hr`

Ovaj stack pokreće zaseban SnappyMail webmail u `/opt/stacks/snappymail`, iza postojećeg Traefik proxyja, bez direktnog izlaganja portova na hostu. Mail sadržaj ostaje na postojećem IMAP/SMTP backendu `mail.finestar.hr`, dok SnappyMail koristi vlastiti app storage u lokalnom bind mountu i PostgreSQL za contacts/state koje aplikacija podržava.

## Što se ovdje deploya

- `compose.yaml` za jedan SnappyMail container
- Traefik routing za `https://webmail.finestar.hr`
- lokalni bind mount `./docker-data/snappymail` za SnappyMail config/cache/runtime data
- wildcard domain konfiguracija tako da jedan SnappyMail instance prihvaća više mail domena na istom backendu
- bootstrap koji upisuje admin lozinku iz `.env` i postavlja PostgreSQL contacts storage

## Preduvjeti

- Docker i Docker Compose plugin
- postojeća eksterna Docker mreža `proxy`
- postojeća eksterna Docker mreža `postgis`
- postojeći Traefik sa resolverom iz `TRAEFIK_CERT_RESOLVER`
- DNS zapis:
  - `A webmail.finestar.hr -> 65.108.196.92`
- postojeći mail backend:
  - IMAP `mail.finestar.hr:993` preko `SSL/TLS`
  - SMTP `mail.finestar.hr:587` preko `STARTTLS`

## 1. Priprema env fajla

```bash
cp .env.example .env
```

Obavezno promijeni:

- `SNAPPYMAIL_ADMIN_PASSWORD`
- `SNAPPYMAIL_DB_PASSWORD`
- po potrebi `TRAEFIK_CERT_RESOLVER`

Preporučene vrijednosti su već podešene za:

- `WEBMAIL_HOST=webmail.finestar.hr`
- login s punim emailom, npr. `user@domena.tld`
- wildcard multi-domain backend na `mail.finestar.hr`

## 2. Priprema PostgreSQL baze

Primjer s postojećim Docker PostGIS containerom `postgis`:

```bash
docker exec -it postgis psql -U postgres -d postgres -c "CREATE USER snappymail WITH PASSWORD 'change-this-db-password';"
docker exec -it postgis psql -U postgres -d postgres -c "CREATE DATABASE snappymail OWNER snappymail;"
```

Ako koristiš druge kredencijale ili drugi DB container, uskladi `.env`.

## 3. Pokretanje

```bash
docker compose up -d
```

Status:

```bash
docker compose ps
docker compose logs -f snappymail
```

## 4. Admin bootstrap

Admin panel je dostupan na:

- `https://webmail.finestar.hr/?admin`

Ovaj stack pri startu upisuje vrijednost `SNAPPYMAIL_ADMIN_PASSWORD` u SnappyMail config i u lokalni bootstrap file:

- `./docker-data/snappymail/_data_/_default_/admin_password.txt`

Prvi admin login koristi lozinku iz `.env`, a ne slučajno generiranu vrijednost.

Nakon prve prijave obavezno provjeri:

- `Security -> Admin Panel Access Credentials`
- `Contacts -> Storage configuration`
- `Domains`

## 5. Multi-domain model

Stack generira wildcard domain konfiguraciju (`*`) koja sve mail domene šalje na isti backend:

- IMAP host: `mail.finestar.hr`
- SMTP host: `mail.finestar.hr`
- korisnički login: puni email

To znači da dodavanje novog mailboxa ili nove domene na postojećem mailserveru ne traži novu promjenu u ovom repo-u, dokle god:

- mailbox postoji na `docker-mailserver` backendu
- IMAP/SMTP autentikacija radi s punim emailom
- nova domena koristi isti backend i iste portove

Ako kasnije želiš ograničiti pristup samo na neke domene ili dodati domenski specifične postavke, uradi to kroz SnappyMail admin panel pod `Domains`.

## 6. Backup i restore

Backup treba obuhvatiti:

- lokalni app data:

```bash
tar -czf snappymail-data-$(date +%F).tar.gz docker-data/snappymail
```

- PostgreSQL bazu:

```bash
docker exec postgis pg_dump -U "${SNAPPYMAIL_DB_USER}" "${SNAPPYMAIL_DB_NAME}" > snappymail-db-$(date +%F).sql
```

Restore radi obrnutim redoslijedom: vratiti bind mount data i zatim obnoviti bazu.

## 7. Operativne napomene

- SnappyMail ne sprema mail sadržaj lokalno; poruke ostaju na IMAP serveru.
- PostgreSQL se ovdje koristi za contacts/state koje SnappyMail podržava, ne za samu poštu.
- Stack nije spojen na `mailserver_default`; prema mail backendu ide preko javnog FQDN-a `mail.finestar.hr`.
- Nema novih bindanih host portova i nema promjena na postojećem `mailserver` stacku.

## 8. Test plan

DNS i web:

- `webmail.finestar.hr` resolvea na server IP
- Traefik servira TLS cert za `webmail.finestar.hr`
- `https://webmail.finestar.hr` otvara login screen

Mail:

- login s `avrcan@finestar.hr`
- login s još jednim mailboxom druge domene ili drugog korisnika
- pregled postojećih IMAP foldera i poruka
- slanje maila prema vanjskoj adresi
- primitak nove poruke i refresh inboxa

Admin:

- login na `/?admin` s lozinkom iz `.env`
- admin lozinka nije default/random
- contacts storage test prolazi s PostgreSQL parametrima
- postavke prežive restart containera
