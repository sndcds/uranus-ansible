# Fehlersuche, Recovery und Updates

Alle Kommandos sind Beispiele für eine später autorisierte Betriebsphase.

| Meldung / Symptom | Sichere Reaktion |
|---|---|
| Deployment disabled | Sperren beibehalten; lokale Tests ausführen. Produktivfreigabe nicht aus Fehlermeldung ableiten. |
| Falsche UUID / Mount fehlt | `findmnt --mountpoint /data`; NVMe und fstab passiv prüfen. Kein Formatieren oder automatisches Remounten. |
| Fremder Incus-Zustand | stop; Offline-Migrationsplan und Backup erstellen. Kein Owner-Marker zum Umgehen der Prüfung setzen. |
| Ressourcen-/Device-Drift | `incus config show --expanded` lesen; Änderung separat planen. Kein Delete/Recreate. |
| Verwaiste Disk / unterbrochenes init | Volume, Instanzstatus, `incus info --show-log` und Incus-Events prüfen. Daten erhalten; manual Recovery. |
| Gestoppte vollständige Instanz | Ursache prüfen; Start ausdrücklich über Incus oder `incus_start_existing=true` autorisieren. |
| SSH/Firewall bestätigt nicht | 120 Sekunden Rollback abwarten, neue Verbindung per Schlüssel herstellen; `/var/lib/uranus/host-access` und Journal prüfen. |
| SSH Match / Serviceoptionen abgelehnt | Hostbestand gesondert prüfen; kein Entfernen fremder Regeln und keine blinde Freigabe von Port 22. |
| Keine neue SSH-Verbindung per Schlüssel | SSH-Agent/privaten Schlüssel, bestehenden Benutzer und authorized_keys prüfen; Passwort oder Rootlogin nicht als Ausweichweg aktivieren. |
| Boot-Recovery schlägt fehl | Konsole/Rescue verwenden; Journal und erhaltenen Pending-Zustand prüfen, ursprüngliche SSH-Datei und Firewall aus gesicherten Transaktionsdaten wiederherstellen. |
| Keine Gast-SSH-Verbindung | Cloud-init, Incus-Konsole, DHCP-Lease und Hostschlüssel kontrollieren; keine Hostkey-Prüfung abschalten. |
| SQL pending marker | DB und Logs prüfen, Backup sichern; unvollständige Erstinitialisierung manuell beheben. Marker nicht blind löschen. |
| Nominatim unvollständig | Daten bewahren und Wiederanlauf planen; Superuserrechte sofort prüfen und widerrufen. |
| TLS schlägt fehl | CA, SAN, Uhrzeit, EKU, Keyrechte und Zertifikatablauf prüfen. Keine verify-Funktion deaktivieren. |
| Kapazität unzureichend | Snapshot-/Backupverbrauch inventarisieren und extern sichern. Keine automatische Löschung bestehender Daten. |
| Backend-Konsistenzprüfung scheitert | passenden Release und Schema wählen; Prüfung nicht per Source-Patch abschalten. |

Incus-, Kernel- und Debianupdates zuerst auf einem isolierten Pilot testen.
Paketinstallation des Workflows verwendet `state: present`, keine unkontrollierte
Dist-Upgrade-Reconciliation. Sicherheitsupdates müssen unabhängig als geplanter
Betriebsprozess erfolgen. Vor Incusupdates native Backups und Restorefähigkeit
prüfen; Debian-Sicherheitsrevisionen innerhalb 6.0 LTS zulassen, Versionswechsel
explizit testen. Hostreboots und Gastreboots benötigen eigene Freigaben und
Wartungsfenster. Container teilen den Hostkernel.

Gastbetriebssystem-Upgrades erfolgen einzeln nach Backup und Pilot. Debian-
Major-Upgrades sind keine automatische Aufgabe des Provisionierungsplaybooks.
Nach Upgrade Fakten, TLS, Services, DB-Clients, Firewall und Monitoring prüfen.

Nominatim-Updates: Replikationsquelle und Sequenz passend zum initialen Extrakt
festlegen, Snapshot/SQL-Dump sichern und zunächst im Pilot die installierte
`nominatim replication --help` prüfen. Initialisierung und einmaliges Update nur
bewusst ausführen; kein Timer oder erneuter Vollimport wird automatisch gestartet.
Index-/Schemaänderungen und Updateprivilegien nach der versionsgebundenen
Nominatim-Dokumentation prüfen. Das Updateverfahren ist vor Produktion noch mit
realen Extrakten zu validieren.

Für Diagnose lokaler Units:

```bash
systemctl status incus incus.socket uranus-host-firewall uranus-access-recovery ssh
journalctl -u incus -u uranus-host-firewall -u uranus-access-recovery -u ssh
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus list
```

Änderungen an vorhandenen CPU-/RAMlimits oder Diskgrößen bleiben bewusste
Incus-Administrationsoperationen nach Review. Danach zentrale Definition
abgleichen. Diskverkleinerung oder Container-/VM-Typwechsel benötigt einen
separaten Datenmigrationsprozess.

TLS-Revisionsverzeichnisse sind unveränderlich. Bei ungültigem neuem Staging
das aktive `current`-Ziel zuerst feststellen und erhalten. Nur die eindeutig
nicht aktive, fehlgeschlagene Revision in einem separat freigegebenen Recovery
bereinigen oder neue geprüfte Zertifikate bereitstellen. Aktive Schlüsseldateien
werden zur Fehlerbehebung nicht überschrieben.
