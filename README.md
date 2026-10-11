# Uranus Ansible – Incus auf Debian 13

Ein Inventory, ein Provisionierungsweg: Incus 6.0 LTS aus Debian 13 verwaltet
`db01` als VM und fünf unprivilegierte Systemcontainer. Die Anwendungskonfiguration
verwendet die konsolidierten Debian-Rollen aus PR #1.

**Produktives Deployment ist gesperrt. Auf `94.130.236.38` wurden keine Änderungen vorgenommen.**

## Lokale Prüfung

```bash
python3 -m venv /tmp/uranus-qa
. /tmp/uranus-qa/bin/activate
pip install -r requirements-test.txt
ansible-galaxy collection install -r requirements.yml
make check
```

Die Tests benötigen lokal `cloud-init`, `nginx`, PostgreSQL samt PostGIS und
`python3-psycopg2`. Sie nutzen temporäre Dateien und einen PostgreSQL-Unix-Socket,
keine produktiven Ziele. Installation dieser Werkzeuge nur auf der eigenen
Testmaschine. CI prüft zusätzlich natives Debian 13.

## Workflow nach späterer ausdrücklicher Freigabe

Zuerst [Vorbereitung und Sperren](docs/deployment.md) lesen. Inventar, Domains,
SSH-Hostschlüssel, Vault, interne PKI, Release-Commits und Backups müssen geprüft
sein. Erst dann:

```bash
ansible-playbook playbooks/site.yml \
  -e @environments/hetzner/deployment.yml \
  -e @environments/hetzner/vault.yml --ask-vault-pass
```

`provision.yml`, `configure.yml` und `ingress.yml` sind getrennt ausführbare
Phasen desselben Workflows. Provisionierung ersetzt vorhandene Instanzen nicht.
Abweichungen führen zum Abbruch. Ressourcengrößen und Instanzart werden zentral
in `environments/hetzner/group_vars/all.yml` definiert.

Administrative SSH-Verbindungen benötigen keine feste Quell-IP. Host und Gäste
erfordern Schlüssel; Passwort-, Keyboard-Interactive- und Rootlogin werden
deaktiviert. Der Host bestätigt SSH-/Firewalländerungen erst nach einer neuen
Verbindung per Schlüssel, mit zeitgesteuerter und beim Boot wirksamer Recovery.
Private Development- und Monitoring-Websites besitzen eine separate Netzfreigabe.

## Dokumentation

- [Architektur und Rollen](docs/architecture.md)
- [Migrationsaudit](docs/migration.md)
- [Incus-Provisionierung](docs/incus-provisioning.md)
- [Netzwerk, Firewall und TLS](docs/networking.md)
- [Storage und Kapazität](docs/storage.md)
- [Sicherheitsbefunde und Selbstreview](docs/security.md)
- [Backup und Wiederherstellung](docs/backup-restore.md)
- [Deployment](docs/deployment.md)
- [Fehlersuche und Upgrades](docs/troubleshooting.md)
- [Testnachweise und Grenzen](docs/testing.md)

Die vorherige Architektur bleibt in der Git-Historie des Merge-Commits
`f766d941e79a4ec03001422390acd0b59da1f4f9` nachvollziehbar. Sie ist kein
unterstützter Deploymentpfad dieses Branches.
