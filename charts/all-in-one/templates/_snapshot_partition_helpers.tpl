{{/*
Helpers for snapshot-partition.yaml volume layout.

Three modes are supported, determined by snapshot.partition.volumeMode:

  "single" (default, backward-compatible)
    - One PVC (snapshot.partition.volume.name) mounted at /data.
    - All of /data/headless, /data/snapshots, /data/snapshot_logs live on
      the same PVC. Matches the pre-existing 9c-main baremetal-1 setup.

  "hybrid"
    - chainDataVolume (SSD-backed) for /data/headless, outputVolume
      (HDD-backed) for /data/snapshots and /data/snapshot_logs.
    - chainDataVolume accepts EITHER `.name` (a pre-created PVC) OR
      `.hostPath` (a host directory). hostPath is used on pt6 where the
      full odin store does not fit on the SSD: everything except the bulk
      `tx` column family lives on the SSD host dir, and `tx` (268G) is
      submounted from the HDD via the optional `txVolume.hostPath` at
      /data/headless/tx. This keeps the random-I/O-heavy `states` CF on
      SSD (create-snapshot's CopyStates is otherwise unusably slow on HDD)
      while the bulk tx stays on the cheap HDD.
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
{{- if $.Values.snapshot.partition.txVolume }}
- name: tx-data
  mountPath: /data/headless/tx
{{- end }}
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
  {{- if $.Values.snapshot.partition.chainDataVolume.hostPath }}
  hostPath:
    path: {{ $.Values.snapshot.partition.chainDataVolume.hostPath }}
    type: Directory
  {{- else }}
  persistentVolumeClaim:
    claimName: {{ $.Values.snapshot.partition.chainDataVolume.name }}
  {{- end }}
{{- if $.Values.snapshot.partition.txVolume }}
- name: tx-data
  hostPath:
    path: {{ $.Values.snapshot.partition.txVolume.hostPath }}
    type: Directory
{{- end }}
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
