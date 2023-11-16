from typing import Dict

from app.types import Network

def infra_dir2network(dir: str) -> Network:
    infra_dir2network_map: Dict[str, Network] = {
        "9c-main": "main",
        "9c-internal": "internal",
    }

    try:
        return infra_dir2network_map[dir]
    except KeyError:
        raise ValueError(f"Not found {dir} matched network")
