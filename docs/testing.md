# Tests und Nachweisgrenzen

## kulturbytes-Handbuch aktiviert am 30. Oktober 2026

`https://docs.kulturbytes.de/` ist über nginx01 mit eigenem
Let's-Encrypt-Zertifikat aktiv. Auf dev01 wurde das Repository
`sndcds/kulturbytes-manual`, Branch `main`, Revision
`b79ebee670d0d0357a8332f6713bde9937c0b827`, als Benutzer `uranus` nach
`/opt/uranus/documentation/kulturbytes-manual` geklont. `npm ci` installierte
die gesperrten Abhängigkeiten einschließlich Blume 2.2.1; `npm run build`
erzeugte erfolgreich 48 statische Seiten in `dist/`.

`playbooks/nginx.yml --limit dev01,nginx01` bestand mit `unreachable=0` und
`failed=0` auf beiden Hosts: dev01 meldete `ok=43`, `changed=2`, nginx01
`ok=91`, `changed=5`. Nur für den neuen Service-Key `manual` wurde ein
Zertifikat angefordert. Es ist bis zum 28. Januar 2027 gültig;
`certbot.timer` und der vorhandene Renewal-Hook sind aktiv. nginx01 prüft
weiterhin CA und Knotennamen der internen TLS-Verbindung nach dev01.

Der private Vhost liefert den statischen Build am Domain-Hauptpfad aus.
Ansible übernahm 43 Weiterleitungen aus `dist/blume-redirects.json`, darunter
die Root-Weiterleitung nach `/en` und bisherige Kapitel-URLs einschließlich
Markdown-/MDX-Varianten. Die HTTP-308-Weiterleitungen und die automatischen
Verzeichnisweiterleitungen erhalten Query-Parameter und enthalten keine
internen Hostadressen. Fehlende Kapitel, Assets, `package.json` und
`/.git/config` lieferten HTTP 404.

Öffentliche IPv4- und IPv6-Aufrufe vom Hetzner-Host endeten jeweils mit HTTP
200 auf `/en/`. Englische, deutsche und dänische Startseiten und Kapitel,
die neuen deutschen Portal-/Team-Seiten, Suchindex, Screenshot und zwölf
eingebundene Assets waren erreichbar. Weitere 80 Abrufe mit bis zu 16
parallelen Verbindungen lieferten ausschließlich HTTP 200, keine HTTP 429.
Ein externer Chromium-Aufruf bestätigte alle drei Sprachversionen, den
Sprachwechsel am gleichen Kapitel, deutsche Suchtreffer, den geladenen
Registrierungs-Screenshot und eine Mobilansicht ohne horizontales Überlaufen.
Dabei traten weder JavaScriptfehler noch fehlgeschlagene Browseranfragen auf.
Die bestehenden Uranus-Docs und das Dashboard lieferten weiterhin HTTP 200.

Vor dem Rollout bestanden 59 lokale nginx-/Rollback-Tests, Repository-Policy,
Syntaxprüfung aller Playbooks und ansible-lint im Production-Profil für die
betroffenen Rollen. Nach der vom Linter verlangten Variablenumbenennung
bestand die gezielte Handbuchprüfung erneut.

Die vorherigen nginx-Konfigurationen liegen geschützt auf dev01 unter
`/var/backups/kulturbytes-manual-20261030-FTc4dl/` und auf nginx01 unter
`/var/backups/kulturbytes-manual-20261030-3dbyAS/`. Build-, Rollout- und
Prüfprotokolle liegen lokal unter `.uranus-private/manual-rollout/`.

## Uranus-Dokumentation unter `/docs` aktiviert am 30. Oktober 2026

Nach DNS-Einrichtung und ausdrücklicher Freigabe wurde
`https://uranus.kulturbytes.de/docs/` auf nginx01 aktiviert. Die Quellen auf
dev01 liegen unter `/opt/uranus/documentation/uranus-docs`, Revision `d628565`.
Der vorhandene Stand wurde als Benutzer `uranus` mit Blume 1.7.3 und
`./node_modules/.bin/blume build --base /docs` erfolgreich neu gebaut
(26 Seiten). nginx liefert ausschließlich den statischen Inhalt aus `dist/`.
Startseite und API-Referenz enthalten die korrekten `/docs`-Präfixe; der
nginx-Benutzer kann die Dateien lesen.

`playbooks/nginx.yml --limit dev01,nginx01` bestand auf dev01 mit
`ok=40`, `changed=2`, `failed=0`, auf nginx01 mit `ok=90`, `changed=5`,
`failed=0`; beide Hosts meldeten `unreachable=0`. Nur für `documentation`
wurde ein neues Let's-Encrypt-Zertifikat angefordert. Es ist für
`uranus.kulturbytes.de` ausgestellt und bis zum 28. Januar 2027 gültig;
`certbot.timer` und der bestehende nginx-Renewal-Hook sind aktiv.

Schnelle Abrufe mehrerer API-Seiten trafen zunächst das gemeinsame
Anwendungslimit. Für statische Docs-Seiten und Assets wurde deshalb ein
eigenes Limit mit 100 Anfragen pro Sekunde und einem Burst von 200 ergänzt.
Die gezielte Aktivierung erfolgte mit Sicherung, erfolgreichem `nginx -t`
und Reload. Die aktive Ingress-Konfiguration stimmt exakt mit der gerenderten
Ansible-Vorlage überein.

Öffentliche HTTPS-Aufrufe über IPv4 und IPv6 lieferten vom Hetzner-Host HTTP
200. Startseite, API-Referenz, Suchindex, OpenAPI-JSON und zehn eingebundene
Assets wurden erfolgreich abgerufen; fehlende Seiten und Dateien lieferten
404. Weiterleitungen für `/`, `/docs` und API-Unterseiten bleiben unter dem
öffentlichen Pfad und erhalten Query-Parameter. Weitere 80 Abrufe mit bis zu
16 parallelen Verbindungen lieferten ausschließlich HTTP 200, keine HTTP 429.
Ein externer Chromium-Aufruf bestätigte Navigation, Suche mit `/docs/`-Links,
den direkten Aufruf von `/docs/api-reference/events/get-events` und eine
Mobilansicht ohne horizontales Überlaufen. Dabei traten weder JavaScriptfehler
noch fehlgeschlagene Browseranfragen auf. Das bestehende Dev-Frontend lieferte
weiterhin seine Weiterleitung mit HTTP 302, das Dashboard HTTP 200.

Die lokalen nginx-/Frontend-Rollback-/Template-Prüfungen bestanden vor dem
Rollout über Gesamtlauf und gezielten Wiederholungslauf (64 Testfälle).
Nach der Limit-Anpassung bestanden vier gezielte Tests für Docs-Vorabrufe,
Weiterleitungen und unveränderte Anwendungslimits. Weitere 44 Policy-,
Zertifikats- und Inventory-Tests, Repository-Policy, Syntaxprüfung aller
Playbooks und ansible-lint im Production-Profil bestanden ebenfalls.

Sicherungen liegen geschützt auf dev01 unter
`/var/backups/uranus-documentation-20261030-k1bdb3/` (nginx und vorheriger Build)
und auf nginx01 unter `/var/backups/uranus-documentation-20261030-m1Ctpd/`
(nginx vor dem Rollout und vor der Limit-Korrektur). Build-, Rollout- und
Prüfprotokolle liegen lokal unter `.uranus-private/documentation-rollout/`.

## Nominatim ohne pauschales Request-Limit am 28. Oktober 2026

Nach ausdrücklicher Produktionsfreigabe wurde `playbooks/ingress.yml` mit
`--limit nginx01` und `debian13_ingress_prepare_only=true` ausgeführt. Bestehende
TLS-Zertifikate und zertifizierte Routen blieben erhalten. Ansible meldete
`ok=72`, `changed=2`, `unreachable=0`, `failed=0`: Die Ingress-Konfiguration wurde
aktualisiert und nginx nach erfolgreichem `nginx -t` neu gestartet. Alle übrigen
geprüften Konfigurationen waren bereits aktuell.

Die vorherige Konfiguration und die Ausgabe von `nginx -T` liegen geschützt
auf `nginx01` unter
`/var/backups/uranus-nominatim-rate-limit-20261028T163945Z-hABuI9/`.
Das pauschale Nominatim-Limit von einer Anfrage pro Sekunde gilt jetzt nur für
explizit eingetragene Missbrauchsquellen. Die Liste
`debian13_ingress_nominatim_abusive_networks` ist beim Rollout leer; es gibt
keine automatische Botnetz-Erkennung und keine Drosselung allein wegen hoher
Request-Zahlen.

Die öffentliche IPv4-Prüfung verwendete je 40 Suchanfragen nach Flensburg über
die HTTPS-Domain und die HTTP-IP-Testroute `/nominatim/search`, mit jeweils bis
zu acht parallelen Verbindungen. Alle 80 Anfragen lieferten HTTP 200 und gültige
Suchergebnisse, keine HTTP 429. Die beiden Statusprüfungen meldeten HTTP 200 und
Nominatim-Status `0`. Die HTTPS-Prüfung validierte das Zertifikat für
`nominatim.oklabflensburg.de`. Die öffentliche DNS-Auflösung bestätigt
`94.130.236.38` und `2a01:4f8:13b:1405::2`; auch der anschließende normale
HTTPS-Domainaufruf der Status-API war mit HTTP 200 und Status `0` erfolgreich.

Die zusätzliche Live-IPv6-Prüfung ist noch offen: Der Controller hat keine
IPv6-Route; beim anschließenden SSH-Zugriff verweigerte der SSH-Agent weitere
Smartcard-Signaturen (`agent refused operation`). Der produktive Rollout war zu
diesem Zeitpunkt bereits erfolgreich abgeschlossen.

Vor dem Rollout bestanden 51 lokale Tests mit echtem nginx, einschließlich
IPv4-/IPv6-Last, Domain- und IP-Routen, gezielter Drosselung und gefälschter
HTTP-Header. Repository-Policy, Syntaxprüfung sämtlicher Playbooks und
ansible-lint im Production-Profil für die geänderte Ingress-Konfiguration
bestanden ebenfalls.

## SMTP-Versand von dev01 am 20. Oktober 2026

Der Betreiber hat auf `dev01` den SMTP-Zugang in `/etc/uranus/config.json`
eingerichtet und den Backend-Dienst danach neu gestartet. Der aktive Zugang
verwendet `smtp.porkbun.com:587` und `hello@kulturbytes.de` als Login und Absender.
Die Konfiguration bleibt mit `uranus:uranus` und Modus `0600` geschützt.

Eine ausdrücklich freigegebene Testmail wurde an den vom Betreiber genannten
Empfänger versendet. Der Test importierte die tatsächliche Mailfunktion
`app.SendEmailWithTimeout` aus dem laufenden Release
`d06a615b4b4c8454f5298902fabcddd1d7985834`. Er lief als Dienstbenutzer `uranus`
mit dem gleichen Zertifikatsspeicher wie das Backend. Das Backend-Paket wurde
mit dem vorhandenen Go-1.25.8-Toolchain und unveränderten Moduldateien gebaut.

Der SMTP-Server nahm die Nachricht am **20.10.2026 um 15:16:29 Uhr MESZ** an.
Der Versandprozess endete mit Exit 0. Ein exklusiv angelegter Versuchsnachweis
verhindert einen erneuten Versand durch den Testhelfer. Ergebnis und Betreff
stehen geschützt unter `/var/lib/uranus/mail-verification-20261020/result.json`
auf `dev01`. Die Bestätigung über den Eingang im Empfängerpostfach steht noch aus.

Die funktionierenden Werte sind in `host_vars/dev01.yml` hinterlegt. Das Passwort
wurde aus der geprüften Konfiguration über SSH in den bestehenden lokalen
Ansible-Vault übernommen und unter `vault_backend_smtp_password_dev`
verschlüsselt gespeichert. Alle übrigen Vault-Werte wurden nach Ver- und
Entschlüsselung auf unveränderten Inhalt geprüft; die vorherige verschlüsselte
Fassung bleibt privat gesichert. Der Klartext wurde nicht in lokale Dateien
geschrieben oder ausgegeben. `prod01` verwendet weiterhin seine bisherige
SMTP-Konfiguration.

Ein lokaler Ansible-Lauf prüfte die tatsächlich aufgelösten SMTP-Werte und die
gerenderte Backend-JSON-Vorlage für `dev01` und `prod01` erfolgreich
(`ok=3`, `changed=0`, `failed=0` je Host). `ansible-lint` bestand im
Production-Profil für 19 Dateien; die Repository-Policy bestand für 185
Quelldateien. Nach dem Test ist der Backend-Dienst aktiv und die öffentliche
Dev-API liefert HTTP 200. Eine erneute Backend-Aktivierung war nicht erforderlich.

## Mail-Konfiguration auf dev01 am 19. Oktober 2026

Die lesende Prüfung von `/etc/uranus/config.json` auf `dev01` ergab leere
SMTP-Host-, Login- und Passwortwerte. Postfix ist nicht eingerichtet. Das
laufende Backend verwendet selbst `net/smtp` mit den `auth_smtp_*`-Werten;
ein lokaler Postfix-Dienst ist für diesen Versandweg nicht erforderlich.

Im tatsächlich laufenden Backend-Release
`d06a615b4b4c8454f5298902fabcddd1d7985834` erwartet `app.Config.AuthReplyEmail`
den JSON-Schlüssel `auth_reply_email`. Die bisherige Ansible-Vorlage schrieb
`auth_reply_email_address`, wodurch das Backend keinen Absender einlas.
Die Vorlage verwendet jetzt den richtigen Schlüssel und serialisiert die
SMTP-Textfelder mit `to_json`, damit Sonderzeichen in Zugangsdaten erhalten
bleiben und die Konfiguration gültiges JSON bleibt.

Auf `dev01` wurde ausschließlich der bisherige Absender in den tatsächlich
gelesenen Schlüssel übernommen. Der atomare Austausch bewahrt übrige Werte,
Eigentümer und Dateimodus. Die geschützte ursprüngliche Konfiguration liegt
unter `/var/backups/uranus-mail-20261019T102429Z/config.json`. Der Backend-Dienst
wurde neu gestartet und antwortet lokal sowie über
`https://api.dev.kulturbytes.de/api/events?limit=1` mit HTTP 200.

Eine lokale Vorlagenprüfung bestätigte gültiges JSON, den vom Backend gelesenen
Absenderschlüssel sowie verlustfreie SMTP-Passwörter mit Anführungszeichen,
Backslash und Zeilenumbruch als Testdaten. `ansible-lint` bestand im
Production-Profil für 18 betroffene Dateien; `git diff --check` war erfolgreich.

**Bei dieser Prüfung vom 19.10. war der Mailversand noch nicht nachgewiesen.**
Es fehlten SMTP-Server, Benutzername und Passwort. Eine einzelne Testmail an den
vom Betreiber genannten Empfänger war freigegeben, wurde zu diesem Zeitpunkt
aber noch nicht gesendet.
Ein HTTP-200-Backend-Check ersetzt keinen SMTP- oder Zustellnachweis.

## Vorbereitung automatischer Nominatim-Updates am 18. Oktober 2026

Die lesende Prüfung der laufenden Europa-Datenbank bestätigt eine eingefrorene
Installation: `place`, `planet_osm_nodes`, `planet_osm_ways` und
`planet_osm_rels` fehlen, ebenso die ursprüngliche Flatnode-Datei. Der Import
ist indiziert, hat den Datenstand `2026-10-15T20:20:56Z` und keine
Replikationssequenz. Die Ursache ist der bereits in der ursprünglichen
Importrolle fest enthaltene Schalter `--no-updates`, der beim Europa-Import
übernommen wurde. Die laufende Suche wurde bei dieser Untersuchung nicht geändert.

Die lokale Vorbereitung behält bei neuen Importen standardmäßig die
Update-Daten. Ein eigener Update-Einstieg prüft den Datenbestand vor jeder
Änderung, initialisiert eine passende Quelle einmalig und richtet danach einen
systemd-Service samt Timer für tägliche Geofabrik-Europa-Diffs ein. Ein
Quellnachweis bindet die Konfiguration an URL und Datenbank-OID.

Die lokalen Prüfungen bestanden:

- 56 Tests für Nominatim, die erste Update-Vorbereitung und die Deployment-Gates.
- Anschließend 22 Tests für die ergänzten Update-Schutzprüfungen und den
  bestehenden Europa-Ablauf. Abgedeckt sind eingefrorene/unfertige Datenbanken,
  fehlende Flatnodes oder Nodes, fremde beziehungsweise doppelte Verbindungen,
  eine abweichende Flatnode-Konfiguration, unbekannte/geänderte Quellen und
  Datenbank-OIDs sowie zulässige neue und bereits initialisierte Datenbestände.
  Die PostgreSQL-Tests erhalten Daten, OIDs, Projektkonfiguration und Quellnachweis.
  Der Importbefehl wurde mit einem inerten Ersatzprogramm für beide Einstellungen
  ausgeführt; die erzeugten Units bestanden `systemd-analyze verify`.
- Syntaxprüfung aller 19 Playbooks, Repository-Policy für 185 Quelldateien und
  `ansible-lint` im Production-Profil für die 22 betroffenen Dateien.

Es wurde keine Produktiv-Replikation initialisiert, kein Timer installiert und
kein neuer Import gestartet. Ein kompletter Replikationslauf mit echten Diffs
ist noch nicht nachgewiesen und benötigt einen neuen updatefähigen Datenbestand.
Auf dem bisherigen physischen `/data`-Dateisystem sind nur rund 163 GiB frei;
der zusätzliche Speicherbedarf muss vor einem Neuimport eingeplant werden.
Die Anleitung steht in [Europa und automatische Updates](nominatim-europe.md#automatische-osm-updates).

## Europa-Import und Nominatim-HTTPS am 18. Oktober 2026

Der vom Betreiber gestartete Europa-Import wurde um 12:01 Uhr MESZ nach rund
41 Stunden 47 Minuten abgeschlossen. Das Manifest enthält `completed: true`,
PostgreSQL meldet `import_status.indexed = true`, und Nominatim 5.3.3 liefert
API-Status 0. Die neue Datenbank umfasst rund 171 GiB; die bisherige Datenbank
`nominatim_sh_20261016` bleibt mit rund 1 GiB erhalten. Der Datenstand des
Auszugs ist der 15. Oktober 2026.

Nach ausdrücklicher Freigabe wurde die vom Betreiber bestätigte Domain
`nominatim.oklabflensburg.de` auf Gast-nginx, öffentlichem Ingress und Monitoring
aktiviert. A und AAAA zeigen auf `94.130.236.38` und
`2a01:4f8:13b:1405::2`. Die lokale Deployment-Datei enthält den korrigierten
Namen und nimmt `nominatim` in die bestehende TLS-Auswahl auf.

Der auf `nom01` und `nginx01` begrenzte Lauf von `playbooks/nginx.yml` bestand
mit `ok=38`, `changed=2`, `failed=0` auf `nom01` und `ok=89`, `changed=5`,
`failed=0` auf `nginx01`. Nur für Nominatim wurde ein neues öffentliches
Zertifikat angefordert. Das Let's-Encrypt-Zertifikat deckt die richtige Domain
ab und gilt bis 16. Januar 2027. `nginx -t`, Hostnamen- und Ablaufprüfung sind
erfolgreich; `certbot.timer` ist aktiviert und aktiv. Der Monitoring-Lauf
bestand mit `ok=36`, `changed=2`, `failed=0`; die Icinga-Konfiguration wurde vor
dem Neustart validiert.

Auf `nom01` fehlte bisher der für die delegierten Prüfungen benötigte
Icinga-Agent. Er wurde mit der vorhandenen Rolle und den bestehenden
Deployment-Gates ergänzt (`ok=28`, `changed=16`, `failed=0`). Der Master
bestätigt die authentifizierte Verbindung von `nom01` und die unveränderte
gültige CA. Der HTTPS-Check als Benutzer `nagios` liefert HTTP 200 und Exit 0;
Agent, Nominatim-Service, Socket und Gast-nginx sind aktiv.

Öffentliches HTTPS liefert mit System-CA- und Hostnamenprüfung API-Status 0 und
Suchergebnisse für Paris, Madrid, Berlin und Flensburg. IPv6-Status und eine
Paris-Suche wurden vom Hetzner-Host aus erfolgreich geprüft; der Arbeitsplatz
prüft den öffentlichen Zugang über IPv4. HTTP leitet mit 301 auf HTTPS weiter.
Der bestehende IP-Zugang sowie Kulturbytes-Dev, Dev-API, Entwicklungsdashboard,
VersaTiles und Plausible antworten nach dem Rollout weiterhin mit HTTP 200.

Vor der Umstellung wurden die bestehenden Konfigurationen auf `nom01`,
`nginx01` und `mon01` unter `/var/backups/uranus-nominatim-domain-*.tar.gz`
gesichert. 13 lokale nginx-/Zertifikatstests und die Syntaxprüfungen der beiden
Rollout-Playbooks bestanden. Ein erster Rolloutversuch scheiterte ohne
Serveränderungen an der lokalen `/tmp`-Quota; der erfolgreiche Lauf verwendete
eine geschützte temporäre Ablage unter `.uranus-private/`.

## Vollständiger lokaler Prüfstand vor PR-Aktualisierung, 16.10.2026

Der aktuelle Gesamtstand besteht `make check`: **380 Tests**, Repository-Policy
für 180 Quelldateien, Syntaxprüfung aller 18 Playbooks und `ansible-lint` im
Production-Profil (174 geprüfte Dateien, keine Verstöße). Zusätzlich besteht
`bash -n scripts/import_nominatim_europe.sh`.

Der erste Gesamtlauf wurde durch die lokale `/tmp`-Quota unterbrochen;
PostgreSQL meldete beim Anlegen einer isolierten Testdatenbank `Disk quota
exceeded`. Der erfolgreiche vollständige Wiederholungslauf verwendete eigene
temporäre Verzeichnisse unter dem ignorierten `.uranus-private/` und benötigte
keine Änderungen am Anwendungscode oder an den Tests. Der privilegierte native
Incus-Vertragstest aus CI wurde bei dieser lokalen Prüfung nicht ausgeführt.

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
| SSH/Firewallrecovery | Timer vor SSH-Änderung, Schlüsselpflicht vor öffentlicher Freigabe, neue Verbindung, Ablauf, Apply-/Reloadfehler, konkurrierende Updates, Boot-Recovery und Konfigurationsdrift; native nftables-Parser für Host und acht Gäste |
| Host-SSH ohne feste IP | wechselnde IPv4-/IPv6-Quellen, Root-/Passwort-/Keyboard-Interactive-Sperre, fremde SSH-Konfigurationen; `scripts/check_ssh.py` prüft mit echtem OpenSSH wirksame Einstellungen und Include-Priorität |
| Cloud-init | native Cloud-init-Schemaprüfung für VM und Container |
| Nginx und TLSrouting | echter Nginxparser mit isolierten Loopbackports und Testzertifikaten |
| Nuxt-Rollout | echte Ansible-Dateiwiederherstellung nach injiziertem SSR-Fehler: vorheriger statischer/Node-Release, Unit, Umgebung und nginx; erster Rollout ohne vorherigen Release |
| Container-Ingress | laufender lokaler Nginx mit TLS-Upstream; PROXY-Client-IP, IPv4-/IPv6-CIDRs, verworfene gefälschte HTTP-Header, ACME und privater Monitoringlistener |
| PostgreSQL Erstimport / Wiederholung / Pending / SQL-Escape | reale Ansible-DB-Tasks gegen temporäre Unix-Sockets und Loopback-TCP mit SCRAM |
| Native Debianpakete / Incus-CLI | isolierte Debian-13-Testumgebung; Ergebnisse im PR |

Eine erfolgreiche statische Prüfung ist kein vollständiger Incus-/Anwendungs-
End-to-End-Nachweis. Container- und VMstart, Gast-Ansible mit realen Anwendungen,
TLS-Clientverbindungen, Import, Updates, externe Backups und kompletter Restore
müssen in einem isolierten Pilot mit geprüften Releases und Secrets abgenommen
werden. Prüfungen auf Hetzner benötigen eine ausdrückliche Freigabe und werden
getrennt von den lokalen Tests dokumentiert. Nicht ausgeführte Prüfungen werden
im PR ausdrücklich benannt.

## VersaTiles-Domain und HTTPS am 16. Oktober 2026

Die vom Betreiber bestätigte Domain lautet `versatiles.oklabflensburg.de`.
Cloudflare- und Google-DNS sowie der Ingress lösen sie auf `94.130.236.38` und
`2a01:4f8:13b:1405::2` auf. Gast-nginx und Ingress verwenden diesen Namen.
Der bestehende Europa-Datensatz wurde beim erneuten `versatiles.yml`-Lauf
erhalten; `ok=54`, `changed=2`, `unreachable=0`, `failed=0`.

Der TLS-Rollout ist auf `versatiles` begrenzt und verwendet nun getrennte
Zertifikate je Domain. Bereits zertifizierte Domains werden auch bei HTTP-
Vorbereitung erhalten. Die lokale nginx-Suite besteht alle 29 Fälle; zwei
weitere Ansible-/OpenSSL-Tests prüfen fehlende, abgelaufene und nicht passende
Zertifikate sowie genau eine gültige Domain. OpenSSL-Hostnamen- und Ablauf-
prüfung laufen getrennt. Repository-Policy, Syntax aller neun Playbooks und
ansible-lint im Production-Profil sind erfolgreich; die abschließend geänderte
Zertifikatsauswahl besteht zusätzlich den gezielten Rollen-Lint.

Der Ingress-Lauf ist abgeschlossen: `ok=86`, `changed=7`, `unreachable=0`,
`failed=0`. Let's Encrypt stellte ein gültiges Zertifikat für die neue Domain
aus, gültig bis 14. Januar 2027. `certbot.timer` ist aktiviert und aktiv. HTTPS
liefert mit System-CA- und Hostnamenprüfung HTTP 200 für Startseite, TileJSON,
Kacheln und Kartenbibliotheken. HTTP leitet auf denselben HTTPS-Namen um.
Beide öffentlichen IP-Adressen wurden vom Hetzner-Host aus erfolgreich mit
TLS 1.3 geprüft; der Arbeitsplatz prüft die Domain extern über IPv4. Der
bestehende HTTP-IP-Kartenzugang liefert weiterhin HTTP 200.

Der echte isolierte Chrome-Browser rendert unter der HTTPS-Domain die
Startansicht, Europa, Berlin auf Zoom 14 und Madrid auf Zoom 12. Es treten
keine JavaScript-Fehler oder unerwarteten fehlgeschlagenen Ressourcenabrufe
auf; Kartenressourcen werden vom eigenen Ursprung geladen. Die Oberfläche
prüft zusätzlich die optionalen Satelliten- und Höhendatensätze: Deren
TileJSON-Abfragen liefern erwartungsgemäß HTTP 404, da nur OSM-Vektorkacheln
installiert sind.

Die bisherigen nginx-/ACME-Konfigurationen sind geschützt unter
`/var/backups/uranus-before-versatiles-domain-20261016T092809Z-4s4jzylq.tar.gz`
auf `vers01` und
`/var/backups/uranus-before-versatiles-domain-20261016T092810Z-iabfnwvz.tar.gz`
auf `nginx01` gesichert.

## VersaTiles für Europa am 16. Oktober 2026

Der stabile GitHub-Release wurde über die aktuelle Release-API geprüft:
VersaTiles 5.2.0 vom 15. Oktober 2026 und Frontend 3.16.0 vom 10. Oktober.
Die heruntergeladenen Releasearchive stimmen mit den offiziellen SHA256-
Digests überein. `vers01` hatte zuvor keine VersaTiles-Installation oder
aktiven Tile-Dienst. Vor dem Rollout wurden die vorhandenen Konfigurationen
unter `/var/backups/uranus-versatiles-before-20261016T083205Z-neklwpf1.tar.gz`
auf `vers01` und
`/var/backups/uranus-before-europe-map-20261016T084139Z-ppyfeavw.tar.gz`
auf `nginx01` geschützt gesichert.

Der neue Einstieg `playbooks/versatiles.yml` besteht die Deployment-Gates
vor jedem Verbindungsaufbau. Die asynchronen Importtasks sind mit realen
lokalen Ansible-Prozessen für Erfolg, abgebrochenen Download und fehlgeschlagene
Dateiprüfung geprüft: Erst eine vollständig geprüfte Datei wird veröffentlicht.
Die nginx-Integration prüft mit echtem TLS-Upstream die Karte, unveränderte
Asset-/Tile-Pfade, Client-IP-Weitergabe und 60 aufeinanderfolgende Kachelanfragen
ohne Drosselung. Alle gezielten Prüfungen sind erfolgreich; Repository-Policy,
Syntax der neun Playbooks und ansible-lint im Production-Profil bestehen.

Der freigegebene Rollout ist abgeschlossen: `vers01` meldet `ok=59`,
`changed=13`, `unreachable=0`, `failed=0`; der anschließende Ingress-Lauf
`ok=66`, `changed=4`, `unreachable=0`, `failed=0`. Der Europa-Datensatz liegt
lokal unter `/srv/versatiles/tiles/europe.versatiles` und umfasst
24.708.411.744 Bytes. VersaTiles 5.2.0 und nginx sind aktiv, der Tile-Dienst
ist für den Boot aktiviert und hört auf Loopback-Port 8080. Die Verbindung
von `nginx01` zu `vers01` ist mit CA- und Knotennamenprüfung erfolgreich.

Die öffentliche IP liefert HTTP 200 für `/map/`, TileJSON, Kartenbibliotheken,
Sprites und Kacheln auf Zoom 14 für Berlin, Paris, Madrid, London, Reykjavík,
Oslo, Helsinki, Rom, Athen, Kyjiw und Moskau. New York und Tokio liefern auf
dieser Zoomstufe erwartungsgemäß HTTP 204 ohne Kachelinhalt. Das Shortbread-
Schema lautet `shortbread@1.0`, Zoom 0–14, 26 Vektorebenen. Die vereinigten
TileJSON-Grenzen reichen wegen der zusätzlichen Randkacheln auf groben
Zoomstufen über den eigentlichen Europa-Ausschnitt hinaus; die Testkarte
setzt ihre Navigationsgrenzen ausdrücklich auf den Europa-Ausschnitt.

Ein isolierter echter Chrome-Browser lädt die öffentliche Karte erfolgreich:
Europa mit 809 sichtbaren Objekten, Berlin auf Zoom 14 mit 25.240 und Madrid
auf Zoom 12 mit 1.416. Es wurden keine JavaScript-Fehler, fehlgeschlagenen
Ressourcenantworten oder Kartenabrufe von fremden HTTP-Ursprüngen beobachtet.
Nominatim-Status über dieselbe öffentliche IP bleibt `0 / OK`.

## HTTP-Testzugang über die IP am 16. Oktober 2026

Der optionale Ingress-Modus `debian13_ingress_ip_testing` wurde mit laufendem
lokalem nginx und einem echten TLS-Upstream geprüft. Alle 27 gezielten Tests
für Ingress, nginx-Vorlagen und den nginx-Rollout sind erfolgreich; ebenso
Repository-Policy, Syntax aller acht Playbooks und ansible-lint im Production-
Profil. Die Tests prüfen die Testseite und Nominatim-Anfragen über IPv4-/IPv6-
Hostnamen vor und nach der öffentlichen TLS-Konfiguration. Der Präfix
`/nominatim/` wird entfernt, Suchparameter bleiben erhalten, die echte Client-IP
wird weitergereicht und die interne TLS-Prüfung bleibt aktiv. Unbekannte
Hostnamen werden weiterhin geschlossen; Domain-ACME bleibt erreichbar. Ohne
die explizite Option bleibt auch der direkte IP-Aufruf geschlossen.

Der freigegebene Rollout auf `nginx01` ist anschließend erfolgreich abgeschlossen:
`ok=65`, `changed=4`, `unreachable=0`, `failed=0`. Die vorherige nginx-Konfiguration
ist unter `/var/backups/uranus-before-ip-test-20261016T064815Z-0fz59mlv.tar.gz`
geschützt gesichert. Die öffentliche IPv4-Adresse liefert ohne Host-Header-
Überschreibung für `/`, `/nominatim/status?format=json`, die Suche nach Flensburg
und Reverse-Geocoding jeweils HTTP 200. Nominatim meldet `0 / OK`, Version 5.3.3
und Datenbank 5.3.3-0. Domain-Aufrufe leiten weiter auf HTTPS um; unbekannte
Hostnamen werden weiterhin geschlossen. Dieselben Prüfungen über die öffentliche
IPv6-Adresse sind vom Hetzner-Host aus erfolgreich. Ein externer IPv6-Nachweis
vom Arbeitsplatz war mangels IPv6-Route nicht möglich.

## Europa-Import vorbereitet am 16. Oktober 2026

- `scripts/import_nominatim_europe.sh` und das eigene Playbook bereiten den
  Austausch des regionalen Datensatzes vor. Der optionale Einstieg `--resize-db`
  vergrößert zuvor `db01` auf 600 GiB mit einer sudo-Passwortabfrage direkt im
  Terminal. Anleitung und Wiederherstellungsweg stehen in `nominatim-europe.md`.
- Autorisierte Leseprüfungen bestätigen weiterhin eine 150-GiB-Disk mit
  `/dev/sda2`, ext4-UUID `ed4bb368-30b1-46bc-abc4-4b657f8e41d1`, rund
  141,5 GiB freiem Gastplatz und rund 774 GiB freiem Hostplatz. PostgreSQL ist
  aktiv; der Nominatim-Benutzer hat keine Superuser-/Create-Rechte.
- **Bei Abschluss der Vorbereitung hatte der Agent weder die Vergrößerung
  noch den Europa-Import ausgeführt.** Der
  Hostzugang erfordert ein sudo-Passwort, das dem Agenten nicht vorliegt.
  Die Zielgröße 600 GiB ist im Inventory vorbereitet; bis zur Ausführung des
  Helfers besteht daher eine beabsichtigte Abweichung zur laufenden VM.
- 145 gezielte lokale Tests für Nominatim, Europa, die Partitionsschutzprüfungen,
  Incus und die Deployment-Sperren erfolgreich. Die sieben Europa-Tests wurden
  nach einem temporären Speicherquota-Fehler des lokalen Testclusters separat
  vollständig erfolgreich wiederholt. Produktive Systeme waren keine Testziele.
- Offline-Syntaxprüfung aller Playbooks, Repository-Policy und ansible-lint
  im Production-Profil für den geänderten Nominatim-Bereich erfolgreich.
  Die Online-Vergrößerung und der große Import sind damit vorbereitet, aber
  noch nicht praktisch auf Hetzner verifiziert.

## Korrektur der db01-Vergrößerung am 16. Oktober 2026

- Der erste Betreiberlauf hat Datenbankdumps und Partitionsmetadaten unter
  `/var/backups/db01-before-resize-20261016T152907563499Z` gesichert. Der
  Konfigurationsbefehl für 600 GiB war erfolgreich, aber im Gast wurden
  weiterhin 150 GiB erkannt. Der Helfer stoppte vor `growpart` und
  `resize2fs`; der Europa-Import wurde dadurch nicht gestartet.
- Eine anschließende Leseprüfung bestätigt `/dev/sda` mit 161.061.273.600 Bytes,
  die unverändert große ext4-Rootpartition und aktives PostgreSQL.
- Der Incus-6.0.4-Quellcode erklärt den Ablauf: Das Directory-Backend verweigert
  die Größenänderung einer verwendeten Disk-Datei und das Disk-Gerät speichert
  sie für den nächsten Start. Der Helfer berücksichtigt jetzt sowohl die
  aufgeschobene Änderung als auch eine konfigurierte 600-GiB-Disk mit noch
  sichtbaren 150 GiB. Er erstellt zunächst Sicherungen und führt bei Bedarf
  einen geordneten Stop/Start durch, wartet auf PostgreSQL und prüft erneut
  die tatsächliche Diskgröße vor Partitionsänderungen. Kein erzwungener Stop.
- Der freie Hostplatz wird anhand der tatsächlichen Gastgröße geprüft, damit
  eine schon gespeicherte Zielgröße den noch benötigten Platz nicht verdeckt.
  Fehler im Controller geben den eingebetteten Python-Quelltext nicht mehr aus.
- 17 lokale Schutz- und Regressionstests für den Vergrößerungshelfer bestanden,
  einschließlich aufgeschobener Größenänderung, Stop/Start, fehlgeschlagenem
  Stop, weiterhin falscher Größe und knapper Kapazität bei bereits gesetztem
  Zielwert. Der korrigierte Stop/Start wurde durch den Agenten nicht ausgeführt.

## db01 mit 600 GiB und Europa-Preflight am 16. Oktober 2026

- Nach dem erneuten Betreiberlauf sieht `db01` die Disk mit 644.245.094.400
  Bytes und eine entsprechend erweiterte ext4-Rootpartition. SSH und PostgreSQL
  sind aktiv; die Gastadresse bleibt `10.77.0.11`.
- Der nachfolgende SSH-Banner-Timeout beim delegierten Datenbankzugriff wurde
  auf eine erneute Anmeldung am Sprunghost eingegrenzt. Ein direkter Test mit
  den ursprünglichen ProxyJump-Einstellungen zeigte die vom Agenten verweigerte
  Kartensignatur; über die bestehende vertrauenswürdige Verbindung war derselbe
  Gast erreichbar. Der Einstieg verwendet jetzt eine gemeinsame Verbindung für
  Vergrößerung, ProxyJump und die direkte Hostprüfung. Ein privater
  Inventory-Zusatz verhindert, dass Ansible für den Host einen abweichenden
  ControlPath verwendet. Die SSH-Bereitschaft von `db01` wird separat geprüft.
- Der vollständige, rein lesende Betreiber-Einstieg `--preflight` wurde durch
  den Agenten erfolgreich geprüft: `ok=33`, `changed=0`, `unreachable=0`,
  `failed=0`. Frei waren 577,4 GiB auf dem Datenbank-Dateisystem und 760,5 GiB
  auf `nom01` beziehungsweise dem gemeinsamen Host-Dateisystem. Bestehendes
  Nominatim-Schema und abgeschlossener Indexstatus sind bestätigt. Es wurde
  kein Europa-Versuch angelegt und kein Download oder Import gestartet.
- 22 lokale Tests für den Vergrößerungshelfer und delegierte SSH-Optionen
  erfolgreich, einschließlich OpenSSH-Prüfung der generierten Konfiguration,
  gemeinsamer Controller-Konfiguration und Delegation von `nom01` zu `db01`.
  Der geänderte Nominatim-Bereich besteht ansible-lint im Production-Profil.

## Nominatim 5.3.3 auf Hetzner am 16. Oktober 2026

- Die aktuelle stabile Version wurde anhand der offiziellen Releaseübersicht
  und der PyPI-Pakete geprüft: Nominatim 5.3.3 vom 14. Oktober 2026. Installiert
  sind `nominatim-db` und `nominatim-api` 5.3.3, Gunicorn 26.2.0 und Falcon 4.4.0.
- Vorher gab es auf `nom01` weder eine Nominatim-Installation noch eine
  Nominatim-Datenbank auf `db01`. Der gezielte Lauf von `nominatim.yml` mit
  einmaliger Erstimportfreigabe ist erfolgreich: `ok=64`, `changed=16`,
  `unreachable=0`, `failed=0`.
- Die VM-Disk von `db01` hatte bereits 150 GiB, ihre ext4-Root-Partition aber nur
  rund 4 GiB. Nach ausdrücklicher Freigabe, Datenbank-/Rollensicherungen und
  Partitionstabellensicherung unter
  `/var/backups/nominatim-pre-deploy-20261016T053939Z` sowie erfolgreichem
  Trockenlauf wurden Partition 2 und ext4 online erweitert. Partitionsanfang,
  EFI-Partition und Dateisystem-UUID bleiben erhalten. Nach dem Import zeigt
  `df` 146 GiB Gesamtgröße und 142 GiB frei; PostgreSQL blieb erreichbar.
- Importiert wurde der Geofabrik-Extrakt
  `schleswig-holstein-261015.osm.pbf` (158.997.912 Bytes), SHA256
  `390de71e3b9bddc91d7bbe4047ed3b01a25cec384d024851d33cd1b976f5a8f1`.
  Die Anbieterprüfsumme wurde zusätzlich geprüft. Der API-Datenstand ist
  `2026-10-15T20:19:31+00:00`; der Import ist vollständig indexiert und ohne
  laufende Replikation eingerichtet. Die Datenbankversion lautet `5.3.3-0`.
- Erhöhte Datenbankrechte wurden nur zur Vorbereitung vergeben und bereits
  vor dem längeren Import widerrufen. Die abschließende SQL-Prüfung bestätigt
  `rolsuper=false`, `rolcreatedb=false` und `rolcreaterole=false`.
- `nominatim.socket`, `nominatim.service` und Gast-nginx sind aktiv. Über den
  nginx-Upstream von `nginx01` zu `nom01` mit CA- und Knotennamenprüfung liefern
  `/status?format=json`, die Suche nach Flensburg und Reverse-Geocoding für
  `54.7833,9.4333` jeweils HTTP 200 und plausible Flensburger Ergebnisse.
  Status meldet `0 / OK`, Software 5.3.3 und Datenbank 5.3.3-0.
- Die bestehenden Entwicklungs- und Produktions-APIs liefern nach der
  Speichererweiterung und dem Import weiterhin HTTP 200. Der vorhandene
  tägliche Datenbank-Backuptimer ist aktiv.
- Lokale Prüfung: 24 gezielte Nominatim-/Gate-Tests erfolgreich; die sieben
  Datenbank-/Rechtetests wurden nach der Variablenkorrektur erneut erfolgreich
  ausgeführt. Repository-Policy, Syntax aller acht Playbooks und vollständiger
  ansible-lint im Production-Profil bestehen.
- Die öffentliche Domain ist weiterhin nicht nutzbar: DNS für die konfigurierten
  Ingress-Domains zeigt noch nicht auf Hetzner; öffentliche Zertifikatsausstellung
  und vollständiger HTTPS-Ingress bleiben ausstehend.

## Freigegebener nginx-Rollout auf Hetzner am 16. Oktober 2026

- Vor den Änderungen wurden auf allen sechs nginx-Gästen geschützte Archive der
  vorhandenen nginx-, TLS-, Firewall- und verwalteten SSH-Konfiguration unter
  `/var/backups/uranus-nginx-before-20261016T*.tar.gz` angelegt.
- Der gezielte Rollout auf `dev01`, `prod01`, `mon01`, `nom01` und `vers01`
  ist ohne fehlgeschlagene oder unerreichbare Hosts abgeschlossen. nginx läuft
  auf allen fünf Gästen mit gültiger Konfiguration und privatem TLS.
- `nginx01` wurde mit `debian13_ingress_prepare_only=true` bis zum öffentlichen
  HTTP-Endpunkt für ACME eingerichtet. Auch dieser Lauf ist erfolgreich.
  Beide Betriebsarten benötigen weiter die normalen Deploymentfreigaben.
- Der Wechsel vom Distribution-Wildcardlistener auf Loopback scheiterte bei
  nginx trotz quittiertem Reload am alten Socket. Der Bootstrap verwendet
  deshalb nach der Syntaxprüfung einen Neustart. Die laufende Instanz hört
  anschließend auf `127.0.0.1:80` mit PROXY-Protokoll.
- Laufzeitprüfung: alle sechs nginx-Konfigurationen gültig, alle sechs Dienste
  aktiv. Frische SSH-Verbindungen einschließlich sudo zu `dev01` und `nginx01`
  sind nach den SSH-/Firewalländerungen erfolgreich.
- Vom Ingress aus wurden alle sieben Upstreams mit CA- und Knotennamenprüfung
  erreicht: Entwicklung und Produktion liefern für Frontend und API jeweils
  HTTP 200; Monitoring liefert den Login-Redirect HTTP 302. Zum Zeitpunkt dieses
  nginx-Rollouts lieferten Nominatim und Tiles HTTP 502; der anschließende
  Nominatim-Rollout ist im vorherigen Abschnitt dokumentiert.
- Ein temporärer ACME-Probeinhalt wurde für alle sieben Domains über die
  öffentliche Hetzner-IP sowohl per IPv4 als auch IPv6 mit HTTP 200 und
  übereinstimmendem Inhalt abgerufen. Die Probedatei wurde wieder entfernt.
- Noch offen: DNS für die sieben Domains auf Hetzner umstellen, anschließend
  öffentliche Zertifikate ausstellen und den vollständigen HTTPS-Ingress prüfen.
  Die HTTP-Prüfung verwendet die Ziel-IP mit passendem Host-Header und ersetzt
  deshalb keinen Nachweis funktionierender öffentlicher DNS-Auflösung.
- Lokale Prüfung der Rolloutänderungen: 39 gezielte Tests erfolgreich;
  nach der HTTP-Vorbereitung erneut 21 nginx-/Ingress-Tests, Repository-Policy,
  Syntax aller sieben Playbooks und ansible-lint erfolgreich. Der korrigierte
  Bootstrap-Neustart besteht zusätzlich den gezielten Rollen-Lint.

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

## Eigener Ingress-Container am 15. Oktober 2026

Die elf Tests in `tests/test_ingress_container.py` sind lokal erfolgreich.
Sie prüfen die Instanzkonfiguration und die Gast-Firewall sowie einen wirklich
gestarteten nginx mit Testzertifikaten und TLS-Upstream: PROXY-Client-Adressen
für IPv4/IPv6, private CIDR-Freigaben, gefälschte HTTP-Header, HTTP-ACME und den
internen HTTPS-Listener ohne PROXY-Protokoll. Dafür werden ausschließlich
temporäre Loopbackports verwendet; die Sandbox benötigt Socketfreigaben.

Die nativen nftables-Parserprüfungen für Host und alle sieben Gastrollen sind
in einem isolierten Netzwerk-Namensraum erfolgreich. Repository-Policy,
Syntaxprüfung aller sechs Playbooks und ansible-lint bestehen. Ein realer
Incus-Start von `nginx01`, öffentliche IPv4-/IPv6-Verbindungen, echte ACME-
Ausstellung und der Wechsel eines laufenden Host-Ingress sind damit weiterhin
nicht nachgewiesen und benötigen den isolierten Pilot.

Alle 204 gezielten Tests für Incus-Preflight, Bootstrap/DHCP, Ingress, interne
PKI, Inventory-Delegation, Firewall und Deployment-Gates bestehen. Der direkte
Pytest-Aufruf benötigt wie `make test` den `ANSIBLE_COLLECTIONS_PATH` aus dem
Makefile; ohne ihn fehlte der virtuellen Umgebung `community.general` bei sechs
Gate-Prüfungen. Diese Prüfungen wurden mit dem vorgesehenen Pfad erfolgreich
wiederholt. Beim anschließenden vollständigen Lauf von `make check` bestehen
alle 266 Tests einschließlich Datenbankintegration, Repository-Policy,
Syntaxprüfung der sechs Playbooks und ansible-lint im Production-Profil.
Der Importtest verwendet den versionierten Entwicklungsdump und prüft alle
56 Tabellen samt Zeilenzahlen und Besitzern. PostgreSQL-Fixtures bevorzugen
Version 17 und verwenden andernfalls die höchste lokal installierte Version.

Für die anschließende DHCP-/Cloud-init-Korrektur bestehen 75 gezielte Tests
für Statusauswertung, Bootstrap, DHCP und Vorlagen. Die sieben nginx-Parserfälle
benötigten lokale Socketfreigaben und wurden außerhalb der Sandbox erfolgreich
wiederholt. Die Tests decken den abgeschlossenen `bootcmd`-Fehler, die exakte
Skriptprüfung, fehlgeschlagene DHCP-Reparatur, fremde Befehle, wiederholte
Provisionierung und die Bereitschaftsprüfung bei der späteren Konfiguration ab.
Neue Cloud-init-Vorlagen bestehen native Schema- und Netzwerk-Rendererprüfungen.
Die vom Betreiber bereitgestellte Statusausgabe belegt inzwischen einen
gestarteten `nginx01` mit abgeschlossenem Cloud-init und altem `bootcmd`-Fehler;
sie belegt noch keine fertige nginx-/ACME-Konfiguration.

Der native GitHub-Vertragstest benötigt `vhost_vsock`. Das erste CI-Lab
verweigerte VM-Initialisierung wegen des fehlenden Moduls. Die CI lädt es jetzt
ausschließlich auf dem wegwerfbaren GitHub-Runner und stellt dessen Device im
Testcontainer bereit. Kernelmodul-Dateien werden nur lesend eingebunden; bei
fehlendem KVM/Transport bricht der Job ab, ohne VMprüfungen zu überspringen.

## SSH-Umstellung auf wechselnde Quelladressen

Die lokale Suite umfasst jetzt 115 Tests, darunter 39 Tests für die kombinierte
SSH-/Firewalltransaktion und die Erhaltung des Verwaltungszugangs. Die 115 Tests
waren lokal erfolgreich. Nach den letzten Task-/Gate-Anpassungen bestanden
zusätzlich alle 48 gezielten SSH-/Policy-Tests sowie alle vier Ansible-
Syntaxprüfungen, Repository-Policy und ansible-lint im Production-Profil.
Sandbox-Läufe können Loopback-/Unix-Sockets verweigern; der
vollständige Lauf benötigt diese ausschließlich für isolierte lokale Fixtures.

Die CI enthält zusätzlich `scripts/check_ssh.py` mit dem echten Debian-OpenSSH.
Für diese Änderung wird gemäß Betreiberwunsch kein weiterer Docker-Lauf gestartet
und kein CI-Ergebnis abgewartet. Der bereits gestartete Docker-Test wurde vor
der OpenSSH-Prüfung beendet; der neue native SSH-Vertragstest ist deshalb lokal
**nicht ausgeführt**. Auch eine reale systemd-Timer-/Boot-Recovery und die
SSH-Erreichbarkeit auf Hetzner sind weiterhin **nicht getestet**.

## Kulturbytes-Client auf Hetzner, 16.10.2026

Commit `359a6cd84afdead4212ae8040e41d969e050b5b9` wurde mit
`playbooks/frontend.yml` zuerst auf `dev01`, danach auf `prod01` installiert
(jeweils `ok=77`, `changed=14`, `failed=0`). Beide `uranus-frontend`-Dienste
laufen ausschließlich auf `127.0.0.1:3000`; Backend und nginx bleiben aktiv.

`https://dev.kulturbytes.de/de` und die Dev-API antworten öffentlich mit HTTP 200.
Frontend-TLS wurde über IPv4 und IPv6 mit Zertifikatsprüfung getestet. Produktion
wurde ausschließlich intern über SSH geprüft; die öffentliche DNS-Umschaltung
und Ausstellung der Produktionszertifikate wurden auf Benutzerwunsch vertagt.
Native Chrome-Prüfungen haben auf beiden Frontends Desktop, Mobilansicht und
`/de/veranstaltungen/laender` geprüft: abgeschlossene Nuxt-Hydration,
API-Basis `/`, getrennte kanonische Domains, keine JavaScriptfehler und keine
HTTP-Fehler in den beobachteten Anfragen. Die Länderliste enthält bereits in der
SSR-Antwort zwei Einträge. Der Ingress erhält die bestehenden IP-Testseiten,
VersaTiles- und Nominatim-Routen; alle antworten nach dem Rollout mit HTTP 200.

Die ursprüngliche gemeinsame Rate-Limit-Zone verursachte beim ersten
Browser-Test HTTP 429. Die ausgerollte Korrektur verwendet getrennte Budgets für
Anwendungsanfragen und Nuxt-/Bilddateien. Zwei zusätzliche Tests mit laufendem
nginx prüfen parallele Downloads und weiterhin wirksame API-Limits; der
zugehörige Testlauf bestand mit 28 Fällen. Der vollständige Testlauf bestand
mit 300 Fällen; die beiden anschließend hinzugefügten Rate-Limit-Fälle wurden
im genannten gezielten Lauf geprüft. Repository-Policy, alle zehn
Playbook-Syntaxprüfungen und Production-Lint bestanden ebenfalls.

Vor der anschließenden Datenmigration waren die Bildverzeichnisse auf beiden
Gästen leer. Ein direkter Aufruf einer in der Dev-Datenbank referenzierten
Bild-ID lieferte HTTP 422 mit `Image read error`. Die nachfolgend beschriebene
Migration behebt diesen Fehler.

## Medienmigration auf Dev und Prod, 16.10.2026

Aus `/opt/dev/go` auf `awendelk@webserver` wurden je Gast 184 Avatar-Dateien,
1.883 Originalbilder und 10.764 Cache-Dateien übernommen. Weitere 156 Dateien
aus dem alten `pluto`-Programmcheckout und der bisherigen `config.json` liegen
ausschließlich im geschützten Migrationsarchiv. Insgesamt wurden je Gast
12.987 Dateien mit 1.865.900.378 Bytes übertragen. Die rsync-Übertragung lief
in begrenzten Paketen über den lokalen Steuerrechner; es gab keine direkte
SSH-Verbindung zwischen Quell- und Zielserver. Alle übertragenen Inhalte wurden
anschließend auf beiden Gästen per SHA-256 sowie auf Eigentümer und Rechte
geprüft. Quelldateien wurden nicht gelöscht.

`playbooks/backend.yml` aktivierte auf beiden Gästen die zentrale Konfiguration
`/etc/uranus/config.json` mit `uranus:uranus` und `0600` sowie die in
`docs/deployment.md` beschriebenen Medienverzeichnisse (jeweils `ok=38`,
`changed=5`, `failed=0`). Die vorherigen Laufzeitdateien wurden unter
`/var/backups/uranus/migration-20261016T103020Z/before-runtime.tar.gz` gesichert.
Backend, Frontend, nginx und Icinga blieben nach der Aktivierung aktiv. Die
Lesbarkeit der TLS-Identitäten durch `nagios` wurde ebenfalls geprüft.

Auf beiden Gästen lieferten drei reale Bildabrufe HTTP 200 mit `image/jpeg`.
Ein Avatarabruf lieferte HTTP 200 mit `image/webp` und identischem SHA-256 zum
gespeicherten Original. Der abschließende native Chrome-Test auf
`https://dev.kulturbytes.de/de` bestätigte 19 erfolgreiche Bildanfragen mit
HTTP 200, sichtbare Veranstaltungsbilder sowie keine JavaScript- oder
Netzwerkfehler. Produktion wurde intern geprüft; ihre öffentliche
DNS-Umschaltung bleibt wie vereinbart vertagt. Vor dieser Umschaltung müssen
zwischenzeitlich hinzugekommene Uploads aus dem laufenden Quellsystem
nachgezogen werden.

Die gezielten Backend-/Policy-Tests bestanden mit 26 Fällen. Ein zusätzlicher
Test führt das tatsächliche Anwendungssicherungsskript aus und prüft zentrale
Konfiguration, Avatare und Originalbilder im Archiv sowie den Ausschluss des
Caches. Drei der Backend-Tests prüfen die Wiederherstellung nach absichtlich
fehlgeschlagenen Aktivierungen mit alter, zentraler oder fehlender
Vorgängerkonfiguration. Repository-Policy, alle elf Playbook-Syntaxprüfungen
und Production-Lint bestanden. Nach der Anpassung der Verzeichnisrechte wurde
der gezielte Production-Lint erneut erfolgreich ausgeführt.

## Uranus-Dashboard auf app.dev.kulturbytes.de, 16.10.2026

Dashboard-Commit `6a1c296c700f16d05350b11d1b295f576031f8f5` wurde zusätzlich
zum Kulturbytes-Client auf dev01 gebaut und aktiviert. Der abschließende Lauf
von `playbooks/dashboard.yml` einschließlich des Backend-Fixes bestand mit
`ok=87`, `changed=6`, `failed=0`. Der Ingress-Lauf bestand mit `ok=87`,
`changed=5`, `failed=0` und stellte ein eigenes vertrauenswürdiges Zertifikat
für `app.dev.kulturbytes.de` aus. Die öffentlichen HTTPS-Prüfungen lieferten
HTTP 200 über IPv4 und IPv6; mangels lokaler IPv6-Verbindung erfolgte die
IPv6-Prüfung vom Hetzner-Host aus. HTTP leitet auf HTTPS weiter.

Ein nativer Chrome-Lauf prüfte Startseite, Login, Mobilansicht und die
Weiterleitung aus `/admin/dashboard` zur Registrierung für einen unbekannten
Besucher. Die Vue-Anwendung wurde vollständig eingebunden; alle beobachteten
API-Anfragen gingen an die Dashboard-Origin. Es gab keine JavaScript-,
Konsolen-, HTTP- oder Netzwerkfehler und keinen horizontalen Überlauf.
Ein echter Kontologin wurde mangels Benutzerzugangsdaten nicht ausgeführt.

Die bestehende Backend-Version hatte die Anmeldung auf fest benannte Origins
begrenzt. Backend-Commit `d06a615b4b4c8454f5298902fabcddd1d7985834`
([Draft-PR 258](https://github.com/sndcds/uranus/pull/258)) ergänzt ausschließlich
die neue HTTPS-Origin. `go test -mod=readonly ./app ./api` bestand einschließlich
zehn neuer Origin-/Referer-Fälle. Öffentlich antwortete ein Refresh-Aufruf mit
absichtlich ungültigem Cookie und korrekter Dashboard-Origin mit HTTP 401;
derselbe Aufruf von einer fremden Origin wurde mit HTTP 403 abgewiesen.
Die benötigte Tabelle `uranus.refresh_token` war bereits vorhanden;
Datenbankmigrationen waren für diesen Rollout nicht nötig.

41 lokale Dashboard-/Policy-/Template-Tests und 20 Ingress-Tests bestanden.
Die nativen nginx-Prüfungen decken SPA-Tiefenlinks, echte fehlende Assets,
getrennte API-Antworten, unveränderte Origin-Weiterleitung und den Fortbestand
des Kulturbytes-Clients ab. Das separate Dashboard-Limit erlaubt den
parallelen Start der Lookup-Anfragen, begrenzt aber weiterhin anhaltende
API-Last. Repository-Policy, alle zwölf Playbook-Syntaxprüfungen und
Production-Lint bestanden. Abschließend lieferten auch Kulturbytes-Dev,
Dev-API und VersaTiles weiterhin HTTP 200.

## Einheitliche Upload-Grenzen, 16.10.2026

Der private Dashboard-Vhost hatte keine `client_max_body_size`-Direktive und
verwendete deshalb die nginx-Standardgrenze von 1 MiB. Die Serverlogs belegten
abgewiesene Requests zwischen rund 1,5 und 12 MB. Die generierte Konfiguration
verwendete außerdem ältere Pluto-Feldnamen, während die eingebundene Bibliothek
`pluto_max_image_size` in Bytes und `pluto_max_image_px` liest.

Die Anwendungskonfiguration enthält nun auf dev01 und prod01 ausdrücklich
20 MiB (`20971520` Bytes) und 1920 Pixel unter beiden Feldnamen. Beide privaten
nginx und die entsprechenden öffentlichen Ingress-Vhosts erlauben dazu
21 MiB (`22020096` Bytes) pro Request, einschließlich Multipart-Rahmen und
Metadaten. Die Werte stammen aus demselben Ansible-Dateilimit; der Ingress
berücksichtigt den jeweiligen Zielgast. Die bestehenden Datenbankregeln für
`event/main` erlaubten bereits 20 MiB und wurden nicht verändert.

Der Backend-Konfigurationslauf bestand auf beiden Gästen mit `ok=38`,
`changed=2`, `failed=0`. Der nginx-Rollout bestand auf dev01 und prod01 jeweils
mit `ok=40`, `changed=2`, `failed=0`, auf nginx01 mit `ok=85`, `changed=2`,
`failed=0`. `nginx -t` und die Anwendungs-Healthchecks waren erfolgreich.

Echte Requests mit einer 20-MiB-Datei und Multipart-Rahmen (insgesamt
`20971680` Bytes) erreichten über `app.dev.kulturbytes.de`,
`api.dev.kulturbytes.de` und `dev.kulturbytes.de` das Backend. Dasselbe wurde
vom Ingress aus direkt gegen beide privaten Anwendungsgäste geprüft.
Die absichtlich nicht angemeldeten Requests erhielten HTTP 401 vom Backend;
es wurden keine Bilder oder Datenbankeinträge angelegt. Requests mit
`22020097` Bytes wurden erwartungsgemäß bereits von nginx mit HTTP 413
abgewiesen.

33 native Dashboard-/Ingress-Tests bestanden, darunter Grenzprüfungen mit
2, 20 und 32 MiB für alle Anwendungsrouten. Neun Template-/Parserprüfungen
und sieben bestehende Wiederherstellungs-/Sicherungstests bestanden ebenfalls.
Repository-Policy, alle zwölf Playbook-Syntaxprüfungen und der gezielte
Production-Lint bestanden.


## Natives Plausible mit Datenübernahme am 16. Oktober 2026

- `plausible01` ist als achter Incus-Gast mit 8 GiB RAM, vier CPUs und
  `10.77.0.18` provisioniert. Die bestehende CA und alle bisherigen Identitäten
  blieben erhalten; ausschließlich das fehlende Knotenzertifikat wurde ergänzt.
- Plausible CE 3.2.1, Commit `e4f5a87a5570bd61605217e7ceb376636db8eddb`, wurde
  nativ mit Debian-Elixir/Erlang, Node.js 24 und Hex 2.5.3 gebaut. Upstream-
  Lockdateien und sämtliche getrackten Dateien sind nach dem Build unverändert.
  PostgreSQL 17 und ClickHouse 26.9.10.4 laufen lokal; Docker ist nicht installiert.
- Die abschließende Migration lief mit `ok=78`, `changed=8`, `failed=0`,
  `rescued=0`. Alle 50 PostgreSQL-Tabellen und 23 ClickHouse-Objekte wurden gegen
  den bei angehaltenem Writer erstellten Snapshot geprüft: drei Benutzer,
  fünf Websites und 234.816 rohe ClickHouse-Zeilen einschließlich der
  Orts-/Referenzdaten. Die endgültigen Datenbanken heißen `plausible_live`
  und `plausible_events_live`. Frühe Teilimporte bleiben separat erhalten.
- Der Restore berücksichtigt Dictionary-Abhängigkeiten, benutzerdefinierte
  Funktionen, leere Native-Streams und SummingMergeTree: Während der Prüfung
  sind Hintergrundmerges und Zusammenfassen beim Einfügen abgeschaltet. Der
  Export begrenzt Threads und Blockgröße für den speicherknappen Quellserver.
- Das neue öffentliche Zertifikat wurde unabhängig per ACME ausgestellt;
  der bisherige HTTP-Challengepfad leitete die Probe weiter. Kein alter
  TLS-Privatschlüssel wurde exportiert. Die neue Kette hat vier Zertifikats-
  Ebenen; die alte Übergangsroute wurde mit Prüftiefe vier in einem separaten
  nativen nginx getestet. Generierte Umschalt-/Rückfallscripte werden vor SSH
  kompiliert und zusätzlich per Regressionstest geparst.
- Autoritative A-/AAAA-Antworten zeigen auf `94.130.236.38` und
  `2a01:4f8:13b:1405::2`. Neue und alte IPv4-Adressen liefern für `/api/health`,
  `/login` und `/js/script.js` HTTP 200 mit gültigem TLS. Neue und alte IPv6-
  Routen wurden von einem Server mit IPv6-Netz mit HTTP 200 und erfolgreicher
  TLS-Prüfung verifiziert. Die lokale Testmaschine hatte keinen nutzbaren
  direkten IPv6-Pfad. Der bisherige Plausible-Dienst ist inaktiv und deaktiviert;
  seine Route leitet für alte DNS-Caches zum neuen Writer weiter.
- Der reguläre Ingress-Lauf nach DNS-Umstellung war erfolgreich und unverändert
  (`ok=86`, `changed=0`, `failed=0`). Plausible gehört zur normalen TLS-Auswahl;
  automatische Zertifikatserneuerung und nginx-Reload-Hook sind aktiv.
- Chrome prüfte Desktop und Mobilansicht der öffentlichen Anmeldung: E-Mail-
  und Passwortfeld vorhanden, kein horizontaler Überlauf, keine JavaScript-
  Fehler und keine fehlgeschlagenen Assets. Eine Anmeldung mit Benutzerpasswort
  wurde nicht durchgeführt. Registrierung und bestehende Mail-/OAuth-
  Konfiguration wurden aus der aktiven Altinstallation erhalten.
- Erste native Sicherung erfolgreich: PostgreSQL-Custom-Dump und ClickHouse-
  Backup unter `/var/backups/plausible/`. Wiederherstellung in neue isolierte
  Datenbanken erfolgreich: 50 PostgreSQL-Tabellen, 23 ClickHouse-Objekte,
  drei Benutzer, fünf Websites und 18.903 Ereignisse in `events_v2`.
  Der tägliche Backup-Timer mit vierzehn abgeschlossenen Sicherungen ist aktiv.
  Ein externer Backuptransport ist damit nicht nachgewiesen.
- Icinga-Master und Gastfilter wurden aktualisiert (`ok=37`, `failed=0`). Der
  Master bestätigt die authentifizierte Verbindung von `plausible01`, gültiges
  Knotenzertifikat und unveränderte CA. Ressourcen-, HTTPS-, Plausible-Health-
  und ClickHouse-Ping-Prüfungen sind eingerichtet.
- Lokale Prüfungen: 86 Incus-Tests, 54 Policy-/PKI-/Importtests, anschließend
  zwölf Import-/Umschalttests sowie 22 native Vorlagen-/Importtests erfolgreich.
  Der breitere Lauf lieferte zunächst 290 erfolgreiche Tests und durch die
  Sandbox blockierte Socket-Tests; native Wiederholungen wurden zusätzlich
  durch lokale Temporärdaten-Quota unterbrochen. Nach Entfernen ausschließlich
  abgeschlossener eigener Fixtures bestanden die betroffenen Tests in
  Teilmengen, einschließlich der letzten drei PostgreSQL-/Nominatim-Prüfungen.
  Alle Playbooks bestehen Syntaxprüfung; vollständiges ansible-lint besteht.
