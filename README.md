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

Damit diese Domains vom Host aus auflösbar sind, brauchst du passende Einträge in `/etc/hosts`. Beispiel mit den typischen libvirt-IP-Adressen:

```hosts
192.168.122.22 dev.uranus.home.arpa api.dev.uranus.home.arpa
192.168.122.237 uranus.home.arpa api.uranus.home.arpa mail.uranus.home.arpa
192.168.122.241 monitoring.uranus.home.arpa
192.168.122.10 nominatim.uranus.home.arpa
```

Die tatsächlich vergebenen IPs stehen nach dem Provisionieren in `inventory/runtime_hosts.yml`.

## Architektur

### Provisioning

Das Provisioning läuft lokal auf dem KVM-Host über `uvtool` und libvirt:

- `playbooks/provision.yml` installiert KVM/libvirt, erzeugt das libvirt-NAT-Netz und erstellt die VMs
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
5. `backup` auf `db01`
6. `certbot`
7. `nginx`
8. `app_backend`
9. `app_frontend`
10. `postfix`
11. `monitoring`
12. `nominatim`

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
- `group_vars/all.yml`: globale Domänen, Versionsstände, App- und Nominatim-Variablen
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

### `host_vars/db01.yml`

Hier wird die Mehrfach-DB-Konfiguration definiert:

```yaml
app_databases:
  - name: uranus_dev
    user: uranus_dev
    password: CHANGE_ME_DB_PASSWORD_DEV
  - name: uranus_prod
    user: uranus_prod
    password: CHANGE_ME_DB_PASSWORD_PROD
```

Zusätzlich:

- `db_schema: "uranus"`
- `postgresql_listen_addresses: "*"`
- `postgresql_allowed_networks`

### `host_vars/dev01.yml` und `host_vars/prod01.yml`

Dev und Prod verwenden jeweils eigene Datenbanken:

- `dev01` -> `uranus_dev` / `uranus_dev`
- `prod01` -> `uranus_prod` / `uranus_prod`

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

1. Platzhalter-Passwörter und Secrets in `group_vars/` und `host_vars/` ersetzen.
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

Aktuell sind mehrere sicherheitsrelevante Variablen Platzhalter und müssen vor echtem Einsatz ersetzt werden:

- `cloudinit_password`
- `backend_jwt_secret`
- `backend_secret_key`
- `db_password` in den App-Host-Variablen
- `app_databases[*].password` in `host_vars/db01.yml`
- `nominatim_db_password`
- `ssl_email`

## Aktueller Status

Das Repository ist kein generisches Produktions-Framework, sondern ein pragmatisch gewachsenes lokales Infrastruktur-Setup. Mehrere Stellen enthalten bewusste Anpassungen an den aktuellen Stand von:

- Upstream-Uranus-Backend
- bereitgestelltem SQL-Dump
- lokaler libvirt-Testumgebung

Die README dokumentiert deshalb den tatsächlichen Zustand des Repos und nicht nur den idealen Zielzustand.
