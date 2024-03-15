import aiohttp
import asyncio
import sys
import os
import requests

from urllib.parse import urljoin
from app.client import GithubClient
from app.config import config

Network = "odin-internal"
Offset = 0
Limit = 10
Delay = 0

class InternalChainTester:
    def __init__(self) -> None:
        self.github_client = GithubClient(
            config.github_token, org="planetarium", repo="TEMP"
        )
    
    def test(
        self,
        network: Network,
        offset: Offset,
        limit: Limit,
        delay: Delay
    ):
        # mainnet headless URL and initial setup
        mainnet_headless = "odin-full-state.nine-chronicles.com"
        internal_target_validator = "odin-internal-validator-5.nine-chronicles.com"
        sleep_time = delay
        if network == "heimdall-internal":
            mainnet_headless = "heimdall-full-state.nine-chronicles.com"
            internal_target_validator = "heimdall-internal-validator-1.nine-chronicles.com"
        mainnet_headless_url = urljoin(f"http://{mainnet_headless}", "graphql")
        target_validator_url = urljoin(f"http://{internal_target_validator}", "graphql")

        original_offset = offset
        tip_index = offset + limit
        print(tip_index)

        # Calculate initial limit (difference between tip index and offset)
        query_limit = 100  # Fixed limit for each query

        # Loop through the blocks in chunks of 100
        while offset < tip_index:
            # Adjusting the limit if the remaining blocks are less than 100
            current_limit = min(query_limit, tip_index - offset + 1)
            mainnet_headless_query = f"""
            query {{
              chainQuery {{
                blockQuery {{
                  blocks(offset: {offset}, limit: {current_limit}) {{
                    index
                    transactions {{
                      id
                      serializedPayload
                    }}
                  }}
                }}
              }}
            }}
            """
            response = requests.post(mainnet_headless_url, json={'query': mainnet_headless_query}, headers={'content-type': 'application/json'})
            data = response.json()
            blocks = data['data']['chainQuery']['blockQuery']['blocks']
            
            # Process the blocks here (e.g., print them out or handle them as needed)
            print(f"Fetched {len(blocks)} blocks starting from offset {offset}")

            # send signed txs to internal miner
            async def send_tx(session, transactions, index):
                print(f"Processing block #{index}...")
                for transaction in transactions:
                    signed_tx = transaction['serializedPayload']
                    query = f'mutation{{stageTxV2(payload: "{signed_tx}")}}'
                    async with session.post(target_validator_url, data=dict(query=query)) as response:
                        print(await response.json())

            async def process_block(blocks):
                async with aiohttp.ClientSession() as session:
                    for block in blocks:
                        transactions = block['transactions']
                        await send_tx(session, transactions, block['index'])
                        await asyncio.sleep(sleep_time)

            asyncio.run(process_block(blocks))

            # Increment the offset for the next query
            offset += current_limit

        # The URL you want to send the data to
        url = f'https://planetariumhq.slack.com/services/hooks/slackbot?token={config.slack_token}&channel=%239c-internal'
        data = f"[9C-INFRA] Finished testing `{network}` network from `#{original_offset}` to `#{tip_index}`."
        headers = {'Content-Type': 'text/plain'}
        response = requests.post(url, data=data, headers=headers)
