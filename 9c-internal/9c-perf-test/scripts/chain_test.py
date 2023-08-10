import aiohttp
import asyncio
import sys
from urllib.parse import urljoin
from requests import post, get

# Instruction: run this script after setting up the 9c-internal cluster.
# mainnet explorer url
explorer = "d131807iozwu1d.cloudfront.net"

offset = sys.argv[1]
limit = sys.argv[2]

print(offset, limit)
# get signed txs from mainnet explorer
explorer_url = urljoin("http://{0}".format(explorer), "graphql")
explorer_query = """
query{
  chainQuery{
    blockQuery{
      blocks(offset: """ + offset + " limit: " + limit + """){
        index
        transactions{
          id
          serializedPayload
        }
      }
    }
  }
}
"""

explorer_res = post(explorer_url, json={'query': explorer_query}, headers={'content-type': 'application/json'})
explorer_result = explorer_res.json()
explorer_data = explorer_result['data']
blocks = explorer_data['chainQuery']['blockQuery']['blocks']

# send signed txs to internal miner
async def send_tx(session, transactions):
    for transaction in transactions:
        await asyncio.sleep(1)
        signed_tx = transaction['serializedPayload']
        query = f'mutation{{stageTxV2(payload: "{signed_tx}")}}'
        async with session.post("http://9c-perf-test-rpc-1.planetarium.dev/graphql", data=dict(query=query)) as response:
            print(await response.json())

async def process_block(blocks):
    async with aiohttp.ClientSession() as session:
        tasks = []
        for block in blocks:
            transactions = block['transactions']
            tasks.append(send_tx(session, transactions))
        await asyncio.gather(*tasks)

asyncio.run(process_block(blocks))

