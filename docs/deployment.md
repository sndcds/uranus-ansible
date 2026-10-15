# Deployment

**Aktuell kein Deployment auf Hetzner, auch kein Check-Mode-Lauf.** Dieses Dokument
beschreibt die spätere, gesondert freizugebende Ausführung. Lokale Entwicklung
und CI dürfen nur Fixtures und isolierte Testumgebungen verwenden.

## Vorbereitung

1. Branch prüfen und `make check` auf der Entwicklungsmaschine ausführen.
2. Zielhost ausschließlich mit autorisiertem SSH-Zugang lesen: Debianversion,
   NVMe-Mount/UUID, freie Kapazität, CPU/KVM, aktive Hypervisorinstanzen, nftables,
   SSH und DNS erfassen. Dieses Repository verändert bestehende Altsysteme nicht.
3. `environments/hetzner/deployment.yml.example` nach `deployment.yml` kopieren.
   Echte Domains, ACME-Kontakt und private Web-CIDRs setzen. Administrative SSH-
   Verbindungen brauchen keine feste Quell-IP; sie erfordern einen Schlüssel.
   Beispielnetze `203.0.113.0/24` sind keine verwendbare Produktionsfreigabe.
4. `vault.yml.example` nach `vault.yml` kopieren. Separate generierte Secrets
   (`openssl rand -hex 32`) einsetzen und mit `ansible-vault encrypt` verschlüsseln.
5. Geprüfte vollständige Release-Commits für Backend/Frontend pro Umgebung
   bereitstellen. Image-Fingerprints verifizieren und Verfügbarkeit sichern.
   Kein automatisches Patchen inkompatibler Releases.
6. Interne PKI unter `environments/hetzner/pki` bereitstellen: `ca.crt` und je
   `hetzner`, `db01`, `dev01`, `prod01`, `mon01`, `nom01`, `vers01`, `nginx01` eine `.crt` und
   eine Ansible-Vault-verschlüsselte `.key`. SANs und EKUs wie in `networking.md`.
   Die CA selbst bleibt offline. Zertifikatsablauf und Rotation planen.
7. Externes Backup, Kapazität, Restore-Nachweis, RPO/RTO und Sicherheitsbefunde
   abnehmen. Schlüssel aus der alten Git-Historie widerrufen/rotieren.
8. Gast-SSH-Hostschlüssel aus vertrauenswürdigem Konsolenkanal in `known_hosts`
   aufnehmen. Firewall-Console/Rescuezugang verfügbar halten.
   Der bestehende Hostbenutzer muss ohne Rootlogin per Schlüssel und mit sudo
   erreichbar sein; einen verschlüsselten privaten Schlüssel vorher im SSH-Agent
   laden. Die Provisionierung ersetzt keine Hostschlüssel oder `authorized_keys`.
9. Erst nach **neuer ausdrücklicher Produktionsfreigabe** beide Sperrvariablen
   aktivieren. Diese Aufgabe enthält diese Freigabe nicht.

## Neue interne CA auf dem Controller vorbereiten

Wenn noch keine interne CA vorhanden ist, erzeugt der lokale Helfer eine neue
CA und die acht Knotenzertifikate aus Inventory und Instanzliste:

```bash
. .venv/bin/activate
python scripts/prepare_pki.py
```

Der Helfer benötigt OpenSSL, PyYAML und `ansible-vault`. Er erstellt
`environments/hetzner/pki/ca.crt` sowie die `.crt`- und `.key`-Dateien aller acht
Knoten. Zertifikate enthalten den Knotennamen als DNS-SAN, die jeweiligen IP-SANs
und `serverAuth`/`clientAuth`. Das Hostzertifikat enthält öffentliche IPv4/IPv6 und
die Bridge-IP. Vor Veröffentlichung prüft OpenSSL Kette, Zwecke, Namen, IPs und
die Übereinstimmung mit dem Schlüssel.

Alle privaten Schlüssel werden mit einer separaten Ansible-Vault-ID `pki`
verschlüsselt. Der verschlüsselte CA-Schlüssel und das neu generierte lokale
Vault-Passwort bleiben unter `.uranus-private/pki` auf dem Controller; dieses
Verzeichnis ist wie die PKI-Dateien von Git ausgeschlossen. Private Verzeichnisse
haben Modus `0700`, Schlüssel und Passwort `0600`. Die CA-Dateien aus dem privaten
Verzeichnis werden von keiner Rolle auf Hosts oder Gäste übertragen.
Der Helfer verweigert vorhandene Zielverzeichnisse, damit Wiederholungen weder
eine neue Vertrauenswurzel erzeugen noch bestehende Zertifikate überschreiben.

Die CA gilt zehn Jahre, Knotenzertifikate ein Jahr. CA, Vault-Zugang und PKI
gesichert aufbewahren und Zertifikate vor Ablauf kontrolliert erneuern.
Bei allen Deploymentphasen mit dieser PKI zum bisherigen Kommando hinzufügen:

```bash
--vault-id pki@.uranus-private/pki/vault-password
```

Das bisherige `--ask-vault-pass` für `vault.yml` kann zusätzlich bleiben.
[Ansible-Vault-IDs](https://docs.ansible.com/projects/ansible/latest/vault_guide/vault_using_encrypted_content.html).
Für vorhandene externe PKI-Dateien stattdessen `uranus_pki_dir` auf deren
Controllerverzeichnis setzen und den passenden Vault-Zugang verwenden.

Für einen mit der Vault-ID `production` verschlüsselten Anwendungs-Vault den
separaten lokalen Zugang ergänzen:

```bash
--vault-id production@.uranus-private/secrets/vault-password
```

`environments/hetzner/vault.yml` und die lokale Passwortdatei haben Modus `0600`;
das Passwortverzeichnis hat Modus `0700`. Beide sind von Git ausgeschlossen.
Dieser Zugang ersetzt `--ask-vault-pass` für den Anwendungs-Vault und wird
zusätzlich zum PKI-Zugang übergeben. Vorhandene gültige Secrets bei erneuter
Vorbereitung erhalten; eine Rotation benötigt abgestimmte Anwendungs- und
Datenbankkonfiguration.

## Start des Ansible-Laufs nach Freigabe

```bash
. /tmp/uranus-qa/bin/activate
ansible-playbook playbooks/site.yml \
  -e @environments/hetzner/deployment.yml \
  -e @environments/hetzner/vault.yml --ask-vault-pass
```

Das zentrale `ansible.cfg` wählt das einzige Inventory. Phaseweise:

```bash
ansible-playbook playbooks/provision.yml -e @environments/hetzner/deployment.yml -e @environments/hetzner/vault.yml --ask-vault-pass
ansible-playbook playbooks/configure.yml -e @environments/hetzner/deployment.yml -e @environments/hetzner/vault.yml --ask-vault-pass
ansible-playbook playbooks/ingress.yml -e @environments/hetzner/deployment.yml -e @environments/hetzner/vault.yml --ask-vault-pass
```

Für einen separaten PostgreSQL-Rollout auf der bereits provisionierten `db01`:

```bash
ansible-playbook playbooks/postgresql.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Dieser Einstieg prüft Freigabe, Debianversion und Bootstrapbestätigung und richtet
die interne TLS-Identität, PostgreSQL 17 mit PostGIS, Datenbankbenutzer,
Anwendungs- und Monitoringdatenbanken sowie tägliche lokale Datenbankbackups ein.
Die Secrets werden wie bei `configure.yml` aus `environments/hetzner/vault.yml`
geladen; bei verschlüsseltem Vault zusätzlich dessen Vault-Zugang angeben.
Abschließend werden PostgreSQL-Version, privater Listener, TLS, SCRAM und die
Syntax der Client-Zugriffsregeln geprüft. Erstimporte bleiben standardmäßig
deaktiviert; bestehende Datenbanken werden erhalten.

Bei erster Provisionierung zuerst `provision.yml`, danach die neuen Gast-
Hostschlüssel vertrauenswürdig prüfen, dann `configure.yml` und `ingress.yml`.
`provision.yml` bereitet Netzwerk, Hostnamen, Benutzer `debian`, Schlüsselzugang,
sudo und die gemeinsamen Pakete einschließlich `htop` auf allen laufenden VMs
und Containern über Incus vor. Bei bestehenden Gästen mit deaktiviertem Cloud-init
übernimmt Ansible diese Grundinstallation direkt. Für die erstmalige Verwendung
dieses Bootstrap-Schritts `provision.yml` auch bei bereits vorhandenen Instanzen
erneut ausführen; `configure.yml` prüft die dabei erstellte Bestätigung.
`site.yml` ist für Wiederholungen mit bereits bestätigten SSH-Identitäten geeignet.
Keine parallel laufenden Controller, kein `--skip-tags always`, keine ungeprüften
Variablenüberschreibungen. Provisionierungs-Check-Mode ist absichtlich gesperrt.

Initialimporte sind separate bewusste Entscheidungen:
`hetzner_app_initial_import` und `hetzner_nominatim_initial_import` sind
standardmäßig false. Bei vorhandenen DBs wird nicht neu importiert. Für einen
Nominatim-Erstimport müssen URL und SHA256 des OSM-Extrakts feststehen.

### Wechsel vom Host-Ingress zum Container

`ingress.yml` konfiguriert ausschließlich `nginx01`; der Host betreibt danach
Incus-Portproxies auf 80/443. Bei einer Erstinstallation müssen diese Ports frei
sein. Für einen bereits laufenden Host-Ingress ist vor der später freigegebenen
Umstellung ein Wartungsfenster nötig: Konfiguration und `/etc/letsencrypt` sichern,
den bisherigen nginx sowie dessen `certbot.timer` auf dem Host stoppen und
deaktivieren. Fremde Listener werden nicht automatisch beendet. Erst danach
`provision.yml` für den zusätzlichen Container ausführen, dessen SSH-Hostschlüssel
prüfen und `configure.yml` sowie `ingress.yml` ausführen. Das verursacht eine
Unterbrechung bis zur erfolgreichen Ingress-Konfiguration.

Bei vorhandener interner PKI `nginx01.crt` und dessen verschlüsselte `.key` mit
der bestehenden CA ausstellen. `prepare_pki.py` erzeugt nur eine neue PKI und
ergänzt bestehende Verzeichnisse nicht. Die vorhandene Vertrauenswurzel erhalten.
Die bisherige ACME-Identität kann aus der Sicherung nach `nginx01` übertragen
werden; andernfalls fordert die Rolle ein neues Zertifikat an. Konfiguration und
Zertifikate auf dem Host werden durch diesen Workflow nicht gelöscht. Den alten
Ingress erst nach erfolgreicher Prüfung des neuen Containers endgültig abbauen.

### Bereits angelegte, leere Anwendungsdatenbanken befüllen

`db01` verwendet für `uranus_prod` und `uranus_dev` denselben Dump `uranus.sql`.
Dieser Produktionsdump wird lokal neben dem Repository-README bereitgestellt
und ist von Git ausgeschlossen. Alternativ `debian13_postgresql_dump_root` auf
das Verzeichnis mit dem freigegebenen Dump setzen. Der versionierte Beispieldump
`uranus_dev.sql` dient den lokalen Integrationstests.
Sind die Datenbanken bereits durch `postgresql.yml` angelegt worden, führt der
separate Einstieg den ausdrücklich freigegebenen Import aus:

```bash
ansible-playbook playbooks/import-databases.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id production@.uranus-private/secrets/vault-password \
  -e hetzner_app_initial_import=true
```

Der Lauf prüft beide Ziele vor dem ersten Import. Jede Datenbank muss bereits
dem jeweiligen Anwendungsbenutzer gehören und PostGIS enthalten. Das Schema
`uranus` muss fehlen oder vollständig leer sein; auch vorhandene Typen oder
Funktionen verhindern den Import. Bestehende Abschluss- oder Unterbrechungsmarker
führen zum Abbruch. Check-Mode ist für diesen Einstieg gesperrt.

Vor jedem Import entsteht eine private Custom-Format-Sicherung unter
`/var/lib/postgresql/<datenbank>.before-initial-import.<zufall>.dump`; der Lauf
zeigt den Pfad an. Der Dump wird als Anwendungsbenutzer in einer Transaktion
über Loopback-TCP mit SCRAM-Anmeldung importiert; administrative Abfragen und
Backups verwenden den lokalen Unix-Socket. Eine erneute Prüfung innerhalb dieser
Transaktion verhindert den Import in ein inzwischen befülltes Schema.
Quelldateien bleiben unverändert;
in der übertragenen Kopie werden `oklab`-Owner-Anweisungen entfernt und das leere
Schema wiederverwendet. Bei Fehlern bleibt der Unterbrechungsmarker für eine
manuelle Prüfung erhalten. Weder Datenbanken noch vorhandene Objekte werden
gelöscht. Die Sicherungen dieses manuellen Imports werden nicht automatisch
bereinigt.

## Releases und Rollback

Frontend/Backend werden in revisionsgebundenen Verzeichnissen aufgebaut.
Backend-Build verwendet unveränderte Go-Modulmetadaten und verifizierte
Toolchain. Frontend-Buildverzeichnisse enthalten zusätzlich den Hash der öffentlichen
Buildkonfiguration und Node-Hauptversion; Änderungen überschreiben keine aktiven
statischen Artefakte. Frontend verlangt genau ein Lockfile und einen versionsgebundenen
pnpm-Manager, falls verwendet. Aktive Releases sind Symlinks; persistente Bilder
bleiben außerhalb der Releaseverzeichnisse.

Bei fehlgeschlagenem Backend-Healthcheck wird die vorherige Codeversion und,
falls vorhanden, die Konfigurationskopie zurückgestellt. Ein fehlgeschlagener
Frontend-Healthcheck stellt den alten statischen Artifact-Link wieder her.
Releaseverzeichnisse werden nicht automatisch gelöscht. Datenbankänderungen
werden nicht automatisch rückgängig gemacht; vor Versionswechsel Datenkompatibilität
prüfen. Für bewusstes Rollback die vorherigen freigegebenen Commit-IDs auswählen
und denselben Workflow ausführen, solange Schema und Releases kompatibel bleiben.
