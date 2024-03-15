import os
from typing import NamedTuple, Optional

from dotenv import load_dotenv

load_dotenv(".env")


class Config(NamedTuple):
    # Github token (commit, read)
    github_token: str
    # signer key passphrase
    key_passphrase: Optional[str] = None
    # signer key address
    key_address: Optional[str] = None
    # slack token
    key_address: Optional[str] = None

    @classmethod
    def init(self):
        github_token = os.environ["GITHUB_TOKEN"]

        if not github_token:
            raise ValueError(f"github_token is required")

        self.github_token = github_token

        for v in [
            "KEY_PASSPHRASE",
            "KEY_ADDRESS",
            "SLACK_TOKEN"
        ]:
            try:
                setattr(self, v.lower(), os.environ[v])
            except KeyError:
                pass

        return self


config = Config.init()
