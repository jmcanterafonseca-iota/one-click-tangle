#!/bin/bash

# Script to add a new Hornet Node to a Private Tangle
# private-hornet.sh [install|start|stop] <node_name> <coo_public_key>? <peer_address>?

set -e

help () {
  echo "usage: private-hornet.sh [install|start|stop] <node_name> <coo_public_key>? <peer_address>?"
}

if [ $#  -lt 2 ]; then
  echo "Illegal number of parameters"
  help
  exit 1
fi

command="$1"
node_name="$2"

if [ -n "$3" ]; then
  coo_public_key="$3"
fi

if [ -n "$4" ]; then
  peer_address="$4"
fi

clean () {
  # TODO: Differentiate between start, restart and remove
  stopContainers

  cd ./nodes/"$node_name"

  if [ -d ./db ]; then
    sudo rm -Rf ./db
  fi

  if [ -d ./p2pstore ]; then
    sudo rm -Rf ./p2pstore
  fi
}

# Sets up the necessary directories if they do not exist yet
volumeSetup () {
  if ! [ -d ./nodes ]; then
    mkdir ./nodes
  fi

  if ! [ -d ./nodes/"$node_name" ]; then
    mkdir ./nodes/"$node_name"
  fi

  cd  ./nodes/"$node_name"
  
  if ! [ -d ./config ]; then
    mkdir ./config
  fi

  if ! [ -d ./db ]; then
    mkdir ./db
  fi

  # P2P
  if ! [ -d ./p2pstore ]; then
    mkdir ./p2pstore
  fi

  ## Change permissions so that the Tangle data can be written (hornet user)
  ## TODO: Check why on MacOS this cause permission problems
  if ! [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Setting permissions for Hornet..."
    sudo chown -R 65532:65532 ./db 
    sudo chown -R 65532:65532 ./p2pstore
  fi 
}

bootstrapFiles () {
  cp ../../docker-compose.yml .
  sed -i 's/node/'$node_name'/g' docker-compose.yml
  cp ../../../config/config-node.json ./config/config.json
  cp ../../../config/profiles.json ./config/profiles.json
}

installNode () {
  # First of all volumes have to be set up
  volumeSetup

  # And only cleaning when we want to really remove all previous state
  # clean

  bootstrapFiles

  # P2P identity is generated
  setupIdentity

  # Peering of the nodes is configured
  # setupPeering

  # Coordinator set up
  # setupCoordinator

  # And finally containers are started
  # startContainer
}

startContainer () {
  # Run a regular node 
  docker-compose --log-level ERROR up -d "$node_name"
}


updateNode () {
  if ! [ -f ./db/LOG ]; then
    echo "Install your Node first with './private-hornet.sh install'"
    exit 129
  fi

  stopContainers

  # We ensure we are now going to run with the latest Hornet version
  image="gohornet\/hornet:latest"
  sed -i 's/image: .\+/image: '$image'/g' docker-compose.yml

  updateContainers

  startContainer
}

# Extracts the public key from a key pair
getPublicKey () {
  echo $(cat "$1" | tail -1 | cut -d ":" -f 2 | sed "s/ \+//g" | tr -d "\n" | tr -d "\r")
}

# Extracts the private key from a key pair
getPrivateKey () {
  echo $(cat "$1" | head -n 1 | cut -d ":" -f 2 | sed "s/ \+//g" | tr -d "\n" | tr -d "\r")
}

###
### Sets the Coordinator up by creating a key pair
###
setupCoordinator () {
  setCooPublicKey "$coo_public_key" config/config.json
}


setCooPublicKey () {
  local public_key="$1"
  sed -i 's/"key": ".*"/"key": "'$public_key'"/g' "$2"
}

generateP2PIdentity () {
  docker-compose run --rm "$node_name" hornet tool p2pidentity > identity.txt
}

setupIdentityPrivateKey () {
  local private_key=$(cat $1 | head -n 1 | cut -d ":" -f 2 | sed "s/ \+//g" | tr -d "\n" | tr -d "\r")
  # and then set it on the config.json file
  sed -i 's/"identityPrivateKey": ".*"/"identityPrivateKey": "'$private_key'"/g' $2
}

###
### Sets up the identities of the different nodes
###
setupIdentity () {
  generateP2PIdentity

  setupIdentityPrivateKey identity.txt config/config.json
}

# Sets up the identity of the peers
setupPeerIdentity () {
  local peerName1="$1"
  local peerID1="$2"

  local peerName2="$3"
  local peerID2="$4"

  local peer_conf_file="$5"

  cat <<EOF > "$peer_conf_file"
  {
    "peers": [
      {
        "alias": "$peerName1",
        "multiAddress": "/dns/$peerName1/tcp/15600/p2p/$peerID1"
      },
      {
        "alias": "$peerName2",
        "multiAddress": "/dns/$peerName2/tcp/15600/p2p/$peerID2"
      }
    ]
  } 
EOF

}

# Extracts the peerID from the identity file
getPeerID () {
  local identity_file="$1"
  echo $(cat $identity_file | sed '3q;d' | cut -d ":" -f 2 | sed "s/ \+//g" | tr -d "\n" | tr -d "\r")
}

### 
### Sets the peering configuration
### 
setupPeering () {
  local node1_peerID=$(getPeerID identity.txt)

  setupPeerIdentity "peer" "$peer_address" config/peering.json
}


stopContainers () {
  echo "Stopping containers..."
	docker-compose --log-level ERROR down -v --remove-orphans
}

startNode () {
  if ! [ -f ./db/LOG ]; then
    echo "Install your Node first with './private-hornet.sh install'"
    exit 128 
  fi

  startContainer
}

case "${command}" in
	"help")
    help
    ;;
	"install")
    installNode
    ;;
  "start")
    startNode
    ;;
  "update")
    updateNode
    ;;
  "stop")
		stopContainer
		;;
  *)
		echo "Command not Found."
		help
		exit 127;
		;;
esac
