# Deployment

**Die Repository-Standardwerte sperren produktive Läufe.** Dieses Dokument
beschreibt die ausdrücklich freizugebende Ausführung. Lokale Entwicklung
und CI verwenden nur Fixtures und isolierte Testumgebungen. Tatsächlich
ausgeführte Deployments und ihre Grenzen stehen in `testing.md`.

## Vorbereitung

1. Branch prüfen und `make check` auf der Entwicklungsmaschine ausführen.
2. Zielhost ausschließlich mit autorisiertem SSH-Zugang lesen: Debianversion,
   NVMe-Mount/UUID, freie Kapazität, CPU/KVM, aktive Hypervisorinstanzen, nftables,
   SSH und DNS erfassen. Die gesonderte Plausible-Migration verändert ausschließlich
   den bisherigen Plausible-Dienst und dessen dedizierte nginx-Route.
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
   `hetzner`, `db01`, `dev01`, `prod01`, `mon01`, `nom01`, `vers01`, `nginx01`, `plausible01` eine `.crt` und
   eine Ansible-Vault-verschlüsselte `.key`. SANs und EKUs wie in `networking.md`.
   Die CA selbst bleibt offline. Zertifikatsablauf und Rotation planen.
7. Externes Backup, Kapazität, Restore-Nachweis, RPO/RTO und Sicherheitsbefunde
   abnehmen. Schlüssel aus der alten Git-Historie widerrufen/rotieren.
8. Gast-SSH-Hostschlüssel aus vertrauenswürdigem Konsolenkanal in `known_hosts`
   aufnehmen. Firewall-Console/Rescuezugang verfügbar halten.
   Der bestehende Hostbenutzer muss ohne Rootlogin per Schlüssel und mit sudo
   erreichbar sein; einen verschlüsselten privaten Schlüssel vorher im SSH-Agent
   laden. Die Provisionierung ersetzt keine Hostschlüssel oder `authorized_keys`.
9. Erst nach **ausdrücklicher Produktionsfreigabe** beide Sperrvariablen
   aktivieren. Die Freigabe muss für die konkrete Ausführung vorliegen.

## Neue interne CA auf dem Controller vorbereiten

Wenn noch keine interne CA vorhanden ist, erzeugt der lokale Helfer eine neue
CA und die neun Knotenzertifikate aus Inventory und Instanzliste:

```bash
. .venv/bin/activate
python scripts/prepare_pki.py
```

Der Helfer benötigt OpenSSL, PyYAML und `ansible-vault`. Er erstellt
`environments/hetzner/pki/ca.crt` sowie die `.crt`- und `.key`-Dateien aller neun
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

Bei vorhandener verwalteter CA ergänzt `python scripts/extend_pki.py` ausschließlich
fehlende Knoten und erhält bestehende Identitäten. Den CA-Schlüssel niemals erneut
verschlüsseln; `input is already encrypted` bedeutet, dass dieser Schritt schon erfolgt ist.

Für den eigenen Plausible-Container, den nativen Build, die gesonderte
Datenübernahme und den DNS-Wechsel siehe [Plausible](plausible.md).

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

Für einen gezielten nginx-Rollout auf bereits provisionierten Gästen:

```bash
. .venv/bin/activate
ANSIBLE_LOCAL_TEMP=/tmp/uranus-ansible-local \
ANSIBLE_COLLECTIONS_PATH="$HOME/.ansible/collections:/usr/share/ansible/collections:/usr/lib/python3/dist-packages/ansible_collections" \
ansible-playbook playbooks/nginx.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Dieser Einstieg richtet interne TLS-Identitäten, die Gastgrundkonfiguration
einschließlich Firewall und nginx auf `dev01`, `prod01`, `mon01`, `nom01` und
`vers01` ein. Anschließend folgt `ingress.yml` für `nginx01` einschließlich ACME.
Anwendungscode, Datenbanken und Datenimporte werden dabei nicht ausgerollt.
Frontendartefakte und Upstreamdienste müssen bereits vorhanden sein. Incus-
Portproxies und SSH-Hostschlüssel müssen ebenfalls vorbereitet sein.
Für Entwicklung und Monitoring echte Zugriffsnetze unter
`hetzner_private_web_networks` setzen; das Beispielnetz ist keine Freigabe.
Wenn ausdrücklich auch diese Websites öffentlich erreichbar sein sollen,
`hetzner_private_sites: []` und `hetzner_private_web_networks: []` in der lokalen
`deployment.yml` setzen. Die zentralen Standardwerte bleiben eingeschränkt.

Solange das öffentliche DNS noch nicht auf Hetzner zeigt, kann derselbe Lauf mit
`-e debian13_ingress_prepare_only=true` die internen Webserver und den öffentlichen
HTTP-Endpunkt für ACME vorbereiten. Dabei werden keine öffentlichen Zertifikate
angefordert und keine zusätzlichen HTTPS-Sites aktiviert. Bereits vorhandene
gültige Domain-Zertifikate und die zugehörigen HTTPS-Routen bleiben aktiv. Nach der DNS-Umstellung den
Lauf ohne diese Option wiederholen; die DNS-Prüfung bleibt vor jeder
Zertifikatsanforderung verpflichtend.

Für einen schrittweisen TLS-Rollout `debian13_ingress_tls_site_keys` auf die
bereits im DNS eingerichteten Dienste beschränken, beispielsweise
`debian13_ingress_tls_site_keys: [versatiles]`. Die aktuelle VersaTiles-Domain
wird in der vorhandenen `hetzner_domains`-Liste mit
`versatiles: versatiles.oklabflensburg.de` gesetzt. Andere Dienste können später
zur TLS-Liste hinzugefügt werden. Die Rolle prüft DNS vor der Ausstellung und
verwendet getrennte Zertifikate unter `/etc/letsencrypt/live/<domain>/`.
Hostnamen- und Ablaufprüfung erfolgen getrennt, weil OpenSSL bei
`-checkend` die zusätzliche Hostnamenprüfung nicht ausführt. Der systemd-Timer
von Certbot übernimmt die Erneuerung; der Deploy-Hook prüft nginx vor dem Reload.

Für Browsertests direkt über die Server-IP zusätzlich
`debian13_ingress_ip_testing: true` in der lokalen `deployment.yml` setzen und
`ingress.yml` mit `-e debian13_ingress_prepare_only=true` ausführen. Unter
`http://94.130.236.38/` erscheint eine Testseite mit Nominatim-Suche und
Statuslinks. `/nominatim/` wird an den vorhandenen Nominatim-Gast weitergeleitet;
die interne TLS-Zertifikatsprüfung bleibt aktiv. Die API muss bereits installiert
und importiert sein. IPv4 und IPv6 funktionieren ohne öffentliche DNS-Auflösung.
Die Domainrouten behalten ihre HTTPS-Weiterleitung. Nach Abschluss der IP-Tests
die Option wieder auf `false` setzen und den Ingress erneut ausrollen.

Für Nominatim auf der provisionierten `nom01` steht ein eigener Einstieg bereit:

Für den vorbereiteten Austausch von Schleswig-Holstein gegen Europa einschließlich
der Vergrößerung von `db01` siehe [Europa-Import](nominatim-europe.md).

```bash
ansible-playbook playbooks/nominatim.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Die Rolle installiert Nominatim 5.3.3 in einer versionsgebundenen Umgebung unter
`/opt/nominatim/5.3.3/venv` und betreibt die Falcon-ASGI-Anwendung mit Gunicorn
über den privaten HTTP-Unix-Socket. Bei einem ausdrücklich freigegebenen
Erstimport zusätzlich `-e hetzner_nominatim_initial_import=true` angeben und
`nominatim_data_url`, `nominatim_data_sha256` sowie `nominatim_data_file` auf den
geprüften datierten Extrakt setzen. Der Datenbankgast benötigt vor dem Import
mindestens 10 GiB freien Platz. Die Rolle verändert keine Partitionen.

Eine vorhandene Datenbank wird nur verwendet, wenn Nominatim-Schema und
abgeschlossener Indexstatus vorliegen; sie wird nicht gelöscht oder neu
importiert. Für die anfängliche Datenbank- und Extensionvorbereitung werden
vorübergehend erhöhte Rechte vergeben und auch bei einem Fehler widerrufen.
Der längere Datenimport läuft danach ohne Superuserrechte mit vier Threads.
Wie im bisherigen Workflow wird ohne laufende OSM-Replikation importiert.
Vor der Aktivierung werden die Datenbankintegrität, die ASGI-Konfiguration
und der API-Status geprüft. Versionswechsel bestehender Datenbanken benötigen
gegebenenfalls eine gesicherte Migration gemäß der jeweiligen Nominatim-Version.

Für Europa-Karten auf der provisionierten `vers01`:

```bash
ansible-playbook playbooks/versatiles.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Die Rolle installiert den per SHA256 festgelegten VersaTiles-Release 5.2.0 und
das Frontend 3.16.0. Der Europa-Ausschnitt wird aus dem datierten
[offiziellen OSM-Kartensatz vom 8. Juni 2026](https://download.versatiles.org/)
geladen: Bounding Box `-32,34,45,72`, Zoomstufen 0–14 und drei Kacheln Rand.
Dies ist ein rechteckiger Ausschnitt einschließlich benachbarter Gebiete,
keine Beschneidung entlang von Ländergrenzen. Die Anbieterprüfsumme der
gesamten Quelldatei lautet
`33891ea780deb8a0eb37b3e238ad33d323efec3ae10bceb6e03d1e5eab7d2cca`;
bei einem Bereichsdownload wird die ganze Quelldatei nicht heruntergeladen
oder vollständig gehasht.

Die TileJSON-Gesamtgrenzen können durch Randkacheln auf niedrigen Zoomstufen
größer als dieser Ausschnitt sein. Die hochauflösenden Kacheln bleiben auf
den gewählten Bereich begrenzt; die Browserkarte verwendet eigene
Navigationsgrenzen für Europa.

Vor dem ersten Download werden mindestens 30 GiB freier Platz geprüft. Der
längere Import läuft asynchron und speichert zunächst eine separate Datei.
Erst nach erfolgreicher Containerprüfung wird `europe.versatiles` atomar
aktiviert. Ein vorhandener fertiger Datensatz wird geprüft und erhalten.
Für andere Regionen oder einen neuen Datenstand einen neuen Dateinamen
konfigurieren; die Rolle überschreibt vorhandene Kartendaten nicht.

VersaTiles hört privat auf `127.0.0.1:8080`; Gast-nginx nimmt TLS ausschließlich
vom Ingress entgegen. Für den vorhandenen HTTP-Testmodus zusätzlich
`debian13_ingress_ip_tiles: true` in `deployment.yml` setzen und `ingress.yml`
mit `-e debian13_ingress_prepare_only=true` ausrollen. Die Karte erscheint unter
`http://94.130.236.38/map/`, TileJSON unter `/tiles/osm/tiles.json`. Bibliotheken,
Schriftarten, Symbole und Kacheln kommen über denselben Ingress mit geprüfter
interner TLS-Verbindung. Domain-TLS wird weiterhin nach der DNS-Umstellung
über den regulären Ingress-Lauf eingerichtet.

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

Der Kulturbytes-Client aus `sndcds/kulturbytes-client` läuft auf `dev01` und
`prod01` als Nuxt-SSR-Anwendung (`frontend_runtime: node`). Beide Umgebungen
verwenden zunächst Commit `359a6cd84afdead4212ae8040e41d969e050b5b9`;
weitere Updates werden über `frontend_repo_version` in den jeweiligen
Hostvariablen freigegeben. Für einen isolierten Frontend-Rollout:

```bash
ansible-playbook playbooks/frontend.yml --limit dev01 \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
# Nach Prüfung denselben Aufruf mit --limit prod01 wiederholen.
```

Das Playbook verändert weder Backend-Code noch Datenbankschemata. Node.js 24
und Corepack bauen mit dem exakten `packageManager`-Eintrag und
`pnpm install --frozen-lockfile`. Eine zusätzliche Nuxt-Konfiguration außerhalb
des Checkouts aktiviert den Node-Server und leitet `/api/**` sowie `/pluto/**`
an das lokale Backend auf Port 9090 weiter. `NUXT_PUBLIC_API_URL=/` gilt für
SSR und Browser; `NUXT_PUBLIC_SITE_URL` enthält die jeweilige Frontend-Domain.
Der Dienst `uranus-frontend` läuft als `uranus` ausschließlich auf
`127.0.0.1:3000`. Der private nginx vermittelt TLS-Verbindungen vom zentralen
Ingress an diesen Dienst. API-Domains bleiben zusätzlich erreichbar.
Der Ingress trennt das Anfragelimit für Nuxt-Dateien, Fonts und Bilder vom
Budget für Seiten und API-Aufrufe, damit parallele Downloads die anschließende
Navigation nicht mit HTTP 429 blockieren.

Nach dem Build werden `/de`, `/api/events` und die interne TLS-Route geprüft.
Öffentliche Zertifikate werden anschließend über `ingress.yml` aktiviert,
sobald die jeweiligen A-/AAAA-Einträge auf den Ingress zeigen. Für Entwicklung
`dev_frontend` und `dev_backend`, für Produktion `prod_frontend` und
`prod_backend` zur bestehenden `debian13_ingress_tls_site_keys`-Liste ergänzen.
Der Kulturbytes-Client bleibt unter `dev.kulturbytes.de`; das separate
Uranus-Dashboard verwendet `app.dev.kulturbytes.de` (siehe unten).

Frontend/Backend werden in revisionsgebundenen Verzeichnissen aufgebaut.
Backend-Build verwendet unveränderte Go-Modulmetadaten und verifizierte
Toolchain. Frontend-Buildverzeichnisse enthalten zusätzlich den Hash der öffentlichen
Buildkonfiguration und Node-Hauptversion; Änderungen überschreiben keine aktiven
Artefakte. Der Nuxt-Build verlangt einen exakt festgelegten pnpm-Manager;
ein Build-Marker entsteht erst nach erfolgreichem Build und Prüfung des
Server-Einstiegspunkts. Der weiterhin unterstützte statische Build verlangt
genau ein Lockfile. Aktive Releases sind Symlinks; persistente Bilder
bleiben außerhalb der Releaseverzeichnisse.

Bei fehlgeschlagenem Backend-Healthcheck wird die vorherige Codeversion und,
falls vorhanden, die Konfigurationskopie zurückgestellt. Ein fehlgeschlagener
Nuxt-Frontend-Healthcheck stellt den bisherigen Release-Link, die vorherige
systemd-Unit, Laufzeitumgebung und nginx-Konfiguration wieder her. Beim ersten
SSR-Rollout wird damit auch das vorherige statische Frontend wieder aktiviert.
Releaseverzeichnisse werden nicht automatisch gelöscht. Datenbankänderungen
werden nicht automatisch rückgängig gemacht; vor Versionswechsel Datenkompatibilität
prüfen. Für bewusstes Rollback die vorherigen freigegebenen Commit-IDs auswählen
und denselben Workflow ausführen, solange Schema und Releases kompatibel bleiben.

## Medien und zentrale Backend-Konfiguration

`playbooks/backend.yml` konfiguriert die bereits installierten Backend-Releases
auf `dev01` und `prod01`, ohne Quellcode neu zu bauen oder Datenbanken zu ändern.
Die Anordnung trennt Konfiguration, persistente Nutzdaten und löschbaren Cache:

| Inhalt | Aktiver Pfad | Konfigurationsschlüssel | Rechte |
|---|---|---|---|
| Backend-Konfiguration | `/etc/uranus/config.json` | systemd `-config` | `uranus:uranus`, `0600` |
| Avatare | `/var/lib/uranus/avatar` | `profile_image_dir` | Verzeichnis `0750`, Dateien `0640` |
| Originalbilder | `/var/lib/uranus/image` | `pluto_image_dir` | Verzeichnis `0750`, Dateien `0640` |
| Bildcache | `/var/cache/uranus` | `pluto_cache_dir` | Verzeichnis `0750`, Dateien `0640` |

Daten und Cache gehören jeweils `uranus:uranus`. `/etc/uranus` bleibt
`root:uranus` mit `0751`, damit andere TLS-Verbraucher ihre Zertifikate erreichen;
die Konfiguration ist nur für den Dienstbenutzer lesbar. `/var/lib/uranus`
selbst bleibt `root:root`, damit Anwendungen die dort
liegende Incus-Bootstrapbestätigung nicht ersetzen können. Der Backend-Dienst
verwendet `UMask=0027`. Bilddateizähler und tägliche Anwendungssicherung beziehen
sich auf die neuen persistenten Verzeichnisse. Der Cache wird nicht täglich
archiviert, weil er aus Originalbildern wieder aufgebaut werden kann.

Vorbereitung und Aktivierung verwenden denselben freigegebenen Einstieg:

```bash
ansible-playbook playbooks/backend.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password \
  -e debian13_backend_prepare_only=true
# Nach der Datenübertragung denselben Aufruf ohne prepare_only wiederholen.
```

Die Vorbereitung installiert rsync und erstellt nur die Zielverzeichnisse.
Danach werden Dateien über SSH mit rsync übertragen, ohne Quell- oder
Zieldateien zu löschen. Für `/opt/dev/go` auf `awendelk@webserver` gilt:
`avatar/` wird nach `/var/lib/uranus/avatar/`, `image/` nach
`/var/lib/uranus/image/` und `cache/` nach `/var/cache/uranus/` übertragen.
Die abschließenden Schrägstriche bedeuten jeweils den Verzeichnisinhalt.
Die Dateieigentümer werden auf den Zielbenutzer umgesetzt; numerische IDs des
alten Benutzers `oklab` werden nicht übernommen. Nach der Übertragung werden
Dateiinhalte per SHA-256, Eigentümer und Rechte auf beiden Gästen geprüft.

`/opt/dev/go/pluto/` enthält einen alten Programmcheckout einschließlich
Git-Metadaten und Binärdatei. Zusammen mit der alten 419-Byte-`config.json` wird
er ausschließlich unter `/var/backups/uranus/migration-<UTC>/source/` als
restriktiv berechtigter Altbestand aufgehoben. Die aktive Konfiguration wird
mit den jeweiligen Ansible-/Vault-Einstellungen für Dev und Prod erzeugt.
Vorherige Laufzeitdateien liegen im selben Sicherungsverzeichnis in
`before-runtime.tar.gz`; Dateien, die rsync ersetzen musste, unter `overwritten/`.
Diese Migrationssicherungen werden nicht automatisch bereinigt.

Bei fehlgeschlagener Aktivierung stellt Ansible die bisherige zentrale
Konfiguration, systemd-Unit und den vorherigen Release-Link wieder her. Beim
ersten Wechsel von einer Konfiguration im Release-Verzeichnis bleibt diese
vorhanden und wird von der wiederhergestellten alten Unit weiter verwendet.
Neue Medienverzeichnisse und bereits übertragene Dateien werden bei einem
Rollback nicht gelöscht. Vor einer späteren öffentlichen Produktionsumschaltung
neu hinzugekommene Originalbilder und Avatare aus dem weiterhin laufenden
Quellsystem nachziehen; eine Dateikopie stoppt dessen laufende Uploads nicht.

## Uranus-Dashboard auf dev01

`app.dev.kulturbytes.de` ist ein zusätzlicher Vhost auf demselben zentralen
nginx wie der Kulturbytes-Client. A und AAAA zeigen auf `94.130.236.38` bzw.
`2a01:4f8:13b:1405::2`. Das Dashboard wird aus
`https://github.com/sndcds/uranus-dashboard.git` gebaut. Quellrevision und Domain
stehen in den Hostvariablen von `dev01`; andere Gäste aktivieren es nicht.

```bash
ansible-playbook playbooks/dashboard.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
ansible-playbook playbooks/ingress.yml \
  -e @environments/hetzner/deployment.yml \
  --vault-id pki@.uranus-private/pki/vault-password \
  --vault-id production@.uranus-private/secrets/vault-password
```

Das erste Playbook stellt den gepinnten Dev-Backend-Stand und anschließend den
separaten statischen Dashboard-Build bereit. Die gesperrte pnpm-Version aus
`package.json` und `pnpm-lock.yaml` bestimmen den Build. Releases liegen unter
`/opt/uranus/dashboard/releases/<Commit>-<Konfigurationshash>/dist`;
`/opt/uranus/dashboard/current` zeigt auf das geprüfte Ergebnis. Bei einer
fehlgeschlagenen Aktivierung werden dieser Link und die vorherige private
nginx-Konfiguration wiederhergestellt.

`VITE_API_URL` verwendet die eigene Dashboard-Domain. nginx auf dev01 leitet
`/api/` an `127.0.0.1:9090` weiter und erhält die ursprüngliche Browser-Origin
für die CSRF-Prüfung. Vue-Routen wie `/app/login` funktionieren auch bei einem
direkten Aufruf. Fehlende Assets und API-Pfade werden nicht durch die SPA-Seite
ersetzt. Statische Vite-Dateien nutzen das Medienbudget; die anfänglichen
parallelen Lookup-Anfragen erhalten ein separates API-Budget mit 20 Anfragen
pro Sekunde und einem Burst von 40. Die übrigen Anwendungslimits bleiben erhalten.
Die Backend-Origin-Liste muss `https://app.dev.kulturbytes.de` ausdrücklich
zulassen; andernfalls werden Cookie-Anmeldung, Erneuerung und Änderungen
abgewiesen. Passwort-Rücksetzlinks für Entwicklung verwenden
`https://app.dev.kulturbytes.de/app/reset-password`.

Upload-Limits werden für Backend und beide nginx-Stufen aus
`backend_pluto_image_max_file_size` abgeleitet. Dieser Ansible-Wert ist in MiB
angegeben (Standard: 20). In `/etc/uranus/config.json` stehen dafür
`pluto_max_image_size: 20971520` und derselbe Bytewert im älteren
`pluto_image_max_file_size`-Feld. Die eingebundene Pluto-Bibliothek liest den
ersten Schlüssel. Entsprechend wird auch `pluto_max_image_px` neben dem
bisherigen Pixelfeld erzeugt. nginx erlaubt die konfigurierte Dateigröße
zuzüglich 1 MiB für Multipart-Rahmen und Metadaten, also standardmäßig
`client_max_body_size 22020096;`. Das gilt auf den privaten Anwendungsgästen
für Client, API und Dashboard und am öffentlichen Ingress jeweils passend zum
Zielgast. Die Backend-Dateigrenze bleibt exakt 20 MiB; zusätzliche
kontextspezifische Pluto-Regeln in der Datenbank gelten weiterhin.

Die dafür nötige zusätzliche Backend-Origin steht in
[Backend-PR 258](https://github.com/sndcds/uranus/pull/258). Dev verwendet den
getesteten Commit `d06a615b4b4c8454f5298902fabcddd1d7985834`; der
Produktions-Backend-Stand wird dadurch nicht geändert.

Die öffentliche TLS-Auswahl enthält zusätzlich `dev_dashboard`; bereits
zertifizierte Domains bleiben aktiv. Eine Produktions-DNS-Umschaltung ist für
diesen Dev-Rollout nicht erforderlich.
