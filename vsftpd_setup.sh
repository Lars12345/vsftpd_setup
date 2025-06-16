#!/bin/bash

# Dieses Skript automatisiert die Installation und Konfiguration von vsftpd
# und erstellt einen neuen Benutzer mit den von dir angegebenen Anmeldedaten.
# Es ist für Debian/Ubuntu-basierte Proxmox LXC-Container gedacht.

# Funktion zum Anzeigen von Fehlern und Beenden des Skripts
error_exit() {
    echo "Fehler: $1" >&2
    exit 1
}

# Überprüfen, ob das Skript als Root ausgeführt wird
if [[ $EUID -ne 0 ]]; then
    error_exit "Dieses Skript muss als Root ausgeführt werden."
fi

echo "--- vsftpd Installations- und Konfigurationsskript ---"
echo " "

# Benutzernamen und Passwort abfragen
read -p "Bitte gib den gewünschten Benutzernamen für FTP ein (z.B. lars): " FTP_USER
if [ -z "$FTP_USER" ]; then
    error_exit "Benutzername darf nicht leer sein."
fi

read -s -p "Bitte gib das Passwort für den Benutzer '$FTP_USER' ein: " FTP_PASS
echo
if [ -z "$FTP_PASS" ]; then
    error_exit "Passwort darf nicht leer sein."
fi
read -s -p "Bitte bestätige das Passwort: " FTP_PASS_CONFIRM
echo
if [ "$FTP_PASS" != "$FTP_PASS_CONFIRM" ]; then
    error_exit "Passwörter stimmen nicht überein. Bitte starte das Skript erneut."
fi

echo " "
echo "Beginne mit der Installation und Konfiguration von vsftpd..."

# 1. System aktualisieren und vsftpd installieren
echo "Aktualisiere Systempakete und installiere vsftpd..."
apt update || error_exit "Fehler beim Aktualisieren der Paketlisten."
apt install vsftpd -y || error_exit "Fehler bei der Installation von vsftpd."

# 2. vsftpd konfigurieren
echo "Sichere die ursprüngliche vsftpd.conf Datei..."
cp /etc/vsftpd.conf /etc/vsftpd.conf.bak || error_exit "Fehler beim Sichern der vsftpd.conf."

echo "Erstelle eine neue vsftpd.conf Datei mit sicheren Standardeinstellungen..."
cat <<EOF > /etc/vsftpd.conf
# vsftpd Konfiguration erstellt durch Skript

# Erlaube lokale Benutzer zum Einloggen
local_enable=YES

# Erlaube Schreibzugriff für lokale Benutzer
write_enable=YES

# Deaktiviere anonyme Anmeldungen
anonymous_enable=NO

# Standardmäßiges FTP-Port-Listening
listen=YES

# Deaktiviere IPv6 Listening, um Konflikte zu vermeiden, falls nicht benötigt
listen_ipv6=NO

# Ermögliche das Sperren von Benutzern in ihrem Home-Verzeichnis (Chroot-Jail)
# Dies ist eine wichtige Sicherheitsmaßnahme!
chroot_local_user=YES

# Erlaube Schreibzugriff, wenn der Benutzer in einem chrooted Verzeichnis ist.
# Dies ist notwendig, wenn chroot_local_user=YES ist und Schreibzugriff erlaubt sein soll.
allow_writeable_chroot=YES

# Aktiviere explizites FTPS (FTP über TLS/SSL) für sichere Datenübertragung
# Du benötigst ein SSL-Zertifikat. Die Standard-Zertifikate reichen oft aus.
ssl_enable=YES
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1_2=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO

# Passive-Modus Konfiguration (wichtig für viele FTP-Clients)
# Diese Ports müssen in deiner Firewall geöffnet sein!
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40005

# Deaktiviere das Senden von Nachrichten bei der Anmeldung
banner_file=/etc/issue.net
ftpd_banner=Willkommen auf dem FTP-Server.
EOF

echo "vsftpd.conf wurde konfiguriert."

# 3. Benutzer erstellen und Passwort setzen
echo "Erstelle den Benutzer '$FTP_USER'..."
# -m erstellt das Home-Verzeichnis, -s /bin/false setzt die Shell auf false (kein Login über SSH)
useradd -m -s /bin/false "$FTP_USER" || error_exit "Fehler beim Erstellen des Benutzers '$FTP_USER'."

echo "$FTP_USER:$FTP_PASS" | chpasswd || error_exit "Fehler beim Setzen des Passworts für '$FTP_USER'."
echo "Benutzer '$FTP_USER' wurde erstellt und das Passwort gesetzt."

# 4. Home-Verzeichnis für Chroot vorbereiten
echo "Bereite das Home-Verzeichnis für den Chroot-Jail vor..."
mkdir -p "/home/$FTP_USER/ftp" || error_exit "Fehler beim Erstellen des FTP-Unterverzeichnisses."
chown "$FTP_USER":"$FTP_USER" "/home/$FTP_USER/ftp" || error_exit "Fehler beim Setzen der Besitzrechte für das FTP-Unterverzeichnis."
chmod 755 "/home/$FTP_USER" # Home-Verzeichnis darf nicht schreibbar für den Benutzer sein (vsftpd-Anforderung)
echo "Home-Verzeichnis und FTP-Unterverzeichnis vorbereitet."

# 5. vsftpd-Dienst neu starten
echo "Starte vsftpd neu..."
systemctl restart vsftpd || error_exit "Fehler beim Neustarten des vsftpd-Dienstes."
systemctl enable vsftpd # vsftpd beim Systemstart aktivieren
echo "vsftpd wurde erfolgreich neu gestartet und für den Systemstart aktiviert."

echo " "
echo "--- Installation und Konfiguration abgeschlossen! ---"
echo " "
echo "Dein FTP-Server ist nun bereit."
echo " "
echo "Um dich zu verbinden, verwende einen FTP-Client (z.B. FileZilla) mit folgenden Details:"
echo "  - Host: Die IP-Adresse deines Proxmox LXC-Containers"
echo "  - Benutzername: $FTP_USER"
echo "  - Passwort: Das von dir eingegebene Passwort"
echo "  - Protokoll: FTP (oder FTPS - Explizites FTP über TLS/SSL, empfohlen!)"
echo "  - Port: 21 (Standard)"
echo " "
echo "Wichtige Sicherheitshinweise:"
echo "1. Firewall: Stelle sicher, dass die Ports 20, 21 und der passive Portbereich (40000-40005) in deiner Container-Firewall oder auf deinem Proxmox-Host offen sind."
echo "2. Chroot-Jail: Der Benutzer '$FTP_USER' ist standardmäßig auf sein Unterverzeichnis '/home/$FTP_USER/ftp' beschränkt (Chroot-Jail). Dies ist die sicherste Konfiguration."
echo "   - Wenn du dem Benutzer Zugriff auf andere Verzeichnisse im Container geben möchtest, ist dies NICHT EMPFOHLEN und ein erhebliches Sicherheitsrisiko!"
echo "   - Du müsstest dafür 'chroot_local_user=YES' in /etc/vsftpd.conf auskommentieren oder auf 'NO' setzen."
echo "   - Danach müsstest du die Dateisystemberechtigungen für die gewünschten Ordner manuell anpassen, damit der Benutzer '$FTP_USER' darauf zugreifen kann."
echo "   - Ein Neustart von vsftpd wäre danach erforderlich: 'systemctl restart vsftpd'."
echo "Viel Erfolg!"
