#!/usr/bin/env python3
import requests
import time
import sys
import argparse
import os
from datetime import datetime

# =====================
# GLOBAL CONFIG
# =====================
INSTANCE_ID = "your-instance-id-here"
IAM_TOKEN = "your-iam-token-here"
CHECK_INTERVAL = 60
CREDENTIALS_FILE = os.path.expanduser("~/.yc_autostart_credentials")


# =====================
# TERMINAL COLORS
# =====================
USE_COLOR = sys.stdout.isatty()

def c(code): return f"\033[{code}m" if USE_COLOR else ""

GREEN = c("32")
RED = c("31")
YELLOW = c("33")
BLUE = c("34")
GRAY = c("90")
BOLD = c("1")
RESET = c("0")

def ok(t): return f"{GREEN}{t}{RESET}"
def warn(t): return f"{YELLOW}{t}{RESET}"
def err(t): return f"{RED}{t}{RESET}"
def info(t): return f"{BLUE}{t}{RESET}"
def dim(t): return f"{GRAY}{t}{RESET}"

def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{dim(ts)} {msg}")


# =====================
# CREDENTIALS HANDLING
# =====================
def load_credentials():
    global INSTANCE_ID, IAM_TOKEN
    if os.path.exists(CREDENTIALS_FILE):
        try:
            with open(CREDENTIALS_FILE, "r") as f:
                for line in f:
                    if line.startswith("INSTANCE_ID="):
                        INSTANCE_ID = line.strip().split("=", 1)[1].strip().strip('"')
                    elif line.startswith("IAM_TOKEN="):
                        IAM_TOKEN = line.strip().split("=", 1)[1].strip().strip('"')
            log(ok(f"Credentials loaded from {CREDENTIALS_FILE}"))
        except Exception as e:
            log(err(f"Failed to load credentials: {e}"))
    else:
        log(warn(f"No credentials file found, using globals"))


def save_credentials(instance_id, iam_token):
    try:
        with open(CREDENTIALS_FILE, "w") as f:
            f.write(f'INSTANCE_ID="{instance_id}"\n')
            f.write(f'IAM_TOKEN="{iam_token}"\n')
        log(ok(f"Credentials saved to {CREDENTIALS_FILE}"))
    except Exception as e:
        log(err(f"Failed to save credentials: {e}"))


# =====================
# API
# =====================
def exchange_oauth_to_iam(oauth):
    r = requests.post(
        "https://iam.api.cloud.yandex.net/iam/v1/tokens",
        json={"yandexPassportOauthToken": oauth},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["iamToken"]


def get_clouds(iam):
    r = requests.get(
        "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds",
        headers={"Authorization": f"Bearer {iam}"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json().get("clouds", [])


def get_folders(iam, cloud_id):
    r = requests.get(
        "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders",
        headers={"Authorization": f"Bearer {iam}"},
        params={"cloudId": cloud_id},
        timeout=10,
    )
    r.raise_for_status()
    return r.json().get("folders", [])


def get_instances(iam, folder_id):
    r = requests.get(
        "https://compute.api.cloud.yandex.net/compute/v1/instances",
        headers={"Authorization": f"Bearer {iam}"},
        params={"folderId": folder_id},
        timeout=10,
    )
    r.raise_for_status()
    return r.json().get("instances", [])


# =====================
# SELECT HELPERS
# =====================
def select_items(items, label):
    if not items:
        raise RuntimeError(f"No {label} found")

    if len(items) == 1:
        return items  # один — берем сразу

    print()
    print(BOLD + f"Available {label}:" + RESET)
    for i, item in enumerate(items, 1):
        print(f" {i}) {item['name']}  {ok(item['id'])}")

    choice = input(
        f"\nSelect {label} number or press Enter for ALL [default: all]: "
    ).strip()

    if choice == "" or choice == "0":
        return items

    idx = int(choice) - 1
    return [items[idx]]


# =====================
# GETMYINFO
# =====================
def get_my_info():
    print()
    print(BOLD + "Yandex Cloud authorization required" + RESET)
    print(ok("https://yandex.cloud/ru/docs/iam/concepts/authorization/oauth-token"))
    print()

    oauth = input("Paste OAuth token: ").strip()
    if not oauth:
        print(err("OAuth token is empty"))
        sys.exit(1)

    log(info("Exchanging OAuth → IAM"))
    iam = exchange_oauth_to_iam(oauth)
    log(ok("IAM token received"))

    clouds = select_items(get_clouds(iam), "Clouds")
    all_instances = []

    for cloud in clouds:
        log(info(f"Processing Cloud {cloud['name']}"))
        folders = select_items(get_folders(iam, cloud["id"]), "Folders")

        for folder in folders:
            log(info(f"Fetching instances from folder {folder['name']}"))
            instances = get_instances(iam, folder["id"])
            for inst in instances:
                inst["_cloud"] = cloud["name"]
                inst["_folder"] = folder["name"]
            all_instances.extend(instances)

    # вывод Available instances
    print()
    print(BOLD + "Available instances:" + RESET)
    for inst in all_instances:
        pre = inst.get("schedulingPolicy", {}).get("preemptible", False)
        pflag = ok("YES") if pre else warn("NO")
        print(inst["name"])
        print(f"  ID:           {ok(inst['id'])}")
        print(f"  Preemptible:  {pflag}")
        print(f"  Cloud:        {inst['_cloud']}")
        print(f"  Folder:       {inst['_folder']}")
        print()

    # CONFIGURATION SUMMARY
    print("=" * 72)
    print(BOLD + "CONFIGURATION SUMMARY" + RESET)
    print("=" * 72)
    print(f"IAM_TOKEN = {ok(iam)}")
    print()
    print(BOLD + "Available instances:" + RESET)
    for inst in all_instances:
        print(inst["name"])
        print(f"  ID:           {ok(inst['id'])}")
        print()

    # предложение сохранить в файл
    save = input("Do you want to save IAM_TOKEN and INSTANCE_ID to file for future runs? [y/N]: ").strip().lower()
    if save == "y":
        # если несколько VM, выбрать одну
        if all_instances:
            if len(all_instances) == 1:
                selected_instance = all_instances[0]
            else:
                print("\nSelect INSTANCE_ID to save:")
                for i, inst in enumerate(all_instances, 1):
                    print(f" {i}) {inst['name']}  {ok(inst['id'])}")
                choice = input("Select number [default 1]: ").strip()
                idx = int(choice) - 1 if choice else 0
                selected_instance = all_instances[idx]
            save_credentials(selected_instance["id"], iam)


# =====================
# RUNTIME
# =====================
def start_instance(iid, iam):
    r = requests.post(
        f"https://compute.api.cloud.yandex.net/compute/v1/instances/{iid}:start",
        headers={"Authorization": f"Bearer {iam}"},
        timeout=10,
    )
    if r.status_code in (200, 202):
        log(ok("Start command sent"))
    else:
        log(err(f"Start failed: {r.status_code}"))


def check_instance_status(iid, iam):
    r = requests.get(
        f"https://compute.api.cloud.yandex.net/compute/v1/instances/{iid}",
        headers={"Authorization": f"Bearer {iam}"},
        timeout=10,
    )
    if r.status_code != 200:
        log(err(f"HTTP {r.status_code}"))
        return

    data = r.json()
    status = data["status"]
    name = data["name"]

    if status == "RUNNING":
        log(f"{name}: {ok(status)}")
    elif status == "STOPPED":
        log(f"{name}: {warn(status)} → starting")
        start_instance(iid, iam)
    else:
        log(f"{name}: {info(status)}")


# =====================
# MAIN
# =====================
def main():
    load_credentials()

    parser = argparse.ArgumentParser()
    parser.add_argument("--getmyinfo", action="store_true")
    args = parser.parse_args()

    if args.getmyinfo:
        get_my_info()
        return

    if INSTANCE_ID.startswith("your-") or IAM_TOKEN.startswith("your-"):
        print(err("INSTANCE_ID and IAM_TOKEN must be set"))
        sys.exit(1)

    log(f"Monitoring {ok(INSTANCE_ID)}")
    while True:
        check_instance_status(INSTANCE_ID, IAM_TOKEN)
        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
