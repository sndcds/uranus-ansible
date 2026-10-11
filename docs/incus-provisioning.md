# Incus-Provisionierung

Debian Trixie liefert Incus 6.0.4 LTS mit Debian-Sicherheitsrevisionen. Der Workflow
verwendet `incus` und `incus-client` aus den konfigurierten Debian-Repositories,
keine Fremdrepositories oder Installationsskripte. Neuere Hauptversionen werden
abgelehnt und brauchen eine gesonderte Kompatibilitätsprüfung.
[Debian-Paket](https://packages.debian.org/trixie/incus).

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
