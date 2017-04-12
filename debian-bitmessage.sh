#!/bin/sh

# DEBIAN-BITMESSAGE version 0.1

GITHUB_BRANCH="v0.6.1" # Last known stable

##### GENERIC CONFIGURATION SECTION FOR DEBIAN 7/8 #####

# Detect Debian release name from /etc/os-release
# Sets variable RELEASENAME, which is used by other modules

OS="$(eval $(grep PRETTY_NAME /etc/os-release) ; echo ${PRETTY_NAME})"
echo "Running on $OS"

RELEASENAME="unsupported"

case $OS in
	"Debian GNU/Linux 7 (wheezy)") 
		RELEASENAME="wheezy"
		;;
	"Debian GNU/Linux 8 (jessie)") 
		RELEASENAME="jessie"
		;;
esac

echo "Release name: $RELEASENAME"

if [ x${RELEASENAME} = "xunsupported" ]; then
	echo "ERROR: Debian GNU/Linux 7 or 8 required, not found."
	exit
fi

### === CHECK-INTERNET

# Check Internet connection

echo -n "Checking Internet connection: "
if wget -q -O - http://httpredir.debian.org/ >/dev/null ; then
	echo "Success"
else
	echo "FAILED."
	echo "ERROR: Internet connection required, not found."
	exit
fi

# globally disable any installation dialogs
export DEBIAN_FRONTEND=noninteractive


# update APT source definitions to use mirror redirector
#
mv -f /etc/apt/sources.list /etc/apt/sources.list.orig
cat >/etc/apt/sources.list <<EOF
# Sane defaults
deb http://httpredir.debian.org/debian ${RELEASENAME} main
deb-src http://httpredir.debian.org/debian ${RELEASENAME} main
deb http://httpredir.debian.org/debian ${RELEASENAME}-updates main
deb-src http://httpredir.debian.org/debian ${RELEASENAME}-updates main
deb http://security.debian.org/ ${RELEASENAME}/updates main
deb-src http://security.debian.org/ ${RELEASENAME}/updates main
EOF

# Update base packages first
#
apt-get update -q
apt-get upgrade -y -q

# Install essential packages
#
apt-get install -y -q curl openssh-server tor privoxy iptables-persistent psmisc

# TORIFY privoxy config
#
echo "forward-socks5 / 127.0.0.1:9050 ." >>/etc/privoxy/config
echo "listen-address 127.0.0.1:8118" >>/etc/privoxy/config

# Start TOR and PRIVOXY services
#
service tor stop
service tor start
service privoxy stop
service privoxy start

## Wait for Tor to sync so we can torify

TOR_READY=0
TOR_TIMER=0
TOR_TIMEOUT=120

echo -n "Waiting for Tor.."

while [ x${TOR_READY} = "x0" ] && [ ${TOR_TIMER} -lt ${TOR_TIMEOUT} ]; do
	sleep 5
	echo -n "."
	if tail -10 /var/log/tor/log |grep Bootstrapped.100 >/dev/null ; then
		TOR_READY=1
	fi
	TOR_TIMER=$(($TOR_TIMER+5))
done

## Torify this session
if [ x${TOR_READY} = "x1" ]; then
	echo "Success."
	export http_proxy=http://127.0.0.1:8118 https_proxy=http://127.0.0.1:8118
else
	echo "Timeout."
	echo "Tor is DISABLED for this session."
fi

# Iptables persistent rules block non-Tor traffic
# DO NOT ENABLE unless you have SSH as a hidden service
#
cat >/etc/iptables/rules.v4.toronly <<EOF
*filter
:INPUT ACCEPT [46:3400]
:FORWARD ACCEPT [0:0]
:OUTPUT DROP [0:0]
-A OUTPUT -m owner --uid-owner debian-tor -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -p udp -m udp --dport 123 -j ACCEPT
-A OUTPUT -d 192.168.0.0/16 -j ACCEPT
-A OUTPUT -d 172.16.0.0/12 -j ACCEPT
-A OUTPUT -d 10.0.0.0/8 -j ACCEPT
COMMIT
EOF

##### END OF GENERIC SECTION - SPECIFIC CONFIG BELOW THIS LINE #####

apt-get install -y git msgpack-python

#
# Configure hiddens service in TOR
#
cat >>/etc/tor/torrc <<_EOF_
### for Bitmessage client ###
SocksPort 9050
SocksPort 9055 IsolateSocksAuth KeepAliveIsolateSOCKSAuth
### Bitmessage server net=8444 api=8442 ###
HiddenServiceDir /var/lib/tor/bitmsg_net/
HiddenServicePort 8444 127.0.0.1:8444
HiddenServiceDir /var/lib/tor/bitmsg_api/
HiddenServicePort 8442 127.0.0.1:8442
_EOF_

# SIGHUP Tor to generate service keys
killall -HUP tor
sleep 10


BITMSG_NET=`cat /var/lib/tor/bitmsg_net/hostname`
BITMSG_API=`cat /var/lib/tor/bitmsg_api/hostname`

#
# Create privsep user
#
if ! grep bitmessage /etc/passwd >/dev/null; then
	adduser --quiet --system --disabled-password --no-create-home --home /opt/PyBitmessage --ingroup nogroup bitmessage
fi

#
# Install pyBitmessage in /opt
#
cd /opt
git clone -b ${GITHUB_BRANCH} https://github.com/Bitmessage/PyBitmessage

#
# Generate API password
#
APIPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1`

cat >/opt/PyBitmessage/src/keys.dat <<_EOF_
[bitmessagesettings]
settingsversion = 10
port = 8444
timeformat = %%c
blackwhitelist = black
startonlogon = False
minimizetotray = False
showtraynotifications = True
startintray = False
socksproxytype = SOCKS5
sockshostname = 127.0.0.1
socksport = 9055
socksauthentication = False
sockslisten = False
socksusername = 
sockspassword = 
keysencrypted = false
messagesencrypted = false
defaultnoncetrialsperbyte = 1000
defaultpayloadlengthextrabytes = 1000
minimizeonclose = false
maxacceptablenoncetrialsperbyte = 20000000000
maxacceptablepayloadlengthextrabytes = 20000000000
userlocale = system
useidenticons = False
replybelow = False
maxdownloadrate = 0
maxuploadrate = 0
ttl = 367200
stopresendingafterxdays = 
stopresendingafterxmonths = 
namecoinrpctype = namecoind
namecoinrpchost = localhost
namecoinrpcuser = 
namecoinrpcpassword = 
namecoinrpcport = 8336
sendoutgoingconnections = True
onionhostname = ${BITMSG_NET}
onionport = 8444
onionbindip = 127.0.0.1
smtpdeliver = 
trayonclose = False
willinglysendtomobile = False
apienabled = true
apiport = 8442
apiinterface = 0.0.0.0
apiusername = bmapiuser
apipassword = ${APIPASS}
daemon = true
_EOF_


cat >/opt/PyBitmessage/src/logging.dat <<_EOF_
[loggers]
keys = root,logfile

[logger_root]
level=DEBUG
handlers=logfile

[logger_logfile]
level=DEBUG
handlers=logfile
qualname=default
propagate=0

[handlers]
keys = logfile

[handler_logfile]
class = FileHandler
formatter = logfile
level = DEBUG
args=('/var/log/bitmessage/log', 'w')

[formatters]
keys = logfile

[formatter_logfile]
format=%(asctime)s %(threadName)s %(filename)s@%(lineno)d %(message)s
datefmt=%b %d %H:%M:%S
_EOF_


#
# Make logfile directory; set ownership
#
mkdir /var/log/bitmessage
chown -R bitmessage /opt/PyBitmessage /var/log/bitmessage

#
# Autostart
#
cp -f /etc/rc.local /etc/rc.local.orig

# remove exit line if any, will re-add it at the end
grep -vE '^exit 0' /etc/rc.local.orig >/etc/rc.local

cat >>/etc/rc.local <<_EOF_
su bitmessage --shell=/bin/bash -c "/opt/PyBitmessage/src/bitmessagemain.py"
exit 0
_EOF_

chmod 0755 /etc/rc.local

# Start it up
su bitmessage --shell=/bin/bash -c "/opt/PyBitmessage/src/bitmessagemain.py"


#
# Save settings to a file in root's home
#
echo "API Host: " ${BITMSG_API} >>/root/bitmessage.txt
echo "Password: " ${APIPASS} >>/root/bitmessage.txt

echo "COMPLETE"
cat /root/bitmessage.txt
