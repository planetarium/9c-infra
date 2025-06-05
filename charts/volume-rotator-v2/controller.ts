import { AppsV1Api, CoreV1Api, KubeConfig } from "npm:@kubernetes/client-node";

const kubeConfig = new KubeConfig();
kubeConfig.loadFromDefault();

const kubeApi = kubeConfig.makeApiClient(CoreV1Api);
const kubeAppsApi = kubeConfig.makeApiClient(AppsV1Api);

const namespace = "heimdall";
const volumePrefix = "volume-rotator";
const replicaCount = 4;

const preloaderSts =
  (await kubeAppsApi.listNamespacedStatefulSet({ namespace }))
    .items.find((v) => v.metadata?.labels?.["volume-preloader"] === "true");

if (!preloaderSts?.metadata?.name) {
  throw new Error("Preloader StatefulSet not found");
}

const preloaderVolumeClaim = preloaderSts.spec?.template.spec?.volumes?.find(
  (v) => v.persistentVolumeClaim?.claimName,
)?.persistentVolumeClaim!;

if (!preloaderVolumeClaim) {
  throw new Error("Preloader Volume Claim not found");
}

await kubeAppsApi.replaceNamespacedStatefulSetScale({
  name: preloaderSts.metadata?.name,
  namespace,
  body: {
    spec: {
      replicas: 0,
    },
  },
});

const time = Date.now();

const pvcs = (await kubeApi.listNamespacedPersistentVolumeClaim({ namespace }))
  .items.filter((v) => v.metadata?.name?.startsWith(`${volumePrefix}-`));

const destroyedPvcs = await Promise.all(
  pvcs.filter((v) => v.status?.phase !== "Bound").map((v) =>
    kubeApi.deleteNamespacedPersistentVolumeClaim({
      name: v.metadata?.name!,
      namespace,
    })
  ),
);

const countToRecreate = replicaCount - pvcs.length + destroyedPvcs.length;

for (let i = 0; i < countToRecreate; i++) {
  await kubeApi.createNamespacedPersistentVolumeClaim({
    namespace,
    body: {
      metadata: {
        name: `${volumePrefix}-${time}-${i}`,
      },
      spec: {
        storageClassName: `${namespace}-longhorn`,
        dataSource: {
          kind: "PersistentVolumeClaim",
          name: preloaderVolumeClaim.claimName,
        },
      },
    },
  });
}
