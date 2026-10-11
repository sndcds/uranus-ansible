# Netzwerk, SSH und TLS

Incus verwaltet die Bridge `uranusincus0`, `10.77.0.1/24`, ausgehendes IPv4-NAT
und feste DHCP-Adressen der sechs NICs. Adressen stammen aus der zentralen
Instanzliste. Die Bridge ist nicht an eine physische öffentliche Schnittstelle
angebunden; IPv6 ist innerhalb der Instanzen deaktiviert. Öffentliche IPv6-
Verbindungen enden wie IPv4 am Host-Ingress, nie direkt an Gästen.

Host-input erlaubt Loopback, etablierte Verbindungen, ICMP/ICMPv6, DNS/DHCP auf
der privaten Bridge, SSH aus den Management-CIDRs und öffentlich 80/443.
Port 80 dient ACME und HTTPS-Weiterleitung. Nur der private Monitoringknoten
kann den Host-Icinga-Agent erreichen. Forward-Regeln blockieren neue externe
Verbindungen zur Incus-Bridge. Gastfilter erlauben SSH und Webzugriff vom Gateway,
PostgreSQL von den vier berechtigten Clients, Metriken von Development und
Production sowie Icinga-Kommunikation zwischen Master und Agenten.

Alle Filter sind explizite Uranus-nftables-Tabellen. Es gibt kein `flush ruleset`.
Andere Regeln einschließlich Incus-NAT bleiben erhalten. Andere Drop-Regeln
können weiterhin Verkehr blockieren; der spätere Host-Audit muss dies klären.
Incus setzt seine eigenen NAT-/Bridge-Regeln; Ansible verwaltet die zusätzlichen
Zugriffsregeln zentral. IPv4- und IPv6-Managementlisten werden getrennt geprüft.

Vor Änderungen muss die aktuelle SSH-Quelladresse in der entsprechenden
Managementliste enthalten sein. Der Rollback wird vor dem nft-Aufruf per
systemd-Timer auf 120 Sekunden bewaffnet. Nach `reset_connection` bestätigt eine
neue authentifizierte SSH-Verbindung innerhalb von 45 Sekunden den Kandidaten.
Erst danach wird die dauerhafte Konfiguration atomar ersetzt. Bei Verbindungs-
verlust stellt der Timer die frühere Uranus-Tabelle wieder her. Er benötigt
keine funktionierende Netzwerkverbindung. Verbliebene fremde Tabellen werden
nicht verändert. Vorhandene Sessions allein gelten nicht als Erfolg.

SSH benutzt Schlüssel, `StrictHostKeyChecking=yes`, ProxyJump und den Benutzer
`debian`; Passwort- und Rootlogin werden in Gästen deaktiviert. Gast-Hostschlüssel
vor Ansible aus einem vertrauenswürdigen Incus-Konsolenkanal übernehmen. Eine
Ausgabe von `ssh-keyscan` allein bestätigt keine Identität. Änderungen von
SSH-Port oder Benutzer sind nicht automatisch unterstützt.

Der Host-Nginx fordert ein ACME-SAN-Zertifikat für zentrale Domainvariablen an.
DNS muss auf die vorgesehene IPv4 zeigen; vorhandene AAAA-Records müssen zuvor
mit der Hostkonfiguration abgeglichen werden. Zertifikatserneuerung lädt nur
nach erfolgreichem `nginx -t` neu. Development und Monitoring sind per CIDR
beschränkt; diese drei privaten Sites dürfen nicht aus der privaten Liste
entfernt werden. PostgreSQL, InfluxDB und Incus haben keine öffentliche Freigabe.

Für die interne PKI werden offline ein CA-Zertifikat und pro Knoten ein
Zertifikat samt verschlüsseltem Schlüssel bereitgestellt. Zertifikate brauchen
DNS-SAN für den Knotennamen und IP-SAN für die jeweilige private Adresse; beim
Host zusätzlich öffentliche Administrationsadresse und Bridgeadresse. Für
Icinga sind serverAuth/clientAuth nötig. CA-Privatschlüssel nie auf Host oder
Gäste kopieren. Das Repository enthält keine privaten Schlüssel.

Host-zu-Gast-Nginx verwendet HTTPS mit CA-/Namensprüfung. PostgreSQL-ACLs verlangen
`hostssl` und SCRAM; Clients benutzen `verify-full` und die CA. `PGSSLMODE` und
`PGSSLROOTCERT` im Backend-Service sichern auch Releases ab, welche das
`ssl_mode`-JSON-Feld nicht selbst auswerten. InfluxDB, Grafana und die Metrikwriter
nutzen intern HTTPS. Der Metrikzugriff bleibt IP-beschränkt; zusätzliche
Influx-Benutzerauthentifizierung ist ein dokumentierter offener Härtungspunkt.

Öffentliches DNS muss eine passende A-Adresse besitzen. Optionale AAAA-Adressen
müssen der zentral konfigurierten Host-IPv6 entsprechen; andere Zieladressen
stoppen ACME vor der ersten Zertifikatsanforderung.
