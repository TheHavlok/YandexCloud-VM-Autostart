#!/usr/bin/env python3
import requests
import time
import sys
from datetime import datetime

# Конфигурация
INSTANCE_ID="your-instance-id-here"
IAM_TOKEN="your-iam-token-here"
CHECK_INTERVAL = 60  # секунды

def start_instance(instance_id, iam_token):
    """Запускает остановленный инстанс"""
    url = f"https://compute.api.cloud.yandex.net/compute/v1/instances/{instance_id}:start"
    
    headers = {
        "Authorization": f"Bearer {iam_token}",
        "Content-Type": "application/json"
    }
    
    try:
        response = requests.post(url, headers=headers, timeout=10)
        
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        if response.status_code in [200, 202]:
            print(f"[{timestamp}] ✓ Start command sent successfully")
            data = response.json()
            operation_id = data.get("id", "N/A")
            print(f"[{timestamp}] Operation ID: {operation_id}")
            return True
        else:
            print(f"[{timestamp}] ✗ Failed to start instance: HTTP {response.status_code}")
            print(f"[{timestamp}] Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] Start request failed: {e}")
        return False

def check_instance_status(instance_id, iam_token):
    """Проверяет статус инстанса в Yandex Cloud"""
    url = f"https://compute.api.cloud.yandex.net/compute/v1/instances/{instance_id}"
    
    headers = {
        "Authorization": f"Bearer {iam_token}"
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        if response.status_code == 200:
            data = response.json()
            status = data.get("status", "UNKNOWN")
            name = data.get("name", "N/A")
            
            print(f"[{timestamp}] Instance: {name} (ID: {instance_id})")
            print(f"[{timestamp}] Status: {status}")
            
            if status == "RUNNING":
                print(f"[{timestamp}] ✓ Instance is RUNNING")
            elif status == "STOPPED":
                print(f"[{timestamp}] ⚠ Instance is STOPPED - attempting to start...")
                start_instance(instance_id, iam_token)
            else:
                print(f"[{timestamp}] ⏳ Instance status: {status}")
            
            print("-" * 60)
            
        else:
            print(f"[{timestamp}] Error: HTTP {response.status_code}")
            print(f"[{timestamp}] Response: {response.text}")
            print("-" * 60)
            
    except requests.exceptions.RequestException as e:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] Request failed: {e}")
        print("-" * 60)

def main():
    if INSTANCE_ID == "your-instance-id-here" or IAM_TOKEN == "your-iam-token-here":
        print("Error: Please set INSTANCE_ID and IAM_TOKEN in the script")
        sys.exit(1)
    
    print(f"Starting instance status monitoring with auto-start...")
    print(f"Instance ID: {INSTANCE_ID}")
    print(f"Check interval: {CHECK_INTERVAL} seconds")
    print("=" * 60)
    
    try:
        while True:
            check_instance_status(INSTANCE_ID, IAM_TOKEN)
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        print("\nMonitoring stopped by user")
        sys.exit(0)

if __name__ == "__main__":
    main()