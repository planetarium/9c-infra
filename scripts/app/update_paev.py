import boto3
import requests
import json

from app.client import GithubClient
from app.config import config

class PluggableActionEvaluatorUpdater:
    def __init__(self) -> None:
        self.github_client = GithubClient(
            config.github_token, org="planetarium", repo="TEMP"
        )

    def update(
        self,
        paev_url,
        end_value,
        lib9c_plugin_url):

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
                print("The specified range was not found in the pairs.")
                return
            
        else:
            print("The specified structure does not exist in the provided JSON data.")
            return

        # Upload the modified file back to S3
        s3_resource = boto3.resource('s3')
        bucket_name = '9c-cluster-config'  # Replace with your actual bucket name
        file_name = '9c-main/odin/appsettings-test.json'  # Replace with the S3 path for the upload

        # Convert the modified data back to JSON string
        file_content = json.dumps(data, indent=4)
        s3_resource.Object(bucket_name, file_name).put(Body=file_content, ContentType='application/json')

        print(data)
        print("File uploaded successfully.")
