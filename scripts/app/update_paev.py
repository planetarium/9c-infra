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
        network_type,
        previous_version_block_index,
        previous_version_lib9c_commit):

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

            # Construct the plugin URL
            plugin_url = f"{base_url}{previous_version_lib9c_commit}{suffix}"

            # Call update function
            self.update(url, previous_version_block_index, plugin_url)

    def update(
        self,
        paev_url,
        end_value,
        lib9c_plugin_url):

        # Check if both URLs exist
        if url_exists(paev_url) and url_exists(lib9c_plugin_url):
            print("Both URLs are valid and accessible.")

            # Download the file
            url = paev_url
            response = requests.get(url)
            data = response.json()

            # Define new values for appending and updating
            start_value = 0
            new_start_value = end_value + 1

            # Navigate to the correct location
            if 'pairs' in data['Headless']['ActionEvaluator']:

                # Append the new value
                pairs = data['Headless']['ActionEvaluator']['pairs']
                insert_index = next((i for i, pair in enumerate(pairs) if pair['actionEvaluator'].get('type') == 'Default'), None)
                start_value = pairs[insert_index - 1]['range']['end'] + 1

                value_to_append = {
                    "range": {
                        "start": start_value,
                        "end": end_value
                    },
                    "actionEvaluator": {
                        "type": "PluggedActionEvaluator",
                        "pluginPath": lib9c_plugin_url
                    }
                }

                if insert_index is not None:
                    pairs[insert_index]['range']['start'] = new_start_value
                    pairs.insert(insert_index, value_to_append)
                else:
                    raise Exception("The specified range was not found in the pairs.")

            else:
                raise Exception("The specified structure does not exist in the provided JSON data.")

            # Upload the modified file back to S3
            s3_resource = boto3.resource('s3')
            bucket_name = '9c-cluster-config'  # Replace with your actual bucket name
            file_name = extract_path_from_url(paev_url)  # Replace with the S3 path for the upload

            # Convert the modified data back to JSON string
            file_content = json.dumps(data, indent=4)
            s3_resource.Object(bucket_name, file_name).put(Body=file_content, ContentType='application/json')

            print(data)
            print(f"File uploaded successfully to {paev_url}.")
        else:
            raise Exception("One or both URLs are not accessible. Please check the URLs and try again.")

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
