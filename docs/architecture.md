# Architektur

Der dedizierte Debian-13-Host verwaltet Incus, nftables, Nginx und ACME. Ein
privater Icinga-Agent überwacht Host und Daten-NVMe. PostgreSQL und alle Uranus-
Anwendungen laufen ausschließlich in Incus-Instanzen. SSH dient Ansible als
Transport; Incus-Konsole und `incus exec` bleiben Recovery-Werkzeuge.

```mermaid
flowchart TD
  Internet -->|HTTPS 443| Host[Hetzner: Nginx / ACME]
  Admin -->|SSH: erlaubte CIDRs| Host
  Host -->|TLS / private Bridge| App[dev01 / prod01]
  Host -->|TLS| Mon[mon01: Icinga / InfluxDB / Grafana]
  Host -->|TLS| Nom[nom01: Nominatim]
  Host -->|TLS| Vers[vers01: VersaTiles]
  App -->|PostgreSQL TLS| DB[db01: Incus VM / PostgreSQL 17]
  Nom -->|PostgreSQL TLS| DB
  Mon -->|PostgreSQL TLS| DB
  Incus[Incus: lokaler Unix-Socket] --> Data[/data/incus: Datenbank, Images, Volumes, Exporte]
```

| Instanz | Standardtyp | RAM | CPU-Limit | Storage-Budget | Private IP |
|---|---|---:|---:|---:|---|
| db01 | VM | 12 GiB | 4 | 150 GiB | 10.77.0.11 |
| dev01 | Container | 4 GiB | 2 | 60 GiB | 10.77.0.12 |
| prod01 | Container | 8 GiB | 4 | 100 GiB | 10.77.0.13 |
| mon01 | Container | 4 GiB | 2 | 50 GiB | 10.77.0.14 |
| nom01 | Container | 12 GiB | 6 | 200 GiB | 10.77.0.15 |
| vers01 | Container | 2 GiB | 2 | 40 GiB | 10.77.0.16 |

Die Konfiguration verwendet GiB/MiB, keine dezimalen GB. Insgesamt 42 GiB RAM,
20 CPU-Zuweisungen und 600 GiB Diskbudget. Auf 12 Hardwarethreads besteht eine
CPU-Überbuchung von etwa 1,67; CPU-Anzahlen reservieren keine dedizierten Kerne.
8 GiB Hostreserve sind zusätzlich eingeplant. Angaben zur Hardware stammen vom
Betreiber; der reale Hostzustand wurde hier nicht inventarisiert.

`type` kann für jede Instanz `container` oder `virtual-machine` sein. Diese Wahl
gilt bei der ersten Erstellung. Ein späterer Typwechsel ist eine Datenmigration,
keine automatische Neuerstellung. Anwendungsrollen kennen nur ihre Dienstrolle;
nur die Gastbasis berücksichtigt fehlende Hardware- und Zeitdienste im Container.

| Zuständigkeit | Implementierung |
|---|---|
| Hostpakete, Datenpfad, Startschutz | `incus_host` |
| Projekt, Pool, Netzwerk, Instanzen | `incus_instance`, native Incus-CLI |
| Sicherheitsprüfung vor Erstellung | rein lesende `uranus_incus_guard` / `uranus_storage_guard` |
| Firewalltransaktion | `host_firewall` |
| Gastbasis / interner TLS-Endpunkt | `debian13_guest`, `internal_tls`, `debian13_guest_web` |
| Anwendungen | konsolidierte `debian13_*`-Rollen |
| Verfügbarkeit, CPU/RAM/Disk/Netz | `icinga_agent`, `debian13_monitoring` |
| Datensicherung | `debian13_backup`, `application_backup`, optional `incus_backup` |

Es gibt keine alternative Provisionierung. Die historischen Ansätze lassen sich
nur über Git vergleichen: Container teilen den Hostkernel und haben weniger
Gast-Overhead; eine Incus-VM besitzt einen eigenen Kernel. Die hybride Auswahl
schützt PostgreSQL mit einer VM und spart Kernel-/Boot-Overhead für Webdienste.
Das sind Architekturmerkmale, keine gemessenen Benchmarks. CPU-Latenz, RAM,
Importdauer, Sicherungsdauer und Restore müssen im späteren isolierten Pilot
mit identischen Daten und Ressourcen gemessen werden.
