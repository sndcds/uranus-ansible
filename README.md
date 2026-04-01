# Uranus Ansible

Ansible-Setup zum lokalen Provisionieren und Konfigurieren einer kleinen Uranus-Umgebung auf einem KVM/libvirt-Host.

Das Repository baut mehrere Ubuntu-VMs, verteilt Rollen je Host und konfiguriert darauf:

- PostgreSQL/PostGIS auf `db01`
- Uranus Backend und Frontend auf `dev01` und `prod01`
- Monitoring auf `mon01`
- Nominatim mit Schleswig-Holstein-Extrakt auf `nom01`

Die Umgebung ist auf einen lokalen Einzelhost mit libvirt-NAT ausgelegt. Aktuell sind die VM-RAM-Werte auf einen Host mit 16 GB RAM abgestimmt.

## Überblick

Die Umgebung besteht standardmäßig aus fünf VMs:

| VM | Rolle | RAM | Disk | CPU |
| --- | --- | ---: | ---: | ---: |
| `db01` | PostgreSQL/PostGIS | 2048 MB | 80 GB | 4 |
| `dev01` | Dev-Frontend + Dev-Backend | 2048 MB | 80 GB | 4 |
| `prod01` | Prod-Frontend + Prod-Backend | 4096 MB | 120 GB | 4 |
| `mon01` | Monitoring | 2048 MB | 40 GB | 2 |
| `nom01` | Nominatim | 4096 MB | 200 GB | 6 |

VM-Definitionen stehen in `vars.yml`.

## Domains

Verwendet werden lokale Domains unter `home.arpa`:

| Host | Domain(s) |
| --- | --- |
| `dev01` | `dev.uranus.home.arpa`, `api.dev.uranus.home.arpa` |
| `prod01` | `uranus.home.arpa`, `api.uranus.home.arpa`, `mail.uranus.home.arpa` |
| `mon01` | `monitoring.uranus.home.arpa` |
| `nom01` | `nominatim.uranus.home.arpa` |

Die Basiswerte stehen in `group_vars/all.yml`, die host-spezifischen Zuweisungen in `host_vars/`.

Damit diese Domains vom Laptop oder einem anderen Gerät im LAN erreichbar sind, zeigt die neue KVM-Ingress-Konfiguration alle Domains auf den KVM-Host. Auf dem Laptop brauchst du passende Einträge in `/etc/hosts` oder lokales DNS, die auf `192.168.1.118` zeigen:

```hosts
192.168.1.118 dev.uranus.home.arpa api.dev.uranus.home.arpa
192.168.1.118 uranus.home.arpa api.uranus.home.arpa
192.168.1.118 monitoring.uranus.home.arpa
192.168.1.118 nominatim.uranus.home.arpa
```

Der KVM-Host terminiert dabei TLS mit lokalen Test-Zertifikaten und leitet die Requests intern an die jeweils aktuellen VM-IP-Adressen aus `inventory/runtime_hosts.yml` weiter.

## Architektur

### Provisioning

Das Provisioning läuft lokal auf dem KVM-Host über `uvtool` und libvirt:

- `playbooks/provision.yml` installiert KVM/libvirt, erzeugt das libvirt-NAT-Netz und erstellt die VMs
- die Provisionierung markiert die libvirt-Domains außerdem als `autostart`, damit sie nach einem Host-Neustart wieder hochkommen
- anschließend werden die per DHCP vergebenen IPs in `inventory/runtime_hosts.yml` geschrieben

Wichtige Templates:

- `templates/libvirt-bridge.xml.j2`
- `templates/user-data.config.j2`
- `templates/runtime-inventory.yml.j2`

### Konfiguration

Die Konfiguration läuft in `playbooks/configure.yml`:

- Host-spezifische Variablen werden aus `host_vars/<hostname>.yml` geladen
- je nach `vm_role` werden Rollen eingebunden

Reihenfolge grob:

1. `postgresql` auf `db01`
2. `common`
3. `ufw`
4. `logrotate`
5. `backup` auf `db01`, `dev01` und `prod01`
6. `certbot`
7. `nginx`
8. `app_backend`
9. `app_frontend`
10. `postfix`
11. `monitoring`
12. `nominatim`

## Pluto-Metriken

Auf `mon01` läuft zusätzlich InfluxDB für einfache Zeitreihen der Pluto-Bilddateien aus den Backend-VMs.

- `dev01` und `prod01` zählen stündlich die Dateien unter `/opt/uranus/backend/pluto/images`
- die Werte werden als Measurement `pluto_image_files` nach InfluxDB auf `mon01` geschrieben
- Beispielabfrage auf `mon01`: `influx -database uranus_metrics -execute 'SELECT last(file_count) FROM pluto_image_files GROUP BY host'`
- Grafana läuft zusätzlich unter `https://monitoring.uranus.home.arpa/grafana/`
- das Dashboard `Uranus Pluto Images` wird automatisch provisioniert

Die frühere Test-Rolle ist absichtlich nicht mehr im Hauptablauf eingebunden.

## Verzeichnisstruktur

```text
.
├── ansible.cfg
├── group_vars/
├── host_vars/
├── inventory/
├── playbooks/
├── roles/
├── templates/
├── uranus.sql
└── vars.yml
```

Wichtige Dateien:

- `ansible.cfg`: zentrale Ansible-Konfiguration
- `vars.yml`: VM-Layout, Provisioning-Defaults, lokaler Testmodus
- `group_vars/all.yml`: globale Domänen, Versionsstände und nicht-sensitive Default-Variablen
- `group_vars/vault.yml`: lokale Secrets und Passwörter, nicht im Repo versionieren
- `group_vars/vault.yml.example`: Beispielstruktur für Secrets
- `host_vars/db01.yml`: Datenbank-Setup
- `host_vars/dev01.yml`: Dev-App-Setup
- `host_vars/prod01.yml`: Prod-App-Setup
- `uranus.sql`: importierter Datenbank-Dump

## Voraussetzungen

Auf dem Host:

- Linux-System mit KVM/libvirt
- Virtualisierung im BIOS/UEFI aktiviert
- Ansible installiert
- SSH-Key unter `~/.ssh/id_rsa` und `~/.ssh/id_rsa.pub`
- `sudo` für lokale Installation und Remote-Konfiguration

Das Repository geht davon aus, dass du lokal als libvirt/KVM-Admin arbeitest und die VMs über das Standard-libvirt-Netz `192.168.122.0/24` laufen.

## Wichtige Variablen

### Secrets

Sensitive Werte sollen nicht mehr in `group_vars/all.yml`, `host_vars/` oder `vars.yml` im Klartext gepflegt werden.

Stattdessen:

1. `group_vars/vault.yml.example` nach `group_vars/vault.yml` kopieren
2. echte Werte in `group_vars/vault.yml` setzen
3. optional `group_vars/vault.yml` mit `ansible-vault encrypt` verschlüsseln

`group_vars/vault.yml` ist in `.gitignore` eingetragen und wird von `playbooks/provision.yml` sowie `playbooks/configure.yml` optional geladen.

Beispiel:

```bash
cp group_vars/vault.yml.example group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
```

### Ansible Vault nutzen

Typischer Ablauf:

1. Datei aus der Vorlage erzeugen
2. Secrets eintragen
3. Datei mit `ansible-vault` verschlüsseln
4. Playbooks mit Vault-Passwort ausführen

Befehle:

```bash
cp group_vars/vault.yml.example group_vars/vault.yml
ansible-vault edit group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
```

Wenn die Datei bereits verschlüsselt ist:

```bash
ansible-vault edit group_vars/vault.yml
ansible-vault view group_vars/vault.yml
ansible-vault decrypt group_vars/vault.yml
```

Playbooks mit Vault-Passwort starten:

```bash
ansible-playbook -i inventory.ini playbooks/db01.yml --ask-vault-pass
ansible-playbook -i inventory.ini playbooks/site.yml --ask-vault-pass
```

### Backup

Backups werden aktuell lokal auf den jeweiligen VMs unter `backup_root` geschrieben. Standard ist:

```yaml
backup_root: /var/backups/uranus
```

Auf `db01` legt die Rolle tägliche PostgreSQL-Dumps unter `db/` ab:

- `/var/backups/uranus/db/uranus_dev_<timestamp>.sql`
- `/var/backups/uranus/db/uranus_prod_<timestamp>.sql`

Auf `dev01` und `prod01` legt die Rolle tägliche Archiv-Backups unter `app/` ab:

- `/var/backups/uranus/app/dev01_<timestamp>.tar.gz`
- `/var/backups/uranus/app/prod01_<timestamp>.tar.gz`

Gesichert werden dabei standardmäßig:

- `/etc/nginx`
- `/etc/uranus`
- `/opt/uranus/frontend/dist`
- `/opt/uranus/backend/bin`
- `/opt/uranus/backend/profile_images`
- `/opt/uranus/backend/pluto/images`
- `/opt/uranus/backend/pluto/cache`

Die Aufbewahrung steuert `backup_retention_days` in `group_vars/all.yml`. Standard ist `14` Tage.

Die Backups laufen per Systemd-Timer:

- `uranus-db-backup.timer` auf `db01`
- `uranus-app-backup.timer` auf `dev01` und `prod01`

Manuell auslösen:

```bash
sudo systemctl start uranus-db-backup.service
sudo systemctl start uranus-app-backup.service
```

Wenn du die Sicherungen nicht nur lokal auf den VMs, sondern zentral auf `db01` oder off-host ablegen willst, musst du zusätzlich einen zweiten Kopierschritt mit `rsync`, `restic` oder einem NAS/SFTP-Ziel ergänzen.

## Mail

`dev01` und `prod01` nutzen Postfix nur als ausgehenden SMTP-Relay. Ein vollständiger Mailserver mit Mailboxen, IMAP/POP3 oder eingehender MX-Zustellung ist nicht eingerichtet.

Die Postfix-Rolle zieht ihre Relay-Daten standardmäßig aus diesen Variablen:

- `backend_smtp_host`
- `backend_smtp_port`
- `backend_smtp_login`
- `backend_smtp_password`

Darauf aufbauend werden automatisch gesetzt:

- `postfix_relay_host`
- `postfix_relay_port`
- `postfix_relay_login`
- `postfix_relay_password`

Wenn du für Postfix andere Zugangsdaten als für das Backend verwenden willst, kannst du die `postfix_relay_*`-Werte separat überschreiben.

Die sensiblen SMTP-Passwörter gehören in `group_vars/vault.yml`.

Wenn der Relay konfiguriert ist, richtet die Rolle zusätzlich `rsyslog` ein und schreibt Postfix-Logs nach:

```text
/var/log/mail.log
```

Nützliche Befehle auf `dev01` oder `prod01`:

```bash
sudo tail -f /var/log/mail.log
sudo journalctl -u postfix -f
postqueue -p
```

## Firewall

Die UFW-Basis ist auf allen VMs aktiv mit `deny incoming` und `allow outgoing`.

Zusätzlich gilt aktuell:

- SSH ist auf die Netze in `ssh_allowed_networks` begrenzt
- HTTP und HTTPS sind nur auf Web-VMs mit Rollen aus `web_exposed_vm_roles` offen
- `db01` öffnet PostgreSQL nur für `postgresql_allowed_networks`
- der Backend-Port `9090` ist nur lokal auf `127.0.0.1` freigegeben
- eingehendes NTP ist nicht freigeschaltet

Die wichtigsten Härtungs-Variablen stehen in `group_vars/all.yml`:

- `ssh_allowed_networks`
- `web_exposed_vm_roles`
- `ufw_logging`

Auf `db01` ist PostgreSQL zusätzlich enger gebunden und lauscht nicht mehr auf allen Interfaces, sondern nur auf `localhost` und der internen VM-IP.

Alternativ mit Passwortdatei:

```bash
ansible-playbook -i inventory.ini playbooks/site.yml --vault-password-file .vault_pass.txt
```

Wichtig:

- `group_vars/vault.yml` wird optional geladen, muss für echte Deployments aber vorhanden sein
- `group_vars/vault.yml` sollte nicht unverschlüsselt im Dateisystem liegen bleiben
- die Beispiel-Datei `group_vars/vault.yml.example` dient nur als Strukturvorlage

### `vars.yml`

Besonders relevant:

- `local_test_mode`
- `create_vms`
- `recreate_existing_vms`
- `ssh_public_key_file`
- `ssh_private_key_file`
- `uvt_release`
- `vms`

`local_test_mode: true` bedeutet aktuell:

- VMs werden lokal mit `uvt-kvm` erstellt
- die Nginx-VHosts für Frontend/Backend leiten HTTP auf HTTPS um

### `group_vars/all.yml`

Besonders relevant:

- `uranus_domains`
- `frontend_repo_url`, `frontend_repo_version`
- `backend_repo_url`, `backend_repo_version`
- `backend_go_version`
- `backend_db_schema`
- `nominatim_*`

Secrets in dieser Datei sind jetzt nur noch Referenzen auf `vault_*`-Variablen.

### `host_vars/db01.yml`

Hier wird die Mehrfach-DB-Konfiguration definiert:

```yaml
app_databases:
  - name: uranus_dev
    user: uranus_dev
    password: "{{ vault_db_password_dev }}"
  - name: uranus_prod
    user: uranus_prod
    password: "{{ vault_db_password_prod }}"
```

Zusätzlich:

- `db_schema: "uranus"`
- `postgresql_listen_addresses: "*"`
- `postgresql_allowed_networks`

### `host_vars/dev01.yml` und `host_vars/prod01.yml`

Dev und Prod verwenden jeweils eigene Datenbanken:

- `dev01` -> `uranus_dev` / `uranus_dev`
- `prod01` -> `uranus_prod` / `uranus_prod`

Die zugehörigen Passwörter kommen aus `group_vars/vault.yml`.

## Datenbanken

Aktuell werden auf `db01` getrennte Datenbanken für Dev und Prod angelegt:

- `uranus_dev`
- `uranus_prod`

Die PostgreSQL-Rolle:

- legt die Benutzer an
- legt die Datenbanken an
- aktiviert PostGIS
- importiert den SQL-Dump in jede Datenbank
- setzt Grants auf Schema, Tabellen und Sequenzen
- schreibt `pg_hba.conf` für die internen Netze

Wichtig: Für Nominatim gibt es zusätzlich eine separate Datenbank:

- `nominatim`

Diese wird nicht durch die generische PostgreSQL-Rolle importiert, sondern von der Nominatim-Rolle vorbereitet und während des Nominatim-Imports verwendet.

## Nominatim

`nom01` ist auf den Schleswig-Holstein-Extrakt von Geofabrik ausgelegt:

- Quelle: `https://download.geofabrik.de/europe/germany/schleswig-holstein-latest.osm.pbf`
- Importstil: `address`
- API-Host: `nominatim.uranus.home.arpa`

Wichtiges Verhalten:

- Nominatim läuft auf `nom01`
- die Datenbank dafür liegt auf `db01`
- PostgreSQL-Port `5432` ist nur im internen VM-Netz freigeschaltet, nicht öffentlich

## Backup

Die Backup-Rolle auf `db01` erzeugt ein tägliches Dump-Backup aller in `app_databases` gelisteten Datenbanken nach:

- `/var/backups/uranus`

Gesichert werden aktuell:

- `uranus_dev`
- `uranus_prod`

## Playbooks

### Gesamter Lauf

```bash
ansible-playbook -i inventory.ini playbooks/site.yml
```

Das läuft nur sauber, wenn Provisioning und nachgelagerte Rollen keine Zwischenfehler erzeugen.

### Einzelne VMs

```bash
ansible-playbook -i inventory.ini playbooks/db01.yml
ansible-playbook -i inventory.ini playbooks/dev01.yml
ansible-playbook -i inventory.ini playbooks/prod01.yml
ansible-playbook -i inventory.ini playbooks/mon01.yml
ansible-playbook -i inventory.ini playbooks/nom01.yml
```

Sobald `inventory/runtime_hosts.yml` geschrieben ist, ist dieses Inventory für Konfigurationsläufe meist praxisnäher:

```bash
ansible-playbook -i inventory/runtime_hosts.yml playbooks/db01.yml
ansible-playbook -i inventory/runtime_hosts.yml playbooks/dev01.yml
```

## Typische Reihenfolge für einen frischen lokalen Aufbau

1. `group_vars/vault.yml.example` nach `group_vars/vault.yml` kopieren und echte Secrets eintragen.
2. Optional `/etc/hosts` für die `*.home.arpa`-Domains ergänzen.
3. `db01` provisionieren und konfigurieren.
4. `dev01` und `prod01` provisionieren und konfigurieren.
5. `mon01` provisionieren und konfigurieren.
6. `nom01` provisionieren und konfigurieren.

Pragmatisch:

```bash
ansible-playbook -i inventory.ini playbooks/db01.yml
ansible-playbook -i inventory/runtime_hosts.yml playbooks/dev01.yml
ansible-playbook -i inventory/runtime_hosts.yml playbooks/prod01.yml
ansible-playbook -i inventory/runtime_hosts.yml playbooks/nom01.yml
```

## SSH-Zugriff auf VMs

Die IPs stehen nach dem Provisionieren in `inventory/runtime_hosts.yml`.

Beispiel:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@192.168.122.22
ssh -i ~/.ssh/id_rsa ubuntu@192.168.122.237
ssh -i ~/.ssh/id_rsa ubuntu@192.168.122.249
```

Mit funktionierender Host-Auflösung auch per Domain, z. B.:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@dev.uranus.home.arpa
```

## Zugriff auf Dienste

Bei `local_test_mode: true` erzwingen die Nginx-VHosts für Frontend und Backend HTTPS.

Typische URLs:

- `https://dev.uranus.home.arpa/`
- `https://api.dev.uranus.home.arpa/`
- `https://uranus.home.arpa/`
- `https://api.uranus.home.arpa/`
- `https://monitoring.uranus.home.arpa/`
- `https://nominatim.uranus.home.arpa/`

## Bekannte Besonderheiten

### 1. Backend-Startup-Check ist aktuell entschärft

Die Rolle `roles/app_backend/tasks/main.yml` patcht nach dem Checkout den Upstream-Backend-Code, um einen fehlschlagenden `CheckAllDatabaseConsistency(...)`-Startup-Check zu deaktivieren.

Grund:

- der aktuelle Dump und der erwartete Tabellenzustand des Backends passen nicht sauber zusammen
- ohne diesen Patch crasht der Dienst beim Start

Das ist eine bewusste pragmatische Deploy-Korrektur, kein idealer Upstream-Fix.

### 2. Der SQL-Dump wird beim Import umgeschrieben

Die PostgreSQL-Rolle normalisiert den Dump vor dem Import:

- `CREATE SCHEMA uranus;` -> `CREATE SCHEMA IF NOT EXISTS uranus;`
- alle `uranus.`-Referenzen -> `uranus.`
- `OWNER TO oklab`-Statements werden entfernt

Grund:

- der Dump stammt offenbar aus einer anderen Umgebung
- Schema- und Ownership-Metadaten passen nicht 1:1 auf das Zielsystem

### 3. Frontend/Backend-Tests laufen nicht automatisch

Die frühere Test-Rolle ist absichtlich nicht mehr in `playbooks/configure.yml` eingebunden, weil sie den Hauptlauf zu häufig blockiert hat.

### 4. Handler können bei späteren Fehlern ausbleiben

Wenn ein späterer Task im Playbook fehlschlägt, kann es passieren, dass ein zuvor notifizierter `nginx`-Reload erst einmal nicht ausgeführt wird. In der Praxis reicht dann oft ein erneuter Lauf oder ein manueller `sudo systemctl reload nginx` auf der betroffenen VM.

## Troubleshooting

### Hostname löst nicht auf

Prüfen:

```bash
getent hosts dev.uranus.home.arpa
```

Wenn kein Treffer kommt, fehlen `/etc/hosts`-Einträge auf dem Host.

### Frontend zeigt die Nginx-Default-Seite

Auf der Ziel-VM prüfen:

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo ls -la /etc/nginx/sites-enabled
```

### Backend liefert `502`

Auf der Ziel-VM prüfen:

```bash
sudo systemctl status uranus-backend.service --no-pager -l
sudo journalctl -u uranus-backend.service -n 100 --no-pager
curl -I http://127.0.0.1:9090/
```

Ein `502` bedeutet fast immer: Nginx läuft, aber der Backend-Prozess auf `localhost:9090` nicht.

### PostgreSQL von anderen VMs nicht erreichbar

Auf `db01` prüfen:

```bash
sudo ss -ltnp | grep 5432
sudo ufw status numbered
```

Die Freigabe ist absichtlich auf interne Netze begrenzt.

### Ansible-Temp-Ordner macht Probleme

Das Repo setzt in `ansible.cfg` bereits:

```ini
remote_tmp = /tmp
```

Das ist wichtig, weil mehrere Rollen per `become_user` auf andere Unix-User wechseln.

## Sicherheit und Platzhalter

Die Platzhalterwerte liegen jetzt gesammelt in `group_vars/vault.yml.example`.

Vor echtem Einsatz solltest du mindestens setzen:

- `vault_cloudinit_password`
- `vault_db_password_dev`
- `vault_db_password_prod`
- `vault_backend_jwt_secret`
- `vault_backend_secret_key`
- `vault_nominatim_db_password`
- `vault_monitoring_web_db_password`
- `vault_monitoring_ido_db_password`
- `vault_monitoring_admin_password`
- `vault_monitoring_api_password`

## Aktueller Status

Das Repository ist kein generisches Produktions-Framework, sondern ein pragmatisch gewachsenes lokales Infrastruktur-Setup. Mehrere Stellen enthalten bewusste Anpassungen an den aktuellen Stand von:

- Upstream-Uranus-Backend
- bereitgestelltem SQL-Dump
- lokaler libvirt-Testumgebung

Die README dokumentiert deshalb den tatsächlichen Zustand des Repos und nicht nur den idealen Zielzustand.
