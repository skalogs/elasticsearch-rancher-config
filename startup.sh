#!/usr/bin/env bash
set -e

RANCHER_BASEURL="rancher-metadata.rancher.internal/latest"


echo "installing custom elasticsearch config"
# elasticsearch.yml
curl -so /usr/share/elasticsearch/config/elasticsearch.yml ${RANCHER_BASEURL}/self/service/metadata/elasticsearch-config

echo "adding rack awareness to elasticsearch config"
# rack aware handling
rack_aware_status_code=$(curl -so /dev/null -w  "%{http_code}" ${RANCHER_BASEURL}/hosts/0/labels/rack)

if [ rack_aware_status_code -eq 200 ]; then
  rack_aware_uri="labels/rack"
elif [[ condition ]]; then
  echo "no host labels 'rack' defined, will use hostname instead"
  rack_aware_uri="hostname"
fi

nb_hosts=`curl --silent http://${RANCHER_BASEURL}/hosts | wc -l`
echo "Parsing rack values from $nb_hosts hosts ..."
rack_values=()
for (( i=0; i < ${nb_hosts}; i++ ))
do
   rack_values+=(`curl --silent "http://${RANCHER_BASEURL}/hosts/$i/${rack_aware_uri}"`)
done

UNIQUE_RACK_VALUES=`printf "%s\n" "${rack_values[@]}" | sort -u | tr '\n' ',' | head -c-1`
echo "Following rack values found on all hosts: $UNIQUE_RACK_VALUES"

rack=`curl --silent http://$RANCHER_HOST/latest/self/host/labels/rack`
echo 'Current rack : ' $rack


echo "
cluster.routing.allocation.awareness.force.rack.values: \"${UNIQUE_RACK_VALUES}\"
cluster.routing.allocation.awareness.attributes: rack
node.attr.rack: \"${rack}\"
" >> /usr/share/elasticsearch/config/elasticsearch.yml

# role mapping specific
echo "installing custom role mapping"

mkdir -p /usr/share/elasticsearch/config/x-pack/config/
curl -so /usr/share/elasticsearch/config/x-pack/role_mapping.yml ${RANCHER_BASEURL}/self/service/metadata/elasticsearch-role-config

echo "configuring xpack audit log"

echo "
logger.xpack_security_audit_logfile.name = org.elasticsearch.xpack.security.audit.logfile.LoggingAuditTrail
logger.xpack_security_audit_logfile.appenderRef.console.ref = console
logger.xpack_security_audit_logfile.level = info
" > /usr/share/elasticsearch/config/x-pack/log4j2.properties

# run elasticsearch
/usr/share/elasticsearch/bin/es-docker