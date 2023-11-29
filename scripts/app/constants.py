import os

ROOT_DIR = os.path.abspath(os.path.dirname(__file__))
DATA_DIR = os.path.abspath(os.path.join(ROOT_DIR, "data"))
OUTPUT_DIR = os.path.abspath(os.path.join(ROOT_DIR, "output"))

RELEASE_BASE_URL = "https://release.nine-chronicles.com"
RELEASE_BUCKET = "9c-release.planetariumhq.com"

MAIN_ODIN_SIGNER="0xAB2da648b9154F2cCcAFBD85e0Bc3d51f97330Fc"
MAIN_HEIMDALL_SIGNER="0xeE394bb942fa7c2d807C170C7Db7F26cb3EA037F"
