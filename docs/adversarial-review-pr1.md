# Adversarial Review: PR #1

Prüfdatum: 11.10.2026. Änderungen ausschließlich im bestehenden Branch
`feat/hetzner-debian13`. GitHub meldet PR #1 seit **11.10.2026, 06:55:15 UTC**
als bereits gemergt (`f766d941e79a4ec03001422390acd0b59da1f4f9`). Das wurde bei
der Statusprüfung festgestellt; während dieser Nachprüfung wurde kein Merge
vorgenommen. Ein gemergter PR kann nicht wieder Draft werden. Der Betreiber
hat einen neuen Draft-PR auf demselben Branch ausdrücklich autorisiert.
Kein Deployment und kein Zugriff auf `94.130.236.38`.
Die vorher fehlgeschlagene lesende Serverbestandsaufnahme bleibt offen.

## Findings und Korrekturen

| Finding | Schweregrad | Ursache | Korrektur | Regression / Nachweis |
| --- | --- | --- | --- | --- |
| F1: SSH-Lockout bei Firewalländerung | Kritisch | Eine bestehende SSH-Verbindung kann trotz gesperrter neuer Verbindungen weiterlaufen; Controller-Rescue reicht bei Verbindungsverlust nicht. | Host-seitige Transaktion mit vorher aktiviertem systemd-Rollback, dauerhaftem Snapshot, neuer SSH-Verbindung ohne Multiplexing, Challenge, Tabellen-Digest, monotoner Frist und Boot-Recovery. Nur eigene Tabelle wird zurückgesetzt. | `test_firewall.py` und verpflichtender echter SSH/nft/systemd-Namespace-Test mit falschen Regeln und Controller-SIGKILL; vollständige Ergebnisse nach CI-Abschluss unten. |
| F2: Storage-Überbelegung | Hoch | Nur neue virtuelle Größen wurden gegen freie Blöcke geprüft; noch nicht belegte Teile vorhandener Sparse-Platten und fremde Datenvolumes fehlten. | Wachstum sämtlicher vorhandener Volumes und volle neue Platten reservieren, Hardlinks deduplizieren, 10 GiB Download-/Cache- und 5 GiB Betriebsreserve. Anfangsbedarf mindestens 615 GiB frei; unbekannte Backing-Chains stoppen. UUID-/Orphan-/Symlink-Schutz bleibt erhalten. | Sechs zusätzliche Fälle in `test_provisioning.py`: alle/teilweise bestehende VMs, Einzel-VM-Auswahl, Cache-Ersetzung, fremdes Volume, unbekannte Backing-Chain; echte QEMU-Datenerhaltung bleibt geprüft. |
| F3: Unterbrochene App-PostgreSQL-Initialisierung | Hoch | Der bisherige Marker entstand erst nach DB-Erstellung; ein Abbruch davor oder zwischen Import und Abschluss ließ mehrdeutigen Zustand zurück. Ein weiterlaufender Worker kann trotz totem Controller committen. | Exklusiver dauerhafter Claim vor DB-Erstellung; Abschluss erst nach Import/Schema/Grants. Vorhandener Claim sperrt jeden Folgelauf; verlorene abgeschlossene DB wird nicht automatisch ersetzt. Bestehende Daten werden weder gelöscht noch erneut importiert. | Fünf zusätzliche echte lokale PostgreSQL-Integrationstests plus drei Claim-Tests; geprüft werden OID, Daten und Sperre bei Wiederholung. |
| F4: IPv4/IPv6-DNS-Prüfung | Mittel | Gemeinsame Adressfamilienprüfung lehnte korrektes Dual-Stack ab und behandelte AAAA nur als generellen Fehler. | A/AAAA getrennt, normalisierte IPv6-Adressen, genaue Mengenprüfung, tatsächliche Host-Zuweisung und Fehler bei temporären DNS-Störungen. Leere AAAA-Liste bleibt sicherer Default. | `test_dns.py`: IPv4, Dual-Stack, alternative IPv6-Schreibweise, doppelte Records, fremde/fehlende A/AAAA, Resolverfehler und Host-Zuweisung. |
| F5: Backend-Konsistenzprüfung deaktiviert | Hoch | Die wiederverwendete Ubuntu-Rolle patchte die Startprüfung aus dem Backend und modifizierte Go-Modulmetadaten; globale Toolchain wurde ersetzt. | Separate Debian-Backend-Rolle, Startup-Prüfung unverändert, `go build -mod=readonly`, SHA-geprüfte versionierte Toolchain, Checkout ohne `force`, Build-Nachweis erst nach Erfolg, JSON-Escaping. Legacy bleibt unverändert. | `test_backend.py` und nativer Debian-Backend-Build mit Quelltext-/Git-Unverändertheitsprüfung. |
| F6: Unbelegte Debian-Anwendungskompatibilität | Mittel | Die bisherigen 74 Tests bewiesen Infrastruktur und PostgreSQL-Schutz, aber keine nativen Builds und Parser aller Anwendungen. Der Grund für Debian-Gäste fehlte. | Betreiberentscheidung „Debian 13 auf Host und allen VMs“ ausdrücklich dokumentiert; separater verpflichtender Debian-13-App-CI-Job und Rollenmatrix. | Sechs native Anwendungstests plus ursprüngliche 74 Tests, alle 14 Syntaxprüfungen und Lint-Profil production. |

## Rollenkompatibilität und Grenzen

| Rolle / Anwendung | Debian-13-Anpassung und ausgeführte Prüfung | Grenze |
| --- | --- | --- |
| `debian13_guest`, Hypervisor | Debian-Pakete/Cloud-init-Netzwerk, QEMU-Vollkopien, NAT, Parser, Kapazität, UUID und Firewall-Transaktionen. | Vollständiger KVM-Boot auf einem separat freizugebenden Testhost steht aus. |
| `debian13_postgresql` | Native PostgreSQL 17/PostGIS; echte Ansible-Tasks gegen isolierten lokalen Unix-Socket, Erstimport/Abbruch/Datenerhaltung. | Reale Datenmigration und Restore-Test bleiben Betriebsaufgaben. |
| `debian13_backend` | SHA-geprüfte Go-Toolchain; echter Build, erhaltene Startup-DB-Konsistenzprüfung, unveränderte Quellen und Moduldateien. | Noch kein fachlicher API-Test gegen Produktivdaten. |
| `debian13_frontend` | Node.js 24, deklarierte pnpm-Version, eingefrorenes Lockfile, echter Build. | Kein Browser-/Backend-End-to-End-Test. |
| `debian13_monitoring` | PHP 8.4, native Icinga-/IDO-Schemapfade und Icinga-Parser, InfluxDB/Grafana-Binaries, Nginx/FPM-Socket-Parser. | Kein vollständiger Monitoring-Datenfluss mit sechs echten VMs. |
| `debian13_nominatim` | Nominatim 5.1 DB/API auf Python 3.13, native osm2pgsql/PG17-Clients, echte ASGI-App-Factory. | Großer OSM-Erstimport und Abbruch-Recovery nicht End-to-End geprüft. |
| `debian13_versatiles` | SHA-geprüfte GNU-v5.0.0-Binary startet auf Debian 13. | Regionaler Daten-Download und Tile-Serving nicht End-to-End geprüft. |
| `debian13_guest_web`, `debian13_ingress` | Echte Nginx-Parser mit privatem HTTP/TLS und A/AAAA-Regressionen. | Reale ACME-Ausstellung und öffentliche IPv6-Erreichbarkeit offen. |
| `postfix` (unverändert) | Debian-Paketinstallation und `postconf`-Version/Defaults geprüft. | Authentifizierung gegen den gewählten SMTP-Relay offen. |
| `debian13_backup`, `backup`, `logrotate` | Native PG-Tools, Shell-Syntax/Logrotate-Parser und unveränderte Legacy-Dateien geprüft. | Verschlüsseltes Off-Host-Ziel und vollständiger Restore-Test offen. |

Die nativen Build-Fixtures pinnen Backend-Commit
`ce426a0f9b2d4c79f81a0ccd291999406cddfa11` und Frontend-Commit
`87658dc2ff8d1492c6e0158afd57e59d428c6451`. Bewegliche `dev`-/`main`-Defaults
sind kein geprüfter Release-Pin; vor Deployment passende Commits festlegen.

## Testergebnisse

Die abschließenden lokalen und CI-Ergebnisse werden nach vollständiger
Ausführung ergänzt. Tests schreiben ausschließlich in temporäre lokale
Fixtures oder isolierte CI-Container/Netzwerk-Namespaces. Der Server wird
nicht als Testziel verwendet. Neue privilegierte/native Tests dürfen lokal
ohne passende Umgebung übersprungen werden; CI führt sie verpflichtend aus.

## Verbleibende Risiken und Entscheidungen

- **Hoch:** Serverzustand und tatsächlich verfügbare `/data`-Kapazität sind wegen
  fehlgeschlagener früherer SSH-Authentifizierung weiterhin unbestätigt.
  Lesende Bestandsaufnahme, externe Konsole, Backup/Restore und Deployment-
  Freigabe sind erforderlich. Defaults allein begründen keine Deployment-Reife.
- **Hoch:** Ein harter Controller-Ausfall während eines Nominatim-Erstimports
  kann den `always`-Entzug temporärer Superuserrechte verhindern. Vor Recovery
  aktive Worker, Rollenrechte und DB-Zustand prüfen; ein eigener Watchdog ist
  eine verbleibende Härtungsaufgabe. App-Importe sind unprivilegiert geschützt.
- **Mittel:** Rollback setzt einen funktionierenden Host-Kernel, systemd und
  les-/schreibbares Transaktionsdateisystem voraus. Eine Host-/Storage-Störung
  braucht externen Konsolenzugang. Andere Firewalltabellen können unabhängig
  sperren; sie werden bewusst weder ersetzt noch entfernt.
- **Mittel:** Kapazität ist eine konservative Momentaufnahme, keine laufende
  Quota. Fremde Prozesse, neue Volumes oder stark wachsende Backups können
  danach Platz verbrauchen; Betrieb benötigt Überwachung und Reserven. Der
  bestätigte Cloud-Image-Pin liegt unter der 10-GiB-Downloadreserve; größere
  angepasste Artefakte erfordern eine neu geprüfte Reserve.
- **Mittel:** App-Release-Pins, Nominatim-Unterabhängigkeiten, externe signierte
  APT-Quellen, privates HTTP/DB-TLS und Off-Host-Sicherung bleiben dokumentierte
  Entscheidungen. Der historische Legacy-Monitoring-Privatschlüssel benötigt
  separat autorisierte Rotation; der Debian-Pfad verwendet ihn nicht.
- **Mittel:** Gast-Firewall, ACME, große Imports, SMTP und vollständige Anwendung
  sind noch nicht zusammen auf echten KVM-Gästen getestet. Die CI-Nachweise
  belegen die einzelnen korrigierten Eigenschaften, keinen Produktiv-Rollout.

Referenzen: [Debian-13-Release-Notes](https://www.debian.org/releases/trixie/release-notes/),
[OpenSSH: ControlPath und Multiplexing](https://man.openbsd.org/ssh_config#ControlPath),
[systemd-run](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html).
