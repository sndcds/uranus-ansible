# Natives Plausible

`plausible01` ist ein unprivilegierter Incus-Systemcontainer mit 8 GiB RAM,
vier CPUs, 80 GiB Storage-Budget und `10.77.0.18`. Ansible installiert Plausible
CE 3.2.1 aus dem offiziellen Commit `e4f5a87a5570bd61605217e7ceb376636db8eddb`,
PostgreSQL 17 und ClickHouse 26.9.10.4 als native Dienste. Der Build verwendet
Elixir/Erlang aus Debian 13, Node.js 24 und das geprüfte Hex-Archiv 2.5.3.
Es wird kein Docker installiert.

Die öffentlichen Verbindungen laufen über `nginx01` und internes TLS zu
`plausible01`; dessen nginx spricht den Dienst auf `127.0.0.1:8200` an.
PostgreSQL und ClickHouse lauschen ausschließlich auf Loopback im Analytics-
Container. Icinga prüft Ressourcen, HTTPS, `/api/health` und ClickHouse `/ping`.

## Provisionierung und Build

Die bestehenden Deployment-Sperren gelten für alle folgenden Playbooks.
Die lokale `deployment.yml` enthält die freigegebenen Werte und die echte
Domain `hetzner_domains.plausible`. Vorhandene interne PKI nur mit
`scripts/extend_pki.py` ergänzen, niemals neu erzeugen.

```bash
. .venv/bin/activate
python scripts/extend_pki.py
ansible-playbook playbooks/provision-plausible.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password --ask-become-pass
```

Der fokussierte Provisionierungslauf prüft den vollständigen vorhandenen
Incus-Bestand und die Kapazität, legt ausschließlich das fehlende `plausible01`
an und hinterlegt dessen per Incus gelesenen SSH-Hostschlüssel geschützt auf
dem Controller. Bestehende Gäste werden nicht neu erstellt.

Die geschützte Datei `environments/hetzner/plausible.vault.yml` wird mit der
Vault-ID `production` verschlüsselt und bleibt von Git ausgeschlossen. Sie enthält
`vault_plausible_environment` mit den bisherigen Anwendungs-, Mail- und OAuth-
Einstellungen sowie zwei frisch generierte lokale Datenbankpasswörter unter
`vault_plausible_postgres_password` und `vault_plausible_clickhouse_password`.
`SECRET_KEY_BASE` muss für bestehende Sitzungen und verschlüsselte Anwendungsdaten
erhalten bleiben. Nur die aktive `/etc/plausible/plausible.env` des Quellservers
verwenden; veraltete `.env`-Dateien im Quellverzeichnis sind keine Grundlage.
`plausible.vault.yml.example` enthält ausschließlich leere Beispielzugänge.
Beim Migrieren dessen Registrierungseinstellung durch die tatsächlich bisherige
Einstellung ersetzen. Bestehende Vault-Dateien nicht erneut verschlüsseln.

```bash
ansible-playbook playbooks/plausible.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

`debian13_plausible_prepare_only=true` ist der sichere Standard: Build und leere
native Datenbanken werden vorbereitet, eine leere Anwendung wird nicht gestartet.
Der versionsgebundene Release liegt unter `/opt/plausible/releases/`; nur ein
vollständig gebauter Release erhält `.uranus-build-complete`. Die geschützte
Laufzeitdatei `/etc/plausible/plausible.env` gehört root und hat Modus `0600`.

## Datenübernahme vom bisherigen Webserver

`plausible-ingress.yml` richtet zuerst ein unabhängiges neues ACME-Zertifikat ein.
Solange DNS noch auf den alten Server zeigt, leitet dessen dedizierte HTTP-Route
nur `/.well-known/acme-challenge/` zum neuen ingress weiter. Eine zufällige
öffentliche Probe muss dort exakt beantwortet werden. Die bisherige HTTPS-
Anwendung läuft bis zur Datenübernahme weiter. Alte TLS-Privatschlüssel werden
nicht übertragen.

Anschließend `plausible-migrate.yml` mit denselben Deployment-/Vault-Argumenten
ausführen. Der Controller benötigt SSH mit sudo zum Alias `awendelk@webserver`
sowie über Hetzner zu `debian@10.77.0.18`. Es gibt kein SSH-Agent-Forwarding.
Bei vorhandenen SSH-Multiplexern können `plausible_migration_control_path` und
`plausible_migration_ssh_config` auf die bestätigte lokale Konfiguration zeigen.

Der Lauf hält den bisherigen Plausible-Dienst an, exportiert PostgreSQL logisch
und ausschließlich die Analytics-Datenbank aus ClickHouse, überträgt den
geschützten Snapshot und prüft SHA256 sowie jede Tabellen-Zeilenzahl. ClickHouse-
Systemlogs werden nicht übernommen. Wörterbuch-Quelldaten werden vor den
Wörterbüchern und abhängigen Ereignistabellen restauriert; benutzerdefinierte
Funktionen werden in Abhängigkeitsreihenfolge erstellt. Materialisierte Views
folgen nach dem Datenimport. Alte Wörterbuch-Zugangsdaten werden durch eine
lokale Loopback-Verbindung ersetzt.

Die finale PostgreSQL-Datenbank heißt `plausible_live`, die ClickHouse-Datenbank
`plausible_events_live`. Snapshot, Prüfergebnisse und Quellpfade bleiben unter
`.uranus-private/plausible/` auf dem Controller und `/var/backups/plausible/`
auf dem Ziel erhalten. Import- und Umschaltmarker liegen root-only unter
`/etc/plausible/`. Ein bereits vorhandener Import wird niemals überschrieben.
Bei Teilfehlern bleiben Daten erhalten und der bisherige öffentliche Dienst
wird wieder aktiviert; vor einer Wiederholung muss der Stand geprüft werden.

Nach erfolgreichem Import aktiviert Ansible `/opt/plausible/current`, führt die
Upstream-Migrationen aus und prüft die neue HTTPS-Adresse mit gültigem Zertifikat
direkt an der neuen öffentlichen IP. Erst dann wird die bisherige dedizierte
nginx-Route auf den neuen Writer umgestellt und der alte Plausible-Dienst
deaktiviert. Alle anderen alten Websites behalten ihre Konfiguration.

Für die DNS-Umstellung von `plausible.oklabflensburg.de`:

| Typ | Wert |
|---|---|
| A | `94.130.236.38` |
| AAAA | `2a01:4f8:13b:1405::2` |

Die alte Route leitet während der DNS-Ausbreitung weiter an den neuen Writer.
Nur die expliziten alten IPv4-/IPv6-Adressen in
`plausible_legacy_proxy_addresses` dürfen dafür die Besucher-IP weiterreichen.
Nach Ablauf der DNS-Caches die Übergangsroute und diese Ausnahme kontrolliert
entfernen. Vorher keine alten Plausible-Daten oder Sicherungen löschen.
Die Übergangsroute prüft die neue öffentliche Zertifikatskette mit
`proxy_ssl_verify_depth 4`; die ausgestellte Kette benötigt mehr als den
nginx-Standardwert eins. Die Zertifikatsprüfung bleibt aktiviert.

## Laufender Betrieb und Sicherungen

Nach dem Import `plausible_enabled: true` und
`debian13_plausible_prepare_only: false` in der lokalen Deployment-Konfiguration
setzen. Dann sorgt `plausible.yml` auch bei Folgerollouts für die Aktivierung.
Nach bestätigtem DNS `plausible` zu `debian13_ingress_tls_site_keys` hinzufügen,
falls diese Liste lokal eingeschränkt ist. `ingress.yml` prüft für reguläre
Zertifikatsanforderungen DNS. Certbot erneuert das eigene Zertifikat automatisch.
`monitoring-checks.yml` ergänzt den neuen Gast im bestehenden Icinga-Master.

`plausible-backup.timer` erstellt täglich gegen 03:40 Uhr eine geschützte lokale
Sicherung mit PostgreSQL-Custom-Dump, nativem ClickHouse-Backup, benutzerdefinierten
Funktionen und Laufzeitkonfiguration. Vierzehn vollständig abgeschlossene
Sicherungen bleiben erhalten. Verzeichnisse: `/var/backups/plausible/daily/`
und `/var/backups/plausible/clickhouse/`. Unvollständige Sicherungen werden
nicht als erfolgreich gezählt. Externe Sicherung dieser geschützten Verzeichnisse
separat einrichten; lokale Kopien schützen nicht vor Hostverlust.

```bash
sudo systemctl status plausible clickhouse-server postgresql@17-main
sudo systemctl start plausible-backup.service
sudo journalctl -u plausible-backup.service -n 20
sudo systemctl list-timers plausible-backup.timer
curl --fail http://127.0.0.1:8200/api/health
```

Wiederherstellungen immer in neue, leere Datenbanken testen. PostgreSQL mit
`pg_restore`, ClickHouse mit `RESTORE DATABASE … AS … FROM Disk('backups', …)`
und geschützte Konfiguration mit root-Rechten wiederherstellen. Datenbanknamen
und Dictionary-Verbindungen müssen zum isolierten Restore passen. Für einen
zeitlich abgestimmten Snapshot beider Systeme den Plausible-Writer vor dem
Export stoppen; laufende tägliche Sicherungen entstehen nacheinander.
