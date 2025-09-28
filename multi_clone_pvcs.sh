#!/bin/bash

NAMESPACE="test"
STORAGE_CLASS="gcnv-flex"
NUM_DVS=2

for ((i=0; i < NUM_DVS; i++)); do
    PVC_NAME="pvc-$i"

    cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
  storageClassName: $STORAGE_CLASS
EOF

    echo "Waiting for PVC $PVC_NAME to be Bound"
    START=$(date +%s)
    oc wait pvc -n $NAMESPACE $PVC_NAME --for=jsonpath='{.status.phase}'=Bound --timeout=600s
    if [ $? -eq 0 ]; then
        echo "PVC $PVC_NAME is Bound: $(($(date +%s) - START)) sec"
    else
        echo "Timeout: PVC $PVC_NAME was not Bound within 600 sec"
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
  #annotations:
    #cdi.kubevirt.io/storage.usePopulator: "false"
spec:
  source:
    pvc:
      name: $PVC_NAME
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
        oc delete pvc -n $NAMESPACE $PVC_NAME
    else
        echo "Timeout: DV $CLONE_NAME was not Succeeded within 600 sec"
        oc delete dv -n $NAMESPACE $CLONE_NAME
        oc delete pvc -n $NAMESPACE $PVC_NAME
        exit 1
    fi

done
