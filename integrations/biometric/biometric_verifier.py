"""
Biometric Verification System for The Omniversity Protocol
Anti-fraud system using Worldcoin SDK and biometric verification
"""

import os
import json
import hashlib
import asyncio
from typing import Dict, Optional, Any, List
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from enum import Enum

# Database
from sqlalchemy import create_engine, Column, String, Integer, Float, DateTime, JSON, Boolean, LargeBinary
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Cryptography
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import base64

# Worldcoin (simulated - in production use actual SDK)
import requests

Base = declarative_base()

class VerificationStatus(Enum):
    PENDING = "pending"
    VERIFIED = "verified"
    FAILED = "failed"
    EXPIRED = "expired"
    REVOKED = "revoked"

class VerificationType(Enum):
    WORLDCOIN = "worldcoin"
    FINGERPRINT = "fingerprint"
    FACE = "face"
    IRIS = "iris"
    VOICE = "voice"

@dataclass
class BiometricTemplate:
    """Biometric template (encrypted)"""
    user_id: str
    verification_type: VerificationType
    template_hash: str  # Hash of biometric data
    encrypted_template: bytes  # Encrypted biometric template
    created_at: datetime
    expires_at: datetime
    is_active: bool

@dataclass
class VerificationAttempt:
    """Verification attempt record"""
    attempt_id: str
    user_id: str
    verification_type: VerificationType
    status: VerificationStatus
    confidence_score: float  # 0-100
    timestamp: datetime
    ip_address: str
    device_info: str
    fraud_score: float  # 0-100 (higher = more suspicious)
    details: Dict[str, Any]

@dataclass
class FraudAlert:
    """Fraud alert record"""
    alert_id: str
    user_id: str
    alert_type: str
    severity: str  # low, medium, high, critical
    description: str
    evidence: Dict[str, Any]
    timestamp: datetime
    resolved: bool
    resolution: Optional[str]

class BiometricTemplateDB(Base):
    """Database model for biometric templates"""
    __tablename__ = 'biometric_templates'
    
    user_id = Column(String, primary_key=True)
    verification_type = Column(String)
    template_hash = Column(String)
    encrypted_template = Column(LargeBinary)
    created_at = Column(DateTime)
    expires_at = Column(DateTime)
    is_active = Column(Boolean, default=True)

class VerificationAttemptDB(Base):
    """Database model for verification attempts"""
    __tablename__ = 'verification_attempts'
    
    attempt_id = Column(String, primary_key=True)
    user_id = Column(String)
    verification_type = Column(String)
    status = Column(String)
    confidence_score = Column(Float)
    timestamp = Column(DateTime)
    ip_address = Column(String)
    device_info = Column(String)
    fraud_score = Column(Float)
    details = Column(JSON)

class FraudAlertDB(Base):
    """Database model for fraud alerts"""
    __tablename__ = 'fraud_alerts'
    
    alert_id = Column(String, primary_key=True)
    user_id = Column(String)
    alert_type = Column(String)
    severity = Column(String)
    description = Column(String)
    evidence = Column(JSON)
    timestamp = Column(DateTime)
    resolved = Column(Boolean, default=False)
    resolution = Column(String)

class BiometricVerifier:
    """
    Biometric verification system for anti-fraud
    Supports multiple verification methods and fraud detection
    """
    
    def __init__(self, db_url: str = "sqlite:///omniversity.db", encryption_key: str = None):
        """Initialize biometric verifier"""
        
        # Initialize database
        self.engine = create_engine(db_url)
        Base.metadata.create_all(self.engine)
        Session = sessionmaker(bind=self.engine)
        self.db_session = Session()
        
        # Initialize encryption
        if encryption_key:
            self.cipher = Fernet(encryption_key.encode())
        else:
            # Generate new key (in production, use secure key management)
            self.cipher = Fernet(Fernet.generate_key())
        
        # Worldcoin API (simulated)
        self.worldcoin_api_url = os.getenv("WORLDCOIN_API_URL", "https://api.worldcoin.org")
        self.worldcoin_api_key = os.getenv("WORLDCOIN_API_KEY")
        
        # Fraud detection thresholds
        self.fraud_thresholds = {
            "max_attempts_per_hour": 5,
            "max_attempts_per_day": 20,
            "min_confidence_score": 70,
            "max_fraud_score": 30,
            "suspicious_ip_threshold": 3,
            "device_change_threshold": 2
        }
    
    async def enroll_biometric(
        self,
        user_id: str,
        verification_type: VerificationType,
        biometric_data: bytes,
        device_info: str = ""
    ) -> Dict[str, Any]:
        """Enroll biometric template for a user"""
        
        # Check if user already has active template
        existing = self.db_session.query(BiometricTemplateDB).filter_by(
            user_id=user_id,
            verification_type=verification_type.value,
            is_active=True
        ).first()
        
        if existing:
            return {
                "success": False,
                "error": "Biometric already enrolled",
                "template_id": existing.user_id
            }
        
        # Hash biometric data
        template_hash = hashlib.sha256(biometric_data).hexdigest()
        
        # Encrypt biometric template
        encrypted_template = self.cipher.encrypt(biometric_data)
        
        # Create template
        template = BiometricTemplateDB(
            user_id=user_id,
            verification_type=verification_type.value,
            template_hash=template_hash,
            encrypted_template=encrypted_template,
            created_at=datetime.utcnow(),
            expires_at=datetime.utcnow() + timedelta(days=365),  # 1 year validity
            is_active=True
        )
        
        self.db_session.add(template)
        self.db_session.commit()
        
        return {
            "success": True,
            "user_id": user_id,
            "verification_type": verification_type.value,
            "template_hash": template_hash,
            "expires_at": template.expires_at.isoformat()
        }
    
    async def verify_biometric(
        self,
        user_id: str,
        verification_type: VerificationType,
        biometric_data: bytes,
        ip_address: str = "",
        device_info: str = ""
    ) -> Dict[str, Any]:
        """Verify user's biometric"""
        
        # Generate attempt ID
        attempt_id = hashlib.sha256(
            f"{user_id}{datetime.utcnow().isoformat()}".encode()
        ).hexdigest()[:16]
        
        # Check for fraud indicators
        fraud_check = await self._check_fraud_indicators(user_id, ip_address, device_info)
        
        if fraud_check["is_suspicious"]:
            # Log suspicious attempt
            await self._log_verification_attempt(
                attempt_id=attempt_id,
                user_id=user_id,
                verification_type=verification_type,
                status=VerificationStatus.FAILED,
                confidence_score=0,
                ip_address=ip_address,
                device_info=device_info,
                fraud_score=fraud_check["fraud_score"],
                details={"reason": "Suspicious activity detected", "details": fraud_check}
            )
            
            # Create fraud alert
            await self._create_fraud_alert(
                user_id=user_id,
                alert_type="suspicious_verification",
                severity="high",
                description=f"Suspicious verification attempt from {ip_address}",
                evidence=fraud_check
            )
            
            return {
                "success": False,
                "error": "Verification blocked due to suspicious activity",
                "fraud_score": fraud_check["fraud_score"]
            }
        
        # Get stored template
        template = self.db_session.query(BiometricTemplateDB).filter_by(
            user_id=user_id,
            verification_type=verification_type.value,
            is_active=True
        ).first()
        
        if not template:
            return {
                "success": False,
                "error": "No biometric template found"
            }
        
        # Check if template is expired
        if template.expires_at < datetime.utcnow():
            template.is_active = False
            self.db_session.commit()
            
            return {
                "success": False,
                "error": "Biometric template expired"
            }
        
        # Decrypt stored template
        stored_data = self.cipher.decrypt(template.encrypted_template)
        
        # Compare biometric data
        confidence_score = await self._compare_biometrics(
            stored_data,
            biometric_data,
            verification_type
        )
        
        # Determine verification status
        if confidence_score >= self.fraud_thresholds["min_confidence_score"]:
            status = VerificationStatus.VERIFIED
        else:
            status = VerificationStatus.FAILED
        
        # Log verification attempt
        await self._log_verification_attempt(
            attempt_id=attempt_id,
            user_id=user_id,
            verification_type=verification_type,
            status=status,
            confidence_score=confidence_score,
            ip_address=ip_address,
            device_info=device_info,
            fraud_score=fraud_check["fraud_score"],
            details={"template_hash": template.template_hash}
        )
        
        return {
            "success": status == VerificationStatus.VERIFIED,
            "attempt_id": attempt_id,
            "status": status.value,
            "confidence_score": confidence_score,
            "fraud_score": fraud_check["fraud_score"]
        }
    
    async def verify_with_worldcoin(
        self,
        user_id: str,
        worldcoin_proof: str,
        ip_address: str = "",
        device_info: str = ""
    ) -> Dict[str, Any]:
        """Verify using Worldcoin"""
        
        attempt_id = hashlib.sha256(
            f"{user_id}{datetime.utcnow().isoformat()}".encode()
        ).hexdigest()[:16]
        
        # Check for fraud
        fraud_check = await self._check_fraud_indicators(user_id, ip_address, device_info)
        
        if fraud_check["is_suspicious"]:
            await self._log_verification_attempt(
                attempt_id=attempt_id,
                user_id=user_id,
                verification_type=VerificationType.WORLDCOIN,
                status=VerificationStatus.FAILED,
                confidence_score=0,
                ip_address=ip_address,
                device_info=device_info,
                fraud_score=fraud_check["fraud_score"],
                details={"reason": "Suspicious activity"}
            )
            
            return {
                "success": False,
                "error": "Verification blocked"
            }
        
        # Verify with Worldcoin API (simulated)
        try:
            # In production, use actual Worldcoin SDK
            # response = requests.post(
            #     f"{self.worldcoin_api_url}/verify",
            #     json={"proof": worldcoin_proof, "user_id": user_id},
            #     headers={"Authorization": f"Bearer {self.worldcoin_api_key}"}
            # )
            
            # Simulated verification
            is_valid = len(worldcoin_proof) > 20  # Simple validation
            confidence_score = 95.0 if is_valid else 0.0
            
            status = VerificationStatus.VERIFIED if is_valid else VerificationStatus.FAILED
            
            await self._log_verification_attempt(
                attempt_id=attempt_id,
                user_id=user_id,
                verification_type=VerificationType.WORLDCOIN,
                status=status,
                confidence_score=confidence_score,
                ip_address=ip_address,
                device_info=device_info,
                fraud_score=fraud_check["fraud_score"],
                details={"worldcoin_proof_hash": hashlib.sha256(worldcoin_proof.encode()).hexdigest()}
            )
            
            return {
                "success": is_valid,
                "attempt_id": attempt_id,
                "status": status.value,
                "confidence_score": confidence_score,
                "fraud_score": fraud_check["fraud_score"]
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Worldcoin verification failed: {str(e)}"
            }
    
    async def _compare_biometrics(
        self,
        stored_data: bytes,
        new_data: bytes,
        verification_type: VerificationType
    ) -> float:
        """Compare biometric data and return confidence score"""
        
        # In production, use actual biometric comparison algorithms
        # For now, use simple hash comparison
        
        stored_hash = hashlib.sha256(stored_data).hexdigest()
        new_hash = hashlib.sha256(new_data).hexdigest()
        
        if stored_hash == new_hash:
            return 100.0
        
        # Calculate similarity (simplified)
        # In production, use specialized algorithms for each biometric type
        similarity = 0.0
        
        if verification_type == VerificationType.FINGERPRINT:
            # Use minutiae matching
            similarity = self._compare_fingerprints(stored_data, new_data)
        elif verification_type == VerificationType.FACE:
            # Use face recognition
            similarity = self._compare_faces(stored_data, new_data)
        elif verification_type == VerificationType.VOICE:
            # Use voice recognition
            similarity = self._compare_voice(stored_data, new_data)
        else:
            # Default comparison
            similarity = 50.0 if stored_hash[:16] == new_hash[:16] else 0.0
        
        return similarity
    
    def _compare_fingerprints(self, data1: bytes, data2: bytes) -> float:
        """Compare fingerprint data (simplified)"""
        # In production, use specialized fingerprint matching algorithm
        return 85.0 if data1[:32] == data2[:32] else 0.0
    
    def _compare_faces(self, data1: bytes, data2: bytes) -> float:
        """Compare face data (simplified)"""
        # In production, use face recognition library
        return 90.0 if data1[:32] == data2[:32] else 0.0
    
    def _compare_voice(self, data1: bytes, data2: bytes) -> float:
        """Compare voice data (simplified)"""
        # In production, use voice recognition library
        return 80.0 if data1[:32] == data2[:32] else 0.0
    
    async def _check_fraud_indicators(
        self,
        user_id: str,
        ip_address: str,
        device_info: str
    ) -> Dict[str, Any]:
        """Check for fraud indicators"""
        
        fraud_score = 0.0
        indicators = []
        
        # Check attempt frequency
        one_hour_ago = datetime.utcnow() - timedelta(hours=1)
        recent_attempts = self.db_session.query(VerificationAttemptDB).filter(
            VerificationAttemptDB.user_id == user_id,
            VerificationAttemptDB.timestamp >= one_hour_ago
        ).count()
        
        if recent_attempts >= self.fraud_thresholds["max_attempts_per_hour"]:
            fraud_score += 40
            indicators.append("Too many attempts in last hour")
        
        # Check for multiple IPs
        one_day_ago = datetime.utcnow() - timedelta(days=1)
        unique_ips = self.db_session.query(VerificationAttemptDB.ip_address).filter(
            VerificationAttemptDB.user_id == user_id,
            VerificationAttemptDB.timestamp >= one_day_ago
        ).distinct().count()
        
        if unique_ips >= self.fraud_thresholds["suspicious_ip_threshold"]:
            fraud_score += 30
            indicators.append("Multiple IP addresses")
        
        # Check for device changes
        unique_devices = self.db_session.query(VerificationAttemptDB.device_info).filter(
            VerificationAttemptDB.user_id == user_id,
            VerificationAttemptDB.timestamp >= one_day_ago
        ).distinct().count()
        
        if unique_devices >= self.fraud_thresholds["device_change_threshold"]:
            fraud_score += 20
            indicators.append("Multiple devices")
        
        # Check for failed attempts
        failed_attempts = self.db_session.query(VerificationAttemptDB).filter(
            VerificationAttemptDB.user_id == user_id,
            VerificationAttemptDB.timestamp >= one_day_ago,
            VerificationAttemptDB.status == VerificationStatus.FAILED.value
        ).count()
        
        if failed_attempts >= 3:
            fraud_score += 10
            indicators.append("Multiple failed attempts")
        
        return {
            "is_suspicious": fraud_score >= self.fraud_thresholds["max_fraud_score"],
            "fraud_score": fraud_score,
            "indicators": indicators,
            "recent_attempts": recent_attempts,
            "unique_ips": unique_ips,
            "unique_devices": unique_devices
        }
    
    async def _log_verification_attempt(
        self,
        attempt_id: str,
        user_id: str,
        verification_type: VerificationType,
        status: VerificationStatus,
        confidence_score: float,
        ip_address: str,
        device_info: str,
        fraud_score: float,
        details: Dict[str, Any]
    ):
        """Log verification attempt"""
        
        attempt = VerificationAttemptDB(
            attempt_id=attempt_id,
            user_id=user_id,
            verification_type=verification_type.value,
            status=status.value,
            confidence_score=confidence_score,
            timestamp=datetime.utcnow(),
            ip_address=ip_address,
            device_info=device_info,
            fraud_score=fraud_score,
            details=details
        )
        
        self.db_session.add(attempt)
        self.db_session.commit()
    
    async def _create_fraud_alert(
        self,
        user_id: str,
        alert_type: str,
        severity: str,
        description: str,
        evidence: Dict[str, Any]
    ):
        """Create fraud alert"""
        
        alert_id = hashlib.sha256(
            f"{user_id}{datetime.utcnow().isoformat()}".encode()
        ).hexdigest()[:16]
        
        alert = FraudAlertDB(
            alert_id=alert_id,
            user_id=user_id,
            alert_type=alert_type,
            severity=severity,
            description=description,
            evidence=evidence,
            timestamp=datetime.utcnow(),
            resolved=False,
            resolution=None
        )
        
        self.db_session.add(alert)
        self.db_session.commit()
    
    async def get_verification_history(
        self,
        user_id: str,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get verification history for a user"""
        
        attempts = self.db_session.query(VerificationAttemptDB).filter_by(
            user_id=user_id
        ).order_by(VerificationAttemptDB.timestamp.desc()).limit(limit).all()
        
        return [
            {
                "attempt_id": a.attempt_id,
                "verification_type": a.verification_type,
                "status": a.status,
                "confidence_score": a.confidence_score,
                "timestamp": a.timestamp.isoformat(),
                "fraud_score": a.fraud_score
            }
            for a in attempts
        ]
    
    async def get_fraud_alerts(
        self,
        user_id: str = None,
        resolved: bool = None,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get fraud alerts"""
        
        query = self.db_session.query(FraudAlertDB)
        
        if user_id:
            query = query.filter_by(user_id=user_id)
        if resolved is not None:
            query = query.filter_by(resolved=resolved)
        
        alerts = query.order_by(FraudAlertDB.timestamp.desc()).limit(limit).all()
        
        return [
            {
                "alert_id": a.alert_id,
                "user_id": a.user_id,
                "alert_type": a.alert_type,
                "severity": a.severity,
                "description": a.description,
                "timestamp": a.timestamp.isoformat(),
                "resolved": a.resolved,
                "resolution": a.resolution
            }
            for a in alerts
        ]
    
    async def resolve_fraud_alert(
        self,
        alert_id: str,
        resolution: str
    ) -> bool:
        """Resolve a fraud alert"""
        
        alert = self.db_session.query(FraudAlertDB).filter_by(alert_id=alert_id).first()
        
        if alert:
            alert.resolved = True
            alert.resolution = resolution
            self.db_session.commit()
            return True
        
        return False

# FastAPI endpoints
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Biometric Verification API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize verifier
verifier = BiometricVerifier(
    db_url=os.getenv("DATABASE_URL", "sqlite:///omniversity.db"),
    encryption_key=os.getenv("ENCRYPTION_KEY")
)

class EnrollRequest(BaseModel):
    user_id: str
    verification_type: str
    biometric_data: str  # Base64 encoded
    device_info: str = ""

class VerifyRequest(BaseModel):
    user_id: str
    verification_type: str
    biometric_data: str  # Base64 encoded
    ip_address: str = ""
    device_info: str = ""

class WorldcoinVerifyRequest(BaseModel):
    user_id: str
    worldcoin_proof: str
    ip_address: str = ""
    device_info: str = ""

@app.post("/enroll")
async def enroll_biometric(request: EnrollRequest):
    """Enroll biometric template"""
    biometric_data = base64.b64decode(request.biometric_data)
    verification_type = VerificationType(request.verification_type)
    
    result = await verifier.enroll_biometric(
        user_id=request.user_id,
        verification_type=verification_type,
        biometric_data=biometric_data,
        device_info=request.device_info
    )
    
    return result

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/verify")
async def verify_biometric(request: VerifyRequest):
    """Verify biometric"""
    biometric_data = base64.b64decode(request.biometric_data)
    verification_type = VerificationType(request.verification_type)
    
    result = await verifier.verify_biometric(
        user_id=request.user_id,
        verification_type=verification_type,
        biometric_data=biometric_data,
        ip_address=request.ip_address,
        device_info=request.device_info
    )
    
    return result

@app.post("/verify/worldcoin")
async def verify_worldcoin(request: WorldcoinVerifyRequest):
    """Verify using Worldcoin"""
    result = await verifier.verify_with_worldcoin(
        user_id=request.user_id,
        worldcoin_proof=request.worldcoin_proof,
        ip_address=request.ip_address,
        device_info=request.device_info
    )
    
    return result

@app.get("/history/{user_id}")
async def get_verification_history(user_id: str, limit: int = 50):
    """Get verification history"""
    history = await verifier.get_verification_history(user_id, limit)
    return {"history": history}

@app.get("/alerts")
async def get_fraud_alerts(user_id: str = None, resolved: bool = None, limit: int = 50):
    """Get fraud alerts"""
    alerts = await verifier.get_fraud_alerts(user_id, resolved, limit)
    return {"alerts": alerts}

@app.post("/alerts/{alert_id}/resolve")
async def resolve_alert(alert_id: str, resolution: str):
    """Resolve fraud alert"""
    success = await verifier.resolve_fraud_alert(alert_id, resolution)
    return {"success": success}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
