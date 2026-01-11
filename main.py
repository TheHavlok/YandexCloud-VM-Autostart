#!/usr/bin/env python3
import time
import sys
import argparse
import os
import json
import logging
import requests
from datetime import datetime

# =====================
# CONFIGURATION
# =====================
APP_NAME = "yandex-autostart"
CONFIG_DIR = os.path.expanduser(f"~/.config/{APP_NAME}")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"

# Setup Logging
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, datefmt="%Y-%m-%d %H:%M:%S")
logger = logging.getLogger(APP_NAME)

# =====================
# ANSII COLORS
# =====================
USE_COLOR = sys.stdout.isatty()

def c(code): return f"\033[{code}m" if USE_COLOR else ""
GREEN, RED, YELLOW, BLUE, GRAY, BOLD, RESET = c("32"), c("31"), c("33"), c("34"), c("90"), c("1"), c("0")

def ok(t): return f"{GREEN}{t}{RESET}"
def warn(t): return f"{YELLOW}{t}{RESET}"
def err(t): return f"{RED}{t}{RESET}"
def info(t): return f"{BLUE}{t}{RESET}"
def dim(t): return f"{GRAY}{t}{RESET}"

# =====================
# API CLIENT
# =====================
class YandexCloudClient:
    def __init__(self, oauth_token=None, iam_token=None):
        self.oauth_token = oauth_token
        self.iam_token = iam_token
        self.iam_expires_at = 0

    def refresh_iam_token(self):
        """Exchanges OAuth token for IAM token."""
        if not self.oauth_token:
            raise ValueError("OAuth token is required to refresh IAM token")
        
        logger.debug("Refreshing IAM token...")
        try:
            r = requests.post(
                "https://iam.api.cloud.yandex.net/iam/v1/tokens",
                json={"yandexPassportOauthToken": self.oauth_token},
                timeout=10
            )
            r.raise_for_status()
            data = r.json()
            self.iam_token = data["iamToken"]
            # IAM tokens live 12h, let's refresh slightly earlier to be safe
            # But here we just set it. The caller can handle timing or we can lazy-load.
            logger.info("IAM token refreshed successfully")
        except Exception as e:
            logger.error(f"Failed to refresh IAM token: {e}")
            raise

    def build_headers(self):
        if not self.iam_token:
            self.refresh_iam_token()
        return {"Authorization": f"Bearer {self.iam_token}"}

    def _request(self, method, url, **kwargs):
        """Wrapper to handle 401 Unauthorized by refreshing token."""
        headers = kwargs.pop("headers", {})
        headers.update(self.build_headers())
        
        try:
            r = requests.request(method, url, headers=headers, **kwargs)
            if r.status_code == 401 and self.oauth_token:
                logger.warning("Token expired (401), refreshing...")
                self.refresh_iam_token()
                headers["Authorization"] = f"Bearer {self.iam_token}"
                r = requests.request(method, url, headers=headers, **kwargs)
            return r
        except requests.RequestException as e:
            logger.error(f"Network error: {e}")
            raise

    def get_clouds(self):
        r = self._request("GET", "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds")
        r.raise_for_status()
        return r.json().get("clouds", [])

    def get_folders(self, cloud_id):
        r = self._request("GET", "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders", params={"cloudId": cloud_id})
        r.raise_for_status()
        return r.json().get("folders", [])

    def get_instances(self, folder_id):
        r = self._request("GET", "https://compute.api.cloud.yandex.net/compute/v1/instances", params={"folderId": folder_id})
        r.raise_for_status()
        return r.json().get("instances", [])

    def get_instance(self, instance_id):
        r = self._request("GET", f"https://compute.api.cloud.yandex.net/compute/v1/instances/{instance_id}")
        r.raise_for_status()
        return r.json()

    def start_instance(self, instance_id):
        r = self._request("POST", f"https://compute.api.cloud.yandex.net/compute/v1/instances/{instance_id}:start")
        if r.status_code in (200, 202):
            logger.info(f"Start command sent for {instance_id}")
            return True
        else:
            logger.error(f"Failed to start instance {instance_id}: Status {r.status_code} - {r.text}")
            return False

# =====================
# CONFIG MANAGER
# =====================
def load_config():
    if not os.path.exists(CONFIG_FILE):
        return None
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        return None

def save_config(config):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        logger.info(f"Config saved to {CONFIG_FILE}")
    except Exception as e:
        logger.error(f"Failed to save config: {e}")

# =====================
# INTERACTIVE SETUP
# =====================
def select_item(items, label):
    if not items:
        print(warn(f"No {label} found"))
        return None
    
    print(f"\n{BOLD}Available {label}:{RESET}")
    for i, item in enumerate(items, 1):
        print(f" {i}) {item['name']} {dim(item['id'])}")
    
    while True:
        choice = input(f"\nSelect {label} (1-{len(items)}) [1]: ").strip()
        if not choice:
            return items[0]
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(items):
                return items[idx]
        print(err("Invalid selection"))

def run_setup():
    print(f"\n{BOLD}=== Yandex Cloud Autostart Setup ==={RESET}")
    print(info("This wizard will help you configure the autostart service."))
    print(info(f"Configuration will be saved to: {CONFIG_FILE}"))
    print(info("You need an OAuth token from Yandex: https://yandex.cloud/ru/docs/iam/concepts/authorization/oauth-token\n"))
    
    oauth = input("Enter OAuth Token: ").strip()
    if not oauth:
        print(err("OAuth token is required!"))
        return

    client = YandexCloudClient(oauth_token=oauth)
    
    try:
        client.refresh_iam_token()
        print(ok("✓ Authentication successful"))
    except Exception:
        print(err("✗ Authentication failed. Check your token."))
        return

    print("Fetching Clouds...")
    clouds = client.get_clouds()
    cloud = select_item(clouds, "Cloud")
    if not cloud: return

    print(f"Fetching Folders in '{cloud['name']}'...")
    folders = client.get_folders(cloud['id'])
    folder = select_item(folders, "Folder")
    if not folder: return

    print(f"Fetching Instances in '{folder['name']}'...")
    instances = client.get_instances(folder['id'])
    instance = select_item(instances, "Instance")
    if not instance: return

    config = {
        "oauth_token": oauth,
        "instance_id": instance['id'],
        "instance_name": instance['name'],
        "check_interval": 60
    }
    
    save_config(config)
    print(ok("\n✓ Configuration setup complete!"))
    print(info(f"Now you can run the script normally or install the systemd service."))

# =====================
# MAIN LOOP
# =====================
def run_loop(config):
    oauth = config.get("oauth_token")
    instance_id = config.get("instance_id")
    interval = config.get("check_interval", 60)
    
    if not oauth or not instance_id:
        logger.error("Invalid config: missing oauth_token or instance_id")
        sys.exit(1)

    client = YandexCloudClient(oauth_token=oauth)
    
    logger.info(f"Starting monitor for Instance ID: {instance_id}")
    logger.info(f"Check Interval: {interval}s")

    while True:
        try:
            inst = client.get_instance(instance_id)
            name = inst.get("name", "Unknown")
            status = inst.get("status", "UNKNOWN")
            
            if status == "RUNNING":
                logger.info(f"{name}: {ok('RUNNING')}")
            elif status == "STOPPED":
                logger.warning(f"{name}: {warn('STOPPED')} -> Starting...")
                client.start_instance(instance_id)
            else:
                logger.info(f"{name}: {dim(status)}")
                
        except Exception as e:
            logger.error(f"Error checking instance: {e}")
        
        time.sleep(interval)

def main():
    parser = argparse.ArgumentParser(description="Yandex Cloud VM Autostart")
    parser.add_argument("--setup", action="store_true", help="Run interactive setup")
    args = parser.parse_args()

    if args.setup:
        run_setup()
        return

    config = load_config()
    if not config:
        print(warn("Configuration not found."))
        run_setup()
        config = load_config()
        if not config:
            return

    run_loop(config)

if __name__ == "__main__":
    main()
