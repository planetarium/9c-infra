from datetime import datetime

import structlog

from app.config import config
from app.tools.planet import Apv, Planet
from app.constants import MAIN_SIGNERS

logger = structlog.get_logger(__name__)
from tempfile import TemporaryFile
from time import time
from typing import List, NamedTuple

import structlog
from ruamel.yaml import YAML

from app.client import GithubClient
from app.config import config

class IntegrationMetadata(NamedTuple):
    manifest_key: str
    dockerhub_org: str
    dockerhub_repo: str
    dockerhub_tag: str

logger = structlog.get_logger(__name__)

class ApvUpdater:
    def __init__(self) -> None:
        self.github_client = GithubClient(
            config.github_token, org="planetarium", repo="9c-infra"
        )

    def update(
        self,
        number: int,
        dir_name: str,
        file_name: str
    ):
        new_branch = f"update-{file_name}-apv-{int(time())}"
        file_path = f"{dir_name}/network/{file_name}.yaml"

        remote_values_file_contents, contents_response = self._init_github_ref(
            branch=new_branch,
            file_path=file_path,
        )

        check_correct_signer(dir_name, file_name)

        apv = generate_apv(Planet(config.key_address, config.key_passphrase), number)

        result_values_file = update_apv(
            remote_values_file_contents,
            apv,
        )

        pr_body = f"Update apv to {number}"
        self._create_pr(
            target_github_repo="9c-infra",
            base_commit_hash=contents_response["sha"],
            file_path=file_path,
            branch=new_branch,
            result_values=result_values_file,
            commit_msg=f"Update {file_path}",
            pr_body=pr_body,
        )
        logger.info("PR Created")

    def _init_github_ref(self, *, branch: str, file_path: str):
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

def update_apv(contents: str, apv: Apv):
    yaml = YAML()
    yaml.preserve_quotes = True
    doc = yaml.load(contents)

    doc["global"]["appProtocolVersion"] = apv.raw

    with TemporaryFile(mode="w+") as fp:
        yaml.dump(doc, fp)
        fp.seek(0)
        new_doc = fp.read()

    return new_doc

def check_correct_signer(dir_name:str, file_name: str):
    if "9c-main" in dir_name:
        assert config.key_address == MAIN_SIGNERS[file_name]

def generate_apv(planet: Planet, number: int) -> Apv:
    timestamp = datetime.utcnow().strftime("%Y-%m-%d")
    extra = {}
    extra["timestamp"] = timestamp

    apv = planet.apv_sign(
        number,
        **extra,
    )

    return apv
