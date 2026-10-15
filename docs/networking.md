# Netzwerk, SSH und TLS

Incus verwaltet die Bridge `uranusincus0`, `10.77.0.1/24`, ausgehendes IPv4-NAT
und feste DHCP-Adressen der sieben NICs. Adressen stammen aus der zentralen
Instanzliste. Die Bridge ist nicht an eine physische öffentliche Schnittstelle
angebunden; IPv6 ist innerhalb der Instanzen deaktiviert. Öffentliche IPv6-
Verbindungen nimmt Incus am Host entgegen und reicht sie an `nginx01` weiter.

Die beiden Incus-Proxygeräte `http` und `https` gehören ausschließlich zum
Container `nginx01`. Ihre TCP-Listener auf `[::]:80` und `[::]:443` nehmen auf
dem Debian-Host IPv4 und IPv6 entgegen. Ohne NAT verbindet Incus im Netzwerk-
Namensraum des Containers nach `127.0.0.1:80/443` und überträgt die Client-IP
mit dem PROXY-Protokoll. Nginx vertraut diesem Protokoll nur auf Loopback;
öffentliche HTTP-Header können weder Client-IP noch private CIDR-Freigaben
überschreiben. TLS und ACME enden im Container. Ein zusätzlicher HTTPS-Listener
auf dessen privater IP dient dem Monitoring ohne PROXY-Protokoll.
[Incus-Proxygeräte in 6.0.4](https://github.com/lxc/incus/blob/v6.0.4/doc/reference/devices_proxy.md).

Das dedizierte Projekt erlaubt dafür `restricted.devices.proxy=allow`.
Alle übrigen Projektrestriktionen bleiben gesetzt. Der Guard prüft die exakten
Proxygeräte und lehnt zusätzliche Geräte auf anderen Instanzen ab. Bei einem
bisherigen verwalteten Projekt wird ausschließlich diese Einstellung nach
erfolgreichem vollständigem Preflight angepasst; fremde Projekte werden abgelehnt.

Die Debian-Cloud-Images verwenden `systemd-networkd`. Dessen DHCPv4-Client
verwendet standardmäßig eine DUID; die festen Incus-DHCP-Zuweisungen erfordern
eine MAC-basierte Kennung. Die Rolle erkennt die einzige Ethernet-Schnittstelle
des Gasts und schreibt `/etc/systemd/network/05-uranus-incus.network`. Die Datei
ordnet den Link anhand von `[Match] MACAddress=...` zu und setzt IPv4-DHCP mit
`[DHCPv4] ClientIdentifier=mac`. Dadurch funktionieren sowohl `eth0` in einem
Container als auch `enp5s0` in einer VM, selbst wenn die bisherige Cloud-init-
Datei die VM-Karte nicht erfasst. Null oder mehrere Ethernet-Schnittstellen
werden vor Änderungen abgelehnt. Neue Instanzen erhalten explizite Cloud-init-
Netzwerkdaten mit Renderer `networkd` und Namensmuster `e*`; die eigene
MAC-basierte Konfiguration wird von der Hostrolle über den Incus-Kanal vor der
Ansible-Paketinstallation eingerichtet. Cloud-init führt weder den zusätzlichen
DHCP-Befehl noch die Paketinstallation aus. Die Hostrolle konfiguriert alle laufenden
neuen und bestehenden Instanzen über den lokalen Incus-Kanal und wartet auf
ihre vorgegebene IPv4-Adresse. Gestoppte Instanzen bleiben gestoppt, sofern
kein Start angefordert wurde. Wiederholungen mit gültiger Netzwerkdatei und gültiger
Adresse laden das Netzwerk nicht neu.
[networkd-Dokumentation](https://manpages.debian.org/trixie/systemd/systemd.network.5.en.html)
und [Incus-DHCP-Zuweisungen](https://linuxcontainers.org/incus/docs/main/reference/network_bridge/).

Host-input erlaubt Loopback, etablierte Verbindungen, ICMP/ICMPv6, DNS/DHCP auf
der privaten Bridge sowie öffentlich SSH auf Port 22 und HTTP/HTTPS auf 80/443.
SSH erfordert einen gültigen Schlüssel, ohne feste IPv4- oder IPv6-Quelladresse.
Port 80 dient ACME und HTTPS-Weiterleitung. Nur der private Monitoringknoten
kann den Host-Icinga-Agent erreichen. Forward-Regeln blockieren neue externe
Verbindungen zur Incus-Bridge. Gastfilter erlauben SSH vom Gateway und HTTPS
zu Anwendungsgästen ausschließlich von `nginx01`,
PostgreSQL von den vier berechtigten Clients, Metriken von Development und
Production sowie Icinga-Kommunikation zwischen Master und Agenten.

Alle Filter sind explizite Uranus-nftables-Tabellen. Es gibt kein `flush ruleset`.
Andere Regeln einschließlich Incus-NAT bleiben erhalten. Andere Drop-Regeln
können weiterhin Verkehr blockieren; der spätere Host-Audit muss dies klären.
Incus setzt seine eigenen NAT-/Bridge-Regeln; Ansible verwaltet die zusätzlichen
Zugriffsregeln zentral. Die SSH-Freigabe gilt für beide Adressfamilien.

Vor Änderungen muss eine neue SSH-Verbindung als bestehender Benutzer ohne
Rootrechte ausschließlich mit einem Schlüssel funktionieren. Ansible unterbindet
Passwort- und Keyboard-Interactive-Anmeldung bereits auf dem Controller. Die
Transaktion sichert die bisherige eigene SSH-Datei und Firewall, bewaffnet einen
unabhängigen systemd-Timer auf 120 Sekunden und installiert erst danach
`/etc/ssh/sshd_config.d/00-uranus-host.conf`. Dieser erzwingt
`AuthenticationMethods publickey`, aktiviert Schlüssel und deaktiviert Passwort,
Keyboard-Interactive und Rootlogin. `sshd -t` sowie `sshd -T` prüfen die wirksame
Konfiguration global und für die aktuelle Verbindung, bevor SSH neu geladen und
der öffentliche Firewallzugang angewendet wird. Nach `reset_connection` muss
eine neue Verbindung per Schlüssel innerhalb von 45 Sekunden funktionieren.

Ohne Bestätigung stellt der Timer die frühere SSH-Datei und Uranus-Tabelle
wieder her. Die Transaktionsdaten unter `/var/lib/uranus/host-access` sind
dauerhaft: `uranus-access-recovery.service` stellt einen unbestätigten Stand
auch nach einem Neustart vor dem Start von SSH wieder her. Die vorherige
persistente Firewall wird ebenfalls erhalten. Andere nftables-Tabellen bleiben
unverändert. Scheitert die Firewallwiederherstellung, bleibt die Schlüsselpflicht
aktiv; die frühere, möglicherweise schwächere SSH-Policy wird nicht öffentlich
freigegeben. In diesem Fehlerfall sind Konsole/Rescue und manuelle Recovery nötig.

Bestehende SSH-Konfigurationen mit `Match`, rekursiven Includes, fremder Datei am
verwalteten Pfad, zusätzlichen Serviceoptionen oder nicht leerem `SSHD_OPTS`
werden vor der Transaktion abgelehnt. Widersprechende Einstellungen in früheren
Include-Dateien werden über die wirksame OpenSSH-Policy erkannt und zurückgerollt.
Diese Bestände benötigen eine eigene Prüfung; der Workflow überschreibt sie nicht.
Vorhandene `authorized_keys`, Hostschlüssel und Sudo-Regeln bleiben erhalten.
Eventuelle `from=`-Beschränkungen vorhandener Schlüssel sind beim Host-Audit auf
Kompatibilität mit wechselnden Adressen zu prüfen.

SSH benutzt Schlüssel, `StrictHostKeyChecking=yes`, ProxyJump und auf dem Host
den vorhandenen Benutzer `awendelk`, in Gästen `debian`. Gast-Hostschlüssel
vor Ansible aus einem vertrauenswürdigen Incus-Konsolenkanal übernehmen. Eine
Ausgabe von `ssh-keyscan` allein bestätigt keine Identität. Änderungen von
SSH-Port oder Benutzer sind nicht automatisch unterstützt.

Nginx in `nginx01` fordert ein ACME-SAN-Zertifikat für zentrale Domainvariablen an.
DNS muss auf die vorgesehene IPv4 zeigen; vorhandene AAAA-Records müssen zuvor
mit der Hostkonfiguration abgeglichen werden. Zertifikatserneuerung lädt nur
nach erfolgreichem `nginx -t` neu. Development und Monitoring sind per CIDR
beschränkt; diese drei privaten Sites dürfen nicht aus der privaten Liste
entfernt werden. PostgreSQL, InfluxDB und Incus haben keine öffentliche Freigabe.

`hetzner_private_web_networks` ist unabhängig von der SSH-Anmeldung. Development
und Monitoring bleiben auf die dort ausdrücklich erlaubten Netze beschränkt.
Bei wechselnder öffentlicher IP müssen diese Webfreigaben über einen separat
geplanten stabilen Verwaltungszugang oder eine bewusste Aktualisierung erfolgen;
die öffentliche SSH-Freigabe öffnet keine privaten Websites.

Für die interne PKI werden offline ein CA-Zertifikat und pro Knoten ein
Zertifikat samt verschlüsseltem Schlüssel bereitgestellt. Zertifikate brauchen
DNS-SAN für den Knotennamen und IP-SAN für die jeweilige private Adresse; beim
Host zusätzlich öffentliche Administrationsadresse und Bridgeadresse. Für
Icinga sind serverAuth/clientAuth nötig. CA-Privatschlüssel nie auf Host oder
Gäste kopieren. Das Repository enthält keine privaten Schlüssel.

Ingress-zu-Gast-Nginx verwendet HTTPS mit CA-/Namensprüfung. Die Anwendungsgäste
vertrauen `X-Real-IP` ausschließlich von der privaten IP von `nginx01`.
PostgreSQL-ACLs verlangen
`hostssl` und SCRAM; Clients benutzen `verify-full` und die CA. `PGSSLMODE` und
`PGSSLROOTCERT` im Backend-Service sichern auch Releases ab, welche das
`ssl_mode`-JSON-Feld nicht selbst auswerten. InfluxDB, Grafana und die Metrikwriter
nutzen intern HTTPS. Der Metrikzugriff bleibt IP-beschränkt; zusätzliche
Influx-Benutzerauthentifizierung ist ein dokumentierter offener Härtungspunkt.

Öffentliches DNS muss eine passende A-Adresse besitzen. Optionale AAAA-Adressen
müssen der zentral konfigurierten Host-IPv6 entsprechen; andere Zieladressen
stoppen ACME vor der ersten Zertifikatsanforderung.
