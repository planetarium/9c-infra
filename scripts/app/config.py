import os
from typing import NamedTuple

from dotenv import load_dotenv

load_dotenv(".env")


class Config(NamedTuple):
    # Github token (commit, read)
    github_token: str

    @classmethod
    def init(self):
        github_token = os.environ["GITHUB_TOKEN"]

        if not github_token:
            raise ValueError(f"github_token is required")

        self.github_token = github_token

        return self


config = Config.init()
