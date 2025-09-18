#!/bin/bash

NAMESPACE="test"
STORAGE_CLASS="gcnv-flex"
NUM_PVCS=10

cleanup() {
    echo -e "\nInterrupted! Cleaning up background jobs..."
    jobs -p | xargs -r kill 2>/dev/null
    echo "Background jobs terminated."
    exit 1
}

trap cleanup INT TERM

set +m

for ((i=0; i < NUM_PVCS; i++)); do
    PVC_NAME="pvc-$i"
    SNAP_NAME="snap-$i"
    {
        echo "Creating PVC: $PVC_NAME"
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
            echo "Timeout: PVC $PVC_NAME did not Bound within 600 sec"
            oc delete pvc -n $NAMESPACE $PVC_NAME
            exit 1
        fi

        echo "Creating VolumeSnapshot: $SNAP_NAME"
        cat <<EOF | oc apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAP_NAME
  namespace: $NAMESPACE
spec:
  source:
    persistentVolumeClaimName: $PVC_NAME
  volumeSnapshotClassName: gcnv-csi-snapclass
EOF
        echo "Waiting for VolumeSnapshot $SNAP_NAME readyToUse"
        START=$(date +%s)
        oc wait volumesnapshot -n $NAMESPACE $SNAP_NAME --for=jsonpath='{.status.readyToUse}'=true --timeout=600s
        if [ $? -eq 0 ]; then
            echo "VolumeSnapshot $SNAP_NAME readyToUse: $(($(date +%s) - START)) sec"
        else
            echo "Timeout: VolumeSnapshot $SNAP_NAME did not become ready within 600 seconds"
        fi

        oc delete pvc -n $NAMESPACE $PVC_NAME
        oc patch volumesnapshot -n $NAMESPACE $SNAP_NAME --type='merge' -p '{"metadata":{"finalizers":[]}}'
        oc delete volumesnapshot -n $NAMESPACE $SNAP_NAME --grace-period=0
    } &
done
 
wait


