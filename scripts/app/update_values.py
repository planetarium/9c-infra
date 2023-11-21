from tempfile import TemporaryFile
from time import time
from typing import List, NamedTuple

import structlog
from ruamel.yaml import YAML

from app.client import GithubClient
from app.config import config
from app.dockerhub.image import check_image_exists
from app.manager import APVHistoryManager
from app.utils.converter import infra_dir2network

class IntegrationMetadata(NamedTuple):
    manifest_key: str
    dockerhub_org: str
    dockerhub_repo: str
    dockerhub_tag: str

logger = structlog.get_logger(__name__)

class ValuesFileUpdater:
    def __init__(self) -> None:
        self.github_client = GithubClient(
            config.github_token, org="planetarium", repo="TEMP"
        )

    def update(
        self,
        file_path_at_github: str,
        sources: List[str],
    ):
        infra_dir = file_path_at_github.split("/")[0]
        new_branch = f"update-{infra_dir}-values-{int(time())}"

        remote_values_file_contents, contents_response = self._init_github_ref(
            branch=new_branch,
            file_path=file_path_at_github,
        )
        result_values_file = remote_values_file_contents

        for source in sources:
            metadata = extract_metadata(source)
            image_is_exists = check_image_exists(metadata.dockerhub_org, metadata.dockerhub_repo, metadata.dockerhub_tag)

            if not image_is_exists:
                raise

            logger.info("Docker image tag", tag=metadata.dockerhub_tag)

            result_values_file = update_image_tag(
                result_values_file,
                manifest_key=metadata.manifest_key,
                repo_to_change=f"{metadata.dockerhub_org}/{metadata.dockerhub_repo}",
                tag_to_change=metadata.dockerhub_tag,
            )

        # logger.debug("Result manifests contents", content=result_values_file)

        pr_body = f"Update {file_path_at_github}\n\n" + "\n".join(sources)
        self._create_pr(
            target_github_repo="9c-infra",
            base_commit_hash=contents_response["sha"],
            file_path=file_path_at_github,
            branch=new_branch,
            result_values=result_values_file,
            commit_msg=f"Update {file_path_at_github}",
            pr_body=pr_body,
        )
        logger.info("PR Created")

    def _init_github_ref(self, *, branch: str, file_path: str):
        self.github_client.org = "planetarium"
        self.github_client.repo = "9c-infra"
        head = self.github_client.get_ref(f"heads/main")
        logger.debug("Prev main branch ref", head_sha=head["object"]["sha"])

        self.github_client.create_ref(f"refs/heads/{branch}", head["object"]["sha"])
        logger.debug("Branch created", branch=branch)

        main_branch_file_contents, response = self.github_client.get_content(
            file_path, "main"
        )

        if main_branch_file_contents is None:
            raise

        return main_branch_file_contents, response

    def _create_pr(
        self,
        *,
        target_github_repo: str,
        base_commit_hash: str,
        file_path: str,
        branch: str,
        result_values: str,
        commit_msg: str,
        pr_body: str,
    ):
        self.github_client.repo = target_github_repo
        self.github_client.update_content(
            commit=base_commit_hash,
            path=file_path,
            branch=branch,
            content=result_values,
            message=commit_msg,
        )
        self.github_client.create_pull(
            title=f"Update values.yaml [{branch}]",
            head=branch,
            base="main",
            body=pr_body,
            draft=False,
        )

    def _get_latest_apv(self, infra_dir: str):
        config_manager = APVHistoryManager()
        network = infra_dir2network(infra_dir)

        apv_history = config_manager.get_apv_history(network)
        keys = apv_history.keys()
        sorted_keys = sorted(keys, reverse=True)

        return apv_history[sorted_keys[0]]["raw"]


def extract_metadata(image_source: str, delimiter: str = "|") -> IntegrationMetadata:
    # Example input: remoteHeadless|planetariumhq/ninechronicles-snapshot:git-e14cb15c049c5648752672571ea3864d50989de5

    manifest_key, dockerhub_info = image_source.split(delimiter)
    dockerhub_org, dockerhub_image_info = dockerhub_info.split("/")
    dockerhub_repo, dockerhub_tag = dockerhub_image_info.split(":")

    return IntegrationMetadata(manifest_key, dockerhub_org, dockerhub_repo, dockerhub_tag)

def update_image_tag(contents: str, *, manifest_key: str, repo_to_change: str, tag_to_change: str):
    def update_tag_recursively(data):
        if isinstance(data, dict):
            for key, value in data.items():
                if key == manifest_key:
                    if data[manifest_key].get("image"):
                        data[manifest_key]["image"]["repository"] = repo_to_change
                        data[manifest_key]["image"]["tag"] = tag_to_change
                    else:
                        d = dict(repository=repo_to_change, tag=tag_to_change)
                        data[manifest_key].insert(1, "image", d)
                else:
                    update_tag_recursively(value)
        elif isinstance(data, list):
            for item in data:
                update_tag_recursively(item)

    yaml = YAML()
    yaml.preserve_quotes = True  # type:ignore
    doc = yaml.load(contents)
    update_tag_recursively(doc)

    with TemporaryFile(mode="w+") as fp:
        yaml.dump(doc, fp)
        fp.seek(0)
        new_doc = fp.read()

    return new_doc


def update_apv(contents: str, apv: str):
    def update_apv_recursively(data):
        if isinstance(data, dict):
            for key, value in data.items():
                if key == "appProtocolVersion":
                    data["appProtocolVersion"] = apv
                else:
                    update_apv_recursively(value)
        elif isinstance(data, list):
            for item in data:
                update_apv_recursively(item)

    yaml = YAML()
    yaml.preserve_quotes = True  # type:ignore
    doc = yaml.load(contents)
    update_apv_recursively(doc)

    with TemporaryFile(mode="w+") as fp:
        yaml.dump(doc, fp)
        fp.seek(0)
        new_doc = fp.read()

    return new_doc
