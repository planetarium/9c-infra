import boto3
import requests
import json
from urllib.parse import urlparse

class PluggableActionEvaluatorUpdater:
    def __init__(self) -> None:
        pass

    def prep_update(
        self,
        network_type: str,
        new_start_value: int,
        new_lib9c_commit: str
    ):
        """
        This method downloads:
          1) appsettings.json (for arm64),
          2) appsettings-nodeinfra.json (for x64),
        modifies the final evaluator's end range to (new_start_value - 1),
        and appends a new evaluator from new_start_value to max long, using
        the plugin path from new_lib9c_commit + (arm64 or x64 suffix).
        """

        # Define base URL and suffixes
        base_url = "https://lib9c-plugin.s3.us-east-2.amazonaws.com/"
        arm64_suffix = "/linux-arm64.zip"
        x64_suffix = "/linux-x64.zip"

        # Define URLs based on network type
        paev_urls = [
            f"https://9c-cluster-config.s3.us-east-2.amazonaws.com/9c-main/{network_type}/appsettings.json",
            f"https://9c-cluster-config.s3.us-east-2.amazonaws.com/9c-main/{network_type}/appsettings-nodeinfra.json",
        ]

        # Iterate over each URL in the list
        for url in paev_urls:
            # Choose the suffix based on the presence of "nodeinfra"
            suffix = x64_suffix if "nodeinfra" in url else arm64_suffix

            # Construct the plugin URL from the new commit
            plugin_url = f"{base_url}{new_lib9c_commit}{suffix}"

            # Update the file, passing new_start_value
            self.update(url, new_start_value, plugin_url)

    def update(
        self,
        paev_url: str,
        new_start_value: int,
        new_plugin_url: str,
        bucket_name: str = "9c-cluster-config"
    ):
        """
        1. Download the appsettings.json from paev_url.
        2. Modify the last evaluator so that its end = new_start_value - 1.
        3. Append a new evaluator that starts at new_start_value and ends at a very large number.
        4. Upload updated JSON back to S3.
        """

        def url_exists(url: str) -> bool:
            try:
                resp = requests.head(url, allow_redirects=True)
                return resp.status_code == 200
            except requests.exceptions.RequestException as e:
                print(f"Error checking URL {url}: {e}")
                return False

        def extract_path_from_url(url: str) -> str:
            parsed = urlparse(url)
            return parsed.path.lstrip('/')

        # 1) Validate URLs
        if not url_exists(paev_url):
            raise Exception(f"URL not accessible: {paev_url}")
        if not url_exists(new_plugin_url):
            raise Exception(f"Plugin URL not accessible: {new_plugin_url}")

        # 2) Download the JSON
        resp = requests.get(paev_url)
        if resp.status_code != 200:
            raise Exception(f"Failed to download JSON from {paev_url}, status: {resp.status_code}")
        data = resp.json()

        # 3) Modify the last pair
        pairs = data.get('Headless', {}).get('ActionEvaluator', {}).get('pairs', [])
        if not pairs:
            raise Exception("No pairs found in ActionEvaluator configuration.")

        last_pair = pairs[-1]
        # The last evaluator ends just before new_start_value
        last_pair['range']['end'] = new_start_value - 1

        # 4) Append the new evaluator
        new_pair = {
            "range": {
                "start": new_start_value,
                "end": 9223372036854775807
            },
            "actionEvaluator": {
                "type": "PluggedActionEvaluator",
                "pluginPath": new_plugin_url
            }
        }
        pairs.append(new_pair)

        # 5) Upload the modified JSON back to S3
        s3_resource = boto3.resource('s3')
        file_content = json.dumps(data, indent=4)
        file_name = extract_path_from_url(paev_url)

        s3_resource.Object(bucket_name, file_name).put(
            Body=file_content,
            ContentType='application/json'
        )

        print(
            f"Successfully updated {paev_url}:\n"
            f" - Last evaluator end = {new_start_value - 1}\n"
            f" - New evaluator start = {new_start_value}, end = 9223372036854775807\n"
            f" - Plugin URL = {new_plugin_url}"
        )
