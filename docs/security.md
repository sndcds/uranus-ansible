# Sicherheit und Freigabebedingungen

Beide Sperrvariablen sind standardmäßig `false`: `hetzner_deployment_approved`
und `uranus_security_review_complete`. Alle Eintrittspunkte prüfen sie vor
Facts, SSH und Rollen, auch im Check Mode. Das ist eine Schutzschranke, keine
technisch unüberwindbare Zugriffssperre für Administratoren. In dieser Arbeit
werden keine Ansible-Läufe oder schreibenden Tests auf dem Zielhost ausgeführt.

## Befunde aus PR #1

| Befund | Behandlung in der Migration / verbleibende Voraussetzung |
|---|---|
| versionierter Legacy-Monitoring-Privatschlüssel | entfernt; frühere Schlüssel müssen widerrufen/rotiert werden; Git-Historie bleibt exponiert |
| private HTTP-, DB- und Metrikverbindungen unverschlüsselt | interne PKI, verifizierter TLS-Ingress, PostgreSQL `hostssl`, HTTPS-Metriken implementiert; vollständiger Client-End-to-End-Nachweis noch erforderlich |
| Backend-Patches deaktivieren Konsistenzprüfung | entfernt; unveränderte, geprüfte Release-Commits verwenden; Daten-/Versionskompatibilität vor Freigabe beweisen |
| bewegliche Release-Branches | Deployment fordert volle Commit-IDs für Frontend/Backend |
| externe APT-/Pythonabhängigkeiten | signierte Repositories und vorhandene Checksummen erhalten; vollständige Supply-chain-Prüfung und Python-Transitivpins offen |
| SSH-Bestandsaufnahme gescheitert | Hostzustand weiterhin ungeprüft; keine neue Serververbindung in dieser Migration |
| externe Backups / Restore ungeklärt | optionale restic-Exporte und Verfahren dokumentiert; produktiver Restore-Nachweis, RPO/RTO und Kapazität offen |

Vor `uranus_security_review_complete=true` sind Schlüsselrotation, Host-Audit,
Firewallinventar, freigegebene Releases, getestete PKI, Backuptransport und
Restore-Protokoll vom Betreiber abzunehmen. Der Code setzt diese Variable nie
selbst. Die Dokumentation behauptet keine bereits erreichte Produktionsfreigabe.

## Sicherheitsmodell

Container sind unprivilegiert, ohne Nesting oder Hostdevices und mit isolierten
UID-Mappings. PostgreSQL ist standardmäßig eine VM. Container teilen den Kernel;
Kernel-Updates und Incus-Sicherheitsupdates sind daher besonders wichtig.
Incus-Gruppen und Unix-Socket-Zugriff sind rootäquivalent. Netzwerk-API, zusätzliche
Managementlistener und fremde Projekte/Volumes werden nicht adoptiert.

Alle Instanzen besitzen Owner-Marker und Löschschutz. Der Preflight ist lesend;
Incus übernimmt die tatsächliche Ressourcenverwaltung. Namen, Typen, CPU/RAM,
Devices, IPs und Projekt-/Pool-/Netzwerkzustand werden geprüft. Drift stoppt den
Lauf. Es gibt keine automatische Löschung, Neuinitialisierung, Typänderung oder
Diskverkleinerung. Datenbankimporte sind standardmäßig deaktiviert; Erstimporte
sind transaktional und nur für gerade erstellte Datenbanken möglich.

## Adversariales Selbstreview

| Fehlerszenario | Verhalten / Restrisiko |
|---|---|
| `/data` fehlt, falsche UUID, Read-only, fremde Unter-Mounts | Abbruch vor Storage-Schreiben; Socket und Daemon starten nicht |
| Storage wird zwischen Prüfung und Write ausgehängt | wiederholte Guards verkleinern das Zeitfenster; root kann die Prüfung trotzdem umgehen; kontinuierliches Monitoring bleibt nötig |
| Instanzname schon belegt / fremder Owner / Ressourcenänderung | Abbruch, kein Delete, kein Adopt und kein automatisches Resize |
| `init` oder Start unterbrochen | bestehende Daten erhalten; manuelle Prüfung und bewusster Start; verwaiste Ressourcen stoppen weitere Erstellung |
| zwei Controller gleichzeitig | Incus verweigert Namenskollisionen; wiederholter Preflight stoppt fremde Zustände; produktive Runs trotzdem serialisieren |
| SSH-Härtung oder neue Firewall verursacht SSH-Verlust | unabhängig laufender Timer stellt frühere eigene SSH-Datei und Firewall wieder her; eine neue Verbindung per Schlüssel ist für Bestätigung erforderlich |
| Controller stirbt oder Host startet während der Änderung neu | keine Bestätigung; Timer oder Boot-Recovery stellt SSH und persistente Firewall wieder her |
| widersprechende SSH-Includes / Match / Serviceoptionen | Abbruch bzw. Rollback; keine öffentliche Freigabe vor Nachweis der wirksamen Schlüsselpflicht |
| Firewallrollback scheitert | Schlüsselpflicht bleibt bestehen; Pending-Zustand erhalten, Recovery über Konsole/Rescue |
| Backend startet nicht / Healthcheck scheitert | alte Codeversion und, wenn verfügbar, Konfigurationskopie zurück; keine automatische DB-Migration |
| vorhandene DB oder fehlender Importmarker | DB-Existenz entscheidet; kein Reimport; Pending-Marker verlangt manuelle Recovery |
| Nominatim-Import unterbrochen | vorhandene unvollständige DB stoppt Wiederholung; temporäre Superuserrechte gelten nur während der Datenbankvorbereitung und werden im Ansible-`always`-Block vor dem eigentlichen Import widerrufen |
| harter Abbruch während Nominatim-Datenbankvorbereitung | `always` kann nicht laufen; Rechte auf db01 sofort prüfen und manuell widerrufen; nie automatisch den Import wiederholen |
| Disk läuft durch Container/Snapshots/Backups voll | Budgets, Reserveprüfung und Warnungen; ohne bestehende ext4-Quotas keine harte Containerbegrenzung |
| TLS-Zertifikat falsch/abgelaufen | Chain-/Identitätsprüfung oder Dienstvalidierung schlägt fehl; sichere Zertifikatrotation und Ablaufmonitoring bleiben Betreiberaufgabe |

## Zusätzlicher Backendbefund

Das vorhandene `app/config.go` der Anwendung gibt bei `Config.Print()` die
Konfiguration auf stdout aus und redigiert nur den JWT-Schlüssel. DB-/SMTP-
Passwörter und weitere Secrets können dadurch in Logs geraten. Der neue
Backend-Service verwirft stdout (`StandardOutput=null`) und behält stderr für
Fehlerdiagnose. Vor Freigabe ein upstream korrigiertes, geprüftes Release wählen
und frühere Logs auf Secrets prüfen. Diese Maßnahme kostet stdout-Logs und
ersetzt die notwendige umfassende Redaktion in der Anwendung nicht.

## Verbleibende Risiken

Port 22 ist für wechselnde IPv4-/IPv6-Quelladressen erreichbar. Die Anmeldung
erfordert SSH-Schlüssel; Passwort-, Keyboard-Interactive- und Rootlogin sind
gesperrt. Damit entfällt die Quellnetzbarriere gegen Internet-Scans. OpenSSH-
Sicherheitsupdates, Schlüsselrotation und Prüfung der Authentifizierungslogs
bleiben Betriebsaufgaben. Der Zugriff auf private Webdienste wird separat per
Netzfreigabe begrenzt. Der reale Host und die Boot-Recovery wurden nicht auf
Hetzner getestet; eine funktionierende Konsole bleibt Voraussetzung.

Ein vollständiger Anwendungsbetrieb mit realen Daten, produktiver PKI und
Restore wurde nicht auf Hetzner getestet. Die Nominatim-Pythonabhängigkeiten sind
noch nicht vollständig transitiv festgeschrieben. InfluxDB besitzt TLS und
Netzwerkbeschränkung, aber noch keine rollenbasierte Benutzerauthentifizierung.
OSM-Replikationsupdates werden separat manuell kontrolliert; kein ungetesteter
Timer verändert produktive Geodaten. Exporte laufender DB-Instanzen ersetzen
keine logische PostgreSQL-Sicherung. Directory-Quotas, Speicherreserve, externe
Backupretention und reale Hostkapazität bleiben Freigabepunkte.

`make policy` prüft doppelte YAML-Schlüssel, unbenutzte zentrale Variablen,
verwaiste Rollen, alte Provisionierungsabhängigkeiten und private Schlüssel.
Diese statischen Checks ersetzen kein vollständiges Secret-/History-Audit.
Die historische Schlüsseloffenlegung wird ausdrücklich nicht als behoben gemeldet.
