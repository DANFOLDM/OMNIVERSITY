#!/bin/bash

# Omniversity Node Deployment Script
# For Raspberry Pi and edge computing nodes
# Version: 1.0.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NODE_ID=${NODE_ID:-"node-$(hostname)"}
NODE_LOCATION=${NODE_LOCATION:-"Unknown"}
NETWORK=${NETWORK:-"polygon"}
API_PORT=${API_PORT:-8080}
P2P_PORT=${P2P_PORT:-30303}

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Omniversity Protocol - Node Deployment            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Detect system
echo -e "${YELLOW}Detecting system...${NC}"
ARCH=$(uname -m)
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')

echo "Architecture: $ARCH"
echo "OS: $OS"
echo "Node ID: $NODE_ID"
echo "Location: $NODE_LOCATION"
echo ""

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update
apt-get upgrade -y

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    docker.io \
    docker-compose \
    nginx \
    certbot \
    python3-certbot-nginx \
    ufw \
    fail2ban \
    htop \
    iotop \
    nethogs

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Create omniversity user
echo -e "${YELLOW}Creating omniversity user...${NC}"
if ! id "omniversity" &>/dev/null; then
    useradd -m -s /bin/bash omniversity
    usermod -aG docker omniversity
fi

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p /opt/omniversity/{bin,config,data,logs,scripts}
mkdir -p /opt/omniversity/data/{blockchain,ipfs,ai,curriculum}
chown -R omniversity:omniversity /opt/omniversity

# Download node software
echo -e "${YELLOW}Downloading Omniversity node software...${NC}"
cd /opt/omniversity

# In production, download from official repository
# For now, create placeholder structure
cat > /opt/omniversity/bin/node << 'EOF'
#!/usr/bin/env python3
"""
Omniversity Node - Edge Computing Node
Handles local learning, verification, and blockchain sync
"""

import os
import sys
import json
import asyncio
import logging
from datetime import datetime
from typing import Dict, Any

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/omniversity/logs/node.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

app = FastAPI(title="Omniversity Node", version="1.0.0")

class NodeStatus(BaseModel):
    node_id: str
    status: str
    uptime: int
    blockchain_sync: bool
    ipfs_connected: bool
    ai_loaded: bool
    peers_connected: int
    last_block: int
    storage_used: float
    storage_total: float

class LearningRequest(BaseModel):
    user_id: str
    module_id: str
    activity_type: str

class VerificationRequest(BaseModel):
    user_id: str
    verification_type: str
    data: str

# Global state
node_state = {
    "node_id": os.getenv("NODE_ID", "node-001"),
    "start_time": datetime.utcnow(),
    "blockchain_sync": False,
    "ipfs_connected": False,
    "ai_loaded": False,
    "peers": [],
    "last_block": 0
}

@app.get("/")
async def root():
    return {"message": "Omniversity Node", "version": "1.0.0"}

@app.get("/status")
async def get_status() -> NodeStatus:
    """Get node status"""
    uptime = (datetime.utcnow() - node_state["start_time"]).seconds
    
    return NodeStatus(
        node_id=node_state["node_id"],
        status="online",
        uptime=uptime,
        blockchain_sync=node_state["blockchain_sync"],
        ipfs_connected=node_state["ipfs_connected"],
        ai_loaded=node_state["ai_loaded"],
        peers_connected=len(node_state["peers"]),
        last_block=node_state["last_block"],
        storage_used=0.0,
        storage_total=100.0
    )

@app.post("/learn")
async def process_learning(request: LearningRequest):
    """Process learning activity locally"""
    logger.info(f"Processing learning: {request.user_id} - {request.module_id}")
    
    # In production, this would:
    # 1. Load AI model locally
    # 2. Process learning activity
    # 3. Calculate rewards
    # 4. Sync with blockchain
    
    return {
        "success": True,
        "user_id": request.user_id,
        "module_id": request.module_id,
        "omni_earned": 10.0,
        "timestamp": datetime.utcnow().isoformat()
    }

@app.post("/verify")
async def verify_identity(request: VerificationRequest):
    """Verify user identity locally"""
    logger.info(f"Verifying identity: {request.user_id}")
    
    # In production, this would:
    # 1. Check biometric data
    # 2. Verify against blockchain
    # 3. Return verification result
    
    return {
        "success": True,
        "user_id": request.user_id,
        "verified": True,
        "confidence": 95.0
    }

@app.get("/peers")
async def get_peers():
    """Get connected peers"""
    return {"peers": node_state["peers"]}

@app.post("/sync")
async def sync_blockchain():
    """Sync with blockchain"""
    logger.info("Starting blockchain sync...")
    
    # In production, this would sync with Polygon
    
    node_state["blockchain_sync"] = True
    node_state["last_block"] = 12345678
    
    return {"success": True, "last_block": node_state["last_block"]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

chmod +x /opt/omniversity/bin/node

# Create configuration
echo -e "${YELLOW}Creating configuration...${NC}"
cat > /opt/omniversity/config/node.json << EOF
{
    "node_id": "$NODE_ID",
    "location": "$NODE_LOCATION",
    "network": "$NETWORK",
    "api_port": $API_PORT,
    "p2p_port": $P2P_PORT,
    "blockchain": {
        "rpc_url": "https://polygon-rpc.com",
        "chain_id": 137,
        "contracts": {
            "omni_token": "0x...",
            "sbt": "0x...",
            "learn_to_earn": "0x...",
            "dao": "0x..."
        }
    },
    "ipfs": {
        "host": "localhost",
        "port": 5001
    },
    "ai": {
        "model_path": "/opt/omniversity/data/ai/model.bin",
        "use_gpu": false
    },
    "storage": {
        "max_size_gb": 100,
        "curriculum_path": "/opt/omniversity/data/curriculum"
    }
}
EOF

# Create systemd service
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/omniversity-node.service << EOF
[Unit]
Description=Omniversity Node
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=omniversity
Group=omniversity
WorkingDirectory=/opt/omniversity
ExecStart=/usr/bin/python3 /opt/omniversity/bin/node
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Environment
Environment=NODE_ID=$NODE_ID
Environment=NODE_LOCATION=$NODE_LOCATION
Environment=NETWORK=$NETWORK

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/omniversity

[Install]
WantedBy=multi-user.target
EOF

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow $API_PORT/tcp
ufw allow $P2P_PORT/tcp
ufw allow $P2P_PORT/udp
ufw --force enable

# Configure fail2ban
echo -e "${YELLOW}Configuring fail2ban...${NC}"
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log

[omniversity]
enabled = true
port = $API_PORT
filter = omniversity
logpath = /opt/omniversity/logs/node.log
EOF

# Create fail2ban filter
cat > /etc/fail2ban/filter.d/omniversity.conf << EOF
[Definition]
failregex = ^.*Failed login from <HOST>.*$
            ^.*Invalid request from <HOST>.*$
ignoreregex =
EOF

# Configure nginx reverse proxy
echo -e "${YELLOW}Configuring nginx...${NC}"
cat > /etc/nginx/sites-available/omniversity << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
}
EOF

ln -sf /etc/nginx/sites-available/omniversity /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# Install Python dependencies
echo -e "${YELLOW}Installing Python dependencies...${NC}"
pip3 install \
    fastapi \
    uvicorn \
    web3 \
    ipfshttpclient \
    torch \
    transformers \
    numpy \
    pandas

# Create monitoring script
echo -e "${YELLOW}Creating monitoring script...${NC}"
cat > /opt/omniversity/scripts/monitor.sh << 'EOF'
#!/bin/bash

# Omniversity Node Monitor

LOG_FILE="/opt/omniversity/logs/monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# Check node status
check_node() {
    if systemctl is-active --quiet omniversity-node; then
        log "Node is running"
    else
        log "Node is not running, restarting..."
        systemctl restart omniversity-node
    fi
}

# Check disk space
check_disk() {
    USAGE=$(df /opt/omniversity | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ $USAGE -gt 90 ]; then
        log "WARNING: Disk usage is ${USAGE}%"
    fi
}

# Check memory
check_memory() {
    FREE=$(free -m | awk 'NR==2{print $4}')
    if [ $FREE -lt 100 ]; then
        log "WARNING: Low memory: ${FREE}MB free"
    fi
}

# Main monitoring loop
while true; do
    check_node
    check_disk
    check_memory
    sleep 60
done
EOF

chmod +x /opt/omniversity/scripts/monitor.sh

# Create backup script
echo -e "${YELLOW}Creating backup script...${NC}"
cat > /opt/omniversity/scripts/backup.sh << 'EOF'
#!/bin/bash

# Omniversity Node Backup Script

BACKUP_DIR="/opt/omniversity/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

mkdir -p $BACKUP_DIR

# Backup data
tar -czf $BACKUP_FILE \
    /opt/omniversity/data \
    /opt/omniversity/config \
    /opt/omniversity/logs

# Keep only last 7 backups
ls -t $BACKUP_DIR/*.tar.gz | tail -n +8 | xargs rm -f

echo "Backup created: $BACKUP_FILE"
EOF

chmod +x /opt/omniversity/scripts/backup.sh

# Add to crontab
echo -e "${YELLOW}Setting up cron jobs...${NC}"
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/omniversity/scripts/monitor.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/omniversity/scripts/backup.sh") | crontab -

# Start services
echo -e "${YELLOW}Starting services...${NC}"
systemctl daemon-reload
systemctl enable omniversity-node
systemctl start omniversity-node
systemctl enable fail2ban
systemctl start fail2ban

# Display status
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Deployment Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Node ID: $NODE_ID"
echo "Location: $NODE_LOCATION"
echo "API Port: $API_PORT"
echo "P2P Port: $P2P_PORT"
echo ""
echo "Service Status:"
systemctl status omniversity-node --no-pager
echo ""
echo "Logs: journalctl -u omniversity-node -f"
echo "Config: /opt/omniversity/config/node.json"
echo "Data: /opt/omniversity/data"
echo ""
echo -e "${GREEN}Node is now running and ready to serve the Omniversity Protocol!${NC}"
