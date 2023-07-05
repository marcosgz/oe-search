# OpenElastic-Search (aka oe-search)

GitHub Action to start multi-version of ElasticSearch or OpenSearch

## Inputs

| Name                     | Required | Default  | Description                                                                         |
|--------------------------|----------|----------|-------------------------------------------------------------------------------------|
| `stack`                  | Yes      |          | Stack to install. It can be `elasticsearch:${version}` or `opensearch:${version}`.  |
| `nodes`                  | No       | 1        | Number of nodes in the cluster.                                                     |
| `port`                   | No       | 9200     | Port where you want to run service.                                                 |

### Supported versions

For ElasticSearch 5.x and up, you can use any version present in [docker.elastic.co](https://www.docker.elastic.co/):
* elasticsearch:8.2.0
* elasticsearch:7.13.2
* elasticsearch:6.8.16
* elasticsearch:5.6.16

ElasticSearch 2.x and 1.x are also supported using the following versions:
* elasticsearch:2.4.6
* elasticsearch:1.7.2

For the OpenSearch project, you can use any version present in [opensearchproject/opensearch docker hub](https://hub.docker.com/r/opensearchproject/opensearch):
* opensearch:1.3.3
* opensearch:2.0.1

# Usage

See [action.yml](action.yml)

Basic:

```yaml
steps:
  - name: Configure sysctl limits
    run: |
      sudo swapoff -a
      sudo sysctl -w vm.swappiness=1
      sudo sysctl -w fs.file-max=262144
      sudo sysctl -w vm.max_map_count=262144

  - uses: marcosgz/oe-search@v1.0
    with:
      stack: elasticsearch:8.2.0
```

# License

The scripts and documentation in this project are released under the [MIT](LICENSE)
