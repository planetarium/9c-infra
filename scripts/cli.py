from typing import List

import typer

from app.update_bridge_service import BridgeServiceUpdater
from app.test_internal_chain import InternalChainTester
from app.update_values import ValuesFileUpdater
from app.update_apv import ApvUpdater
from app.update_paev import PluggableActionEvaluatorUpdater

k8s_app = typer.Typer()

@k8s_app.command()
def update_values(
    file_path_at_github: str = typer.Argument(
        ..., help="e.g. 9c-main/chart/values.yaml"
    ),
    sources: List[str] = typer.Argument(
        ...,
        help="Please send formatted text like this: [service key in the YAML file|Docker Hub repository name|image tag to change] (e.g. 'remoteHeadless|planetariumhq/ninechronicles-headless|from planetarium/NineChronicles.Headless tag 1', 'dataProvider|planetariumhq/ninechronicles-dataprovider|from planetarium/NineChronicles.DataProvider branch main', 'worldBoss|planetariumhq/world-boss-service|from planetarium/world-boss-service commit 2dfn2988d8f7')",
    ),
):
    """
    Update images like headless, data-provider, seed...

    """

    ValuesFileUpdater().update(file_path_at_github, sources)

@k8s_app.command()
def update_bridge_service(
    dir_name: str = typer.Argument(
        ...,
        help="9c-internal or 9c-main",
    ),
    file_name: str = typer.Argument(
        ...,
        help="general, odin, heimdall, ...",
    ),
):
    """
    Run post deploy script
    """

    BridgeServiceUpdater().update(dir_name, file_name)  # type:ignore

@k8s_app.command()
def test_internal_chain(
    network: str = typer.Argument(
        ...,
        help="odin-internal, heimdall-internal, ...",
    ),
    offset: int = typer.Argument(
        ...,
    ),
    limit: int = typer.Argument(
        ...,
    ),
    delay_interval: int = typer.Argument(
        ...,
    ),
):
    """
    Run post deploy script
    """

    InternalChainTester().test(network, offset, limit, delay_interval)

@k8s_app.command()
def update_apv(
    number: int,
    dir_name: str = typer.Argument(
        ...,
        help="9c-internal or 9c-main",
    ),
    file_name: str = typer.Argument(
        ...,
        help="general, odin, heimdall, ...",
    ),
):
    """
    Run post deploy script
    """

    ApvUpdater().update(number, dir_name, file_name)

@k8s_app.command()
def update_paev(
    network_type: str = typer.Argument(
        ...,
    ),
    previous_version_block_index: int = typer.Argument(
        ...,
    ),
    previous_version_lib9c_commit: str = typer.Argument(
        ...,
    ),
):
    """
    Run post deploy script
    """

    PluggableActionEvaluatorUpdater().prep_update(network_type, previous_version_block_index, previous_version_lib9c_commit)

if __name__ == "__main__":
    k8s_app()
