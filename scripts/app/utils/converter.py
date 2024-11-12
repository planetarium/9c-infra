def infra_dir2network(dir: str):
    infra_dir2network_map = {
        "9c-main": "main",
        "9c-internal": "internal",
    }

    try:
        return infra_dir2network_map[dir]
    except KeyError:
        raise ValueError(f"Not found {dir} matched network")
