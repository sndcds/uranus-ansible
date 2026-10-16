# Europa in Nominatim importieren

`db01` wurde inzwischen auf **600 GiB** vergrößert. Die anschließende Leseprüfung
bestätigt die größere Disk und Rootpartition, aktives PostgreSQL und rund
577 GiB freien Datenbankplatz. Der vollständige Europa-Preflight ist erfolgreich.
Der Import selbst wurde vom Agenten nicht ausgeführt.

Im eigenen Terminal im Repository ausführen, vorzugsweise in `tmux`:

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
6. Die vorhandene Rolle verwendet vier Threads und ein Zeitlimit von sieben
   Tagen. Flatnode-Speicherung reduziert den Cachebedarf des Importprozesses.
   Importstil `address` umfasst Adressen; POI-Suche erfordert den Stil `full`
   und eine entsprechende neue Speicherplanung. Der Import verwendet weiterhin
   `--no-updates`; automatische OSM-Replikation wird nicht eingerichtet.
7. Datenbankintegrität, API-Status und Ergebnisse für Paris, Madrid, Berlin
   und Flensburg müssen erfolgreich sein, bevor der Abschluss protokolliert wird.

Die Konfiguration steht in `environments/hetzner/nominatim-europe.yml`.
Keine anderen Deployments parallel ausführen. Während des längeren Imports
Gast- und Hostspeicher beobachten. Die 600-GiB-VM und die übrigen Planungsbudgets
sind zusammen größer als die physische NVMe; sie dürfen nicht gleichzeitig
voll belegt werden. Die bestehenden Sicherungen bleiben erhalten und müssen
mit eigener Retention beziehungsweise externem Backup eingeplant werden.

## Weitere Nominatim-Deployments

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
