#!/bin/bash

NAMESPACE="test"
STORAGE_CLASS="gcnv-flex"
NUM_PVCS=10

for ((i=0; i < NUM_PVCS; i++)); do
    PVC_NAME="pvc-$i"
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
done

START=$(date +%s)
timeout 600s oc wait pvc -n $NAMESPACE --all --for=jsonpath='{.status.phase}'=Bound --timeout=600s
if [ $? -eq 0 ]; then
    echo "All PVCs are Bound: $(($(date +%s) - START)) sec"
else
    echo "Timeout: PVCs did not Bound within 600 seconds"
fi

for ((i=0; i < NUM_PVCS; i++)); do
    PVC_NAME="pvc-$i"
    SNAP_NAME="snap-$i"

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
done

START=$(date +%s)
timeout 600s oc wait volumesnapshot -n $NAMESPACE --all --for=jsonpath='{.status.readyToUse}'=true --timeout=600s
if [ $? -eq 0 ]; then
    echo "All VolumeSnapshots readyToUse: $(($(date +%s) - START)) sec"
else
    echo "Timeout: VolumeSnapshots did not become ready within 600 seconds"
fi

for ((i=0; i < NUM_PVCS; i++)); do
    PVC_NAME="pvc-$i"
    SNAP_NAME="snap-$i"
    oc delete pvc -n $NAMESPACE $PVC_NAME
    oc patch volumesnapshot -n $NAMESPACE $SNAP_NAME --type='merge' -p '{"metadata":{"finalizers":[]}}'
    oc delete volumesnapshot -n $NAMESPACE $SNAP_NAME --grace-period=0
done
