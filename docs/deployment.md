# The Omniversity Protocol - Deployment Guide

## Prerequisites

### System Requirements
- Node.js 18+
- Python 3.9+
- Docker & Docker Compose
- Git
- Solidity compiler (solc)
- Hardhat or Foundry

### Accounts & API Keys
- OpenAI API key (for AI Sensei)
- Polygon RPC endpoint
- M-Pesa API credentials
- Worldcoin API key
- Infura/Alchemy account

## Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/omniversity/protocol.git
cd protocol
```

### 2. Install Dependencies
```bash
# Smart contracts
npm install

# AI backend
cd ai-backend
pip install -r requirements.txt

# Frontend
cd ../frontend
npm install
```

### 3. Configure Environment
```bash
cp .env.example .env

# Edit .env with your credentials
nano .env
```

**Required Environment Variables**:
```env
# Blockchain
POLYGON_RPC_URL=https://polygon-rpc.com
PRIVATE_KEY=your_private_key
POLYGONSCAN_API_KEY=your_api_key

# AI
OPENAI_API_KEY=your_openai_key
DATABASE_URL=sqlite:///omniversity.db

# M-Pesa
MPESA_CONSUMER_KEY=your_key
MPESA_CONSUMER_SECRET=your_secret
MPESA_SHORTCODE=your_shortcode
MPESA_PASSKEY=your_passkey

# Biometric
WORLDCOIN_API_KEY=your_worldcoin_key
ENCRYPTION_KEY=your_encryption_key

# IPFS
IPFS_API_URL=http://localhost:5001
```

## Smart Contract Deployment

### 1. Compile Contracts
```bash
npx hardhat compile
```

### 2. Run Tests
```bash
npx hardhat test
```

### 3. Deploy to Polygon
```bash
# Deploy all contracts
npx hardhat run scripts/deploy.js --network polygon

# Deploy individual contracts
npx hardhat run scripts/deploy-token.js --network polygon
npx hardhat run scripts/deploy-sbt.js --network polygon
npx hardhat run scripts/deploy-learn-to-earn.js --network polygon
npx hardhat run scripts/deploy-dao.js --network polygon
```

### 4. Verify Contracts
```bash
npx hardhat verify --network polygon DEPLOYED_CONTRACT_ADDRESS
```

### 5. Initialize Contracts
```bash
npx hardhat run scripts/initialize.js --network polygon
```

## AI Backend Deployment

### 1. Setup Database
```bash
cd ai-backend

# Create database
python manage.py db init
python manage.py db migrate
python manage.py db upgrade
```

### 2. Start Services
```bash
# AI Sensei (port 8000)
cd sensei
uvicorn ai_sensei:app --host 0.0.0.0 --port 8000 --reload

# Opportunity Radar (port 8001)
cd ../radar
uvicorn opportunity_radar:app --host 0.0.0.0 --port 8001 --reload

# Biometric Verifier (port 8002)
cd ../integrations/biometric
uvicorn biometric_verifier:app --host 0.0.0.0 --port 8002 --reload

# Solar Manager (port 8003)
cd ../physical-nodes/solar
uvicorn solar_manager:app --host 0.0.0.0 --port 8003 --reload
```

### 3. Using Docker
```bash
# Build images
docker-compose build

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## Physical Node Deployment

### 1. Prepare Raspberry Pi
```bash
# Flash Raspberry Pi OS
# Enable SSH
# Configure WiFi
```

### 2. Deploy Node
```bash
# Copy deployment script
scp physical-nodes/raspberry-pi/deploy_node.sh pi@node-ip:~/

# SSH into node
ssh pi@node-ip

# Run deployment
sudo ./deploy_node.sh
```

### 3. Configure Node
```bash
# Edit configuration
sudo nano /opt/omniversity/config/node.json

# Restart service
sudo systemctl restart omniversity-node
```

### 4. Monitor Node
```bash
# Check status
sudo systemctl status omniversity-node

# View logs
sudo journalctl -u omniversity-node -f

# Monitor resources
htop
iotop
nethogs
```

## M-Pesa Integration

### 1. Register M-Pesa App
- Visit Safaricom Developer Portal
- Create new app
- Get consumer key and secret
- Configure callback URLs

### 2. Configure USSD
```bash
# Create USSD service
mpesa ussd create --shortcode YOUR_SHORTCODE --callback-url https://your-domain.com/ussd

# Test USSD
mpesa ussd test --shortcode YOUR_SHORTCODE
```

### 3. Setup Callbacks
```python
# callbacks/mpesa.py
from fastapi import APIRouter, Request

router = APIRouter()

@router.post("/mpesa/callback")
async def mpesa_callback(request: Request):
    data = await request.json()
    # Process M-Pesa callback
    return {"ResultCode": 0, "ResultDesc": "Success"}
```

## Biometric Setup

### 1. Install Worldcoin SDK
```bash
pip install worldcoin-sdk
```

### 2. Configure Biometric Devices
```bash
# Fingerprint scanner
sudo apt-get install libfprint-dev

# Camera for face recognition
sudo apt-get install python3-opencv

# Microphone for voice
sudo apt-get install portaudio19-dev
```

### 3. Test Verification
```bash
curl -X POST http://localhost:8002/verify \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test_user",
    "verification_type": "face",
    "biometric_data": "base64_encoded_data"
  }'
```

## Frontend Deployment

### 1. Build Frontend
```bash
cd frontend

# Install dependencies
npm install

# Build for production
npm run build

# Preview build
npm run preview
```

### 2. Deploy to Vercel
```bash
# Install Vercel CLI
npm i -g vercel

# Deploy
vercel --prod
```

### 3. Deploy to AWS
```bash
# Build Docker image
docker build -t omniversity-frontend .

# Push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.us-east-1.amazonaws.com
docker tag omniversity-frontend:latest ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/omniversity-frontend:latest
docker push ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/omniversity-frontend:latest

# Deploy to ECS
aws ecs update-service --cluster omniversity --service frontend --force-new-deployment
```

## Monitoring & Maintenance

### 1. Setup Monitoring
```bash
# Install Prometheus
docker run -d -p 9090:9090 prom/prometheus

# Install Grafana
docker run -d -p 3000:3000 grafana/grafana

# Install Node Exporter
docker run -d -p 9100:9100 prom/node-exporter
```

### 2. Configure Alerts
```yaml
# prometheus/alerts.yml
groups:
  - name: omniversity
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
```

### 3. Backup Strategy
```bash
# Database backup
pg_dump omniversity > backup_$(date +%Y%m%d).sql

# IPFS backup
ipfs repo gc
ipfs pin ls > pins_backup.txt

# Blockchain backup
# Use snapshot services
```

## Security Checklist

### Smart Contracts
- [ ] Audit completed
- [ ] Reentrancy guards
- [ ] Access control
- [ ] Input validation
- [ ] Overflow protection
- [ ] Pausable functionality

### Backend
- [ ] Rate limiting
- [ ] CORS configured
- [ ] Authentication
- [ ] Authorization
- [ ] Input sanitization
- [ ] SQL injection prevention
- [ ] XSS protection

### Infrastructure
- [ ] Firewall configured
- [ ] SSL/TLS enabled
- [ ] DDoS protection
- [ ] Backup strategy
- [ ] Monitoring enabled
- [ ] Alerting configured

### Data
- [ ] Encryption at rest
- [ ] Encryption in transit
- [ ] Access logs
- [ ] Data retention policy
- [ ] GDPR compliance

## Troubleshooting

### Common Issues

**Contract deployment fails**
```bash
# Check gas
npx hardhat run scripts/check-gas.js

# Increase gas limit
--gas-limit 10000000
```

**AI backend crashes**
```bash
# Check logs
tail -f /var/log/omniversity/ai.log

# Increase memory
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
```

**Node offline**
```bash
# Check service
sudo systemctl status omniversity-node

# Check network
ping google.com

# Check disk space
df -h
```

**M-Pesa integration fails**
```bash
# Verify credentials
mpesa auth test

# Check callback URL
curl -X POST https://your-domain.com/mpesa/callback
```

## Performance Optimization

### Database
```sql
-- Add indexes
CREATE INDEX idx_user_id ON learner_profiles(user_id);
CREATE INDEX idx_skill ON skill_demand(skill);
CREATE INDEX idx_timestamp ON energy_readings(timestamp);
```

### Caching
```python
# Redis caching
import redis

cache = redis.Redis(host='localhost', port=6379, db=0)

@cache.memoize(timeout=3600)
def get_user_profile(user_id):
    return db.query(User).filter_by(id=user_id).first()
```

### Load Balancing
```nginx
# nginx.conf
upstream omniversity {
    server 127.0.0.1:8000;
    server 127.0.0.1:8001;
    server 127.0.0.1:8002;
}

server {
    listen 80;
    location / {
        proxy_pass http://omniversity;
    }
}
```

## Scaling Guide

### Horizontal Scaling
```bash
# Add more backend instances
docker-compose up -d --scale ai-sensei=3

# Load balancer
nginx -s reload
```

### Database Scaling
```bash
# Read replicas
postgresql.conf:
hot_standby = on
wal_level = replica
```

### CDN Setup
```bash
# CloudFront distribution
aws cloudfront create-distribution \
  --origin-domain-name your-domain.com
```

## Support

### Documentation
- [Architecture](architecture.md)
- [Smart Contracts](contracts.md)
- [AI Sensei](ai-sensei.md)
- [DAO](dao.md)

### Community
- Discord: https://discord.gg/omniversity
- Twitter: @OmniversityDAO
- Email: support@omniversity.protocol

### Emergency Contacts
- Security: security@omniversity.protocol
- Operations: ops@omniversity.protocol
- Development: dev@omniversity.protocol

## Conclusion

This deployment guide covers all aspects of deploying The Omniversity Protocol. Follow the steps carefully and refer to the troubleshooting section if you encounter issues.

For production deployments, ensure all security measures are in place and conduct thorough testing before going live.
