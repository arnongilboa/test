#!/bin/bash

NAMESPACE="test"
STORAGE_CLASS="gcnv-flex"
NUM_DVS=5

for ((i=0; i < NUM_DVS; i++)); do
    DV_NAME="imported-volume-$i"
    #DV_NAME="imported-volume"
    cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: $DV_NAME
  namespace: $NAMESPACE
spec:
  source:
      registry:
        url: docker://quay.io/kubevirt/cirros-container-disk-demo:devel
  storage:
    storageClassName: $STORAGE_CLASS
    resources:
      requests:
        storage: 512Mi
EOF

    echo "Waiting for DV $DV_NAME to be Succeeded"
    START=$(date +%s)
    oc wait dv -n $NAMESPACE $DV_NAME --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
    if [ $? -eq 0 ]; then
        echo "DV $DV_NAME is Succeeded: $(($(date +%s) - START)) sec"
    else
        echo "Timeout: DV $DV_NAME was not Succeeded within 600 sec"
        exit 1
    fi

    CLONE_NAME="clone-$i"
    echo "Creating clone DV: $CLONE_NAME"
    cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: $CLONE_NAME
  namespace: $NAMESPACE
spec:
  source:
    pvc:
      name: $DV_NAME
      namespace: $NAMESPACE
  storage:
    storageClassName: $STORAGE_CLASS
    resources:
      requests:
        storage: 512Mi
EOF

    echo "Waiting for DV $CLONE_NAME to be Succeeded"
    START=$(date +%s)
    oc wait dv -n $NAMESPACE $CLONE_NAME --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
    if [ $? -eq 0 ]; then
        echo "DV $CLONE_NAME is Succeeded: $(($(date +%s) - START)) sec"
        oc delete dv -n $NAMESPACE $CLONE_NAME
        oc delete dv -n $NAMESPACE $DV_NAME
    else
        echo "Timeout: DV $CLONE_NAME was not Succeeded within 600 sec"
        oc delete dv -n $NAMESPACE $CLONE_NAME
        oc delete dv -n $NAMESPACE $DV_NAME
        exit 1
    fi

done
