import boto3
import requests
import json
from urllib.parse import urlparse

class PAEVReverter:
    def revert_last_pair(
        self,
        paev_url: str,
        bucket_name: str = "9c-cluster-config"
    ):
        """
        1) Download the appsettings.json from paev_url.
        2) Remove the LAST pair from the pairs array.
        3) Update the (new) LAST pair's 'range.end' to 9223372036854775807.
        4) Upload updated JSON back to S3.
        """

        data = self.download_json(paev_url)

        pairs = data.get("Headless", {}).get("ActionEvaluator", {}).get("pairs", [])
        if not pairs:
            raise Exception("No pairs found in ActionEvaluator configuration.")

        # 1. Remove the last pair
        last_pair = pairs.pop()
        print(f"Removed pair: {last_pair}")

        # 2. If there is still at least one pair left, set its 'end' to a very large number
        if not pairs:
            # Edge case: If there was only one pair, we removed it, so now zero remain.
            # You can decide how to handle that scenario, or raise an exception.
            raise Exception("No pairs left after removing the last one. Cannot revert further.")
        
        # 3. Edit the new last pair's end value
        pairs[-1]["range"]["end"] = 9223372036854775807

        # 4. Upload updated JSON back to S3
        self.upload_json(paev_url, data, bucket_name)
        print(f"Successfully reverted the last pair in {paev_url}.")

    def download_json(self, url: str) -> dict:
        def url_exists(u: str) -> bool:
            try:
                resp = requests.head(u, allow_redirects=True)
                return resp.status_code == 200
            except requests.exceptions.RequestException:
                return False

        if not url_exists(url):
            raise Exception(f"Cannot access {url}.")

        resp = requests.get(url)
        if resp.status_code != 200:
            raise Exception(f"Failed to download JSON from {url}, status={resp.status_code}")

        return resp.json()

    def upload_json(self, url: str, data: dict, bucket_name: str):
        file_content = json.dumps(data, indent=4)
        file_name = urlparse(url).path.lstrip('/')

        s3 = boto3.resource('s3')
        s3.Object(bucket_name, file_name).put(
            Body=file_content,
            ContentType='application/json'
        )
        print(f"Reverted file uploaded back to {bucket_name}/{file_name}")
