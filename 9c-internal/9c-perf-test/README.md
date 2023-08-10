## 9c-perf-test

 - 9c-internal-v2 cluster 내부에 `9c-perf-test` namespace에 위치하는 네트워크입니다.
 - 메인넷과 같은 노드 사양으로 구성되어 있습니다.
 - internal argocd의 9c-perf-test application을 통해 관리합니다.
 - `values.yaml`의 `global.image.tag`필드에서 headless image를 교체할 수 있습니다.
   - 각각의 컴포넌트에서 별도 이미지를 사용하도록 설정할 수도 있습니다.

## Tx test

`$ python3 scripts/chain_test.py ${block index} ${block count}`

 - 메인넷에서 특정 인덱스의 블록에서부터 원하는 개수만큼, 블록에 포함된 tx hash를 전부 들고와서 9c-perf-test network로 보냅니다.
 - 따라서 nonce값이 맞도록 tx를 보내야하기 때문에 block index를 계속 기억하고 있어야 합니다.
 - `chain_test.py` 에서 tx를 보내는 방식을 수정할 수 있습니다.
