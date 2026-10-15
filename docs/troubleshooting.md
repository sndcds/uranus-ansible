# Fehlersuche, Recovery und Updates

Alle Kommandos sind Beispiele für eine später autorisierte Betriebsphase.

| Meldung / Symptom | Sichere Reaktion |
|---|---|
| Deployment disabled | Sperren beibehalten; lokale Tests ausführen. Produktivfreigabe nicht aus Fehlermeldung ableiten. |
| Falsche UUID / Mount fehlt | `findmnt --mountpoint /data`; NVMe und fstab passiv prüfen. Kein Formatieren oder automatisches Remounten. |
| Fremder Incus-Zustand | stop; Offline-Migrationsplan und Backup erstellen. Kein Owner-Marker zum Umgehen der Prüfung setzen. |
| Ressourcen-/Device-Drift | `incus config show --expanded` lesen; Änderung separat planen. Kein Delete/Recreate. |
| Verwaiste Disk / unterbrochenes init | Volume, Instanzstatus, `incus info --show-log` und Incus-Events prüfen. Daten erhalten; manual Recovery. |
| QEMU-Featurechecks / VM-Treiber nicht betriebsfähig | `sudo journalctl -u incus -b --no-pager` nach `Unable to run feature checks during QEMU initialization` durchsuchen. Die folgende Ursache prüfen: UEFI-Firmware (`ovmf`), QEMU-Pakete oder KVM-Zugriff. Nach behobenen Voraussetzungen Incus neu starten, damit die beim Daemonstart gespeicherte Prüfung erneut läuft. |
| `security.ipv6_filtering requires bridge netfilter` | Hostrolle erneut ausführen; sie lädt `br_netfilter` und aktiviert `net.bridge.bridge-nf-call-ip6tables=1` dauerhaft. Bereits initialisierte, gestoppte Instanzen bleiben erhalten und benötigen einen ausdrücklich angeforderten Start. |
| `incusd forkstart ... exit status 1` | Dies ist die Sammelmeldung des LXC-Starts. Die Rolle gibt jetzt automatisch `incus info --show-log` aus; die konkrete Ursache aus diesem Log prüfen. Für `dev01`: `sudo env INCUS_DIR=/data/incus incus --force-local --project uranus info --show-log dev01`. |
| `Permission denied - Could not access /data/incus` | Das Basisverzeichnis benötigt Modus `0711`, damit die abgebildete Container-Root-UID es traversieren kann. Hostrolle erneut ausführen oder ausschließlich `sudo chmod 0711 /data/incus` anwenden; anschließend die erhaltene Instanz starten. |
| Gestoppte vollständige Instanz | Ursache prüfen; Start ausdrücklich über Incus oder `incus_start_existing=true` autorisieren. |
| SSH/Firewall bestätigt nicht | 120 Sekunden Rollback abwarten, neue Verbindung per Schlüssel herstellen; `/var/lib/uranus/host-access` und Journal prüfen. |
| SSH Match / Serviceoptionen abgelehnt | Hostbestand gesondert prüfen; kein Entfernen fremder Regeln und keine blinde Freigabe von Port 22. |
| Keine neue SSH-Verbindung per Schlüssel | SSH-Agent/privaten Schlüssel, bestehenden Benutzer und authorized_keys prüfen; Passwort oder Rootlogin nicht als Ausweichweg aktivieren. |
| Boot-Recovery schlägt fehl | Konsole/Rescue verwenden; Journal und erhaltenen Pending-Zustand prüfen, ursprüngliche SSH-Datei und Firewall aus gesicherten Transaktionsdaten wiederherstellen. |
| Keine Gast-SSH-Verbindung | Cloud-init, Incus-Konsole, DHCP-Lease und Hostschlüssel kontrollieren; keine Hostkey-Prüfung abschalten. |
| DNS/APT scheitert und Gast hat eine abweichende DHCP-Adresse | `incus config device get NAME eth0 ipv4.address` mit `ip -4 address show dev eth0` im Gast vergleichen. Bei networkd-DUID die folgende MAC-basierte DHCP-Recovery verwenden oder das korrigierte Provisionierungsplaybook erneut ausführen. IP-/MAC-Filter aktiv lassen. |
| VM läuft, aber Incus zeigt keine IPv4-Adresse | Über `incus exec db01 -- ip -br link` und `networkctl status --all --no-pager` im Gast prüfen. `ip -4 address` allein zeigt nicht alle vorhandenen Links. Bei `enp5s0 DOWN` und `Network File: n/a` die folgende VM-Recovery oder das korrigierte Provisionierungsplaybook verwenden. |
| Cloud-init deaktiviert, Image-Build-Hostname oder fehlender Benutzer `debian` | Das aktualisierte `provision.yml` erneut ausführen. Es richtet Hostname, Benutzer, SSH-Zugang und gemeinsame Pakete einschließlich `htop` auf allen laufenden Instanzen direkt über Incus ein. Laufendes Cloud-init wird abgewartet. |
| Cloud-init zeigt abgeschlossene Fehler bei `package-update-upgrade-install` und `scripts-user` nach dem behobenen Netzwerkproblem | `provision.yml` erneut ausführen. Wenn ausschließlich die verwalteten Basispakete und der SSH-Start betroffen sind, übernimmt Ansible diese Schritte und prüft den fertigen Gast. Die ursprüngliche Cloud-init-Fehlerhistorie bleibt bestehen. Andere Module oder eigene Pakete/Kommandos werden nicht als repariert gewertet. |
| Cloud-init meldet einen alten `bootcmd`-Fehler beim DHCP-Skript | Das aktualisierte `provision.yml` erneut ausführen. Es prüft den gespeicherten Befehl gegen das exakte verwaltete DHCP-Skript und verifiziert dessen erfolgreiche Netzwerkkorrektur über Incus vor dem Bootstrap. Eigene oder zusätzliche `bootcmd`-Befehle bleiben gesperrt. Neue Instanzen führen diesen frühen Befehl nicht mehr aus. |
| `instance-bootstrap.json` fehlt bei `configure.yml` | Zuerst das aktualisierte `provision.yml` mit den Deployment- und Vault-Argumenten ausführen. Die Bestätigung wird erst nach erfolgreich geprüftem Bootstrap geschrieben. |
| Bootstrap meldet `kbdinteractiveauthentication`; Hauptdatei lädt kein `sshd_config.d` | Das aktualisierte `provision.yml` setzt den Include der verwalteten SSH-Datei vor die vorhandene Hauptkonfiguration. Es prüft Schlüsselanmeldung, `UsePAM yes`, deaktivierte Passwort-/interaktive Anmeldung und deaktivierten Rootlogin vor dem SSH-Reload. Vorhandene Hostschlüssel bleiben erhalten. |
| SQL pending marker | DB und Logs prüfen, Backup sichern; unvollständige Erstinitialisierung manuell beheben. Marker nicht blind löschen. |
| Nominatim unvollständig | Daten bewahren und Wiederanlauf planen; Superuserrechte sofort prüfen und widerrufen. |
| TLS schlägt fehl | CA, SAN, Uhrzeit, EKU, Keyrechte und Zertifikatablauf prüfen. Keine verify-Funktion deaktivieren. |
| Controller-PKI fehlt / `ca.crt: File not found` | PKI wird auf dem Ansible-Controller gelesen. Bestehende CA und Knotenzertifikate unter `uranus_pki_dir` bereitstellen oder für eine neue CA `python scripts/prepare_pki.py` ausführen. Für die erzeugten Schlüssel zusätzlich `--vault-id pki@.uranus-private/pki/vault-password` zum bisherigen Kommando hinzufügen. |
| Kapazität unzureichend | Snapshot-/Backupverbrauch inventarisieren und extern sichern. Keine automatische Löschung bestehender Daten. |
| Backend-Konsistenzprüfung scheitert | passenden Release und Schema wählen; Prüfung nicht per Source-Patch abschalten. |

Bei einem fehlgeschlagenen ersten Start von `db01` ist `init` bereits erfolgt.
Nach dem Fix das Provisionierungsplaybook mit den bisherigen Deployment- und
Vault-Argumenten sowie zusätzlich `-e incus_start_existing=true` wiederholen.
Dadurch startet Incus die validierten gestoppten Instanzen und erstellt die
übrigen fehlenden Instanzen. Für eine sofortige Recovery am freigegebenen Host:

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus start db01
```

Die ersten beiden Kommandos wirken nur bis zum Neustart; die Hostrolle richtet
die dauerhafte Konfiguration ein.

Auch nach einem fehlgeschlagenen Containerstart bleibt die initialisierte
Instanz erhalten. Neue und ausdrücklich angeforderte Starts verwenden dieselbe
Storageprüfung und Fehlerdiagnose. Schlägt das Lesen des Incus-Logs ebenfalls
fehl, zeigt Ansible den ursprünglichen Startfehler und den Diagnosefehler und
bricht weiterhin ab. Nach behobener Ursache den Start mit
`-e incus_start_existing=true` ausdrücklich anfordern.

Für die gezielte Recovery eines wegen Modus `0700` gescheiterten `dev01`:

```bash
sudo chmod 0711 /data/incus
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus start dev01
```

Der korrigierte Hosttask erhält Modus `0711` auch bei späteren Wiederholungen.

Wenn beispielsweise `dev01` statt `10.77.0.12` eine dynamische Adresse wie
`10.77.0.91` erhält, blockiert `security.ipv4_filtering=true` den Verkehr mit
dieser abweichenden Quelladresse. Ein DNS-Stub `127.0.0.53` in `/etc/resolv.conf`
ist bei laufendem `systemd-resolved` normal; die Datei muss dafür nicht ersetzt
werden. `networkctl status eth0 --no-pager` zeigt die verwendete Netzwerkdatei,
den über DHCP gelieferten DNS-Server und die DHCPv4-Clientkennung. Eine
`IAID:.../DUID`-Kennung wird auf MAC umgestellt.

Auf dem Host den lokalen Incus-Kanal öffnen:

```bash
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus exec dev01 -- bash
```

Im Gast das Drop-in für die bestätigte Cloud-init-Netzwerkdatei einrichten:

```bash
install -d -m 0755 /etc/systemd/network/10-cloud-init-eth0.network.d
cat > /etc/systemd/network/10-cloud-init-eth0.network.d/50-uranus-dhcp-mac.conf <<'EOF'
[DHCPv4]
ClientIdentifier=mac
EOF
chmod 0644 /etc/systemd/network/10-cloud-init-eth0.network.d/50-uranus-dhcp-mac.conf
networkctl reload
networkctl reconfigure eth0
```

Nach einigen Sekunden `ip -4 address show dev eth0` und
`timeout 10 getent ahostsv4 deb.debian.org` prüfen. Für `dev01` muss die Adresse
nun `10.77.0.12/24` sein. Sobald DNS funktioniert, APT erneut ausführen. Das
korrigierte Provisionierungsplaybook richtet eine eigene MAC-basierte
Netzwerkdatei auch auf laufenden bestehenden Instanzen ein; deren Daten bleiben erhalten. Andere
Instanzen erhalten ihre eigenen reservierten Adressen aus `incus_instances`.
Der Workflow überschreibt weder `resolv.conf` noch die von Cloud-init verwaltete
Basis-Netzwerkdatei und benötigt keine rohe dnsmasq-Konfiguration.

Wenn `db01` als VM die Karte `enp5s0` besitzt, aber `networkctl` für sie
`Network File: n/a` und `off (unmanaged)` ausgibt, gibt es keine passende
Netzwerk-Konfiguration. Der Incus-Gerätename `eth0` ist dann nicht der tatsächliche
Gastname. Der sichtbare Treiber `virtio_net` zeigt, dass die Karte erkannt wurde;
ein Wechsel der VM-Hardware ist dafür nicht erforderlich.

Auf dem Host:

```bash
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus exec db01 -- bash
```

In der VM die bestätigte Karte anhand ihrer aktuellen MAC-Adresse erfassen:

```bash
install -d -m 0755 /etc/systemd/network
uranus_network_mac=$(cat /sys/class/net/enp5s0/address)
cat > /etc/systemd/network/05-uranus-incus.network <<EOF
[Match]
MACAddress=$uranus_network_mac

[Network]
DHCP=ipv4
IPv6AcceptRA=no

[DHCPv4]
ClientIdentifier=mac
EOF
chmod 0644 /etc/systemd/network/05-uranus-incus.network
networkctl reload
networkctl reconfigure enp5s0
networkctl up enp5s0
```

Nach einigen Sekunden `ip -4 address show dev enp5s0`, `ip -4 route` und
`timeout 10 getent ahostsv4 deb.debian.org` prüfen. Für `db01` ist
`10.77.0.11/24` reserviert. Die Rolle erkennt die Schnittstelle für diese Datei
automatisch und erhält vorhandene Cloud-init-Dateien. Anschließend
`cloud-init status --long` prüfen, da fehlender Netzwerkzugang zuvor auch
Benutzer- oder Paketinitialisierung verhindert haben kann.

Für die gemeinsame Recovery aller sieben bestehenden Instanzen vom Controller
im Repository aus:

```bash
ansible-playbook playbooks/provision.yml \
  -e @environments/hetzner/deployment.yml \
  -e @environments/hetzner/vault.yml \
  --ask-vault-pass --ask-become-pass \
  --vault-id pki@.uranus-private/pki/vault-password \
  -e incus_start_existing=true
```

Nach einem erfolgreichen Lauf sind Netzwerk, Hostname, `debian`, SSH und
`incus_guest_bootstrap_packages` einschließlich `htop` auf allen sieben Gästen
vorbereitet. Die Anwendungspakete und Dienste folgen weiterhin in `configure.yml`.
Cloud-init kann bei einer vorhandenen VM deaktiviert bleiben; Ansible führt
dort die geprüfte Grundinstallation selbst aus. Es werden keine Cloud-init-
Caches gelöscht, vorhandenen SSH-Hostschlüssel ersetzt oder Gäste neu erstellt.

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
