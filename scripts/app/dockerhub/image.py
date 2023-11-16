import structlog

from app.client import DockerHubClient

logger = structlog.get_logger(__name__)


def check_image_exists(org: str, repo: str, tag_name: str):
    docker_client = DockerHubClient(namespace=org)

    try:
        result = docker_client.check_image_exists(repo, tag_name)
        return bool(result["id"])
    except KeyError:
        return False
