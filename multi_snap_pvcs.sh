#!/bin/bash

NAMESPACE="test"
STORAGE_CLASS="gcnv-flex"
NUM_DVS=4

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

    echo "Waiting for VolumeSnapshot $SNAP_NAME to be readyToUse"
    START=$(date +%s)
    oc wait volumesnapshot -n $NAMESPACE $SNAP_NAME --for=jsonpath='{.status.readyToUse}'=true --timeout=600s
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "VolumeSnapshots $SNAP_NAME readyToUse: $(($(date +%s) - START)) sec"
    else
        echo "Timeout: VolumeSnapshot $SNAP_NAME did not become ready within 600 seconds"
        oc delete volumesnapshot -n $NAMESPACE $SNAP_NAME
        oc delete pvc -n $NAMESPACE $PVC_NAME
        exit 1
    fi

    RESTORE_NAME="restore-$i"

    cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $RESTORE_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
  storageClassName: $STORAGE_CLASS
  dataSource:
    name: $SNAP_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

    echo "Waiting for PVC $RESTORE_NAME to be Bound"
    START=$(date +%s)
    oc wait pvc -n $NAMESPACE $RESTORE_NAME --for=jsonpath='{.status.phase}'=Bound --timeout=600s
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "PVC $RESTORE_NAME is Bound: $(($(date +%s) - START)) sec"
    else
        echo "Timeout: PVC $RESTORE_NAME was not Bound within 600 sec"
        exit 1
    fi

    #oc delete pvc -n $NAMESPACE $RESTORE_NAME
    #oc delete volumesnapshot -n $NAMESPACE $SNAP_NAME
    #oc delete pvc -n $NAMESPACE $PVC_NAME

    if [ "$rc" -ne 0 ]; then
        exit 1
    fi

done
