# Storage

`/data` muss ein eigener, schreibbarer ext4-Mount mit UUID
`7f882d89-a2cf-46d2-9db8-5333be51a300` sein. Der Guard prüft den exakten Mount,
UUID, Schreibmodus, Symlinks und Dateisystemgrenzen an Datenbank, Images, Backups
und Pool. Er mountet, formatiert und repariert nichts. Die vorhandene Partition
und Mountoptionen werden nicht verändert.

`INCUS_DIR=/data/incus` gilt für Daemon, Socketaktivierung, Startup, Shutdown,
Ansible und Backup. Damit liegen die Incus-Datenbank, Imagecache, Instanzverweise,
Volumes und Exporte gemeinsam auf der Daten-NVMe. Der native Pool liegt unter
`/data/incus/storage-pools/uranus`; Incus legt seine Verzeichnisse selbst an. Systemd-Mountabhängigkeiten
und ein Guard vor Socket-/Daemonstart verhindern den Start ohne korrekten Mount.
Ein bisheriger Incus-Zustand unter `/var/lib/incus` wird nicht automatisch
verschoben oder adoptiert. Die Incus-internen Symlinks auf eigene Volumes sind
normal; fremde Symlinks an den geschützten Basispfaden werden abgelehnt.

Das Basisverzeichnis `/data/incus` gehört `root:root` und hat Modus `0711`.
Der auf eine Host-UID abgebildete Rootbenutzer eines unprivilegierten Containers
braucht das Suchrecht (`x`), um dessen Rootdateisystem zu erreichen. Modus `0700`
verhindert deshalb den LXC-Start. `0711` erlaubt anderen Benutzern die Traversierung,
aber kein Auflisten oder Schreiben im Basisverzeichnis. Incus verwaltet die
Rechte seiner Unterverzeichnisse und Volumes; die Hostrolle ändert ausschließlich
das Basisverzeichnis, ohne rekursiven `chmod` oder `chown`.
[LXC-Pfadprüfung](https://github.com/lxc/lxc/blob/stable-6.0/src/lxc/start.c#L73).

| Backend | Bewertung bei vorhandener ext4-NVMe |
|---|---|
| Directory | Standard: bestehendes ext4 nutzbar, keine Partitionseingriffe; höhere Kosten für Kopien/Snapshots |
| Btrfs | bessere Snapshot-/Copy-on-write-Eigenschaften; native Nutzung braucht ein anderes Dateisystem |
| ZFS | effizientere Snapshots und weitere Verwaltungsfunktionen; zusätzliche Verwaltung, native Nutzung braucht eigenen Pool |

Loopbasierte Pools auf ext4 würden mehr Komplexität und zusätzliche
Kapazitätsgrenzen einführen. Sie werden nicht automatisch eingerichtet.
[Incus Directory-Dokumentation für 6.0.4](https://github.com/lxc/incus/blob/v6.0.4/doc/reference/storage_dir.md).

Die VM-Diskgröße wird technisch durchgesetzt. Directory-Container können auf
ext4 nur dann Diskquoten erhalten, wenn bereits Project-Quotas aktiviert sind.
Standardmäßig ist `incus_container_quotas=false`: Die Containergrößen sind
Planungsbudgets, keine harten Quotas. `true` verlangt vorhandenes `prjquota` und
setzt Rootdiskgrößen; Ansible aktiviert keine Dateisystemfeatures. Diese Wahl
muss vor Produktion entschieden und mit einem realen Fülltest geprüft werden.

Die sieben Budgets ergeben 610 GiB; eine 960-GB-NVMe hat etwa 894 GiB rohe
Kapazität. Der Guard fordert für neue Instanzen volle Diskbudgets plus 160 GiB
Reserve. Images, Metadaten, Snapshots, SQL-Dumps, Exporte und restic benötigen
zusätzlichen Platz. Ein Voll-Export aller Budgets kann neben den laufenden
Instanzen nicht garantiert auf dieselbe NVMe passen. Der optionale Exportjob
bricht bei unzureichender Kapazität ab. Für große produktive Daten sind inkrementelle
externe Sicherungen oder zusätzliche Backupkapazität einzuplanen.

Warnung ab 75 %, kritisch ab 85 % Belegung. Der private Host-Icinga-Agent prüft
`/data`; Gäste melden ihre eigene Sicht. Kein automatischer Snapshotplan und
keine automatische Host-Exportlöschung. Retention muss kontrolliert werden;
SQL-/Anwendungsdump-Retention ist standardmäßig 14 Tage.

Vor Snapshots oder manuellen Exporten den Guard und freien Platz prüfen. Snapshot-
und Backupbudgets konservativ nach tatsächlichem Datenvolumen berechnen. Ein
während des Betriebs verlorener Mount erfordert sofortige Betriebsreaktion;
Startguards ersetzen keine kontinuierliche Dateisystemüberwachung oder UPS.
