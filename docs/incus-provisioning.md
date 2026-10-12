# Incus-Provisionierung

Debian Trixie liefert Incus 6.0.4 LTS mit Debian-Sicherheitsrevisionen. Der Workflow
verwendet `incus` und `incus-client` aus den konfigurierten Debian-Repositories,
keine Fremdrepositories oder Installationsskripte. Neuere Hauptversionen werden
abgelehnt und brauchen eine gesonderte Kompatibilitätsprüfung.
[Debian-Paket](https://packages.debian.org/trixie/incus).

Für DHCP und DNS der verwalteten Bridge wird `dnsmasq-base` ausdrücklich
installiert. Das Paket liefert die von Incus gestartete `dnsmasq`-Binärdatei,
ohne einen separaten systemweiten Dienst einzurichten.
[Debian-Paket](https://packages.debian.org/trixie/dnsmasq-base).

Für VMs installiert die Hostrolle `qemu-system-x86`, `qemu-utils`,
`qemu-system-modules-spice` und `ovmf` ausdrücklich. UEFI-Firmware und mehrere
QEMU-Komponenten sind unter Debian nur Empfehlungen; eine Installation mit
deaktivierten Recommends kann sie auslassen.
[QEMU-Paket](https://packages.debian.org/trixie/qemu-system-x86).
Wenn diese VM-Paketinstallation etwas ergänzt, startet die Rolle den geschützten
Incus-Daemon neu, damit er die beim Start gespeicherten QEMU-Featurechecks
wiederholt. Unveränderte Wiederholungen lösen dadurch keinen Neustart aus.
Der lesende Preflight verlangt bei ausgewählten VMs den betriebsfähigen Treiber
`qemu` in `/1.0.environment.driver`, bevor Projekt, Pool, Netzwerk oder Instanzen
erstellt werden. Ein vorhandenes `/dev/kvm` allein genügt nicht.

Die NICs verwenden `security.ipv6_filtering=true`, auch auf der Bridge ohne
IPv6-Subnetz. Dafür lädt die Hostrolle `br_netfilter` vor dem ersten Instanzstart
und hinterlegt das Modul in `/etc/modules-load.d/uranus-incus.conf`. Sie setzt
`net.bridge.bridge-nf-call-ip6tables=1` im laufenden Kernel und dauerhaft in
`/etc/sysctl.d/90-uranus-incus.conf`. Wiederholungen korrigieren auch einen
abweichenden Laufzeitwert; die Einstellung wird vor der Instanzprovisionierung
geprüft. `kmod` und `procps` werden für `modprobe` und `sysctl` ausdrücklich
installiert.
[Incus-Prüfung](https://github.com/lxc/incus/blob/v6.0.4/internal/server/device/nic_bridged.go#L907).

Incus verwaltet sämtliche Instanzen und Metadaten. Ansible führt native
`project create`, `storage create`, `network create`, `init` und `start` aus.
Die vorhandene `community.general.lxd_container`-Abstraktion erlaubt Zustands-
Reconciliation und verwendet LXD/PyLXD; sie liefert nicht die hier erforderliche
strikte Verweigerung bei fremden Ressourcen, Drift und unklaren Storagezuständen.
Deshalb wird `ansible.builtin.command` mit strukturierten Argumenten verwendet.
Eigene Pythonmodule lesen ausschließlich den Incus-Zustand oder prüfen Storage
und SQL; sie implementieren keine Virtualisierung und keinen Lifecycle.
[Moduldokumentation](https://docs.ansible.com/projects/ansible/latest/collections/community/general/lxd_container_module.html).

Das Projekt `uranus` besitzt eigene Images, Profile und Volumes. Ein dediziertes
hostweites NAT-Netz wird über `restricted.networks.access` freigegeben. Privilegierte
Container, Nesting, unverwaltete Disks und NICs werden durch Projektrestriktionen
verhindert. Jede Instanz verwendet explizite Geräte und keine geerbten Profile.
Container nutzen isolierte UID-Mappings; VMs verwenden keine Containeroptionen.

Die beiden Debian-Trixie-Cloud-Images sind über vollständige Fingerprints aus dem
offiziellen Imageindex vom 11.10.2026 referenziert. Die Image-Server können alte
Images entfernen: Vor Freigabe aktuelle Fingerprints überprüfen und verifizierte
Images in einen kontrollierten Mirror übernehmen. `images:` muss auf den
vorgesehenen offiziellen HTTPS-Image-Server zeigen. Vorhandene Instanzen werden
bei einem Wechsel des Image-Fingerprints nicht ersetzt.

Vor jeder Erstellung validiert Ansible erneut Projekt, Pool, Netzwerk, Instanzen,
freie Kapazität und Ownership. `init` erhält Ressourcen, Geräte und Cloud-init in
einem einzigen Aufruf. Erst danach erfolgt `start`. Autostart und Löschschutz
sind gesetzt. Bestehende gestoppte Instanzen bleiben gestoppt, solange
`incus_start_existing` nicht ausdrücklich aktiviert wird.

Nach den Starts konfiguriert die Rolle den DHCPv4-Client jeder laufenden
Instanz über `incus exec` auf `ClientIdentifier=mac` und prüft, dass die erkannte
Ethernet-Schnittstelle die reservierte IPv4-Adresse erhält. Container verwenden
üblicherweise `eth0`, die VM kann beispielsweise `enp5s0` verwenden. Die eigene
Datei `/etc/systemd/network/05-uranus-incus.network` erfasst diese Schnittstelle
über ihre MAC-Adresse und aktiviert DHCP auch bei bisher unverwaltetem Link.
Mehrere Ethernet-Schnittstellen werden vor Änderungen abgelehnt.
Dieser lokale Kanal funktioniert auch,
wenn eine falsche dynamische Adresse durch den Incus-IP-Filter blockiert wird
und Gast-SSH/DNS deshalb noch nicht verfügbar sind. Neue Instanzen führen
dieselbe Konfiguration über Cloud-init `bootcmd` vor APT aus. Die bestehende
Cloud-init-Netzwerkdatei bleibt erhalten; eine eigene networkd-Datei wird
geschrieben. Bei korrekter Netzwerkdatei und korrekter Adresse bleibt eine Wiederholung
ohne Netzwerkänderung. Die Incus-IP-/MAC-Filter bleiben aktiv, und der DNS-Dienst
der Bridge behält seine AppArmor-Konfiguration.

Anschließend richtet `provision.yml` auf jeder laufenden VM und jedem laufenden
Container dieselbe Grundinstallation über den lokalen Incus-Kanal ein. Dazu
gehören der Instanzname als Hostname, der Benutzer `debian` mit Bash und
Passwortsperre, die Gruppen `adm` und `sudo`, kennwortloses sudo und der
öffentliche SSH-Schlüssel aus `hetzner_ssh_public_key_file`. Zusätzliche vorhandene
SSH-Schlüssel und Gruppen bleiben erhalten. Die gemeinsame Paketliste
`incus_guest_bootstrap_packages` enthält `ca-certificates`, `openssh-server`,
`python3`, `sudo`, `acl` und `htop`. Cloud-init für neue Instanzen und die spätere
Debian-Gastrolle verwenden dieselbe Liste.

Vor diesem Bootstrap wartet Ansible auf laufendes Cloud-init. Abgeschlossene
Fehler der ursprünglichen Paketinstallation und des anschließenden SSH-Starts
werden gezielt durch den Bootstrap repariert, wenn die damalige Paketliste und
`runcmd` zur verwalteten Grundinstallation passen. Fehler anderer Module,
zusätzlicher Pakete oder eigener Kommandos brechen den Lauf ab. Die ursprüngliche
Cloud-init-Fehlerhistorie bleibt erhalten; die geprüfte Ansible-Grundinstallation
entscheidet anschließend über die Bereitschaft des Gasts.
Bei `status: disabled` richtet Ansible die Grundinstallation
direkt ein, ohne Cloud-init erneut zu starten. Das funktioniert auch bei einer
bestehenden VM mit fehlendem Benutzer oder noch nicht verfügbarem Gast-SSH.
Fehlende SSH-Hostschlüssel werden mit `ssh-keygen -A` ergänzt; bestehende werden
erhalten. sudoers und SSH-Konfiguration werden vor Aktivierung geprüft. SSH
verwendet ausschließlich Schlüssel und erlaubt keinen Rootlogin. Die Rolle setzt
einen expliziten Include der verwalteten SSH-Datei an den Anfang von
`/etc/ssh/sshd_config`, auch wenn Cloud-init vor der Paketinstallation lediglich
`PasswordAuthentication no` in dieser Datei hinterlassen hat. Die übrige
Hauptkonfiguration bleibt erhalten. `UsePAM yes` ermöglicht die PAM-Konto- und
Sitzungsprüfung bei Schlüsselanmeldung; Passwort- und interaktive Anmeldung
bleiben abgeschaltet. Bootstrap und Gastrolle verwenden dieselbe SSH-Vorlage.
Fehlt das SFTP-Subsystem in der effektiven Konfiguration, ergänzt der Bootstrap
`Subsystem sftp internal-sftp` für Ansible-Dateitransfers. Ein bereits eingerichtetes
SFTP-Subsystem bleibt erhalten.
Ein korrekter
Wiederholungslauf installiert keine Pakete erneut und lädt SSH nicht erneut.

Erst nach erfolgreicher Prüfung hinterlegt Ansible
`/var/lib/uranus/instance-bootstrap.json` mit dem Instanznamen.
`configure.yml` verlangt diese Bestätigung vor der Anwendungskonfiguration;
ein deaktiviertes Cloud-init allein gilt damit nicht als erledigte Grundinstallation.
Für bereits vorhandene Gäste zuerst das aktualisierte `provision.yml` erneut
ausführen. Mit `-e incus_start_existing=true` werden auch validierte gestoppte
Instanzen gestartet und anschließend vorbereitet.

Wiederholungen erhalten Datenträger und Instanzen. Bei abweichender CPU, RAM,
Diskbudget, Typ, Netzwerk, Owner, Extra-Geräten oder unsicherer Konfiguration
bricht der Lauf ab. Ansible setzt keine automatischen Resizes, Imports, Deletes
oder Neuinitialisierungen ein. Ein unterbrochenes `init` kann eine gestoppte
Instanz zurücklassen; Zustand prüfen und den Start bewusst autorisieren.
Verwaiste Verzeichnisse/Volumes werden nie bereinigt.

Für Administration am später freigegebenen Host:

```bash
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus list
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus config show db01 --expanded
sudo env INCUS_DIR=/data/incus incus --force-local --project uranus console db01
```

Incus-Gruppen und der Unix-Socket sind rootäquivalent. Nur benannte Administratoren
haben Zugriff. Diese Kommandos sind Betriebsbeispiele, keine Erlaubnis für eine
Änderung des Zielhosts.

Die eingetragenen Image-Fingerprints beziehen sich auf den geprüften Debian-13-
Cloud-Build vom 11. Oktober 2026. Vor Freigabe deren Verfügbarkeit sichern
(geprüfter eigener Image-Cache/Mirror) oder neue vollständige Fingerprints in
einem Review freigeben. Der öffentliche Image-Server kann alte Builds entfernen;
dann bricht die Erstellung ab, statt unbemerkt ein neues Image zu verwenden.
