import aiohttp
import asyncio
import sys
import os
import requests

from urllib.parse import urljoin
from app.client import GithubClient
from app.config import config
from typing import Literal

Network = Literal["odin"]
Offset = 0
Limit = 10

class InternalChainTester:
    def __init__(self) -> None:
        self.github_client = GithubClient(
            config.github_token, org="planetarium", repo="TEMP"
        )
    
    def test(
        self,
        network: Network,
        offset: Offset,
        limit: Limit
    ):
        # mainnet headless URL and initial setup
        mainnet_headless = "odin-full-state.nine-chronicles.com"
        target_validator = "k8s-9cnetwor-validato-708e2c954f-b762efe682772dcb.elb.us-east-2.amazonaws.com"
        if network == "heimdall-internal":
            mainnet_headless = "heimdall-full-state.nine-chronicles.com"
            target_validator = "k8s-heimdall-validato-5d9ca0e47e-85607ecfee8a803f.elb.us-east-2.amazonaws.com"
        mainnet_headless_url = urljoin(f"http://{mainnet_headless}", "graphql")
        target_validator_url = urljoin(f"http://{target_validator}", "graphql")

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

            asyncio.run(process_block(blocks))

            # Increment the offset for the next query
            offset += current_limit
