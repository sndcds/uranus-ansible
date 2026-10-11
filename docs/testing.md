# Tests und Nachweisgrenzen

`make check` umfasst Repository-Policy, Python-/Ansible-Integrationstests,
Syntaxprüfung aller unterstützten Playbooks und `ansible-lint` im Production-
Profil. Tests verwenden ausschließlich lokale Fixtures und isolierte Datenbanken.

| Prüfung | Methode |
|---|---|
| YAML / Abhängigkeiten / Variablen / private Schlüssel | Repository-Policy und ansible-lint |
| Gates vor jeder SSH-Verbindung | reale Ansible-Läufe gegen nicht erreichbare Loopback-Fixtures, normal und Check Mode |
| Incus Erstplan / Wiederholung / gestoppte Instanzen | lesender API-Preflight mit echten Incus-API-Schemas als Fixtures |
| UUID / Read-only / fehlender Mount / Symlink / Unter-Mount | Fehler-Injektion, kein Formatieren |
| Kapazität / Netzwerküberschneidung / APIfehler / Drift | adversariale Python-Tests |
| Init-Abbruch / fremde Geräte / Owner / verwaiste Daten | Erhaltungstests und Fail-closed-Verhalten |
| Firewallrecovery | Timerreihenfolge, bestätigter Wechsel, Ablauf, Applyfehler, konkurrierende Updates; native nftables-Parser für Host und sechs Gäste |
| Cloud-init | native Cloud-init-Schemaprüfung für VM und Container |
| Nginx und TLSrouting | echter Nginxparser mit isolierten Loopbackports und Testzertifikaten |
| PostgreSQL Erstimport / Wiederholung / Pending / SQL-Escape | reale Ansible-DB-Tasks gegen temporären Unix-Socket, ohne TCP |
| Native Debianpakete / Incus-CLI | isolierte Debian-13-Testumgebung; Ergebnisse im PR |

Eine erfolgreiche statische Prüfung ist kein vollständiger Incus-/Anwendungs-
End-to-End-Nachweis. Container- und VMstart, Gast-Ansible mit realen Anwendungen,
TLS-Clientverbindungen, Import, Updates, externe Backups und kompletter Restore
müssen in einem isolierten Pilot mit geprüften Releases und Secrets abgenommen
werden. Tests auf Hetzner gehören nicht zu dieser Arbeit. Nicht ausgeführte
Prüfungen werden im PR ausdrücklich benannt.

## Lokal ausgeführte Prüfungen am 11. Oktober 2026

- Vollständiger lokaler Lauf: 86 Tests erfolgreich. Syntax und ansible-lint prüfen alle
  vier unterstützten Playbooks und sämtliche verbleibenden Rollen.
- Native Debian-13-Pakete: Incus 6.0.4, PostgreSQL 17, Icinga 2.14.6.
- Ein isolierter Docker-Lab prüfte mit echten Debian-Cloudimages die Erstellung
  von Projekt, Directory-Pool, privatem Netzwerk und allen sechs Instanzen.
  Der tatsächliche lesende Incus-Preflight lief anschließend zweimal erfolgreich
  ohne Zustandsänderung. Der produktive NVMe-/UUID-Guard wurde dabei bewusst
  durch einen Fixture ersetzt; dessen Fehlerfälle prüft die Python-Suite.
- `db01` erreicht den Incus-Zustand `Running`; Gastbetriebssystem und SSH sind
  noch nicht nachgewiesen, weil der VM-Agent im Lab nicht erreichbar war.
- Der Containerstart schlug im verschachtelten Docker-Lab fehl: LXC konnte die
  cgroup-v2-Controller nicht delegieren (`Device or resource busy`, anschließend
  `memory.max` nicht verfügbar). Dieser Integrationstest ist **nicht bestanden**.
- Die nativen nftables-Parserprüfungen für Host und sechs Gastrollen inklusive
  IPv4/IPv6 sind erfolgreich, ohne Regeln anzuwenden.
- Die echten Icinga-Parserprüfungen für Host, Master, Container und VM sind
  erfolgreich. Sie fanden und behoben fehlende Monitoring-Zonenzuordnungen.

Die CI führt `scripts/incus_smoke.py` nur in einem privilegierten, wegwerfbaren
Debian-Container mit frischem `/tmp/uranus-incus-smoke-*` aus. Es testet die
native Initialisierung und wiederholten Preflight. `--boot` fordert zusätzlich
Container-/VM-Boot, Cloud-init und SSH und ist für einen Pilot mit delegierten
cgroups und KVM vorgesehen. Ohne diesen Schalter werden diese Prüfungen sichtbar
als `NOT RUN` ausgegeben. Auch dieser Test verwendet niemals den Zielhost.

Ein vollständiger Anwendungspilot einschließlich Healthchecks, TLS, realen
Importen und externem Restore ist weiterhin offen. Ein grüner CI-Lauf ersetzt
keinen dieser ausdrücklich fehlenden Nachweise.

Der native GitHub-Vertragstest benötigt `vhost_vsock`. Das erste CI-Lab
verweigerte VM-Initialisierung wegen des fehlenden Moduls. Die CI lädt es jetzt
ausschließlich auf dem wegwerfbaren GitHub-Runner und stellt dessen Device im
Testcontainer bereit. Kernelmodul-Dateien werden nur lesend eingebunden; bei
fehlendem KVM/Transport bricht der Job ab, ohne VMprüfungen zu überspringen.
