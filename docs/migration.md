# Nachvollziehbares Migrationsaudit

Ausgangspunkt ist der Merge von [PR #1](https://github.com/sndcds/uranus-ansible/pull/1),
Commit `f766d941e79a4ec03001422390acd0b59da1f4f9`. GitHub meldet den Merge vom
11.10.2026, 06:55:15 UTC, durch `p3t3r67x0`. Alle vier angezeigten Prüfungen der
beiden PR-Läufe waren erfolgreich. Der Merge war bereits erfolgt; diese Migration
hat ihn nicht erneut ausgeführt und keine Branch-Protection umgangen.

Die alten Pfade wurden anhand statischer Rollen-/Template-Verweise und der
Eintrittspunkte untersucht. Das [Dateimanifest](migration-manifest.json) nennt
entfernte Dateien und die Herkunft übernommener Templates.

| Bestand | Entscheidung und Begründung |
|---|---|
| uvtool/libvirt/KVM-Provisionierung | entfernen: vollständig durch Incus-CLI ersetzt |
| alte Host-/Gastinventare, Runtime-Inventory | entfernen: ein statisches Inventar, IPs aus zentraler Instanzliste |
| alte KVM-/Cloud-init-Templates | entfernen: natives Incus-Cloud-init, gemeinsame Container-/VM-Konfiguration |
| Debian PostgreSQL-Rolle | erhalten: SCRAM, eingeschränkte ACLs, geschützter Erstimport, Unterbrechungsmarker |
| SQL-Schutzmodul | aus Hypervisorutility lösen; unverändertes Grundprinzip, weiterhin real getestet |
| Debian Frontend, Nominatim, VersaTiles, Monitoring | erhalten und auf eigene Templates konsolidieren |
| bisheriger Go-Backendpfad | übernehmen und härten: feste Commits, keine Source-Patches, versionierte Releases, Healthcheck/Rollback |
| TLS-Ingress / Gast-Nginx | erhalten und interne TLS-Prüfung ergänzen |
| alter Monitoring-SSH-Key und Bandbreitenrolle | entfernen: private TLS-Icinga-Agenten statt versioniertem Schlüssel |
| alte PostgreSQL-/Monitoring-/Web-/Firewallrollen | entfernen: die jeweiligen Debianrollen sind alleinige Implementierung |
| Anwendungsbackup, Postfix, Logrotation | sichere Teile konsolidieren; alte DB-Backupduplikate entfernen |
| reine VM-Disk-/XML-/Legacy-Hash-Tests | entfernen; Incus-Drift-/API-/Mount-/Recovery-Tests ersetzen sie |
| PostgreSQL- und Nginx-Integrationstests | erhalten; an TLS und konsolidierte Pfade anpassen |

Lokale, uncommittete Einstellungen der alten `vars.yml` und
`inventory/hetzner.ini` wurden vor dem Entfernen außerhalb des Repositorys unter
`/tmp/uranus-local-before-incus` mit restriktiven Rechten gesichert. Sie werden
nicht veröffentlicht. Die Migration konvertiert keine existierenden Server-
Instanzen und löscht dort keine Daten oder Konfigurationen.

Die laufende Infrastruktur kann nicht durch Auschecken des alten Commits
zurückgebaut werden. Eine spätere Produktionsmigration benötigt Inventarisierung,
Backups, verifizierten Restore, Pilot, Umschaltplan und eine ausdrückliche Freigabe.
Alte Hypervisordienste und Firewalls werden durch dieses Repository nicht
automatisch deaktiviert oder entfernt.
