# SAP HANA Pre-Freeze / Post-Thaw

## VeeamHub
Veeamhub projects are community driven projects, and are not created by Veeam R&D nor validated by Veeam Q&A. They are maintained by community members which might be or not be Veeam employees.

## Author
* Tom Sightler (tom.sightler@veeam.com)
* Stefan Zimmermann
* Wolfgang Scheer (@vNote42, wolfgang.scheer@veeam.com)

## Function
These scripts let Veeam Backup & Replication take **storage-snapshot based backups of SAP HANA on Linux** through application-aware pre-freeze / post-thaw processing. They are executed on the HANA host before and after the volume snapshot is taken.

* **`hana-pre-freeze.sh`** - discovers every SAP HANA instance on the host, creates an internal HANA data snapshot for each, and waits until the snapshot reaches the *prepared* state so the storage snapshot is application-consistent.
* **`hana-post-thaw.sh`** - closes the snapshot as *successful* so HANA records a valid snapshot backup and, optionally, purges old backup catalog entries and log backups from the filesystem.

### What's new in version 2.0
* Supports both the legacy **`sapstartsrv`** and the current **`systemctl`** format of `/usr/sap/sapservices` (auto-detected).
* Full support for **SAP HANA 2.0 multitenant database containers (MDC)** - snapshots are created on the **SYSTEMDB** with the `FOR FULL SYSTEM` clause.
* **Secure User Store (hdbuserstore) key-prefix authentication** documented.
* Correct detection of **multiple HANA instances** on a single host.
* Optional catalog/log purge now runs **per database** - the SYSTEMDB and every active tenant - since each database keeps its own backup catalog and log backups.

## Requirements
* SAP HANA 1.0 or 2.0 running on Linux.
* The SAP HANA client (`hdbsql`), which is installed with every HANA instance.
* A HANA database user with the **`BACKUP ADMIN`** and **`CATALOG READ`** system privileges. For MDC systems this user must exist (with these privileges) in the **SYSTEMDB** and, if the catalog/log purge is enabled, in **each tenant** to be purged.
* `bash` and standard GNU userland (`grep`, `sed`, `systemctl` on modern distributions).
* [Veeam Backup & Replication](https://www.veeam.com/vm-backup-recovery-replication-software.html) configured to run these scripts as the guest pre-freeze / post-thaw scripts for the HANA Linux machine.

## Files
| File                 | Description                                                                          |
| -------------------- | ------------------------------------------------------------------------------------ |
| `hana-pre-freeze.sh` | Pre-freeze script - creates the HANA data snapshot(s).                               |
| `hana-post-thaw.sh`  | Post-thaw script - closes the snapshot(s) and optionally purges catalog/log backups. |

## Configuration
Both scripts can be configured either by editing the variables at the top of each file, or through an external config file so the same unmodified scripts can be deployed to many hosts. By default the scripts read **`/etc/veeam/hana.conf`**; override the path with `-c`.

### Authentication
The scripts support two authentication methods. Leave `username` empty to use the Secure User Store.

#### Secure User Store (recommended)
Create one hdbuserstore key per instance using the configured **key prefix** (default `HDB`) combined with the two-digit instance number - e.g. prefix `HDB` + instance `00` = key **`HDB00`**.

> **Important for MDC (HANA 2.0):** the key must connect to the **SYSTEMDB**, because the snapshot is created there. Point the key at the SYSTEMDB SQL port, which is **`3<instance#>13`** (for example `30013` for instance `00`, `39013` for instance `90`), using the `@SYSTEMDB` suffix:

```bash
# Run as the OS user that will execute the scripts (Veeam normally runs them as root)
hdbuserstore set HDB00 hana01:30013@SYSTEMDB <HANA_USER> <HANA_PASSWORD>
```

With such a key the scripts connect to the SYSTEMDB and route to each tenant with `-d <tenant>` when purging. If the key points at a tenant instead, the snapshot step fails with `SYSTEMDB not connected`.

#### Username / password
Set `username` and `password` at the top of the script (or in the config file). The instance number is supplied automatically. Storing credentials in a file is less secure than the Secure User Store.

### Options
| Option | Scripts | Default | Description |
| --- | --- | --- | --- |
| `username` | both | *(empty)* | HANA user for username/password auth. Leave empty to use the Secure User Store. |
| `password` | both | *(empty)* | Password for `username`. |
| `keyprefix` | both | `HDB` | Prefix of the hdbuserstore key; the instance number is appended to form the full key (e.g. `HDB00`). |
| `purgelogs` | post-thaw | `false` | When `true`, purge old backup catalog entries and delete log backups from the filesystem. |
| `purgedays` | post-thaw | `3` | Keep backups/log backups newer than the newest successful snapshot older than this many days; older entries are purged. |

Example `/etc/veeam/hana.conf`:

```ini
# Leave username empty to use the Secure User Store (hdbuserstore)
username=
password=
keyprefix=HDB
# Post-thaw only
purgelogs=false
purgedays=3
```

## Usage
In normal operation **Veeam runs these scripts automatically** - configure them as the pre-freeze and post-thaw scripts for the SAP HANA Linux machine in the backup job's guest processing options. Veeam copies the scripts to the guest and runs them with root privileges.

To run or test them manually:

```bash
./hana-pre-freeze.sh  [-d] [-t] [-c /path/to/hana.conf]
./hana-post-thaw.sh   [-d] [-t] [-c /path/to/hana.conf]
```

| Flag        | Description                                                                       |
| ----------- | --------------------------------------------------------------------------------- |
| `-d`        | Debug mode - print detailed diagnostic output.                                    |
| `-t`        | Test mode - show the `hdbsql` commands that would run **without** executing them. |
| `-c <file>` | Use an alternate config file (default `/etc/veeam/hana.conf`).                    |

A dry run of the full cycle:

```bash
./hana-pre-freeze.sh -d -t
./hana-post-thaw.sh  -d -t
```

## Known Issues
* *None*

## 📗 Documentation
Configuration and usage instructions are contained in this README and in the header comments of each script.

## ✍ Contributions
We welcome contributions from the community! We encourage you to create [issues](https://github.com/VeeamHub/applications/issues/new/choose) for Bugs &amp; Feature Requests and submit Pull Requests. For more detailed information, refer to the [Contributing Guide](https://github.com/VeeamHub/applications/blob/master/CONTRIBUTING.md).

## 🤝🏾 License
* [MIT License](https://github.com/VeeamHub/applications/blob/master/LICENSE)

## 🤔 Questions
If you have any questions or something is unclear, please don't hesitate to [create an issue](https://github.com/VeeamHub/applications/issues/new/choose) and let us know!
