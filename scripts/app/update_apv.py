from datetime import datetime

import structlog

from app.config import config
from app.manager import APVHistoryManager
from app.tools.planet import Apv, Planet

logger = structlog.get_logger(__name__)


def append_apv(number: int, cluster_name: str, network: str):
    planet = Planet(config.key_address, config.key_passphrase)
    apv_manager = APVHistoryManager()

    apv = generate_apv(planet, number)
    logger.info("APV Created", cluster_name=cluster_name, version=apv.version, signer=apv.signer)

    apv_manager.append_apv(apv, network)

def generate_apv(planet: Planet, number: int) -> Apv:
    timestamp = datetime.utcnow().strftime("%Y-%m-%d")
    extra = {}
    extra["timestamp"] = timestamp

    apv = planet.apv_sign(
        number,
        **extra,
    )

    return apv
