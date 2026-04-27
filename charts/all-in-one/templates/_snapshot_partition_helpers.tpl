{{/*
Helpers for snapshot-partition.yaml volume layout.

Three modes are supported, determined by snapshot.partition.volumeMode:

  "single" (default, backward-compatible)
    - One PVC (snapshot.partition.volume.name) mounted at /data.
    - All of /data/headless, /data/snapshots, /data/snapshot_logs live on
      the same PVC. Matches the pre-existing 9c-main baremetal-1 setup.

  "hybrid"
    - Two PVCs: snapshot.partition.chainDataVolume.name (SSD-backed) for
      /data/headless, snapshot.partition.outputVolume.name (HDD-backed)
      for /data/snapshots and /data/snapshot_logs.
    - Intended for pt6 where Samsung 850 PRO SSD handles RocksDB random
      I/O while the Toshiba HDD absorbs large sequential zip writes.

  heimdall (9c-main only)
    - Special-case hostPath /output (existing behavior, unchanged).

Both the mount spec (`snapshot.partition.volumeMounts`) and the volume
spec (`snapshot.partition.volumes`) must be kept in sync across the two
helpers below.
*/}}

{{- define "snapshot.partition.volumeMounts" -}}
{{- if eq $.Values.snapshot.partition.volumeMode "hybrid" }}
- name: chain-data
  mountPath: /data/headless
- name: snapshot-output
  mountPath: /data/snapshots
- name: snapshot-output
  mountPath: /data/snapshot_logs
  subPath: snapshot_logs
{{- else if and (eq $.Values.provider "RKE2") (eq $.Release.Name "heimdall") }}
- name: snapshot-volume-partition
  mountPath: /output
{{- else }}
- name: snapshot-volume-partition
  mountPath: /data
{{- end }}
{{- end }}

{{- define "snapshot.partition.volumes" -}}
{{- if eq $.Values.snapshot.partition.volumeMode "hybrid" }}
- name: chain-data
  persistentVolumeClaim:
    claimName: {{ $.Values.snapshot.partition.chainDataVolume.name }}
- name: snapshot-output
  persistentVolumeClaim:
    claimName: {{ $.Values.snapshot.partition.outputVolume.name }}
{{- else if and (eq $.Values.provider "RKE2") (eq $.Release.Name "heimdall") }}
- name: snapshot-volume-partition
  hostPath:
    path: /output
    type: Directory
{{- else }}
- name: snapshot-volume-partition
  persistentVolumeClaim:
    claimName: {{ $.Values.snapshot.partition.volume.name }}
{{- end }}
{{- end }}
