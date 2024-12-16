import boto3  # type: ignore
import requests
import json

from app.client import GithubClient
from app.config import config
from urllib.parse import urlparse

class PluggableActionEvaluatorUpdater:
    def __init__(self) -> None:
        self.github_client = GithubClient(
            config.github_token, org="planetarium", repo="TEMP"
        )

    def prep_update(
        self,
        network_type: str,
        new_start_value: int,
        new_plugin_url: str
    ):
        """
        Prepares and updates the PAEV configuration for both appsettings.json 
        and appsettings-nodeinfra.json by computing cutoff_value automatically.
        """
        cutoff_value = new_start_value - 1  # always set cutoff_value to new_start_value - 1

        paev_urls = [
            f"https://9c-cluster-config.s3.us-east-2.amazonaws.com/9c-main/{network_type}/appsettings.json",
            f"https://9c-cluster-config.s3.us-east-2.amazonaws.com/9c-main/{network_type}/appsettings-nodeinfra.json",
        ]

        for url in paev_urls:
            self.update(url, cutoff_value, new_start_value, new_plugin_url)

    def update(
        self,
        paev_url: str,
        cutoff_value: int,
        new_start_value: int,
        new_plugin_url: str,
        bucket_name: str = "9c-cluster-config"
    ):
        """
        1. Download the appsettings.json from paev_url.
        2. Modify the last evaluator so that its end = cutoff_value.
        3. Append a new evaluator that starts at new_start_value and ends at a very large number.
        4. Upload updated JSON back to S3.
        """

        # Example logic adapted to your code:
        import boto3
        import requests
        import json
        from urllib.parse import urlparse

        def url_exists(url):
            try:
                resp = requests.head(url, allow_redirects=True)
                return resp.status_code == 200
            except requests.exceptions.RequestException as e:
                print(f"Error checking URL {url}: {e}")
                return False

        def extract_path_from_url(url):
            parsed = urlparse(url)
            return parsed.path.lstrip('/')

        if not url_exists(paev_url):
            raise Exception(f"URL not accessible: {paev_url}")
        if not url_exists(new_plugin_url):
            raise Exception(f"Plugin URL not accessible: {new_plugin_url}")

        resp = requests.get(paev_url)
        if resp.status_code != 200:
            raise Exception(f"Failed to download JSON from {paev_url}, status: {resp.status_code}")

        data = resp.json()

        pairs = data.get('Headless', {}).get('ActionEvaluator', {}).get('pairs', [])
        if not pairs:
            raise Exception("No pairs found in ActionEvaluator configuration.")

        # Modify the last pair
        last_pair = pairs[-1]
        last_pair['range']['end'] = cutoff_value

        # Append the new pair
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

        # Upload updated JSON back to S3
        s3_resource = boto3.resource('s3')
        file_content = json.dumps(data, indent=4)
        file_name = extract_path_from_url(paev_url)

        s3_resource.Object(bucket_name, file_name).put(
            Body=file_content,
            ContentType='application/json'
        )

        print(f"Successfully updated {paev_url} with new evaluator from {cutoff_value} to {new_start_value}.")

def url_exists(url):
    try:
        response = requests.head(url, allow_redirects=True)
        return response.status_code == 200
    except requests.exceptions.RequestException as e:
        print(f"Error checking URL {url}: {e}")
        return False

def extract_path_from_url(url):
    # Parse the URL to get the path part
    parsed_url = urlparse(url)
    # The `path` attribute contains the path component of the URL
    return parsed_url.path.lstrip('/')
