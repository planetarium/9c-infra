# Tx test

`$ python3 scripts/chain_test.py ${block index} ${block count}`
메인넷에서 특정 인덱스의 블록에서부터 원하는 개수만큼, tx hash를 전부 들고와서 9c-perf-test network로 보냅니다.
따라서 nonce값이 맞도록 tx를 보내야하기 때문에 block index를 계속 기억하고 있어야 합니다.
