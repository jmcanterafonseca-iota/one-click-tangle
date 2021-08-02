#!/bin/bash

# Script to add a new Hornet Node to a Private Tangle
# private-hornet.sh [install|start|stop] <node_name> <coo_public_key>? <peer_address>?

set -e

# Common utility functions
source ../utils.sh

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
else 
  if [ -f ../coo-milestones-public-key.txt ]; then
    coo_public_key=$(cat ../coo-milestones-public-key.txt | tr -d "\n")
  else 
    echo "Please provide the coordinator's public key"
    exit 129
  fi
fi

if [ -n "$4" ]; then
  peer_address="$4"
else 
  if [ -f ../node1.identity.txt ]; then
    peer_address="/dns/node1/tcp/15600/p2p/$(getPeerID ../node1.identity.txt)"
  else
    echo "Please provide a peering address"
    exit 130
  fi
fi

echo $coo_public_key
echo $peer_address

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

  if [ -f ./config/peering.json ]; then
    sudo rm -f ./config/peering.json
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
  setupPeering

  # Coordinator set up
  setupCoordinator

  # And finally containers are started
  startContainer
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


###
### Sets the Coordinator address
###
setupCoordinator () {
  echo "$(pwd)"
  setCooPublicKey "$coo_public_key" "./config/config.json"
}

###
### Sets up the identities of the different nodes
###
setupIdentity () {
  generateP2PIdentity "$node_name" identity.txt

  setupIdentityPrivateKey identity.txt "./config/config.json"
}

# Sets up the identity of the peers
setupPeerIdentity () {
  local peerName1="$1"
  local peerAddr="$2"

  local peer_conf_file="$3"

  cat <<EOF > "$peer_conf_file"
  {
    "peers": [
       {
        "alias": "$peerName1",
        "multiAddress": "$peerAddr"
      }
    ]
  } 
EOF

}

### 
### Sets the peering configuration
### 
setupPeering () {
  local node1_peerID=$(getPeerID identity.txt)

  setupPeerIdentity "peer1" "$peer_address" ./config/peering.json
  if ! [[ "$OSTYPE" == "darwin"* ]]; then
    sudo chown 65532:65532 ./config/peering.json
  fi
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
