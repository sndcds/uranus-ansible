# Backup und Wiederherstellung

Snapshots auf derselben NVMe sind kein externes Backup. Ziele vor Produktion:
verschlüsselte Sicherung außerhalb des Hetzner-Hosts, kontrollierte Zugangsdaten,
Retention, dokumentiertes RPO/RTO und ein erfolgreich protokollierter Restore auf
einem isolierten System. Standard-Startwert zur Diskussion: tägliche logische
Dumps (RPO maximal 24 Stunden); RTO muss mit den realen Nominatim-Daten gemessen
werden. Der Betreiber muss diese Ziele ausdrücklich bestätigen.

`debian13_backup` sichert täglich um 02:00 alle zugänglichen Nicht-Template-
Datenbanken mit `pg_dump --format=custom` über lokalen Peer-Zugriff. Dumps werden
zunächst als `.partial` geschrieben und nur nach Erfolg veröffentlicht. 14 Tage
lokale Retention. Anwendungen erhalten private TAR-Sicherungen ihrer Releases,
Konfiguration und persistenten Bilder. Archive und Credentials bleiben restriktiv
berechtigt; keine Passwörter werden in den DB-Backupskripttext eingebettet.

Optional führt `incus_export_backups_enabled=true` wöchentliche native Incus-
Exporte, ein Initialisierungsmanifest und einen globalen SQL-Metadatendump in
`/data/incus/backups` aus. Vor dem Lauf und jedem schreibenden Schritt wird die
Storage-UUID geprüft. Ein gemeinsames Lock verhindert parallele Exportjobs.
Der Job verlangt Kapazität für vollständige Diskbudgets plus Reserve und lädt
anschließend über restic in ein **vorher initialisiertes** externes Repository.
`restic check` prüft dessen Struktur. Zugang/SSH-Hostschlüssel bzw. Objektstorage-
Credentials separat bereitstellen; `restic.env` ist root-only. Repository und
Passwort müssen zeilen-/serialisierungssicher sein. Der Job führt kein `prune`,
keine Instanzlöschung und keine automatische lokale Exportbereinigung aus.

Für große Datenmengen ist dieses Voll-Exportmodell auf einer einzelnen 960-GB-
NVMe begrenzt. Externe inkrementelle Sicherung der logischen Dumps und Anwendungs-
daten benötigt einen gesondert getesteten Transport; ohne ihn keine Produktions-
freigabe. Laufende Instanzexporte sind höchstens crashkonsistent. SQL-Dumps sind
für PostgreSQL-Wiederherstellung maßgeblich. Für Disaster Recovery zusätzlich
Incus-/Projektkonfiguration, Vault, PKI, Zugangsdaten und Versionsmanifest sichern.
Eine laufende Incus-Datenbank niemals durch beliebiges Kopieren einzelner Dateien
sichern; native Metadatensicherung oder kontrollierte Offline-Gesamtsicherung
verwenden. [Incus-Backupverfahren](https://linuxcontainers.org/incus/docs/main/backup/).

## Isolierter Restore-Test

1. Separaten Debian-13-Testhost und externe Backupkopie bereitstellen. Kein
   produktives Inventar verwenden; Netzwerk-/Domainkollisionen verhindern.
2. Checksummen, restic-Repository, PKI und Versionsmanifest prüfen. Exporte in ein
   **neues** Incus-Projekt bzw. unter neuen Instanznamen importieren. Namens-
   konflikte führen zum Abbruch, bestehende Instanzen niemals überschreiben.
3. Für PostgreSQL einen neuen Cluster/neue Datenbanken anlegen; Rollen und
   Erweiterungen kontrolliert installieren. Mit `pg_restore --exit-on-error`
   in die leere Ziel-DB restaurieren. Kein `--clean` gegen eine bestehende DB.
4. Anzahl Datensätze, Schema, PostGIS, Backend-Konsistenzprüfung, Anwendungen,
   Nominatim, VersaTiles und Monitoring prüfen. Neue Instanzen zunächst ohne
   öffentliche DNS-/Ingressfreigabe testen.
5. Dauern, Datenumfang, Prüfsummen und Abweichungen dokumentieren. RPO/RTO mit
   Ergebnis vergleichen; erst danach Umschaltung separat freigeben.

Bei vollständigem Hostverlust: vorhandene ext4-Daten-NVMe nicht formatieren,
Mount/UUID überprüfen, Incus-Zustand nur nach Offline-Prüfung übernehmen oder in
leeres Testprojekt restaurieren. Die automatische Erstinstallation lehnt
unverwaltete vorhandene Daten absichtlich ab. Der ursprüngliche Owner-Marker
allein ist kein Beweis für einen konsistenten Restore.
