#!/bin/bash

set -euxo pipefail

if [[ -z $OE_SEARCH_STACK ]]; then
  echo -e "\033[31;1mERROR:\033[0m Required environment variable [OE_SEARCH_STACK] not set\033[0m"
  exit 1
fi

# split distribution from version separated by :
STACK_DISTRIBUTION="${OE_SEARCH_STACK%%:*}"
STACK_VERSION="${OE_SEARCH_STACK#*:}"
echo -e "\033[34;1mINFO:\033[0m Starting ${STACK_DISTRIBUTION} v${STACK_VERSION}\033[0m"

PORT="${PORT:-9200}"
COM_PORT="${COM_PORT:-9300}"
NODES="${NODES:-1}"
STACK_DISTRIBUTION="${STACK_DISTRIBUTION:-elasticsearch}" # elasticsearch or opensearch
SERVICE_HEAP_SIZE="${SERVICE_HEAP_SIZE:-512m}"
MAJOR_VERSION=`echo ${STACK_VERSION} | cut -c 1`

DOCKER_NAME_PREFIX="oe-search-${STACK_DISTRIBUTION}-v${MAJOR_VERSION}-"
DOCKER_NETWORK="oe-search"

WAIT_FOR_URL="https://github.com/eficode/wait-for/releases/download/v2.2.3/wait-for"
ROOT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")"; cd ../ ; pwd -P )
WAIT_FOR_PATH="${ROOT_PATH}/tmp/wait-for"

for (( node=1; node<=${NODES-1}; node++ )) do
  port_com=$((COM_PORT + $node - 1))
  UNICAST_HOSTS+="${DOCKER_NAME_PREFIX}${node}:${port_com},"
  HOSTS+="${DOCKER_NAME_PREFIX}${node},"
done
UNICAST_HOSTS=${UNICAST_HOSTS::-1}
HOSTS=${HOSTS::-1}

trace() {
	(
		set -x
		"$@"
	)
}

install_wait_for() {
  mkdir -p "${ROOT_PATH}/tmp"
	curl -fsSL -o "${WAIT_FOR_PATH}" "$WAIT_FOR_URL"
	chmod +x "${WAIT_FOR_PATH}"
	"${WAIT_FOR_PATH}" --version
}

start_docker_services() {
  local servicesHosts=()
  for (( node=1; node<=${NODES-1}; node++ )) do
    port=$((PORT + $node - 1))
    port_com=$((COM_PORT + $node - 1))
    servicesHosts+=("0.0.0.0:${port}")

    docker ps -a -q --filter ancestor="${DOCKER_IMAGE}:${STACK_VERSION}" | xargs -r docker rm -f || true

    echo -e "\033[34;1mINFO:\033[0m Starting ${DOCKER_NAME_PREFIX}${node} on port ${port} and ${port_com}"
    docker run \
      --rm \
      --env "node.name=${DOCKER_NAME_PREFIX}${node}" \
      --env "http.port=${port}" \
      "${environment[@]}" \
      --ulimit nofile=65536:65536 \
      --ulimit memlock=-1:-1 \
      --publish "${port}:${port}" \
      --publish "${port_com}:${port_com}" \
      --detach \
      --network="$DOCKER_NETWORK" \
      --name="${DOCKER_NAME_PREFIX}${node}" \
      ${DOCKER_IMAGE}:${STACK_VERSION}
  done
}

function check_service_healthy() {
  "${WAIT_FOR_PATH}" -t 10 "$1" -- echo "Service is up"
}

function cleanup_network {
  if [[ "$(docker network ls -q -f name=$1)" ]]; then
    echo -e "\033[34;1mINFO:\033[0m Removing network $1\033[0m"
    (docker network rm "$1") || true
  fi
}

function create_network {
  cleanup_network "$1"
  echo -e "\033[34;1mINFO:\033[0m Creating network $1\033[0m"
  docker network create "$1" || true
}


environment=($(cat <<-END
  --env cluster.name=docker-${STACK_DISTRIBUTION}
  --env cluster.routing.allocation.disk.threshold_enabled=false
  --env bootstrap.memory_lock=true
END
))

case "${STACK_DISTRIBUTION}-${MAJOR_VERSION}" in
  elasticsearch-1|elasticsearch-2)
    DOCKER_IMAGE=elasticsearch
    DOCKER_IMAGE="${DOCKER_IMAGE:-elasticsearch}"
    environment+=($(cat <<-END
        --env xpack.security.enabled=false
        --env discovery.zen.ping.unicast.hosts=${UNICAST_HOSTS}
END
    ))
    environment+=(--env "ES_JAVA_OPTS=-Xms${SERVICE_HEAP_SIZE} -Xmx${SERVICE_HEAP_SIZE}")
    ;;
  elasticsearch-5)
    DOCKER_IMAGE="${DOCKER_IMAGE:-docker.elastic.co/elasticsearch/elasticsearch}"
    environment+=($(cat <<-END
        --env xpack.security.enabled=false
        --env xpack.monitoring.collection.interval=-1
        --env discovery.zen.ping.unicast.hosts=${UNICAST_HOSTS}
END
    ))
    environment+=(--env "ES_JAVA_OPTS=-Xms${SERVICE_HEAP_SIZE} -Xmx${SERVICE_HEAP_SIZE} -da:org.elasticsearch.xpack.ccr.index.engine.FollowingEngineAssertions")
    ;;
  elasticsearch-6)
    DOCKER_IMAGE="${DOCKER_IMAGE:-docker.elastic.co/elasticsearch/elasticsearch}"
    environment+=($(cat <<-END
        --env xpack.security.enabled=false
        --env xpack.license.self_generated.type=basic
        --env discovery.zen.ping.unicast.hosts=${UNICAST_HOSTS}
        --env discovery.zen.minimum_master_nodes=${NODES}
END
    ))
    environment+=(--env "ES_JAVA_OPTS=-Xms${SERVICE_HEAP_SIZE} -Xmx${SERVICE_HEAP_SIZE}")
    ;;
  elasticsearch-7|elasticsearch-8)
    DOCKER_IMAGE="${DOCKER_IMAGE:-docker.elastic.co/elasticsearch/elasticsearch}"
    environment+=($(cat <<-END
      --env xpack.security.enabled=false
      --env xpack.license.self_generated.type=basic
      --env action.destructive_requires_name=false
      --env discovery.seed_hosts=${HOSTS}
END
    ))
    environment+=(--env "ES_JAVA_OPTS=-Xms${SERVICE_HEAP_SIZE} -Xmx${SERVICE_HEAP_SIZE}")
    if [ "x${NODES}" == "x1" ]; then
      environment+=(--env discovery.type=single-node)
    else
      environment+=(--env cluster.initial_master_nodes=${HOSTS})
    fi
    ;;
  opensearch-1|opensearch-2)
    DOCKER_IMAGE="${DOCKER_IMAGE:-opensearchproject/opensearch}"
    environment+=($(cat <<-END
      --env bootstrap.memory_lock=true
      --env plugins.security.disabled=true
      --env discovery.seed_hosts=${HOSTS}
END
    ))
    environment+=(--env "OPENSEARCH_JAVA_OPTS=-Xms${SERVICE_HEAP_SIZE} -Xmx${SERVICE_HEAP_SIZE}")
    if [ "x${NODES}" == "x1" ]; then
      environment+=(--env discovery.type=single-node)
    else
      environment+=(--env cluster.initial_master_nodes=${HOSTS})
    fi
    ;;
  *)
    echo -e "\033[31;1mERROR:\033[0m Unknown service type [${STACK_DISTRIBUTION}] and/or version [${STACK_VERSION}]"
    exit 1
    ;;
esac

trace create_network "$DOCKER_NETWORK"
trace install_wait_for
trace start_docker_services
trace check_service_healthy "localhost:${PORT}"
