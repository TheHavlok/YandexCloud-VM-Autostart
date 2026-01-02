#!/bin/bash

# Конфигурация
INSTANCE_ID="your-instance-id-here"
IAM_TOKEN="your-iam-token-here"
CHECK_INTERVAL=60  # секунды

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция запуска инстанса
start_instance() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local url="https://compute.api.cloud.yandex.net/compute/v1/instances/${INSTANCE_ID}:start"
    
    echo -e "[$timestamp] ${BLUE}⚡ Sending start command...${NC}"
    
    # Выполняем POST запрос
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${IAM_TOKEN}" \
        -H "Content-Type: application/json" \
        "${url}")
    
    # Разделяем тело ответа и HTTP код
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 202 ]; then
        echo -e "[$timestamp] ${GREEN}✓ Start command sent successfully${NC}"
        
        if command -v jq &> /dev/null; then
            operation_id=$(echo "$body" | jq -r '.id')
            echo "[$timestamp] Operation ID: $operation_id"
        fi
    else
        echo -e "[$timestamp] ${RED}✗ Failed to start instance: HTTP $http_code${NC}"
        echo "[$timestamp] Response: $body"
    fi
}

# Функция проверки статуса
check_instance_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local url="https://compute.api.cloud.yandex.net/compute/v1/instances/${INSTANCE_ID}"
    
    # Выполняем GET запрос
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer ${IAM_TOKEN}" \
        "${url}")
    
    # Разделяем тело ответа и HTTP код
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ]; then
        # Извлекаем статус и имя (требуется jq)
        if command -v jq &> /dev/null; then
            status=$(echo "$body" | jq -r '.status')
            name=$(echo "$body" | jq -r '.name')
            
            echo "[$timestamp] Instance: $name (ID: $INSTANCE_ID)"
            echo "[$timestamp] Status: $status"
            
            if [ "$status" == "RUNNING" ]; then
                echo -e "[$timestamp] ${GREEN}✓ Instance is RUNNING${NC}"
            elif [ "$status" == "STOPPED" ]; then
                echo -e "[$timestamp] ${YELLOW}⚠ Instance is STOPPED - attempting to start...${NC}"
                start_instance
            else
                echo -e "[$timestamp] ${BLUE}⏳ Instance status: $status${NC}"
            fi
        else
            # Если jq не установлен, используем grep
            echo "[$timestamp] Raw response (install jq for better output):"
            
            if echo "$body" | grep -q '"status": "RUNNING"'; then
                echo -e "[$timestamp] ${GREEN}✓ Instance is RUNNING${NC}"
            elif echo "$body" | grep -q '"status": "STOPPED"'; then
                echo -e "[$timestamp] ${YELLOW}⚠ Instance is STOPPED - attempting to start...${NC}"
                start_instance
            else
                echo -e "[$timestamp] ${BLUE}⏳ Instance status unknown or transitioning${NC}"
                echo "$body"
            fi
        fi
    else
        echo -e "[$timestamp] ${RED}Error: HTTP $http_code${NC}"
        echo "[$timestamp] Response: $body"
    fi
    
    echo "------------------------------------------------------------"
}

# Проверка параметров
if [ "$INSTANCE_ID" == "your-instance-id-here" ] || [ "$IAM_TOKEN" == "your-iam-token-here" ]; then
    echo -e "${RED}Error: Please set INSTANCE_ID and IAM_TOKEN in the script${NC}"
    exit 1
fi

# Главный цикл
echo "Starting instance status monitoring with auto-start..."
echo "Instance ID: $INSTANCE_ID"
echo "Check interval: $CHECK_INTERVAL seconds"
echo "============================================================"

# Обработка прерывания (Ctrl+C)
trap 'echo -e "\n${YELLOW}Monitoring stopped by user${NC}"; exit 0' INT

while true; do
    check_instance_status
    sleep $CHECK_INTERVAL
done