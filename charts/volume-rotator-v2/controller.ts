import {
  AppsV1Api,
  CoreV1Api,
  KubeConfig,
  KubernetesObjectApi,
  type V1PersistentVolumeClaim,
} from "npm:@kubernetes/client-node";

const kubeConfig = new KubeConfig();
kubeConfig.loadFromDefault();

const kubeApi = kubeConfig.makeApiClient(CoreV1Api);
const kubeAppsApi = kubeConfig.makeApiClient(AppsV1Api);
const kubeObjectApi = kubeConfig.makeApiClient(KubernetesObjectApi);

const namespace = Deno.env.get("NAMESPACE") ?? "heimdall";
const volumePrefix = Deno.env.get("VOLUME_PREFIX") ?? "volume-rotator";
const replicaCount = Number(Deno.env.get("REPLICA_COUNT") ?? 1);

const preloaderSts =
  (await kubeAppsApi.listNamespacedStatefulSet({ namespace }))
    .items.find((v) => v.metadata?.labels?.["volume-preloader"] === "true");

if (!preloaderSts?.metadata?.name) {
  throw new Error("Preloader StatefulSet not found");
}

const preloaderVolumeClaim = await kubeApi
  .readNamespacedPersistentVolumeClaimStatus({
    name: preloaderSts.spec?.template.spec?.volumes?.find(
      (v) => v.persistentVolumeClaim?.claimName,
    )?.persistentVolumeClaim?.claimName!,
    namespace,
  });

if (!preloaderVolumeClaim) {
  throw new Error("Preloader Volume Claim not found");
}

await kubeAppsApi.patchNamespacedStatefulSet({
  name: preloaderSts.metadata.name,
  namespace,
  body: [{
    op: "replace",
    path: "/spec/replicas",
    value: 0,
  }],
});

const time = Date.now();

const pvcs = (await kubeApi.listNamespacedPersistentVolumeClaim({ namespace }))
  .items.filter((v) => v.metadata?.name?.startsWith(`${volumePrefix}-`));

const destroyedPvcs = await Promise.all(
  pvcs.flatMap((v) =>
    kubeApi.deleteNamespacedPersistentVolumeClaim({
      name: v.metadata?.name!,
      namespace,
    }).then(() => [v]).catch(() => [])
  ),
) as V1PersistentVolumeClaim[];

if (destroyedPvcs.length > 0) {
  console.log(`Removed ${destroyedPvcs.length} unbound PVCs`);
}

const countToRecreate = replicaCount - pvcs.length + destroyedPvcs.length;

const createdPvcs = await Promise.all(
  Array.from({ length: countToRecreate }, async (_, i) => {
    const name = `${volumePrefix}-${time}-${i}`;
    console.log(`Creating PVC ${name}`);
    await kubeApi.createNamespacedPersistentVolumeClaim({
      namespace,
      body: {
        metadata: {
          name,
        },
        spec: {
          storageClassName: `${namespace}-volume-rotator-longhorn`,
          dataSource: {
            kind: "PersistentVolumeClaim",
            name: preloaderVolumeClaim.metadata?.name!,
          },
          accessModes: ["ReadWriteOnce"],
          resources: {
            requests: {
              storage: (await kubeApi.readPersistentVolume({
                name: preloaderVolumeClaim.spec?.volumeName!,
              })).spec?.capacity?.storage!,
            },
          },
        },
      },
    });

    let volumeName: string | undefined;
    while (!volumeName) {
      const updatedPvc = await kubeApi
        .readNamespacedPersistentVolumeClaimStatus({
          name,
          namespace,
        });
      volumeName = updatedPvc.spec?.volumeName;
      if (!volumeName) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }

    while (true) {
      const volume = await kubeObjectApi.read({
        apiVersion: "longhorn.io/v1beta2",
        kind: "Volume",
        metadata: {
          name: volumeName,
          namespace: "longhorn-system",
        },
      }) as { status?: { cloneStatus?: { state?: string } } };

      const state = volume.status?.cloneStatus?.state;
      if (state === "completed") {
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
  }),
);

console.log(`${createdPvcs.length} PVCs have been created`);

await kubeAppsApi.patchNamespacedStatefulSet({
  name: preloaderSts.metadata.name,
  namespace,
  body: [{
    op: "replace",
    path: "/spec/replicas",
    value: 1,
  }],
});
