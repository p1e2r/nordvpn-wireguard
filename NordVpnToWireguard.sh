#!/bin/bash

COUNTRY=""
CITY=""
SERVER=""
VERSION="1.0.0"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as sudo."
  echo "Run: sudo $0 [options]"
  exit 1
fi

REQUIRED_PKGS=()

command -v wg >/dev/null 2>&1 || REQUIRED_PKGS+=("wireguard")
command -v curl >/dev/null 2>&1 || REQUIRED_PKGS+=("curl")
command -v jq >/dev/null 2>&1 || REQUIRED_PKGS+=("jq")
command -v ifconfig >/dev/null 2>&1 || REQUIRED_PKGS+=("net-tools")
command -v getent >/dev/null 2>&1 || REQUIRED_PKGS+=("libc-bin")

if [ ${#REQUIRED_PKGS[@]} -ne 0 ]; then
  apt update
  apt install -y "${REQUIRED_PKGS[@]}"
fi

nordvpn set technology nordlynx || exit 1

while [ "$1" != "" ]; do
  case $1 in
    -v | --version)
      echo "NordVPN → WireGuard (Gluetun) v$VERSION"
      exit
      ;;
    -c | --country)
      shift
      [ -n "$1" ] && COUNTRY="$1"
      ;;
    -s | --city)
      shift
      [ -n "$1" ] && CITY="$1"
      ;;
    -server)
      shift
      [ -n "$1" ] && SERVER="$1"
      ;;
    -h | --help)
      echo "Usage: sudo $0 [OPTIONS]"
      echo "  -c | --country  Country name"
      echo "  -s | --city     City name"
      echo "  -server         Specific server"
      exit
      ;;
    *)
      exit 1
      ;;
  esac
  shift
done

if [[ -n "$SERVER" ]]; then
  nordvpn c "$SERVER"
elif [[ -z "$COUNTRY" && -z "$CITY" ]]; then
  nordvpn c
elif [[ -n "$COUNTRY" && -z "$CITY" ]]; then
  nordvpn c "$COUNTRY"
elif [[ -z "$COUNTRY" && -n "$CITY" ]]; then
  nordvpn c "$CITY"
else
  nordvpn c "$COUNTRY" "$CITY"
fi

if [ $? -ne 0 ]; then
  exit 1
fi

echo "[Interface]" > wg0.conf

privateKey=$(wg show nordlynx private-key)
echo "PrivateKey = $privateKey" >> wg0.conf

localAddress=$(ifconfig nordlynx | grep inet | awk '{ print $2 }')
echo "Address = $localAddress/32" >> wg0.conf

echo "DNS = 103.86.96.100, 103.86.99.100" >> wg0.conf
echo "" >> wg0.conf

curl -s "https://api.nordvpn.com/v1/servers/recommendations?&filters[servers_technologies][identifier]=wireguard_udp&limit=1" \
| jq -r '.[]|.hostname, (.technologies|.[].metadata|.[].value)' > peer.tmp

endpointHost=$(head -n 1 peer.tmp)
publicKey=$(tail -n 1 peer.tmp)
rm peer.tmp

nordvpn d >/dev/null 2>&1

endpointIP=$(getent ahostsv4 "$endpointHost" | awk '{ print $1 }' | head -n 1)

if [ -z "$endpointIP" ]; then
  exit 1
fi

echo "[Peer]" >> wg0.conf
echo "PublicKey = $publicKey" >> wg0.conf
echo "AllowedIPs = 0.0.0.0/0" >> wg0.conf
echo "Endpoint = $endpointIP:51820" >> wg0.conf
echo "PersistentKeepalive = 25" >> wg0.conf

exit 0
