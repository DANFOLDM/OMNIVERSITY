from datetime import datetime
from typing import List

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Biometric Verification Lite API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class EnrollRequest(BaseModel):
    user_id: str
    verification_type: str
    biometric_data: str
    device_info: str = ""

class VerifyRequest(BaseModel):
    user_id: str
    verification_type: str
    biometric_data: str
    ip_address: str = ""
    device_info: str = ""

class WorldcoinVerifyRequest(BaseModel):
    user_id: str
    worldcoin_proof: str
    ip_address: str = ""
    device_info: str = ""

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/enroll")
async def enroll_biometric(request: EnrollRequest):
    return {
        "success": True,
        "message": "Biometric enrolled",
        "user_id": request.user_id,
        "verification_type": request.verification_type
    }

@app.post("/verify")
async def verify_biometric(request: VerifyRequest):
    return {
        "success": True,
        "status": "verified",
        "confidence": 97.5,
        "user_id": request.user_id
    }

@app.post("/verify/worldcoin")
async def verify_worldcoin(request: WorldcoinVerifyRequest):
    return {
        "success": True,
        "status": "verified",
        "user_id": request.user_id
    }

@app.get("/history/{user_id}")
async def get_verification_history(user_id: str, limit: int = 50):
    history = [
        {
            "attempt_id": "demo_1",
            "status": "verified",
            "timestamp": datetime.utcnow().isoformat()
        }
    ]
    return {"history": history[:limit]}

@app.get("/alerts")
async def get_fraud_alerts(user_id: str = None, resolved: bool = None, limit: int = 50):
    return {"alerts": []}

@app.post("/alerts/{alert_id}/resolve")
async def resolve_alert(alert_id: str, resolution: str):
    return {"success": True, "alert_id": alert_id, "resolution": resolution}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
