#!/bin/bash

PARALLEL_MAX=5
function start_job() {
  while [ $(ps -f | awk '{print $2}' | awk 'NR>1' | grep -w $$  | wc -l) -gt $PARALLEL_MAX ]; do
    sleep .1
  done
  echo "Running '$@' ..."
  eval "$@" &
}

kubectl api-resources -o name | while read resource; do
  if [ "$resource" = "events" ]; then
    continue;
  fi
  kubectl get $resource --all-namespaces -o go-template --template='{{range .items}}{{if .metadata.namespace}}{{.metadata.namespace}}{{else}}_{{end}} {{.metadata.name}}{{"\n"}}{{end}}' | while IFS=" " read -r namespace name; do
    IFS='.' read -r -a array <<< "$resource"
    n=${#array[*]}
    # echo "MyArray = ${array[@]}"
    dirname="${array[n-1]}"
    # echo "dirname = ${dirname}"
    for (( i = n-2; i >= 0; i-- ))
    do
        dirname="${dirname}.${array[i]}"
    done
    mkdir -p $dirname
    yamlfile="$dirname/$namespace.$name.yaml"
    if [ $namespace = "_" ]; then nsflag=""; else nsflag="-n $namespace"; fi
    start_job "kubectl get $resource $name $nsflag -o yaml > $yamlfile"
    # kubectl get $resource $name $nsflag -o yaml > $yamlfile
  done
done