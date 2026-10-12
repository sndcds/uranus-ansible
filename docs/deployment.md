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
   `hetzner`, `db01`, `dev01`, `prod01`, `mon01`, `nom01`, `vers01` eine `.crt` und
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
CA und die sieben Knotenzertifikate aus Inventory und Instanzliste:

```bash
. .venv/bin/activate
python scripts/prepare_pki.py
```

Der Helfer benötigt OpenSSL, PyYAML und `ansible-vault`. Er erstellt
`environments/hetzner/pki/ca.crt` sowie die `.crt`- und `.key`-Dateien aller sieben
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
