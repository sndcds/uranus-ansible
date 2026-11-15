# Europa in Nominatim importieren

Der Europa-Import wurde am **18.10.2026 um 12:01 Uhr (MESZ)** erfolgreich
abgeschlossen. `db01` hat eine **600-GiB-Disk**; die neue Datenbank umfasst rund
171 GiB. Die bisherige Schleswig-Holstein-Datenbank bleibt unter
`nominatim_sh_20261016` erhalten.

Die bestätigte öffentliche Domain ist **`nominatim.oklabflensburg.de`**.
Gast-nginx, öffentlicher Ingress und Monitoring verwenden diesen Namen. HTTPS
liefert über IPv4 und IPv6 einen gesunden API-Status; Suchen nach Paris, Madrid,
Berlin und Flensburg sind erfolgreich. Das eigene Let's-Encrypt-Zertifikat
und die automatische Erneuerung sind eingerichtet. Ausgeführte Prüfungen stehen
in [Tests und Nachweisen](testing.md).

Der Einstieg wird im eigenen Terminal im Repository ausgeführt, vorzugsweise in
`tmux`. Mit vorhandenem Abschlussmanifest prüft er den bestehenden Zustand und
die Suchergebnisse; ein neuer Import wird dabei nicht gestartet:

```bash
./scripts/import_nominatim_europe.sh
```

Der SSH-Schlüssel muss im Agenten verfügbar sein. Für die optionale Vergrößerung
wird das sudo-Passwort für den Hetzner-Host direkt im SSH-Terminal abgefragt. Es wird weder in einer
Datei gespeichert noch an Ansible oder im Chat übergeben. Die vorhandenen
Vault-Zugänge unter `.uranus-private` werden wie bisher verwendet. Die
Deployment-Sperren bleiben wirksam und werden durch das Skript nicht freigegeben.

Der Einstieg erzeugt eine private SSH-Konfiguration und einen Inventory-Zusatz
unter `.uranus-private/ssh`. Vergrößerungshelfer, ProxyJump und die direkte
Ansible-Hostverbindung nutzen damit dieselbe bereits authentifizierte
Hetzner-Verbindung. Hostschlüsselprüfung und die persönlichen SSH-Einstellungen
bleiben aktiv. Vor Gastverbindungen wird nach den Deployment-Sperren die
Hostanmeldung geprüft; zusätzlich wartet der Ablauf ausdrücklich auf SSH zu
`db01`. Ein gesperrter Karten-Schlüssel wird damit bereits an der Hostanmeldung
sichtbar und nicht erst als Proxy-Banner-Timeout bei einem Gast.

Für einen noch nicht vergrößerten Datenbankgast lässt sich die Erweiterung mit
dem Import kombinieren:

```bash
./scripts/import_nominatim_europe.sh --resize-db
```

**Beim Vergrößern kann ein geordneter Stop/Start von `db01` nötig sein.**
Dabei werden die Verbindungen aller Datenbanken auf diesem Gast kurz
unterbrochen, einschließlich der Backend- und Monitoring-Datenbanken.
Der Helfer erstellt zuerst Sicherungen und verwendet keinen erzwungenen Stop.

Nur die Vergrößerung ausführen:

```bash
python3 scripts/resize_db01.py
```

Nur Datenbankzustand und Platz prüfen, ohne Download, Sicherung, Vergrößerung,
Datenbankumbenennung oder Dienststopp:

```bash
./scripts/import_nominatim_europe.sh --preflight
```

## Ablauf und Kapazität

1. Der Vergrößerungshelfer prüft den verwalteten Incus-Gast, die bekannte
   Dateisystem-UUID und die beiden GPT-Partitionen. Er sichert alle
   Nicht-Template-Datenbanken, Rollen, Partitionstabelle und Incus-Konfiguration
   unter `/var/backups/db01-before-resize-<UTC-Zeit>` auf Gast beziehungsweise
   Host. Er prüft die Dump-Verzeichnisse mit `pg_restore --list`; das ersetzt
   keinen Restore-Test. Anschließend erweitert er die Disk. Bei einer
   aufgeschobenen Änderung oder weiterhin alter Gastgröße stoppt er die VM
   geordnet und startet sie neu; ein reiner Gast-Reboot reicht für den
   Incus-Gerätestart nicht aus. Nach Agent- und PostgreSQL-Bereitschaft müssen
   im Gast tatsächlich 600 GiB sichtbar sein. Erst dann folgen ein
   `growpart`-Trockenlauf und die Erweiterung von Partition 2 und ext4. EFI,
   Partitionsanfang, UUID und Datenbank-OIDs werden geprüft. Eine beim Boot
   bereits erfolgte automatische Erweiterung wird ebenfalls berücksichtigt.
2. Vor jedem neuen Import müssen auf dem PostgreSQL-Dateisystem mindestens
   **400 GiB**, auf `nom01` **160 GiB** und auf dem physischen Host **720 GiB**
   frei sein. Der letzte Wert umfasst beide Importbudgets plus 160 GiB Reserve,
   weil Gäste und VM auf derselben Daten-NVMe liegen. Diese Budgets sind
   vorsichtige Planungsgrenzen, kein gemessener Europa-Speicherbedarf. Zusätzliche
   Backups und andere Last während des Imports können mehr Platz benötigen.
3. Das Skript lädt den datierten Geofabrik-Extrakt, prüft die über HTTPS
   gelieferte Anbieter-MD5 und berechnet SHA256 für die vorhandene Importrolle.
   Dabei läuft die bisherige Suche weiter.
4. Vor dem Wartungsfenster wird auf `db01` ein weiterer Dump unter
   `/var/backups/nominatim-before-europe-261015/nominatim.dump` erstellt und
   dessen Archivverzeichnis geprüft. Projekt und Service-Unit werden auf
   `nom01` unter `/var/lib/uranus/nominatim-europe` gesichert.
5. Socket und API werden gestoppt. Die alte Datenbank wird unter
   `nominatim_sh_20261016` erhalten. Europa wird als neue `nominatim` importiert.
   **Während Import und Indexierung ist die Suche nicht verfügbar.**
6. Die Rolle verwendet vier Threads und ein Zeitlimit von sieben
   Tagen. Flatnode-Speicherung reduziert den Cachebedarf des Importprozesses.
   Importstil `address` umfasst Adressen; POI-Suche erfordert den Stil `full`
   und eine entsprechende neue Speicherplanung. Der abgeschlossene Import vom
   16.–18.10.2026 verwendete `--no-updates`. Seit der anschließenden Anpassung
   behält ein neuer Import standardmäßig die für Updates benötigten Daten.
   Ein erneuter Lauf mit Abschlussmanifest führt diesen neuen Import nicht aus.
7. Datenbankintegrität, API-Status und Ergebnisse für Paris, Madrid, Berlin
   und Flensburg müssen erfolgreich sein, bevor der Abschluss protokolliert wird.

Die Konfiguration steht in `environments/hetzner/nominatim-europe.yml`.
Keine anderen Deployments parallel ausführen. Während des längeren Imports
Gast- und Hostspeicher beobachten. Die 600-GiB-VM und die übrigen Planungsbudgets
sind zusammen größer als die physische NVMe; sie dürfen nicht gleichzeitig
voll belegt werden. Die bestehenden Sicherungen bleiben erhalten und müssen
mit eigener Retention beziehungsweise externem Backup eingeplant werden.

## Automatische OSM-Updates

**Die laufende Europa-Datenbank ist eingefroren und derzeit nicht updatefähig.**
Der bisher fest im Importbefehl enthaltene Schalter `--no-updates` entfernte nach
der Indexierung unter anderem `place`, `planet_osm_ways`, `planet_osm_rels` und
die Flatnode-Datei. Das sparte dauerhaft Speicher; die fertige Datenbank umfasst
rund 171 GiB. Das ist keine Voraussetzung für Europa, sondern eine Entscheidung
für einen statischen Datenbestand. Ein Timer oder `replication --init` kann die
gelöschten Daten nicht wiederherstellen. Der Datenstand bleibt vorerst
`2026-10-15T20:20:56Z`.

Neue Importe verwenden standardmäßig `debian13_nominatim_import_updates: true`.
Nur für eine bewusst statische neue Installation darf dieser Wert auf `false`
gesetzt werden. Die Änderung wirkt auf keinen bestehenden Datenbestand zurück.
Die Flatnode-Datei muss bei einem updatefähigen Import dauerhaft erhalten bleiben.

Das vorbereitete Playbook `playbooks/nominatim-updates.yml` installiert eine
systemd-Service-/Timer-Kombination **erst nach erfolgreicher Vorprüfung**:

- Es müssen Rohdaten, ein abgeschlossener Import und die konfigurierte
  Flatnode-Datei vorhanden sein. Das Projekt muss dieselbe Datenbank verwenden.
- Eine bereits initialisierte Replikation benötigt einen bekannten Quellnachweis.
  Quell-URL und Datenbank-OID werden festgehalten; ein Quellenwechsel oder eine
  unbemerkt ersetzte Datenbank führt zum Abbruch.
- Pyosmium wird im vorhandenen venv als `osmium==4.3.1` installiert. Einmalig wird
  die Sequenz mit `nominatim replication --init` bestimmt. Bestehende Sequenzen
  werden nicht bei jedem Deployment zurückgesetzt. Die Replikationsquelle wird
  auch in der Projekt-`.env` festgehalten, damit manuelle Befehle dieselbe Quelle
  verwenden.
- `nominatim-updates.service` verarbeitet mit zwei Threads jeweils einen Batch
  über `replication --once`. Quelle ist
  `https://download.geofabrik.de/europe-updates`, deren Veröffentlichungsintervall
  86.400 Sekunden beträgt. Der Timer startet nach dem Boot und jeweils 15 Minuten
  nach dem Ende eines Laufs erneut. Nominatim wartet bei Bedarf selbst bis zum
  nächsten täglichen Diff. Ein gemeinsames `flock` verhindert parallele
  Initialisierung und Updates durch diese verwalteten Abläufe.
- systemd führt den Prozess auf `nom01` aus; eine unterbrochene SSH-Verbindung
  oder eine ausgeschaltete lokale Arbeitsstation beendet ihn nicht.

**Noch nicht auf dem aktuellen Datenbestand ausführen.** Nach einem separat
geplanten und erfolgreich geprüften Neuimport aktiviert folgender Befehl die
Updates. Er importiert oder ersetzt selbst keine Datenbank und bricht auf der
heutigen eingefrorenen Datenbank vor jeder Änderung ab:

```bash
. .venv/bin/activate
ansible-playbook playbooks/nominatim-updates.yml \
  -e @environments/hetzner/deployment.yml \
  -e @environments/hetzner/nominatim-europe.yml \
  -e '{"debian13_nominatim_updates_enabled":true}' \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Nach der Aktivierung zusätzlich `debian13_nominatim_updates_enabled: true` in der
eigenen `deployment.yml` festhalten. Dann prüfen spätere normale
Nominatim-Deployments auch die Update-Konfiguration. `false` überspringt deren
Verwaltung; es stoppt keinen bereits aktivierten Timer.

Vor dem Neuimport muss die Kapazität für dauerhaft erhaltene Rohdaten,
Flatnodes, temporäre Indexdaten und die bisherige Suche geplant werden. Bei der
Prüfung am 18.10.2026 waren auf dem physischen `/data`-Dateisystem nur rund
163 GiB verfügbar. Rund 802 GiB waren auf der separaten System-NVMe verfügbar,
gehören aber bislang nicht zum freigegebenen Incus-Datenpool. Eine Verwendung
erfordert einen eigenen Storage-Plan samt Anpassung der bestehenden Guards;
die nominellen 600 GiB von `db01` allein belegen keine ausreichende physische
Reserve. Es wurde weder ein Neuimport gestartet noch zusätzlicher Speicher
zugewiesen oder ein Timer aktiviert.

Nach einer späteren Aktivierung auf `nom01` prüfen:

```bash
sudo systemctl status nominatim-updates.timer nominatim-updates.service
sudo journalctl -u nominatim-updates.service --since yesterday
curl -fsS 'https://nominatim.oklabflensburg.de/status?format=json'
```

Für Wartung zuerst `sudo systemctl stop nominatim-updates.timer` ausführen und
das Ende des laufenden Service abwarten. Zum dauerhaften Abschalten zusätzlich
`sudo systemctl disable nominatim-updates.timer` verwenden. Den laufenden
Service nicht während einer Datenverarbeitung abbrechen. Manuelle
Replikationsläufe müssen dieselbe Projektsperre verwenden. Ein Wechsel der
Update-Quelle erfordert eine bewusst geplante neue Initialisierung; den
Quellnachweis nicht einfach löschen.

Grundlagen: [Import und Freeze](https://nominatim.org/release-docs/latest/admin/Import/#dropping-data-required-for-dynamic-updates)
und [Replikation und systemd](https://nominatim.org/release-docs/latest/admin/Update/).

## Weitere Nominatim-Deployments

In der vorhandenen Domain-Zuordnung der lokalen `deployment.yml` muss
`hetzner_domains.nominatim` auf `nominatim.oklabflensburg.de` stehen. Die
bestehende Liste `debian13_ingress_tls_site_keys` enthält zusätzlich `nominatim`,
damit spätere Ingress-Läufe diese Domain weiter berücksichtigen.

Das Europa-Profil muss nach `deployment.yml` übergeben werden, damit dessen
bisherige Schleswig-Holstein-Werte nicht wieder aktiviert werden:

```bash
. .venv/bin/activate
ansible-playbook playbooks/nominatim.yml \
  -e @environments/hetzner/deployment.yml \
  -e @environments/hetzner/nominatim-europe.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Das gilt auch für `configure.yml`, wenn dort `nom01` enthalten ist. Alternativ
die dauerhaften Projekt-, Daten- und Flatnode-Einstellungen nach erfolgreichem
Import in die eigene Deployment-Datei übernehmen. Die Erstimportfreigabe
bleibt außerhalb des einmaligen Austauschs ausgeschaltet. Ein erneuter Lauf
des Europa-Einstiegs mit Abschlussmanifest prüft nur Zustand und Suchergebnisse.

## Unterbrechung und Wiederherstellung

Wenn der ursprüngliche Vergrößerungshelfer mit
`The guest has not detected the new disk size` abgebrochen ist, wurde der
Europa-Ablauf noch nicht gestartet. Die bereits erstellten Sicherungen wie
`/var/backups/db01-before-resize-20261016T152907563499Z` bleiben erhalten.
Mit dem korrigierten Stand denselben Befehl erneut ausführen. Der Helfer
erkennt auch die Kombination aus konfigurierten 600 GiB und weiterhin im Gast
sichtbaren 150 GiB, prüft den Platz anhand der tatsächlichen Größe, erstellt
eine neue Sicherung und übernimmt die aufgeschobene Änderung per Stop/Start.

Technischer Hintergrund: Incus 6.0.4 verweigert im
[Storage-Treiber](https://github.com/lxc/incus/blob/v6.0.4/internal/server/storage/drivers/utils.go#L343)
die Vergrößerung einer verwendeten Disk-Datei und speichert im
[Disk-Gerät](https://github.com/lxc/incus/blob/v6.0.4/internal/server/device/disk.go#L1329)
eine aufgeschobene Änderung für den nächsten Start. Ein erfolgreicher
Konfigurationsbefehl allein bestätigt daher noch keine größere Gastdisk.

Der Versuch wird exklusiv unter `/var/lib/uranus/nominatim-europe` reserviert.
Das Manifest enthält Phase, Original-OID, Backup-Pfade und nach erfolgreicher
Prüfung den SHA256. Bei Fehlern bleibt es erhalten. Ein unvollständiger Versuch
wird niemals automatisch erneut importiert oder gelöscht. Auch bei Abbruch
des Controllers kann der asynchrone Prozess auf dem Gast noch laufen.

Bei Phase `preparing` sind Dienste und Datenbank noch nicht umgestellt. Vor
einer Wiederholung laufende Download-/Backup-Prozesse und Datenbanknamen
prüfen; dann das Versuchsverzeichnis und gegebenenfalls das Backup-Verzeichnis
unter einem neuen Namen archivieren. Keine Sicherung löschen.

Bei Phase `replacing` zuerst prüfen, ob noch Import-/Indexprozesse laufen.
Diese müssen geordnet beendet oder abgeschlossen sein, bevor Datenbanknamen
wieder geändert werden. Socket und Dienst während der Wiederherstellung stoppen.
Auf `db01` die Datenbank-OID mit `previous_oid` im Manifest vergleichen:

```sql
SELECT datname, oid FROM pg_database
WHERE datname IN ('nominatim', 'nominatim_sh_20261016');
```

Wenn `nominatim_sh_20261016` die Original-OID hat, die unvollständige neue
`nominatim` nach Prüfung ihrer Verbindungen unter einem freien Namen wie
`nominatim_europe_incomplete_20261016` erhalten und die alte Datenbank zurück
nach `nominatim` benennen. Ist die Original-OID noch unter `nominatim`
vorhanden, war die Umbenennung noch nicht erfolgt; sie bleibt unverändert.
Es ist kein `DROP DATABASE` erforderlich.

Auf `nom01` die gesicherte `previous.service` als
`/etc/systemd/system/nominatim.service` mit Modus `0644` wiederherstellen,
`systemctl daemon-reload` ausführen und Socket und Dienst starten. Die Unit
verwendet dann wieder das erhaltene ursprüngliche Projekt. Status und Flensburg
prüfen, bevor die Suche freigegeben wird. Den Versuch samt neuer Datenbank für
die Fehleranalyse behalten und das Europa-Profil bis zum nächsten geplanten
Import nicht für normale Deployments verwenden.
